#!/bin/bash
# =============================================================
# Inventario dinamico Ansible (Alumno B)
# Usa IP PUBLICA para conectar (el portatil no esta en la VPC)
# Grupos: linux, nginx, postgres
# =============================================================

REGION="eu-south-2"
PROFILE_PERSONAL="AlumnoB"
TMPDIR_INV=$(mktemp -d)

trap "rm -rf $TMPDIR_INV" EXIT

get_instances() {
    local profile=$1
    local vpc_cidr=$2
    local outfile=$3

    local vpc_id
    vpc_id=$(aws ec2 describe-vpcs \
        --profile "$profile" --region "$REGION" \
        --filters "Name=cidr,Values=${vpc_cidr}" "Name=isDefault,Values=false" \
        --query 'Vpcs[0].VpcId' --output text 2>/dev/null)

    if [ -z "$vpc_id" ] || [ "$vpc_id" = "None" ] || [ "$vpc_id" = "null" ]; then
        echo "[]" >"$outfile"
        return
    fi

    # Recogemos IP privada, IP publica, nombre, plataforma
    aws ec2 describe-instances \
        --profile "$profile" \
        --region "$REGION" \
        --filters \
        "Name=vpc-id,Values=${vpc_id}" \
        "Name=instance-state-name,Values=running" \
        --query 'Reservations[*].Instances[*].{
            private_ip:PrivateIpAddress,
            public_ip:PublicIpAddress,
            name:Tags[?Key==`Name`]|[0].Value,
            platform:Platform}' \
        --output json 2>/dev/null |
        python3 -c "
import sys, json
data = json.load(sys.stdin)
result = [i for sub in data for i in sub]
print(json.dumps(result))
" >"$outfile" 2>/dev/null || echo "[]" >"$outfile"
}

# Solo recogemos los datos de la red del Alumno B (CORREGIDO AL CIDR 10.8.0.0/16)
get_instances "$PROFILE_PERSONAL" "10.8.0.0/16" "$TMPDIR_INV/personal.json"

python3 - "$TMPDIR_INV/personal.json" <<'PYEOF'
import json, sys

with open(sys.argv[1]) as f:
    personal = json.load(f)

# Inventario simplificado
inventory = {
    "_meta": {"hostvars": {}},
    "all": {"children": ["linux_personal"]},
    "linux_personal": {"hosts": []},
    "nginx": {"hosts": []},
    "postgres": {"hosts": []}
}
def linux_vars(private_ip, public_ip, name, account):
    # Usamos la IP publica para conectar desde el portatil
    connect_ip = public_ip if public_ip else private_ip
    return {
        "ansible_host": connect_ip,
        "ansible_user": "ec2-user",  # Asegúrate de que este usuario existe en tu AMI, si no, usa "ec2-user"
        "ansible_ssh_private_key_file": "/home/pablo/.ssh/llave-B.pem", # <--- LA CLAVE PARA ENTRAR
        "ansible_become": True,
        "ansible_become_method": "sudo",
        "ansible_ssh_common_args": "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null",
        "private_ip": private_ip,
        "public_ip": public_ip or "",
        "instance_name": name,
        "account": account
    }
for inst in personal:
    priv = inst.get("private_ip") or ""
    pub  = inst.get("public_ip") or ""
    name = inst.get("name") or ""
    
    if not priv:
        continue
        
    # Usamos la IP privada como clave del inventario (identificador unico)
    key = priv
    
    inventory["linux_personal"]["hosts"].append(key)
    inventory["_meta"]["hostvars"][key] = linux_vars(priv, pub, name, "AlumnoB")
    
    if "nginx"    in name.lower(): inventory["nginx"]["hosts"].append(key)
    if "postgres" in name.lower(): inventory["postgres"]["hosts"].append(key)

print(json.dumps(inventory, indent=2))
PYEOF
