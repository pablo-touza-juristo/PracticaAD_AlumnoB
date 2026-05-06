#!/bin/bash
# =============================================================
# setup-all-jobs.sh
# Crea los 4 jobs de Jenkins del proyecto ufv-infra
# =============================================================

set -e

JENKINS_URL="${JENKINS_URL:-http://localhost:8080}"
JENKINS_USER="${JENKINS_USER:-admin}"
JENKINS_PASS="${JENKINS_PASS:-admin}"
BASE_DIR="/usr/local/ufv/ufv-infra"

echo "============================================"
echo " Configurando todos los jobs Jenkins"
echo " Jenkins URL: ${JENKINS_URL}"
echo " Base dir:    ${BASE_DIR}"
echo "============================================"

# Obtener crumb y cookie con curl (fiable)
echo "Obteniendo crumb CSRF..."
CRUMB_RESPONSE=$(curl -s \
    -u "${JENKINS_USER}:${JENKINS_PASS}" \
    -c /tmp/jenkins_setup_cookies.txt \
    "${JENKINS_URL}/crumbIssuer/api/json")

CRUMB_FIELD=$(echo "$CRUMB_RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['crumbRequestField'])" 2>/dev/null)
CRUMB_VALUE=$(echo "$CRUMB_RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['crumb'])" 2>/dev/null)

if [ -z "$CRUMB_FIELD" ] || [ -z "$CRUMB_VALUE" ]; then
    echo "❌ No se pudo obtener crumb"
    echo "   Respuesta: $CRUMB_RESPONSE"
    exit 1
fi

# Extraer JSESSIONID de la cookie
SESSION_COOKIE=$(grep JSESSIONID /tmp/jenkins_setup_cookies.txt | awk '{print "JSESSIONID="$NF}' | head -1)
echo "   Crumb OK (${CRUMB_FIELD}: ${CRUMB_VALUE:0:16}...)"

create_job() {
    local job_name=$1
    local jenkinsfile=$2

    echo ""
    echo "--- Job: ${job_name} ---"

    if [ ! -f "$jenkinsfile" ]; then
        echo "❌ Jenkinsfile no encontrado: ${jenkinsfile}"
        return 1
    fi

    # Construir XML con Python (escapa correctamente el contenido)
    local xml_file="/tmp/jenkins_job_${job_name// /_}.xml"
    python3 - "$jenkinsfile" "$job_name" "$xml_file" << 'PYEOF'
import sys

jenkinsfile = sys.argv[1]
job_name    = sys.argv[2]
out_file    = sys.argv[3]

with open(jenkinsfile, "r", encoding="utf-8") as f:
    script = f.read()

# Escapar ]]> para que no cierre el bloque CDATA
script = script.replace("]]>", "]]]]><![CDATA[>")

xml = """<?xml version='1.1' encoding='UTF-8'?>
<flow-definition plugin="workflow-job">
  <description>{name}</description>
  <keepDependencies>false</keepDependencies>
  <properties/>
  <definition class="org.jenkinsci.plugins.workflow.cps.CpsFlowDefinition" plugin="workflow-cps">
    <script><![CDATA[
{script}
]]></script>
    <sandbox>true</sandbox>
  </definition>
  <disabled>false</disabled>
</flow-definition>""".format(name=job_name, script=script)

with open(out_file, "w", encoding="utf-8") as f:
    f.write(xml)
PYEOF

    # Comprobar si el job existe
    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" \
        -u "${JENKINS_USER}:${JENKINS_PASS}" \
        "${JENKINS_URL}/job/${job_name}/api/json")

    local url http_code
    if [ "$status" = "200" ]; then
        echo "   Actualizando job existente..."
        url="${JENKINS_URL}/job/${job_name}/config.xml"
    else
        echo "   Creando nuevo job..."
        url="${JENKINS_URL}/createItem?name=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${job_name}'))")"
    fi

    http_code=$(curl -s -o /tmp/jenkins_response.txt -w "%{http_code}" \
        -u "${JENKINS_USER}:${JENKINS_PASS}" \
        -b /tmp/jenkins_setup_cookies.txt \
        -H "${CRUMB_FIELD}: ${CRUMB_VALUE}" \
        -H "Content-Type: application/xml; charset=utf-8" \
        -X POST \
        --data-binary "@${xml_file}" \
        "$url")

    if [ "$http_code" = "200" ] || [ "$http_code" = "201" ]; then
        echo "   ✅ OK → ${JENKINS_URL}/job/${job_name}/"
    else
        echo "   ❌ HTTP ${http_code}"
        grep -i "message\|error\|exception" /tmp/jenkins_response.txt | head -3 || true
    fi

    rm -f "$xml_file"
}

create_job "AWS-UFV-CloudFormation-Deploy"    "${BASE_DIR}/jenkins/Jenkinsfile-infra"
create_job "AWS-UFV-Ansible-Inventory-Build"  "${BASE_DIR}/jenkins/Jenkinsfile-inventory"
create_job "AWS-UFV-Ansible-App-Deploy"       "${BASE_DIR}/jenkins/Jenkinsfile-provision"
create_job "AWS-UFV-Ansible-Web-Deploy"       "${BASE_DIR}/jenkins/Jenkinsfile-webdeploy"
create_job "AWS-UFV-DB-Backup-Restore"          "${BASE_DIR}/jenkins/Jenkinsfile-dbbackup"

echo ""
echo "============================================"
echo " ✅ Setup completado. Jobs disponibles:"
echo ""
echo " 1. CloudFormation + VPC Peering:"
echo "    ${JENKINS_URL}/job/AWS-UFV-CloudFormation-Deploy/"
echo ""
echo " 2. Actualizar inventario Ansible:"
echo "    ${JENKINS_URL}/job/AWS-UFV-Ansible-Inventory-Build/"
echo ""
echo " 3. Provisionar infraestructura:"
echo "    ${JENKINS_URL}/job/AWS-UFV-Ansible-App-Deploy/"
echo ""
echo " 4. Actualizar web y Node.js:"
echo "    ${JENKINS_URL}/job/AWS-UFV-Ansible-Web-Deploy/"
echo "============================================"
