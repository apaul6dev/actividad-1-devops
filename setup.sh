#!/bin/bash

# Salir si ocurre un error
set -e
export DEBIAN_FRONTEND=noninteractive

# Variables
APP_NAME="mi-app-node"
APP_DIR="/var/www/$APP_NAME"
REPO_URL="https://github.com/apaul6dev/example-server-nodejs.git"
NODE_VERSION="20"
DOMAIN="example.com"
USER_NODE="nodeapp"
PORT="3000"
USER_HOME="/home/$USER_NODE"

echo "==> Actualizando sistema..."
sudo apt update && sudo apt upgrade -y

echo "==> Instalando dependencias..."
sudo apt install -y curl git build-essential ufw nginx

echo "==> Instalando Node.js y npm..."
curl -fsSL https://deb.nodesource.com/setup_$NODE_VERSION.x | sudo -E bash -
sudo apt install -y nodejs

echo "==> Creando usuario sin privilegios para la app..."
if ! id -u $USER_NODE >/dev/null 2>&1; then
    sudo adduser --system --group --shell /bin/bash --home $USER_HOME $USER_NODE
    sudo mkdir -p $USER_HOME
    sudo chown -R $USER_NODE:$USER_NODE $USER_HOME
else
    echo "Usuario $USER_NODE ya existe."
fi

echo "==> Clonando aplicación..."
sudo mkdir -p $APP_DIR
sudo chown -R $USER_NODE:$USER_NODE $APP_DIR
sudo -u $USER_NODE git clone $REPO_URL $APP_DIR

echo "==> Instalando dependencias de la app..."
cd $APP_DIR
sudo -u $USER_NODE HOME=$USER_HOME npm install --omit=dev

echo "==> Instalando PM2..."
sudo npm install -g pm2

echo "==> Ejecutando aplicación con PM2..."
sudo -u $USER_NODE HOME=$USER_HOME pm2 start index.js --name "$APP_NAME"
sudo -u $USER_NODE HOME=$USER_HOME pm2 save
sudo pm2 startup systemd -u $USER_NODE --hp $USER_HOME

echo "==> Configurando firewall (UFW)..."
sudo ufw allow OpenSSH
sudo ufw allow 'Nginx Full'
sudo ufw --force enable

echo "==> Configurando Nginx como proxy reverso..."
NGINX_CONF="/etc/nginx/sites-available/$APP_NAME"

sudo bash -c "cat > $NGINX_CONF" <<EOL
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        proxy_pass http://localhost:$PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }

    access_log /var/log/nginx/${APP_NAME}_access.log;
    error_log /var/log/nginx/${APP_NAME}_error.log;
}
EOL

sudo ln -sf $NGINX_CONF /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx

echo "==> Corrigiendo permisos finales..."
sudo chown -R $USER_NODE:$USER_NODE $APP_DIR

echo "==> Despliegue completo: $APP_NAME en producción con PM2 y Nginx"
