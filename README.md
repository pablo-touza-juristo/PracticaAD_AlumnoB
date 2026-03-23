# ufv-infra — Infraestructura AWS Multi-Cuenta + Ansible

Proyecto unificado para desplegar y gestionar infraestructura AWS en dos cuentas
(`AlexPersonal` y `AlexUFV`) con VPC Peering cross-account, y automatizar la
configuración y despliegue de la aplicación académica con Ansible desde Jenkins.

---

## Arquitectura

```
Internet
    │
    ▼
AlexPersonal (10.0.0.0/16)              AlexUFV (10.1.0.0/16)
┌────────────────────────────┐          ┌────────────────────────────┐
│  10.0.1.10  PostgreSQL     │          │  10.1.1.10  Nginx + Node   │
│  10.0.1.11  Nginx (LB)     │◄────────►│  10.1.1.11  Nginx + Node   │
│  10.0.1.12  Windows DC01   │  Peering │                            │
│             AD+DNS+NTP     │          │                            │
└────────────────────────────┘          └────────────────────────────┘

Región:      eu-south-2
AMI Linux:   ami-073422177b6b3ed22  (Amazon Linux 2023)
AMI Windows: ami-0349104b138bf332c  (Windows Server 2019)
```

**Flujo de peticiones:**
```
Usuario → 10.0.1.11 (Nginx LB Personal)
               ├── /static/*         → /var/www/public   (ficheros estáticos)
               ├── /                 → index.html
               └── /profesores/*     → 10.1.1.10:3001 / 10.1.1.11:3001 (Node.js)

Instancias UFV → 10.1.1.10 y 10.1.1.11
               ├── Nginx (puerto 80) → proxy a Node.js local (3001)
               └── ufvNodeService    → Node.js (profesores.js, puerto 3001)
                                          └── PostgreSQL 10.0.1.10:5432
```

**Security Groups — simplificados para el lab:**

| Origen | Destino | Regla |
|---|---|---|
| Mi IP (Jenkins) | Todos | Todo el tráfico (-1) |
| 10.1.0.0/16 | AlexPersonal Linux | Todo el tráfico (-1) |
| 10.0.0.0/16 | AlexUFV | Todo el tráfico (-1) |
| 0.0.0.0/0 | Linux (HTTP) | TCP 80 |
| 0.0.0.0/0 | Windows (WinRM) | TCP 5985/5986 |

---

## Estructura del proyecto

```
ufv-infra/
├── cloudformation/
│   ├── stack-personal.yaml     # VPC + 2 EC2 Linux + EC2 Windows (AlexPersonal)
│   └── stack-ufv.yaml          # VPC + 2 EC2 Linux (AlexUFV)
│
├── jenkins/
│   ├── Jenkinsfile-infra        # Pipeline CloudFormation + VPC Peering
│   ├── Jenkinsfile-inventory    # Pipeline inventario Ansible
│   ├── Jenkinsfile-provision    # Pipeline playbooks Ansible (AD, venv, DNS, deploy)
│   └── Jenkinsfile-webdeploy    # Pipeline actualización web + Node.js
│
├── ansible/
│   ├── ansible.cfg
│   ├── requirements.yml
│   ├── inventory/
│   │   └── aws_inventory.sh     # Inventario dinámico (consulta AWS en tiempo real)
│   ├── playbooks/
│   │   ├── update_inventory.yml       # Ping + facts + reporte de estado
│   │   ├── setup_ad_dns_ntp.yml       # Convierte DC01 en AD + DNS + NTP
│   │   ├── setup_python_venv.yml      # Instala venv Python 3.12 en nginx
│   │   ├── configure_dns_clients.yml  # Configura DNS en Linux para usar DC01
│   │   ├── deploy_app.yml             # Despliegue inicial completo (nginx + Node.js)
│   │   └── update_web.yml             # Actualización de contenido web + Node.js
│   └── roles/
│       ├── ad_setup/            # Rol: AD DS, DNS, NTP en Windows
│       └── python_venv/         # Rol: virtualenv Python 3.12
│
├── ufv-app/                     # Código y assets de la aplicación
│   ├── nginx/
│   │   ├── AlexPersonal_nginx.conf   # Config nginx load balancer
│   │   └── AlexUFV_nginx.conf        # Config nginx proxy Node.js
│   ├── node/
│   │   ├── package.json              # Dependencias Node.js
│   │   └── profesores.js             # API REST gestión de asignaturas (puerto 3001)
│   └── public/
│       ├── index.html                # Portal de entrada
│       ├── css/style.css
│       └── img/logo.png
│
└── scripts/
    ├── setup-all-jobs.sh        # Crea los 4 jobs en Jenkins (ejecutar 1 vez)
    ├── setup-jenkins-job.sh     # Crea solo el job de CloudFormation
    └── check-prerequisites.sh  # Verifica AWS CLI, perfiles, AMIs, etc.
```

