
> **Nota:** El peering se establece desde la cuenta Personal hacia UFV, y se acepta automáticamente usando el rol IAM creado en UFV.

---

## Flujo del Pipeline (`ACTION=deploy`)

El pipeline ejecuta los siguientes pasos de forma secuencial:

### 1. Inicialización
- Detecta la IP pública del usuario que ejecuta el pipeline (si no se proporcionó).
- Obtiene los **Account IDs** de ambas cuentas.
- Inicializa variables de entorno necesarias.

### 2. Validación de Templates
- Valida la sintaxis de las plantillas de CloudFormation.
- **No despliega** ningún recurso en esta etapa.

### 3. Creación de Rol IAM en UFV
- Crea el rol `vpc-peering-acceptor-role` en la cuenta UFV.
- Este rol permite a la cuenta Personal aceptar el peering.

### 4. Deploy de VPC en UFV
- Crea la infraestructura base en la cuenta UFV:
  - VPC (`10.1.0.0/16`)
  - Subnets públicas
  - Tablas de rutas
  - Internet Gateway
- **Todavía no hay peering.**

### 5. Deploy en Personal + Creación del Peering
- Crea en la cuenta Personal:
  - VPC (`10.0.0.0/16`)
  - Subnets públicas
  - Instancias EC2 (Linux y Windows)
  - Bucket S3 para backups
- Inicia la creación del **VPC Peering** hacia la cuenta UFV.

### 6. Aceptación del VPC Peering
- Se ejecuta en la cuenta UFV.
- Espera a que el peering esté en estado `pending-acceptance`.
- Acepta la solicitud automáticamente.

### 7. Actualización de Rutas en UFV
- Añade una ruta en la tabla de rutas de UFV hacia la VPC Personal (`10.0.0.0/16`).
- Esto permite tráfico bidireccional.

### 8. Verificación Final de Rutas
- Comprueba que ambas tablas de rutas tengan las entradas necesarias.
- Verifica que el peering esté en estado `active`.
- Si falta alguna ruta, la añade automáticamente.

### 9. Resumen Final
Muestra información clave:
- ID del VPC Peering
- CIDRs de ambas VPCs
- IPs públicas/privadas de las instancias
- Outputs de CloudFormation (como el nombre del bucket S3)

---

## Flujo de Destrucción (`ACTION=destroy`)

Cuando se selecciona `destroy`, el pipeline:

1. **Elimina los VPC Peerings** (si existen).
2. **Elimina los stacks de CloudFormation** en orden inverso:
   - Stack de UFV
   - Stack de Personal
   - Stack de prerequisitos (rol IAM en UFV)
3. **Valida** que todos los recursos hayan sido eliminados.

> **Resultado:** Infraestructura completamente eliminada sin dejar rastros.

---

## Consideraciones Importantes

- El peering es **cross-account**, por lo que se requiere un rol IAM en la cuenta UFV con permisos para aceptar peering.
- La aceptación del peering es **automatizada** dentro del pipeline; no es necesario intervenir manualmente.
- Las **rutas** deben configurarse explícitamente en ambas direcciones; el pipeline lo hace automáticamente.
- Se utiliza `|| true` en algunos comandos para evitar fallos en updates donde no hay cambios.

---

## Resumen Ejecutivo

1. **Detectar IP y cuentas** – Obtiene la IP del ejecutante y los Account IDs.
2. **Crear rol IAM en UFV** – Para permitir la aceptación del peering.
3. **Crear VPC en UFV** – Infraestructura base en la cuenta secundaria.
4. **Crear VPC en Personal + Peering** – Recursos principales y solicitud de peering.
5. **Aceptar Peering** – Automático desde UFV.
6. **Configurar rutas** – Bidireccionales.
7. **Verificar conectividad** – Comprobación final.

---

## Uso

1. En Jenkins, selecciona el pipeline.
2. Configura los parámetros requeridos (key pairs, AMIs, etc.).
3. Elige la `ACTION`:
   - `deploy` → Crea toda la infraestructura.
   - `destroy` → Elimina todos los recursos.
4. Ejecuta el pipeline.

---

## Resultado Final

Se obtiene una infraestructura AWS completamente funcional con:

- **Conectividad de red** entre dos VPCs en cuentas diferentes.
- **Recursos desplegados automáticamente** (VPCs, instancias, S3).
- **Arquitectura reproducible y destructible** con un solo clic.
- **Seguridad** mediante el uso de roles IAM y restricción de acceso por IP.

---

## Seguridad y Buenas Prácticas

- El acceso SSH/RDP está restringido a la IP pública detectada.
- Las credenciales de AWS se manejan mediante **Jenkins Credentials** (no se exponen en el código).
- Los roles IAM utilizan el **principio de mínimo privilegio**.
- El bucket S3 se crea con políticas de acceso privado por defecto.

---

## Recursos Adicionales

- [Documentación de AWS VPC Peering](https://docs.aws.amazon.com/vpc/latest/peering/what-is-vpc-peering.html)
- [Guía de CloudFormation](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/Welcome.html)
- [Jenkins Pipeline Syntax](https://www.jenkins.io/doc/book/pipeline/syntax/)

---

> **Nota:** Este pipeline está diseñado para entornos de desarrollo/pruebas. Ajusta los parámetros y las políticas según las necesidades de tu organización.