#!/bin/bash
# =============================================================
# Inventario dinamico Ansible
# Usa IP PUBLICA para conectar (el portátil no está en la VPC)
# Grupos: linux_personal, linux_ufv, nginx, postgres, windows_personal
# =============================================================

REGION="eu-south-2"
PROFILE_PERSONAL="AlexPersonal"
PROFILE_UFV="AlexUFV"

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
        echo "[]" > "$outfile"
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
        --output json 2>/dev/null \
    | python3 -c "
import sys, json
data = json.load(sys.stdin)
result = [i for sub in data for i in sub]
print(json.dumps(result))
" > "$outfile" 2>/dev/null || echo "[]" > "$outfile"
}

get_instances "$PROFILE_PERSONAL" "10.0.0.0/16" "$TMPDIR_INV/personal.json"
get_instances "$PROFILE_UFV"      "10.1.0.0/16" "$TMPDIR_INV/ufv.json"

python3 - "$TMPDIR_INV/personal.json" "$TMPDIR_INV/ufv.json" << 'PYEOF'
import json, sys

with open(sys.argv[1]) as f:
    personal = json.load(f)

with open(sys.argv[2]) as f:
    ufv = json.load(f)

inventory = {
    "_meta": {"hostvars": {}},
    "all": {"children": ["linux", "windows_personal"]},
    "linux": {"children": ["linux_personal", "linux_ufv"]},
    "linux_personal":   {"hosts": []},
    "linux_ufv":        {"hosts": []},
    "windows_personal": {"hosts": []},
    "nginx":            {"hosts": []},
    "postgres":         {"hosts": []}
}

def linux_vars(private_ip, public_ip, name, account):
    # Usamos la IP publica para conectar desde el portatil
    # Si no hay IP publica usamos la privada como fallback
    connect_ip = public_ip if public_ip else private_ip
    return {
        "ansible_host": connect_ip,
        "ansible_user": "ansible",
        "ansible_password": "Airbusds2026",
        "ansible_become": True,
        "ansible_become_method": "sudo",
        "ansible_become_pass": "",
        "ansible_ssh_common_args": "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null",
        "private_ip": private_ip,
        "public_ip": public_ip or "",
        "instance_name": name,
        "account": account
    }

def windows_vars(private_ip, public_ip, name):
    connect_ip = public_ip if public_ip else private_ip
    return {
        "ansible_host": connect_ip,
        "ansible_user": "ansible",
        "ansible_password": "Airbusds2026",
        "ansible_connection": "winrm",
        "ansible_winrm_transport": "basic",
        "ansible_winrm_server_cert_validation": "ignore",
        "ansible_port": 5985,
        "ansible_become": False,
        "private_ip": private_ip,
        "public_ip": public_ip or "",
        "instance_name": name,
        "account": "AlexPersonal"
    }

for inst in personal:
    priv = inst.get("private_ip") or ""
    pub  = inst.get("public_ip") or ""
    name = inst.get("name") or ""
    plat = (inst.get("platform") or "").lower()
    if not priv:
        continue
    # Usamos la IP privada como clave del inventario (identificador unico)
    key = priv
    if plat == "windows":
        inventory["windows_personal"]["hosts"].append(key)
        inventory["_meta"]["hostvars"][key] = windows_vars(priv, pub, name)
    else:
        inventory["linux_personal"]["hosts"].append(key)
        inventory["_meta"]["hostvars"][key] = linux_vars(priv, pub, name, "AlexPersonal")
        if "nginx"    in name.lower(): inventory["nginx"]["hosts"].append(key)
        if "postgres" in name.lower(): inventory["postgres"]["hosts"].append(key)

for inst in ufv:
    priv = inst.get("private_ip") or ""
    pub  = inst.get("public_ip") or ""
    name = inst.get("name") or ""
    if not priv:
        continue
    key = priv
    inventory["linux_ufv"]["hosts"].append(key)
    inventory["nginx"]["hosts"].append(key)
    inventory["_meta"]["hostvars"][key] = linux_vars(priv, pub, name, "AlexUFV")

print(json.dumps(inventory, indent=2))
PYEOF