---

## Prerrequisitos

### 1. Perfiles AWS CLI

```ini
# ~/.aws/credentials
[AlexPersonal]
aws_access_key_id     = AKIA...
aws_secret_access_key = ...

[AlexUFV]
aws_access_key_id     = AKIA...
aws_secret_access_key = ...

# ~/.aws/config
[profile AlexPersonal]
region = eu-south-2

[profile AlexUFV]
region = eu-south-2
```

### 2. Key Pairs en AWS

```bash
aws ec2 create-key-pair --key-name aws \
  --profile AlexPersonal --region eu-south-2 \
  --query 'KeyMaterial' --output text > ~/.ssh/aws.pem && chmod 400 ~/.ssh/aws.pem

aws ec2 create-key-pair --key-name aws_ufv \
  --profile AlexUFV --region eu-south-2 \
  --query 'KeyMaterial' --output text > ~/.ssh/aws_ufv.pem && chmod 400 ~/.ssh/aws_ufv.pem
```

### 3. Colecciones Ansible y dependencias

```bash
source /usr/local/ufv/ansible_venv/bin/activate
ansible-galaxy collection install -r /usr/local/ufv/ufv-infra/ansible/requirements.yml
ansible-galaxy collection install microsoft.ad
pip install pywinrm --break-system-packages
```

---

## Instalación y puesta en marcha

### Paso 1 — Copiar el proyecto

```bash
cp -r ufv-infra /usr/local/ufv/
chmod +x /usr/local/ufv/ufv-infra/scripts/*.sh
chmod +x /usr/local/ufv/ufv-infra/ansible/inventory/aws_inventory.sh
```

### Paso 2 — Verificar prerrequisitos

```bash
/usr/local/ufv/ufv-infra/scripts/check-prerequisites.sh
```

### Paso 3 — Crear los 4 jobs en Jenkins (una sola vez)

```bash
cd /usr/local/ufv/ufv-infra
JENKINS_USER=admin JENKINS_PASS=Airbusds2026 ./scripts/setup-all-jobs.sh
```

---

## Jobs de Jenkins

### 1. `AWS-UFV-CloudFormation-Deploy` — Infraestructura AWS

Despliega / destruye toda la infraestructura con CloudFormation y configura el VPC Peering cross-account.

| Parámetro | Default | Descripción |
|---|---|---|
| `KEY_PAIR_PERSONAL` | `aws` | Key Pair en AlexPersonal |
| `KEY_PAIR_UFV` | `aws_ufv` | Key Pair en AlexUFV |
| `AMI_LINUX` | `ami-073422177b6b3ed22` | AMI Amazon Linux 2023 |
| `AMI_WINDOWS` | `ami-0349104b138bf332c` | AMI Windows Server 2019 |
| `AWS_REGION` | `eu-south-2` | Región AWS |
| `ACTION` | `deploy` | `deploy` o `destroy` |

**Orden de ejecución:** VPC UFV → VPC Personal + Peering request → Accept Peering → Rutas retorno → Summary

---

