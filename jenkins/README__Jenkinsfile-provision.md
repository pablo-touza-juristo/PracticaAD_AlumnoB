# Jenkins Pipeline – Provisionar Entorno del Aplicativo con Ansible

![Jenkins](https://img.shields.io/badge/Jenkins-Pipeline-blue?logo=jenkins)
![Ansible](https://img.shields.io/badge/Ansible-Playbooks-red?logo=ansible)
![AWS](https://img.shields.io/badge/AWS-EC2-orange?logo=amazonaws)

## Descripción General

Este pipeline de Jenkins ejecuta **playbooks de Ansible** sobre el Entorno del Aplicativo desplegada en AWS (cuentas Personal y UFV). Permite seleccionar entre varios playbooks predefinidos, limitar la ejecución a hosts específicos, y activar modos de prueba (`dry-run`) y verbosidad.

Está diseñado para automatizar tareas de configuración de servidores, despliegue de aplicaciones, instalación de entornos Python, configuración de DNS y Active Directory, entre otras.

---

## Objetivos

- **Ejecutar playbooks Ansible** de forma controlada y parametrizada.
- **Actualizar el inventario dinámico** antes de cada ejecución.
- **Permitir limitar la ejecución** a un subconjunto de hosts.
- **Ofrecer modo *dry-run*** para simular cambios sin aplicarlos.
- **Proporcionar flexibilidad** mediante parámetros configurables (ruta de venv, paquetes, dominio AD, etc.).
- **Mostrar resultados** claros y facilitar la depuración con logs verbosos.

---

## Parámetros del Pipeline

| Parámetro | Tipo | Descripción |
|-----------|------|-------------|
| `PLAYBOOK` | `choice` | Playbook a ejecutar: `setup_ad_dns_ntp`, `setup_python_venv`, `configure_dns_clients`, `deploy_app`, `update_inventory`, `all`. |
| `LIMIT_HOSTS` | `string` | Limitar ejecución a hosts específicos (ej: `10.0.1.11`, `nginx`, `web_servers`). Vacío = todos los hosts del playbook. |
| `DRY_RUN` | `boolean` | Modo `--check`: simula cambios sin aplicarlos. |
| `VERBOSE` | `boolean` | Salida detallada (`-vv`). |
| `VENV_PATH` | `string` | Ruta donde se creará el virtualenv (solo para `setup_python_venv`). |
| `VENV_PACKAGES` | `string` | Paquetes pip a instalar en el venv, separados por comas (solo para `setup_python_venv`). |
| `AD_DOMAIN` | `string` | Nombre del dominio Active Directory (solo para `setup_ad_dns_ntp`). |

---

## Entorno y Variables

| Variable | Valor | Descripción |
|----------|-------|-------------|
| `ANSIBLE_DIR` | `/usr/local/ufv/ufv-infra/ansible` | Directorio raíz de Ansible. |
| `ANSIBLE_CFG` | `.../ansible/ansible.cfg` | Ruta al archivo de configuración de Ansible. |
| `INVENTORY` | `.../inventory/aws_inventory.sh` | Script de inventario dinámico. |
| `ANSIBLE_HOST_KEY_CHECKING` | `False` | Deshabilita verificación de host keys (entornos controlados). |
| `ANSIBLE_COLLECTIONS_PATHS` | (varias rutas) | Rutas donde buscar colecciones de Ansible. |
| `ANSIBLE_FORCE_COLOR` | `true` | Fuerza salida con colores en Ansible. |
| `TERM` | `xterm` | Terminal para soporte de colores. |

---

## Playbooks Disponibles

| Playbook | Descripción |
|----------|-------------|
| `setup_ad_dns_ntp` | Convierte un servidor (DC01) en Controlador de Dominio Active Directory, configura DNS y NTP. |
| `setup_python_venv` | Instala un entorno virtual de Python 3.12 en los servidores nginx con los paquetes especificados. |
| `configure_dns_clients` | Configura las instancias Linux para usar el DC01 como servidor DNS. |
| `deploy_app` | Despliega configuración de nginx, contenido web estático y un servicio Node.js (o Python). |
| `update_inventory` | Solo actualiza y muestra el inventario dinámico (sin aplicar cambios). |
| `all` | Ejecuta todos los playbooks anteriores en orden secuencial. |

---

## Flujo del Pipeline

### 1. Verificar entorno
- Muestra versión de Ansible.
- Imprime el playbook seleccionado, límite de hosts y modo dry-run.
- Asigna permisos de ejecución al script de inventario.
- Muestra el gráfico de inventario actual (`ansible-inventory --graph`).

### 2. Actualizar inventario
- Ejecuta `ansible-inventory --graph` nuevamente para confirmar que el inventario está actualizado.

### 3. Ejecutar playbook(s) seleccionado(s)
- Dependiendo del valor de `PLAYBOOK`, se ejecutan uno o varios stages:
  - **setup_ad_dns_ntp**: Pasa parámetros de dominio, netbios y contraseña de modo seguro.
  - **setup_python_venv**: Pasa ruta del venv y paquetes a instalar.
  - **deploy_app**: Ejecuta sin parámetros adicionales.
  - **configure_dns_clients**: Ejecuta sin parámetros adicionales.
  - **update_inventory**: Ejecuta playbook de actualización (solo muestra inventario).
  - **all**: Ejecuta los cinco playbooks en orden.

Cada stage aplica:
- `--limit` si `LIMIT_HOSTS` no está vacío.
- `--check` si `DRY_RUN = true`.
- Verbosidad (`-v` o `-vv`) según `VERBOSE`.

---

## Detalles de Ejecución

### Modo `all`
Si se selecciona `all`, los playbooks se ejecutan en este orden:
1. `setup_ad_dns_ntp`
2. `setup_python_venv`
3. `deploy_app`
4. `configure_dns_clients`
5. `update_inventory` (aunque este último solo muestra inventario)

### Parámetros Especiales
- **AD_DOMAIN**: Se usa en `setup_ad_dns_ntp`. Automáticamente se deriva el nombre NetBIOS (parte antes del primer punto en mayúsculas).
- **VENV_PATH** y **VENV_PACKAGES**: Solo aplican para `setup_python_venv`. Los paquetes se instalan mediante pip dentro del venv.
- **Contraseña de AD**: Actualmente está fijada en `Airbusds2026!` (debería parametrizarse en un entorno real).

---

## Uso

1. En Jenkins, selecciona el pipeline **Provisionar Infraestructura con Ansible**.
2. Configura los parámetros:
   - **PLAYBOOK**: Elige la tarea a ejecutar.
   - **LIMIT_HOSTS**: (opcional) Restringe a uno o varios hosts.
   - **DRY_RUN**: Activar para ver qué cambios se aplicarían sin realizarlos.
   - **VERBOSE**: Activar para obtener logs detallados.
   - **VENV_PATH**, **VENV_PACKAGES**, **AD_DOMAIN**: según corresponda.
3. Ejecuta el pipeline.

**Ejemplo de configuración típica:**
- `PLAYBOOK = setup_python_venv`
- `LIMIT_HOSTS = nginx_servers`
- `DRY_RUN = false`
- `VERBOSE = true`

---

## Consideraciones Importantes

- **Inventario dinámico**: El script `aws_inventory.sh` debe estar configurado correctamente y ser ejecutable.
- **Credenciales AWS**: Se asume que los perfiles `AlexPersonal` y `AlexUFV` están configurados en el nodo Jenkins.
- **Modo `--check`**: Ansible no aplicará cambios, pero puede haber efectos colaterales si los playbooks usan módulos que no soportan check mode (como `command` o `shell`).
- **Parámetros de AD**: La contraseña del modo seguro está hardcodeada; en entornos productivos se debe externalizar a variables de Jenkins o a Vault.
- **Colecciones de Ansible**: La variable `ANSIBLE_COLLECTIONS_PATHS` incluye rutas específicas; verificar que las colecciones requeridas estén instaladas.

---

## Resumen Ejecutivo

1. **Verificar entorno** – Versiones, límites, dry-run.
2. **Actualizar inventario** – Asegurar que la lista de hosts esté fresca.
3. **Ejecutar playbook(s)** – Según selección, con los parámetros adecuados.
4. **Mostrar resultado** – Éxito o fallo, con sugerencias de comandos manuales.

---

## Resultado Final

Al finalizar la ejecución, según el playbook elegido, habrás:

- Configurado Active Directory, DNS y NTP en DC01.
- Instalado un entorno virtual Python con paquetes en servidores específicos.
- Desplegado aplicaciones web con nginx y servicios backend.
- Configurado los clientes Linux para usar el DNS del dominio.
- Actualizado y verificado el inventario.

Todo ello con trazabilidad, logs y opción de simulación.

---

## Seguridad y Buenas Prácticas

- **Host key checking** deshabilitado por simplicidad en entornos controlados; en producción se recomienda mantenerlo activo.
- **Dry-run** permite validar cambios antes de aplicarlos.
- **Parámetros sensibles** (contraseñas) deberían gestionarse con Ansible Vault o credenciales de Jenkins.
- **Limitación de hosts** ayuda a evitar impactos no deseados en entornos grandes.

---

## Recursos Adicionales

- [Documentación de Ansible Playbooks](https://docs.ansible.com/ansible/latest/user_guide/playbooks.html)
- [Módulos de Ansible para Windows](https://docs.ansible.com/ansible/latest/collections/ansible/windows/)
- [Jenkins Pipeline Syntax](https://www.jenkins.io/doc/book/pipeline/syntax/)
- [Ansible Vault](https://docs.ansible.com/ansible/latest/user_guide/vault.html)

---

> **Nota:** Este pipeline está optimizado para el entorno de desarrollo/UFV. Ajusta las rutas, perfiles AWS y parámetros según tu configuración local.