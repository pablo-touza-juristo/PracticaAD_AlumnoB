#!/bin/bash
# =============================================================
#  check-prerequisites.sh
#  Verifica que todo lo necesario está configurado antes
#  de ejecutar el pipeline de Jenkins
# =============================================================

set -e

REGION="${1:-eu-south-2}"
PROFILE_PERSONAL="AlexPersonal"
PROFILE_UFV="AlexUFV"

PASS=0
FAIL=0

check() {
    local desc="$1"
    local cmd="$2"
    if eval "$cmd" > /dev/null 2>&1; then
        echo "  ✅  $desc"
        PASS=$((PASS+1))
    else
        echo "  ❌  $desc"
        FAIL=$((FAIL+1))
    fi
}

echo "============================================"
echo " Verificando prerrequisitos del pipeline"
echo " Region: ${REGION}"
echo "============================================"
echo ""

echo "[ AWS CLI ]"
check "aws-cli instalado" "which aws"
check "version aws-cli >= 2" "aws --version 2>&1 | grep -q 'aws-cli/2'"

echo ""
echo "[ Perfiles AWS ]"
check "Perfil '${PROFILE_PERSONAL}' configurado" "aws configure list --profile ${PROFILE_PERSONAL}"
check "Perfil '${PROFILE_UFV}' configurado" "aws configure list --profile ${PROFILE_UFV}"

echo ""
echo "[ Autenticacion AWS ]"
check "Acceso cuenta AlexPersonal" "aws sts get-caller-identity --profile ${PROFILE_PERSONAL} --region ${REGION}"
check "Acceso cuenta AlexUFV" "aws sts get-caller-identity --profile ${PROFILE_UFV} --region ${REGION}"

echo ""
echo "[ IDs de cuenta ]"
ACCOUNT_PERSONAL=$(aws sts get-caller-identity --profile ${PROFILE_PERSONAL} --region ${REGION} --query Account --output text 2>/dev/null || echo "ERROR")
ACCOUNT_UFV=$(aws sts get-caller-identity --profile ${PROFILE_UFV} --region ${REGION} --query Account --output text 2>/dev/null || echo "ERROR")
echo "  AlexPersonal Account ID: ${ACCOUNT_PERSONAL}"
echo "  AlexUFV Account ID:      ${ACCOUNT_UFV}"

if [ "$ACCOUNT_PERSONAL" = "$ACCOUNT_UFV" ]; then
    echo "  ⚠️  ATENCION: Ambas cuentas tienen el mismo ID - asegurate de que los perfiles apuntan a cuentas distintas"
fi

echo ""
echo "[ Key Pairs ]"
echo "  Listando Key Pairs en AlexPersonal (${REGION}):"
aws ec2 describe-key-pairs --profile ${PROFILE_PERSONAL} --region ${REGION} \
    --query 'KeyPairs[*].KeyName' --output table 2>/dev/null || echo "  (sin key pairs o error de acceso)"

echo "  Listando Key Pairs en AlexUFV (${REGION}):"
aws ec2 describe-key-pairs --profile ${PROFILE_UFV} --region ${REGION} \
    --query 'KeyPairs[*].KeyName' --output table 2>/dev/null || echo "  (sin key pairs o error de acceso)"

echo ""
echo "[ AMIs disponibles - Amazon Linux 2023 ]"
AMI_PERSONAL=$(aws ec2 describe-images \
    --profile ${PROFILE_PERSONAL} \
    --region ${REGION} \
    --owners amazon \
    --filters "Name=name,Values=al2023-ami-*-x86_64" "Name=state,Values=available" \
    --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
    --output text 2>/dev/null || echo "ERROR")
echo "  AMI mas reciente AlexPersonal: ${AMI_PERSONAL}"

AMI_WINDOWS=$(aws ec2 describe-images \
    --profile ${PROFILE_PERSONAL} \
    --region ${REGION} \
    --owners amazon \
    --filters "Name=name,Values=Windows_Server-2019-English-Full-Base-*" "Name=state,Values=available" \
    --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
    --output text 2>/dev/null || echo "ERROR")
echo "  AMI Windows 2019 AlexPersonal:  ${AMI_WINDOWS}"

AMI_UFV=$(aws ec2 describe-images \
    --profile ${PROFILE_UFV} \
    --region ${REGION} \
    --owners amazon \
    --filters "Name=name,Values=al2023-ami-*-x86_64" "Name=state,Values=available" \
    --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
    --output text 2>/dev/null || echo "ERROR")
echo "  AMI mas reciente AlexUFV:      ${AMI_UFV}"

if [ "$AMI_PERSONAL" != "ERROR" ]; then
    echo ""
    echo "  ℹ️  Usa esta AMI en el Jenkinsfile o en los parametros del stack:"
    echo "     Personal: ${AMI_PERSONAL}"
    echo "     UFV:      ${AMI_UFV}"
fi

echo ""
echo "[ Permisos IAM minimos necesarios ]"
check "AlexPersonal puede crear CloudFormation" \
    "aws cloudformation list-stacks --profile ${PROFILE_PERSONAL} --region ${REGION}"
check "AlexUFV puede crear CloudFormation" \
    "aws cloudformation list-stacks --profile ${PROFILE_UFV} --region ${REGION}"
check "AlexPersonal puede crear VPCs" \
    "aws ec2 describe-vpcs --profile ${PROFILE_PERSONAL} --region ${REGION}"
check "AlexUFV puede crear VPCs" \
    "aws ec2 describe-vpcs --profile ${PROFILE_UFV} --region ${REGION}"

echo ""
echo "[ IP Publica ]"
MY_IP=$(curl -s --max-time 5 https://checkip.amazonaws.com 2>/dev/null || echo "no detectada")
echo "  Tu IP publica actual: ${MY_IP}/32"

echo ""
echo "[ Jenkins ]"
check "Jenkins corriendo en localhost:8080" "curl -s -o /dev/null -w '%{http_code}' http://localhost:8080 | grep -qE '200|403'"

echo ""
echo "============================================"
echo " RESULTADO: ${PASS} OK  |  ${FAIL} FALLOS"
echo "============================================"

if [ $FAIL -gt 0 ]; then
    echo ""
    echo "⚠️  Hay ${FAIL} problema(s) que resolver antes de ejecutar el pipeline."
    echo "   Consulta el README.md para instrucciones de configuracion."
    exit 1
else
    echo ""
    echo "✅ Todo listo para ejecutar el pipeline!"
fi
