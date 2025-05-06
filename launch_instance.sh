#!/bin/bash

set -e

# Configuración
KEY_NAME="ec2-packer-new"
PEM_FILE="${KEY_NAME}.pem"
REGION="us-east-1"
INSTANCE_TYPE="t2.micro"
SECURITY_GROUP_NAME="default"

# Paso 1: Verificar o crear Key Pair
echo "🔍 Verificando si existe el key pair \"$KEY_NAME\"..."
if ! aws ec2 describe-key-pairs --key-names "$KEY_NAME" --region "$REGION" &>/dev/null; then
  echo "🔐 Key pair no encontrado. Creando nuevo \"$KEY_NAME\"..."
  aws ec2 create-key-pair \
    --key-name "$KEY_NAME" \
    --query 'KeyMaterial' \
    --region "$REGION" \
    --output text > "$PEM_FILE"
  chmod 400 "$PEM_FILE"
  echo "✅ Clave privada guardada como $PEM_FILE"
else
  echo "✅ Key pair \"$KEY_NAME\" ya existe."
fi

# Paso 2: Obtener el ID de la AMI desde manifest.json
AMI_ID=$(jq -r '.builds[-1].artifact_id | split(":")[1]' manifest.json)

if [ -z "$AMI_ID" ]; then
  echo "❌ No se pudo extraer el AMI ID desde manifest.json"
  exit 1
fi
echo "✅ AMI encontrado: $AMI_ID"
echo "$AMI_ID" > ami_id.txt

# Paso 3: Obtener ID del security group
SG_ID=$(aws ec2 describe-security-groups \
  --filters Name=group-name,Values=$SECURITY_GROUP_NAME \
  --region "$REGION" \
  --query "SecurityGroups[0].GroupId" \
  --output text)

echo "🔐 Security Group ID: $SG_ID"

# Paso 4: Asegurar que los puertos 22 y 80 estén abiertos
for PORT in 22 80; do
  if ! aws ec2 describe-security-groups \
    --group-ids "$SG_ID" \
    --region "$REGION" \
    --query "SecurityGroups[0].IpPermissions[?ToPort==\`${PORT}\`]" \
    --output text | grep -q "${PORT}"; then
    echo "🌐 Agregando regla para permitir tráfico en el puerto $PORT..."
    aws ec2 authorize-security-group-ingress \
      --group-id "$SG_ID" \
      --protocol tcp \
      --port "$PORT" \
      --cidr 0.0.0.0/0 \
      --region "$REGION"
  else
    echo "✅ El puerto $PORT ya está habilitado."
  fi
done

# Paso 5: Lanzar instancia EC2
echo "🚀 Lanzando instancia EC2..."
INSTANCE_INFO=$(aws ec2 run-instances \
  --image-id "$AMI_ID" \
  --instance-type "$INSTANCE_TYPE" \
  --key-name "$KEY_NAME" \
  --security-group-ids "$SG_ID" \
  --region "$REGION" \
  --associate-public-ip-address \
  --output json)

INSTANCE_ID=$(echo "$INSTANCE_INFO" | jq -r '.Instances[0].InstanceId')
echo "✅ Instancia creada con ID: $INSTANCE_ID"

# Paso 6: Esperar hasta que esté en estado "running"
echo "⏳ Esperando a que la instancia esté 'running'..."
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID" --region "$REGION"
echo "✅ Instancia en ejecución."

# Paso 7: Obtener IP pública
PUBLIC_IP=$(aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --region "$REGION" \
  --query "Reservations[0].Instances[0].PublicIpAddress" \
  --output text)

echo "🌐 IP pública: $PUBLIC_IP"
echo "$PUBLIC_IP" > public_ip.txt

# Resultado final
echo ""
echo "🎉 Instancia EC2 desplegada y lista para usarse."
echo "👉 Puedes conectarte con:"
echo "ssh -i $PEM_FILE ubuntu@$PUBLIC_IP"
echo ""