### 2. `AWS-UFV-Ansible-Inventory-Build` — Inventario dinámico

Consulta AWS en tiempo real, verifica conectividad de todos los hosts y genera un snapshot del inventario.

| Parámetro | Default | Descripción |
|---|---|---|
| `VERIFY_CONNECTIVITY` | `true` | Ping a todos los hosts |
| `SHOW_FACTS` | `false` | Recoger facts completos (más lento) |

---

### 3. `AWS-UFV-Ansible-App-Deploy` — Provisionar infraestructura

Ejecuta playbooks de configuración sobre los servidores.

| Parámetro | Default | Descripción |
|---|---|---|
| `PLAYBOOK` | — | Playbook a ejecutar (ver tabla abajo) |
| `LIMIT_HOSTS` | `` | Limitar a hosts específicos (ej: `10.0.1.11`) |
| `DRY_RUN` | `false` | Simular sin aplicar cambios |
| `VERBOSE` | `false` | Salida `-vv` |
| `VENV_PATH` | `/opt/venv/app` | Ruta del virtualenv |
| `AD_DOMAIN` | `corp.ufv.local` | Dominio AD |

**Opciones de PLAYBOOK:**

| Valor | Acción |
|---|---|
| `setup_ad_dns_ntp` | Convierte DC01 en AD + DNS + NTP |
| `setup_python_venv` | Instala venv Python 3.12 en todos los nginx |
| `configure_dns_clients` | Configura Linux para usar DC01 como DNS |
| `deploy_app` | Despliegue inicial: nginx config + web + Node.js service |
| `update_inventory` | Solo actualiza y muestra inventario |
| `all` | Ejecuta todos en orden |

---

### 4. `AWS-UFV-Ansible-Web-Deploy` — Actualizar aplicación web

Actualiza el contenido estático y el código Node.js sin tocar la infraestructura.

| Parámetro | Default | Descripción |
|---|---|---|
| `DRY_RUN` | `false` | Simular sin aplicar |
| `VERBOSE` | `false` | Salida `-vv` |
| `LIMIT_HOSTS` | `` | Limitar a hosts específicos |

**Qué hace en cada grupo:**

| Grupo | Acciones |
|---|---|
| `linux_personal` (10.0.1.11) | Sincroniza `public/` → `/var/www/public` + reinicia nginx |
| `linux_ufv` (10.1.1.10, 10.1.1.11) | Sincroniza `public/` + reinicia nginx + actualiza `profesores.js` + reinicia `ufvNodeService` |

---

## Inventario dinámico

El script `ansible/inventory/aws_inventory.sh` consulta AWS en tiempo real usando los perfiles `AlexPersonal` y `AlexUFV`, y genera los grupos:

| Grupo | Hosts | ansible_host |
|---|---|---|
| `linux_personal` | 10.0.1.10, 10.0.1.11 | IP pública |
| `linux_ufv` | 10.1.1.10, 10.1.1.11 | IP pública |
| `windows_personal` | 10.0.1.12 (DC01) | IP pública |
| `nginx` | 10.0.1.11, 10.1.1.10, 10.1.1.11 | IP pública |
| `postgres` | 10.0.1.10 | IP pública |

**Credenciales Ansible:**
- **Linux:** usuario `ansible`, password `Airbusds2026`, sudo sin contraseña
- **Windows:** usuario `ansible`, password `Airbusds2026`, WinRM básico puerto 5985

---

## Base de datos PostgreSQL (10.0.1.10)

| Rol | Usuario | Password | Base de datos | Uso |
|---|---|---|---|---|
| Aplicación | `backend` | `ContraseñaSegura123` | `academico` | Conexión desde Node.js |
| Administración | `postgres` | `postgres123` | `*` | Solo mantenimiento |

**Esquema `academico`:**
```
academico
├── asignaturas     (id, nombre, descripcion, creditos, fecha_creacion)
├── alumnos         (id, nombre, email, fecha_registro)
├── inscripciones   (id, alumno_id→alumnos, asignatura_id→asignaturas, nota)
├── practicas       (id, asignatura_id→asignaturas, titulo, descripcion, fecha_limite)
└── entregas        (id, practica_id→practicas, alumno_id→alumnos, calificacion, comentario)
```

