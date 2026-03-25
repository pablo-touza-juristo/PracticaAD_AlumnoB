# Jenkins Pipeline – AWS-UFV-DB-Backup-Restore

![Jenkins](https://img.shields.io/badge/Jenkins-Pipeline-blue?logo=jenkins)
![Ansible](https://img.shields.io/badge/Ansible-Playbook-red?logo=ansible)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-Backup-blue?logo=postgresql)
![AWS S3](https://img.shields.io/badge/AWS-S3-orange?logo=amazonaws)

## Descripción General

Este pipeline de Jenkins automatiza las operaciones de **backup y restauración** de una base de datos PostgreSQL, almacenando los *dumps* en un bucket S3 (`eu-west-1`). Está diseñado para el entorno de la cuenta `AlexPersonal` y permite:

- Realizar un **dump** del esquema académico y subirlo a S3.
- **Listar** los *dumps* disponibles en el bucket.
- **Restaurar** una base de datos a partir de un *dump* existente.

Además, incluye una etapa opcional para **crear el bucket** con políticas de seguridad, versionado y ciclo de vida (transición a Glacier y expiración).

---

## Objetivos

- **Automatizar backups** regulares de la base de datos PostgreSQL.
- **Almacenar backups** de forma segura en S3 con versionado.
- **Facilitar restauraciones** desde la consola de Jenkins.
- **Aplicar políticas de retención** para optimizar costos (Glacier a los 30 días, eliminación tras 365 días).
- **Permitir modo *dry-run*** para simular operaciones sin efectos.

---

## Parámetros del Pipeline

| Parámetro | Tipo | Descripción |
|-----------|------|-------------|
| `ACTION` | `choice` | Operación a realizar: `dump`, `list`, `restore`. |
| `S3_BUCKET` | `string` | Nombre del bucket S3 donde se guardan los dumps. Por defecto `ufv-postgres-backups`. |
| `S3_DUMP_FILE` | `string` | **[Solo para restore]** Nombre del archivo a restaurar (ej: `dump_academico_20260322T120000.sql.gz`). Se puede obtener con `ACTION=list`. |
| `CREATE_BUCKET_IF_NOT_EXISTS` | `boolean` | Crear el bucket en `eu-west-1` si no existe (solo la primera vez). Aplica políticas de seguridad y ciclo de vida. |
| `DRY_RUN` | `boolean` | Modo `--check`: muestra qué haría sin ejecutar cambios. |
| `VERBOSE` | `boolean` | Salida detallada (`-vv`). |

---

## Entorno y Variables

| Variable | Valor | Descripción |
|----------|-------|-------------|
| `ANSIBLE_DIR` | `/usr/local/ufv/ufv-infra/ansible` | Directorio raíz de Ansible. |
| `ANSIBLE_CFG` | `.../ansible/ansible.cfg` | Ruta al archivo de configuración de Ansible. |
| `INVENTORY` | `.../inventory/aws_inventory.sh` | Script de inventario dinámico. |
| `ANSIBLE_HOST_KEY_CHECKING` | `False` | Deshabilita verificación de host keys. |
| `ANSIBLE_COLLECTIONS_PATHS` | (varias rutas) | Rutas donde buscar colecciones de Ansible. |
| `AWS_PROFILE` | `AlexPersonal` | Perfil AWS utilizado para operaciones con S3. |
| `AWS_REGION_BUCKET` | `eu-west-1` | Región donde se encuentra el bucket S3. |
| `ANSIBLE_FORCE_COLOR` | `true` | Fuerza salida con colores en Ansible. |
| `TERM` | `xterm` | Terminal para soporte de colores. |

---

## Flujo del Pipeline

### 1. Verificar entorno
- Muestra la acción seleccionada y el nombre del bucket.
- Asigna permisos de ejecución al script de inventario.
- Filtra y muestra los hosts con etiqueta `postgres` en el inventario.
- Verifica las credenciales AWS con `aws sts get-caller-identity` usando el perfil `AlexPersonal` y la región `eu-west-1`.

### 2. Crear bucket S3 (opcional)
- *Solo si `CREATE_BUCKET_IF_NOT_EXISTS = true`.*
- Comprueba si el bucket existe; si no:
  - Crea el bucket en la región `eu-west-1`.
  - **Bloquea acceso público** (política restrictiva).
  - **Habilita versionado** de objetos.
  - **Configura ciclo de vida**:
    - Transición a `GLACIER` después de 30 días.
    - Expiración (borrado) después de 365 días.
- Muestra un resumen de la configuración aplicada.

### 3. Ejecutar operación
- Llama al playbook `db_backup_restore.yml` con los parámetros adecuados:
  - `db_action` → valor de `ACTION`.
  - `s3_bucket_name` → valor de `S3_BUCKET`.
  - `s3_dump_file` → solo si `ACTION=restore` y se proporcionó.
  - `--check` si `DRY_RUN = true`.
  - `-vv` si `VERBOSE = true`.
- El playbook ejecuta la lógica correspondiente (dump, listado o restore) sobre la base de datos PostgreSQL.

---

## Detalles de las Acciones

### `dump`
- Realiza un volcado del esquema académico de la base de datos.
- Comprime el archivo (`.gz`) y lo sube a `s3://<BUCKET>/postgres-dumps/`.
- El nombre del archivo incluye un timestamp (ej: `dump_academico_20260325T120000.sql.gz`).

### `list`
- Lista todos los archivos de *dump* disponibles en el bucket (prefijo `postgres-dumps/`).
- Muestra nombres, tamaños y fechas de modificación.
- Útil para seleccionar el archivo adecuado antes de una restauración.

### `restore`
- Descarga el archivo especificado en `S3_DUMP_FILE` desde S3.
- Restaura la base de datos PostgreSQL a partir de ese *dump*.
- **Importante:** Requiere que el archivo exista en el bucket y que la base de datos esté accesible.

---

## Uso

1. En Jenkins, selecciona el pipeline **AWS-UFV-DB-Backup-Restore**.
2. Configura los parámetros:
   - **ACTION**: elige `dump`, `list` o `restore`.
   - **S3_BUCKET**: (opcional) si usas otro bucket distinto al predeterminado.
   - **S3_DUMP_FILE**: solo si `ACTION=restore`, escribe el nombre exacto del archivo (puedes obtenerlo con `list`).
   - **CREATE_BUCKET_IF_NOT_EXISTS**: activa solo la primera vez que se usa un nuevo bucket.
   - **DRY_RUN**: activar para simular.
   - **VERBOSE**: activar para logs detallados.
3. Ejecuta el pipeline.

**Ejemplo de flujo típico:**
1. Primera ejecución con `CREATE_BUCKET_IF_NOT_EXISTS=true` para crear el bucket y sus políticas.
2. Luego, ejecuciones regulares de `dump` para realizar backups automáticos.
3. En caso de necesidad, ejecutar `list` para ver los dumps disponibles y luego `restore` con el nombre elegido.

---

## Consideraciones Importantes

- **Credenciales AWS**: El pipeline usa el perfil `AlexPersonal`. Asegúrate de que esté configurado en el nodo Jenkins y tenga permisos para S3 (`s3:CreateBucket`, `s3:PutObject`, `s3:GetObject`, `s3:ListBucket`) y para ejecutar `sts:GetCallerIdentity`.
- **Región del bucket**: El bucket se crea en `eu-west-1` y las operaciones se realizan contra esa región. Asegúrate de que el playbook de Ansible tenga acceso a la base de datos en la misma región (o en una accesible por red).
- **Políticas de seguridad**: Al crear el bucket, se bloquea el acceso público y se habilita versionado. Esto evita pérdidas accidentales y garantiza la seguridad de los backups.
- **Ciclo de vida**: Los *dumps* se moverán a Glacier después de 30 días y se borrarán después de 365 días. Ajusta estos valores en el código si es necesario.
- **Modo `dry-run`**: Ansible soporta `--check` para la mayoría de los módulos, pero algunos (como `command` o `shell`) pueden ignorarlo. Verifica que el playbook esté preparado para este modo.

---

## Resumen Ejecutivo

1. **Verificar entorno** – Inventario, credenciales AWS.
2. **Crear bucket (opcional)** – Configuración de seguridad, versionado y lifecycle.
3. **Ejecutar operación** – Llamada al playbook con los parámetros adecuados.
4. **Mostrar resultado** – Éxito con mensaje personalizado según la acción.

---

## Resultado Final

Al finalizar, según la acción seleccionada:

- **`dump`**: Un archivo comprimido en S3 con el backup de la base de datos.
- **`list`**: Una lista en la consola con los *dumps* disponibles.
- **`restore`**: La base de datos restaurada al estado del *dump* elegido.

Todo ello con trazabilidad, logs y opción de simulación.

---

## Seguridad y Buenas Prácticas

- **Acceso público bloqueado**: El bucket se crea con políticas que impiden cualquier acceso no autorizado.
- **Versionado habilitado**: Protege contra sobrescrituras accidentales y permite recuperar versiones anteriores.
- **Dry-run**: Permite validar los comandos sin modificar datos.
- **Ciclo de vida**: Optimiza costos moviendo backups antiguos a Glacier y eliminando los muy antiguos.
- **Credenciales específicas**: Se usa un perfil AWS dedicado, evitando credenciales por defecto.

---

## Recursos Adicionales

- [Documentación de Ansible – Módulo aws_s3](https://docs.ansible.com/ansible/latest/collections/amazon/aws/s3_bucket_module.html)
- [AWS CLI – Comandos S3](https://aws.amazon.com/cli/)
- [Políticas de ciclo de vida de S3](https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lifecycle-mgmt.html)
- [Jenkins Pipeline Syntax](https://www.jenkins.io/doc/book/pipeline/syntax/)

---

> **Nota:** Este pipeline está pensado para el entorno de desarrollo/UFV. Ajusta los parámetros, rutas y políticas según las necesidades de tu organización.