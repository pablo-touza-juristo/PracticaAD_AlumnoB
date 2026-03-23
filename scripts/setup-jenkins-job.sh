#!/bin/bash
# =============================================================
#  setup-jenkins-job.sh
#  Configura el job de Jenkins para el pipeline AWS
#  Ejecutar una sola vez desde tu portatil
# =============================================================

set -e

JENKINS_URL="${JENKINS_URL:-http://localhost:8080}"
JENKINS_USER="${JENKINS_USER:-admin}"
JENKINS_PASS="${JENKINS_PASS:-admin}"
JOB_NAME="aws-multi-account-deploy"

echo "============================================"
echo " Configurando Jenkins Job: ${JOB_NAME}"
echo " Jenkins URL: ${JENKINS_URL}"
echo "============================================"

# Verificar que Jenkins esta disponible
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "${JENKINS_URL}")
if [ "$HTTP_STATUS" != "200" ] && [ "$HTTP_STATUS" != "403" ]; then
    echo "❌ Jenkins no responde en ${JENKINS_URL} (HTTP $HTTP_STATUS)"
    exit 1
fi
echo "Jenkins accesible (HTTP $HTTP_STATUS)"

# Obtener crumb CSRF guardando la cookie de sesion
echo "Obteniendo crumb CSRF..."
CRUMB_JSON=$(curl -s \
    -u "${JENKINS_USER}:${JENKINS_PASS}" \
    -c /tmp/jenkins_cookies.txt \
    "${JENKINS_URL}/crumbIssuer/api/json")

CRUMB_FIELD=$(echo "$CRUMB_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['crumbRequestField'])" 2>/dev/null || echo "")
CRUMB_VALUE=$(echo "$CRUMB_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['crumb'])" 2>/dev/null || echo "")

if [ -z "$CRUMB_FIELD" ] || [ -z "$CRUMB_VALUE" ]; then
    echo "❌ No se pudo obtener el crumb CSRF."
    echo "   Respuesta: $CRUMB_JSON"
    exit 1
fi
echo "   Crumb obtenido (${CRUMB_FIELD})"

# Funcion auxiliar curl con auth + crumb + cookie
jenkins_curl() {
    curl -s \
        -u "${JENKINS_USER}:${JENKINS_PASS}" \
        -b /tmp/jenkins_cookies.txt \
        -H "${CRUMB_FIELD}: ${CRUMB_VALUE}" \
        "$@"
}

# Ruta absoluta al Jenkinsfile — debe ser accesible por el usuario jenkins
WORKSPACE_PATH="$(pwd)"
JENKINSFILE_PATH="${WORKSPACE_PATH}/jenkins/Jenkinsfile"

echo "   Workspace: ${WORKSPACE_PATH}"
echo "   Jenkinsfile: ${JENKINSFILE_PATH}"

# Verificar que el Jenkinsfile existe
if [ ! -f "$JENKINSFILE_PATH" ]; then
    echo "❌ No se encuentra el Jenkinsfile en: ${JENKINSFILE_PATH}"
    echo "   Asegurate de ejecutar este script desde la raiz del proyecto."
    exit 1
fi

# Leer el contenido del Jenkinsfile y escaparlo para meterlo en XML
# Se usa CDATA para evitar problemas con caracteres especiales
JENKINSFILE_CONTENT=$(cat "$JENKINSFILE_PATH")

# Construir el XML con el pipeline embebido (no depende de ningun plugin SCM)
JOB_CONFIG=$(cat << XMLEOF
<?xml version='1.1' encoding='UTF-8'?>
<flow-definition plugin="workflow-job">
  <description>Pipeline despliegue multi-cuenta AWS (AlexPersonal + AlexUFV) con VPC Peering</description>
  <keepDependencies>false</keepDependencies>
  <properties>
  </properties>
  <definition class="org.jenkinsci.plugins.workflow.cps.CpsFlowDefinition" plugin="workflow-cps">
    <script><![CDATA[
$(cat "$JENKINSFILE_PATH")
]]></script>
    <sandbox>true</sandbox>
  </definition>
  <disabled>false</disabled>
</flow-definition>
XMLEOF
)

# Comprobar si el job ya existe
EXISTING=$(jenkins_curl -o /dev/null -w "%{http_code}" \
    "${JENKINS_URL}/job/${JOB_NAME}/api/json")

if [ "$EXISTING" = "200" ]; then
    echo "Job ya existe, actualizando..."
    HTTP_CODE=$(jenkins_curl \
        -o /tmp/jenkins_output.txt \
        -w "%{http_code}" \
        -X POST \
        -H "Content-Type: application/xml" \
        --data-binary "$JOB_CONFIG" \
        "${JENKINS_URL}/job/${JOB_NAME}/config.xml")
else
    echo "Creando nuevo job..."
    HTTP_CODE=$(jenkins_curl \
        -o /tmp/jenkins_output.txt \
        -w "%{http_code}" \
        -X POST \
        -H "Content-Type: application/xml" \
        --data-binary "$JOB_CONFIG" \
        "${JENKINS_URL}/createItem?name=${JOB_NAME}")
fi

if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
    echo "✅ Job '${JOB_NAME}' configurado correctamente"
else
    echo "❌ HTTP $HTTP_CODE al configurar el job"
    cat /tmp/jenkins_output.txt
    exit 1
fi

echo ""
echo "============================================"
echo " ✅ Listo! Accede al pipeline en:"
echo " ${JENKINS_URL}/job/${JOB_NAME}/"
echo ""
echo " Usa 'Build with Parameters' para lanzarlo."
echo "============================================"