```bash
# Conectar como aplicación
psql -h 10.0.1.10 -U backend -d academico

# Listar tablas
psql -h 10.0.1.10 -U backend -d academico -c "\dt academico.*"
```

---

## Uso manual de Ansible (sin Jenkins)

```bash
cd /usr/local/ufv/ufv-infra

# Ver inventario completo
ansible-inventory -i ansible/inventory/aws_inventory.sh --graph

# Ping a todos los Linux
ansible linux -i ansible/inventory/aws_inventory.sh -m ping

# Ping a Windows
ansible windows_personal -i ansible/inventory/aws_inventory.sh -m ansible.windows.win_ping

# Despliegue inicial completo
ansible-playbook -i ansible/inventory/aws_inventory.sh ansible/playbooks/deploy_app.yml -v

# Actualizar solo la web
ansible-playbook -i ansible/inventory/aws_inventory.sh ansible/playbooks/update_web.yml -v

# Actualizar solo en un host
ansible-playbook -i ansible/inventory/aws_inventory.sh ansible/playbooks/update_web.yml \
  --limit 10.1.1.10 -v
```

---

## Orden de ejecución recomendado (primer despliegue)

```
1. AWS-UFV-CloudFormation-Deploy   (ACTION=deploy)
2. AWS-UFV-Ansible-Inventory-Build (verificar que los 5 hosts responden)
3. AWS-UFV-Ansible-App-Deploy      (PLAYBOOK=setup_ad_dns_ntp)
4. AWS-UFV-Ansible-App-Deploy      (PLAYBOOK=configure_dns_clients)
5. AWS-UFV-Ansible-App-Deploy      (PLAYBOOK=setup_python_venv)
6. AWS-UFV-Ansible-App-Deploy      (PLAYBOOK=deploy_app)
```

Para actualizaciones posteriores de la web: solo lanzar `AWS-UFV-Ansible-Web-Deploy`.

---

## Solución de problemas

### Stack en ROLLBACK
```bash
aws cloudformation delete-stack --stack-name stack-personal \
  --profile AlexPersonal --region eu-south-2
aws cloudformation wait stack-delete-complete --stack-name stack-personal \
  --profile AlexPersonal --region eu-south-2
```

### Ver logs del UserData en la instancia
```bash
sudo cat /var/log/userdata.log
```

### Ansible no conecta a Linux
```bash
ssh -o StrictHostKeyChecking=no ansible@<IP_PUBLICA>
# password: Airbusds2026
```

### Ansible no conecta a Windows (WinRM)
```bash
# Reconectar por RDP y ejecutar en PowerShell como Administrador:
Set-WSManQuickConfig -Force
winrm set winrm/config/service '@{AllowUnencrypted="true"}'
winrm set winrm/config/service/auth '@{Basic="true"}'
New-NetFirewallRule -Name "WinRM-HTTP-5985" -Protocol TCP -LocalPort 5985 -Action Allow -Direction Inbound
Set-Service winrm -StartupType Automatic
Start-Service winrm
```

### Verificar servicio Node.js en UFV
```bash
ssh ansible@<IP_PUBLICA_UFV>
sudo systemctl status ufvNodeService
sudo journalctl -u ufvNodeService -n 50
```

### VPC Peering no conecta (verificar rutas)
```bash
aws ec2 describe-route-tables --profile AlexPersonal --region eu-south-2 \
  --filters "Name=vpc-id,Values=<vpc-id>" \
  --query 'RouteTables[*].Routes[*].[DestinationCidrBlock,VpcPeeringConnectionId,State]' \
  --output table
```

### Verificar PostgreSQL
```bash
psql -h 10.0.1.10 -U backend -d academico
\dt academico.*
sudo cat /var/log/userdata.log
```
