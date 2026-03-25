# Jenkins Pipeline – Actualizar Inventario Ansible

![Jenkins](https://img.shields.io/badge/Jenkins-Pipeline-blue?logo=jenkins)
![Ansible](https://img.shields.io/badge/Ansible-Dynamic%20Inventory-red?logo=ansible)
![AWS](https://img.shields.io/badge/AWS-EC2-orange?logo=amazonaws)

## Descripción General

Este pipeline de Jenkins automatiza la **actualización del inventario dinámico de Ansible** basado en AWS, y opcionalmente verifica la conectividad con los hosts y recopila *facts* del sistema. Está diseñado para entornos con múltiples cuentas AWS (Personal y UFV) y diferentes tipos de hosts (Linux y Windows).

El pipeline ejecuta el script de inventario dinámico, valida su salida, y puede realizar pruebas de conectividad (`ping`) y recolección de *facts* utilizando Ansible. Finalmente, guarda una instantánea del inventario como artefacto.

---

## Objetivos

- **Refrescar el inventario dinámico** de Ansible a partir de instancias EC2 en AWS.
- **Validar la estructura** del inventario generado.
- **Verificar conectividad** con los hosts (Linux y Windows) de manera paralela.
- **Recopilar *facts*** de los hosts para su análisis (opcional).
- **Archivar una instantánea** del inventario para su trazabilidad.

---

## Parámetros del Pipeline

| Parámetro | Tipo | Descripción |
|-----------|------|-------------|
| `VERIFY_CONNECTIVITY` | `boolean` | Si es `true`, realiza pings a todos los hosts después de actualizar el inventario. |
| `SHOW_FACTS` | `boolean` | Si es `true`, ejecuta un playbook que recopila *facts* de los hosts (más lento). |

---

## 🔧 Entorno y Variables

| Variable | Valor | Descripción |
|----------|-------|-------------|
| `ANSIBLE_DIR` | `/usr/local/ufv/ufv-infra/ansible` | Directorio raíz de Ansible. |
| `ANSIBLE_CFG` | `.../ansible/ansible.cfg` | Ruta al archivo de configuración de Ansible. |
| `INVENTORY` | `.../inventory/aws_inventory.sh` | Script de inventario dinámico. |
| `ANSIBLE_FORCE_COLOR` | `true` | Fuerza salida con colores en Ansible. |
| `TERM` | `xterm` | Terminal para soporte de colores. |

> **Nota:** Los perfiles AWS utilizados son `AlexPersonal` y `AlexUFV`, configurados en las credenciales del nodo Jenkins. La región por defecto es `eu-south-2`.

---

## Flujo del Pipeline

### 1. Verificar entorno Ansible
- Muestra versiones de Ansible, Python y AWS CLI.
- Verifica las credenciales de AWS para ambos perfiles (`AlexPersonal` y `AlexUFV`).
- Confirma que se puede llamar a `aws sts get-caller-identity`.

### 2. Generar inventario dinámico
- Asigna permisos de ejecución al script `aws_inventory.sh`.
- Ejecuta el script para mostrar el inventario **raw** (salida JSON).
- Valida que el script devuelva una estructura válida.

### 3. Validar inventario con Ansible
- Utiliza `ansible-inventory --list --yaml` para ver el inventario en formato legible.
- Muestra las primeras 80 líneas para una revisión rápida.

### 4. Mostrar grupos del inventario
- Ejecuta `ansible-inventory --graph` para visualizar la jerarquía de grupos y hosts.
- Útil para ver rápidamente qué hosts pertenecen a cada grupo.

### 5. Verificar conectividad (paralelo)
- *Solo si `VERIFY_CONNECTIVITY = true`.*
- Se ejecutan en **paralelo** tres pruebas:
  - **Ping Linux Personal** – `ansible linux_personal -m ping`
  - **Ping Linux UFV** – `ansible linux_ufv -m ping`
  - **Ping Windows** – `ansible windows_personal -m ansible.windows.win_ping`
- Cada prueba tiene un timeout específico y se permite que falle (`|| true`).

### 6. Recoger facts completos (opcional)
- *Solo si `SHOW_FACTS = true`.*
- Ejecuta el playbook `update_inventory.yml` con verbosidad (`-v`).
- Recopila *facts* de todos los hosts (puede ser lento si hay muchos hosts).

### 7. Guardar inventario estático
- Ejecuta nuevamente el script de inventario y guarda su salida JSON en `/tmp/inventory_snapshot.json`.
- Muestra un resumen de grupos y hosts usando un pequeño script Python.
- **Archiva** el archivo JSON como artefacto de Jenkins para su posterior análisis.

---

## Detalles de Ejecución en Paralelo

El pipeline aprovecha la ejecución paralela en la etapa de verificación de conectividad, lo que reduce significativamente el tiempo total de ejecución. Las tres pruebas se lanzan simultáneamente y cada una muestra su salida por separado.

---

## Uso

1. En Jenkins, selecciona el pipeline **Actualizar Inventario Ansible**.
2. Configura los parámetros según necesites:
   - **VERIFY_CONNECTIVITY**: activar si deseas comprobar que los hosts responden.
   - **SHOW_FACTS**: activar si necesitas recopilar información detallada de los sistemas.
3. Ejecuta el pipeline.

**Ejemplo de configuración típica:**
- `VERIFY_CONNECTIVITY = true`
- `SHOW_FACTS = false` (para una ejecución rápida)

---

## Artefactos Generados

- **`inventory_snapshot.json`** – Instantánea del inventario en el momento de la ejecución.
- **Logs de ejecución** – Se pueden revisar en la consola de Jenkins.

---

## Consideraciones Importantes

- El script de inventario dinámico (`aws_inventory.sh`) debe estar correctamente configurado para consultar las instancias EC2 en las cuentas y regiones correspondientes.
- Los perfiles AWS (`AlexPersonal` y `AlexUFV`) deben estar definidos en el nodo Jenkins donde se ejecuta el pipeline.
- Las pruebas de ping en Windows requieren que el módulo `ansible.windows.win_ping` esté disponible (incluido en `ansible.windows` collection).
- Si algún host no responde al ping, la etapa no falla gracias al `|| true`, pero el error quedará registrado en los logs.
- La recolección de *facts* (`SHOW_FACTS`) puede aumentar considerablemente el tiempo de ejecución si hay muchos hosts.

---

## Resumen Ejecutivo

1. **Verificar entorno** – Versiones y credenciales AWS.
2. **Generar inventario** – Ejecutar script y validar salida.
3. **Validar con Ansible** – Usar herramientas nativas de Ansible.
4. **Mostrar grupos** – Visualización jerárquica.
5. **Probar conectividad (paralelo)** – Ping a Linux y Windows.
6. **Recoger facts (opcional)** – Ejecutar playbook.
7. **Archivar instantánea** – Guardar inventario como artefacto.

---

## Resultado Final

Al finalizar la ejecución, obtendrás:

- Un inventario actualizado y validado.
- (Opcional) Informe de conectividad de todos los hosts.
- (Opcional) *Facts* recopilados de los hosts.
- Un archivo JSON con el inventario completo, disponible para auditoría o integración con otros sistemas.

---

## Seguridad y Buenas Prácticas

- Las credenciales AWS se gestionan mediante perfiles locales en el nodo Jenkins; no se exponen en el código.
- El pipeline utiliza `|| true` en los pings para evitar fallos falsos positivos, pero mantiene visibilidad de los errores.
- Los artefactos se archivan automáticamente, permitiendo trazabilidad.

---

## Recursos Adicionales

- [Documentación de Ansible Inventory](https://docs.ansible.com/ansible/latest/user_guide/intro_inventory.html)
- [Módulo ansible.windows.win_ping](https://docs.ansible.com/ansible/latest/collections/ansible/windows/win_ping_module.html)
- [Jenkins Pipeline Syntax](https://www.jenkins.io/doc/book/pipeline/syntax/)
- [AWS CLI – Configuración de perfiles](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-profiles.html)

---

> **Nota:** Este pipeline está optimizado para entornos con infraestructura en AWS y gestión con Ansible. Ajusta las rutas y perfiles según tu configuración local.