# Manual de migración e instalación Banbaj 486

Versión del 01/11/2026

## Qué es Banbaj 486

Banbaj sustituye los programas de Visual FoxPro del cliente 486 (Banco Bajío) por una base de SQL Server. En producción todo corre dentro de SQL Server: carga de archivos, reglas, archivos planos para CYBER, correos, consultas a CYBER y migración. No hay Python ni otro lenguaje en la operación.

| Antes (FoxPro) | Ahora (SQL Server) |
| --- | --- |
| `paso.prg`, `asig_bases.prg`, macro `ASIG_486.xlsm` | `ops.sp_asignacion_486` (la base maestra llega directo como CSV) |
| `saldos.prg`, `pagos.prg`, `estructura.prg` | `ops.sp_actualizacion_486` |
| `prog15.prg`, `devfianey.prg` | `ops.sp_retiro`, `ops.sp_retiro_solicitud`, `ops.sp_aviso_devolucion` |
| `asi486.prg`, `telbnx.prg`, `ges*.prg`, `email.prg` | Salidas por catálogo + `ops.sp_exportar_salidas` |
| `status.prg`, `cyadd.sql`, `BAJ.sql` (sqlplus) | `ops.sp_bajar_cyber` por servidor vinculado a Oracle |
| DAT.DBF, TAB7, historia, PAGTOT, etiquetas | Tablas `dat.*`, `cfg.*` |
| Correos CDO con "¿Deseas enviar…?" | `mail.PLANTILLA` + Database Mail |

El flujo diario es de lunes a viernes: primero llega la actualización de saldos y pagos; la asignación puede llegar o no, y siempre llega después. El arribo a CYBER sigue siendo manual: Banbaj deja los archivos y scripts, y la persona de asignaciones los sube.

El código está en el repositorio privado `0marMF/Banbaj`: carpeta `sql/` (objetos en orden), `cyber/486/` (guías y el programa de exportación de FoxPro) y `docs/` (correos, pendientes y equivalencias).

## Requisitos del servidor

Todo se instala en un solo servidor Windows con SQL Server. Los archivos de salida, el ZIP y el correo dependen de que las rutas `C:\` sean las de esa misma máquina.

| Requisito | Para qué | Quién |
| --- | --- | --- |
| SQL Server 2017 o superior, edición Standard o Enterprise (no Express) | Base, SQL Server Agent (job diario) y Database Mail | Administrador |
| Cliente de Oracle de 64 bits con el proveedor OLE DB `OraOLEDB.Oracle`, con "Allow inprocess" activado en SSMS (Server Objects → Linked Servers → Providers) | Consultar CYBER (status, correos, teléfonos, pagos) | Administrador |
| 7-Zip en `C:\Program Files\7-Zip\7z.exe` | ZIP con contraseña de retiros | Administrador |
| Servidor SMTP alcanzable (hoy los .prg usan `192.168.50.7`, puerto 25) | Database Mail | Infraestructura |
| Acceso a la unidad `Q:` = `\\192.168.50.13\q` | Leer `Q:\CYBER\C_486\aaaa\mes\dd\` y escribir en `Q:\MIS\SERTEC98\CLIENTES\486\` | Infraestructura |
| Usuario y contraseña de Oracle (CYBER) | Servidor vinculado | Dueño de CYBER |
| Visual FoxPro en una máquina con acceso a `O:\` | Solo para exportar los DBF una vez (migración) | Asignaciones |

**Permisos de la cuenta del servicio de SQL Server:**

- Lectura en `\\192.168.50.13\q\CYBER\C_486\` (archivos del banco).
- Escritura en `C:\BANBAJ\486\SALIDA\` (archivos planos y scripts), en `C:\` (ZIP de retiros) y en `\\192.168.50.13\q\MIS\SERTEC98\CLIENTES\486\` (copia del DAT para MIS).
- Lectura en la carpeta de la migración (`C:\MIGRA486\`), solo el día de la migración.

La cuenta del servicio no ve unidades mapeadas como `Q:`: por eso las rutas ya vienen configuradas con la ruta UNC `\\192.168.50.13\q`.

## Instalación de la base

La base se crea vacía y se llena corriendo los archivos de `sql/` en orden alfabético. Todos se pueden volver a correr: crean lo que falta y actualizan los procedimientos.

1. Crear la base: `CREATE DATABASE Banbaj;` (o el nombre que se decida; el job lo usa).
2. Correr los scripts de `sql/` en este orden, conectado a esa base:
   - `01_esquemas_tablas.sql`, `02_catalogos.sql`, `03_correo.sql`, `05_tabla_dat_486.sql`
   - `10_funciones.sql`, `12_credenciales.sql` (crea la llave de cifrado de la base)
   - `20_sp_comunes.sql` … `80_sp_migracion.sql`
   - `90_semilla_486.sql` al final (catálogos, reglas, salidas, correos y parámetros del 486)
3. Con `sqlcmd`, usar siempre `-I` y `-f 65001` (los scripts están en UTF-8). En SSMS basta con abrir y ejecutar cada archivo.

```
for %f in (sql\*.sql) do sqlcmd -S <servidor> -d Banbaj -E -I -b -f 65001 -i "%f"
```

4. Verificar:

```sql
SELECT COUNT(*) AS PROCEDIMIENTOS FROM sys.procedures;          -- más de 60
SELECT CODIGO, LISTA, PERFIL_DBMAIL FROM mail.PLANTILLA;           -- 8 plantillas, perfil asig.486.cdmx
SELECT CLAVE, VALOR FROM cfg.PARAMETRO WHERE CLIENTE = '486';     -- parámetros del 486
```

**Ojo al volver a correr la semilla:** `90_semilla_486.sql` reescribe catálogos y parámetros. La dirección de Oracle regresa a vacío, así que después hay que volver a correr la línea de `CYBER_ORACLE_ORIGEN` de `sql/instalacion/03_parametros_y_credenciales.sql`. Las rutas de `Q:` ya vienen en la semilla. Las credenciales, el DAT y el histórico no se tocan.

## Configuración del servidor

Cuatro scripts en `sql/instalacion/`, en orden. Los tres primeros no los corre el CI porque tocan el servidor real; el 04 (accesos) sí se prueba con usuarios de SQL.

### 1. Opciones del servidor y correo (`01_configurar_servidor.sql`)

Lo corre un administrador (sysadmin) en `master`. Hace lo siguiente:

- Activa `Ole Automation Procedures` (escritura de archivos), `xp_cmdshell` (7-Zip) y `Database Mail XPs`.
- Crea la cuenta y el perfil **asig.486.cdmx**: SMTP 192.168.50.7, puerto 25, remitente asig.486.cdmx@sertec.com.mx, nombre "Asignaciones". El perfil queda como principal y público.
- Manda un correo de prueba. Si no llega, revisar `msdb.dbo.sysmail_event_log`.

Antes de correrlo, confirmar con Sistemas el servidor SMTP y si pide usuario. Si pide, agregar `@username` y `@password` en `sysmail_add_account_sp`.

### 2. Job diario (`02_crear_job_486.sql`)

Crea el job **Banbaj 486 diario** en el Agente de SQL Server. Corre un solo paso, `EXEC ops.sp_diario_486;`, en la base Banbaj, cada 30 minutos de lunes a viernes entre 07:00 y 22:00. El procedimiento revisa si ya llegaron los archivos y si ya corrió hoy, así que repetirlo no duplica nada. Si la base tiene otro nombre, cambiar `@base` al inicio del script.

### 3. Rutas, Oracle y credenciales (`03_parametros_y_credenciales.sql`)

1. Copiar el script fuera del repo y reemplazar los cuatro valores `<<…>>`:
   - origen de Oracle de CYBER (`host:1521/servicio`)
   - usuario y contraseña de Oracle
   - contraseña del ZIP; acepta `{MM}` y `{AAAA}` para el mes y el año
2. Correrlo en la base Banbaj. Hace lo siguiente:
   - Guarda las credenciales cifradas.
   - Crea el servidor vinculado `[CYBER]` y prueba una bajada de STATUS.
3. Borrar la copia editada. Nunca se sube al repo.

Para cambiar una contraseña después, basta con otro `INSERT` a la vista de captura, que reemplaza la anterior:

```sql
INSERT INTO cfg.CAPTURA_CREDENCIAL (SISTEMA, USUARIO, CLAVE) VALUES ('CYBER_ORACLE', N'usuario', N'nueva');
SELECT SISTEMA, USUARIO, CLAVE, FE_ACT FROM cfg.CAPTURA_CREDENCIAL;   -- la clave se ve como ********
```

### Parámetros que conviene revisar

| Parámetro (`cfg.PARAMETRO`, cliente 486) | Valor de fábrica | Para qué |
| --- | --- | --- |
| RUTA\_SALIDA | C:\\BANBAJ\\486\\SALIDA\\ | Dónde se escriben los planos y scripts |
| CARPETA\_ZIP | C:\\ | Dónde queda el ZIP de retiros |
| RUTA\_7ZIP | C:\\Program Files\\7-Zip\\7z.exe | Ejecutable de 7-Zip |
| RUTA\_MIS | \\\\192.168.50.13\\q\\MIS\\SERTEC98\\CLIENTES\\486\\ | Copia del DAT para MIS |
| CYBER\_LINKED\_SERVER | CYBER | Nombre del servidor vinculado |
| CYBER\_ORACLE\_ORIGEN | (vacío) | Lo llena el script 03 |
| RETROCESO\_AUTOMATICO | 1 | 0 para apagarlo |
| NEGATIVO\_MODO | CERO | Saldos negativos suben como cero |

Cambiar uno: `UPDATE cfg.PARAMETRO SET VALOR = N'…' WHERE CLIENTE = '486' AND CLAVE = '…';`

### Teléfonos: quejas y plan de numeración de CYBER

En cada asignación, antes de armar los teléfonos, `ops.sp_telefonos_refrescar_cyber` trae lo vigente de CYBER, igual que `G4_025_TELEFONOS`:

- **Quejas:** lee `telbaj`, `telbaj1` y `TENOVA1` del grupo 1 por el servidor vinculado `[192.168.50.53]` y toma los últimos 10 dígitos de `telo` y `telpho`. Se guardan en `cfg.TEL_QUEJA_CYBER` y se quitan de esa cuenta, además de las quejas migradas.
- **Plan de numeración:** reemplaza `cfg.PLAN_NUMERACION` con `CYBER.dbo.CAT_PNM` de la misma instancia.

Si el servidor vinculado o la tabla no están disponibles, deja un aviso en la bitácora (paso `TELEFONOS CYBER`) y sigue con la última lectura.

Reglas desde el 01/11:

- El teléfono que no está en ningún rango del plan se descarta (antes salía como fijo).
- Además de 1000000000, 9999999999 y 0999999999, nunca se mandan 1111111111, 4444444444, 5555555555 ni 5000000000.

| Parámetro | Valor de fábrica |
| --- | --- |
| TELBAJ\_LINKED\_SERVER | 192.168.50.53 |
| TELBAJ\_GRUPO | 1 |
| TELBAJ\_TABLAS | cyber.dbo.telbaj,cyber.dbo.telbaj1,tenova.dbo.TENOVA1 |
| PNM\_TABLA | CYBER.dbo.CAT\_PNM |
| TEL\_EXIGIR\_PNM | 1 (0 = como telbnx.prg, fuera del plan sale como fijo) |
| TEL\_INVALIDOS | lista de números que nunca se mandan |

La cuenta del servicio de SQL Server necesita lectura en esas tablas y un mapeo de inicio de sesión en el servidor vinculado. Si en la primera corrida el aviso dice que no pudo leer, revisar eso.

### Proveedor de Oracle

En SSMS: Objetos de servidor → Servidores vinculados → Proveedores → **OraOLEDB.Oracle** → Propiedades → marcar **Permitir en proceso** (*Allow inprocess*). Sin esto la bajada falla con un error de acceso al proveedor.

> **Si se vuelve a correr `90_semilla_486.sql`**, el origen de Oracle regresa a vacío. Hay que volver a correr la línea de `CYBER_ORACLE_ORIGEN` del script 03. Las rutas de `Q:` y las credenciales no se pierden.

### Conexión desde otras computadoras

Por omisión SQL Server solo acepta conexiones locales. Para trabajar desde SSMS en otra PC de la red:

**1. Activar TCP/IP con puerto fijo** (en el servidor)

1. Abrir **SQL Server Configuration Manager** → Configuración de red de SQL Server → Protocolos de MSSQLSERVER (o de la instancia con nombre).
2. **TCP/IP** → Habilitar.
3. Propiedades de TCP/IP → pestaña Direcciones IP → sección **IPAll**: borrar *Puertos dinámicos TCP* y poner **Puerto TCP = 1433**.
4. Reiniciar el servicio **SQL Server**. Si es instancia con nombre y no se quiere escribir el puerto al conectarse, iniciar también **SQL Server Browser**.

**2. Permitir conexiones remotas**

En SSMS, clic derecho en el servidor → Propiedades → Conexiones → marcar **Permitir conexiones remotas con este servidor**. Viene marcado de fábrica.

**3. Abrir el firewall de Windows** (PowerShell como administrador)

```
New-NetFirewallRule -DisplayName "SQL Server 1433" -Direction Inbound -Protocol TCP -LocalPort 1433 -Action Allow -Profile Domain
New-NetFirewallRule -DisplayName "SQL Browser 1434" -Direction Inbound -Protocol UDP -LocalPort 1434 -Action Allow -Profile Domain   # solo instancia con nombre
```

Si hay un firewall de red entre las PCs y el servidor, pedir a Sistemas que abra el mismo puerto.

**4. Autenticación**

- **Recomendado:** usuarios de Windows del dominio (`DOMINIO\usuario`). No hay contraseñas en SQL.
- **Usuarios de SQL:** solo si no hay dominio. Requieren modo mixto: Propiedades del servidor → Seguridad → **Modo de autenticación de SQL Server y Windows**, y reiniciar el servicio. No usar `sa` para trabajar.

**5. Crear los accesos** (`sql/instalacion/04_accesos_remotos.sql`)

Llenar la lista `@accesos` con cada usuario y su nivel, y correr el script como sysadmin. Se puede volver a correr para agregar gente.

| Nivel | Qué puede hacer | Para quién |
| --- | --- | --- |
| CONSULTA | Leer DAT, histórico, corridas y bitácora | Supervisión, MIS |
| OPERADOR | Correr todos los procesos (es db\_owner de la base), bajar de CYBER, mandar correos | Equipo de asignaciones |
| ADMIN | Todo, incluida la escritura de archivos y el ZIP (`sp_exportar_salidas`) | 1 o 2 responsables |

CONSULTA y OPERADOR tienen negado leer `cfg.CREDENCIAL` y `cfg.sp_credencial_leer`. Capturar credenciales en `cfg.CAPTURA_CREDENCIAL` sí está permitido, porque la vista nunca muestra la contraseña.

Escribir archivos y armar el ZIP usa Automatización OLE y `xp_cmdshell`, y SQL Server solo los permite a sysadmin. Por eso `sp_exportar_salidas` necesita ADMIN. El job diario no se ve afectado porque corre como el Agente.

Un db\_owner podría quitarse a sí mismo la negación sobre las credenciales. El nivel OPERADOR es para gente de confianza del equipo.

**6. Conectarse desde la otra PC**

- Probar el puerto: `Test-NetConnection <servidor> -Port 1433` debe decir `TcpTestSucceeded : True`.
- En SSMS, nombre del servidor:
  - `SERVIDOR` (instancia por omisión)
  - `SERVIDOR\INSTANCIA` (instancia con nombre)
  - `192.168.x.x,1433` (por IP; la coma separa el puerto)
- SSMS 20 o superior cifra la conexión por omisión. Si el servidor no tiene certificado propio, marcar **Confiar en el certificado del servidor** (*Trust server certificate*). Si no, sale un error de cadena de certificados.

**Errores frecuentes al conectar**

| Error | Causa |
| --- | --- |
| 53 / "No se encontró el servidor" | TCP/IP apagado, firewall cerrado o nombre mal escrito |
| 18456 | Usuario sin inicio de sesión, contraseña mal o modo mixto apagado (ver `sys.server_principals` y el log de errores) |
| 4060 | El inicio de sesión no tiene usuario en la base Banbaj (correr el script 04) |
| Cadena de certificados no confiable | Marcar *Confiar en el certificado del servidor* |

## Migración de los datos de FoxPro

Se hace **una sola vez**, justo antes de la primera corrida en SQL Server. Trae lo que el proceso necesita para seguir donde se quedó FoxPro: el DAT vigente, el histórico de folios, el consecutivo, los pagos arribados, las etiquetas, las exclusiones y los catálogos de LADA y PNC. **PURGA y DEVOL no se migran.**

### Qué se lleva y a dónde

| CSV (DBF de origen) | Campos que se usan | Destino en SQL Server |
| --- | --- | --- |
| DAT | todos los que existen en `dat.DAT_486` (los demás se ignoran) | `dat.DAT_486` y el periodo vigente en `dat.HISTORIA_FOLIO` |
| HISTORIA | CUENTA, FOLIO, CUENTA2, RIESGO, SEGMENTO, STATUS, TRAMO, ETIQUETA, FE\_ASIG, SDO\_ACT, CAPITAL, TEL1-TEL16, DIRECC1-DIRECC5, ESTADO, EDO | `dat.HISTORIA_FOLIO`: cada asignación anterior como baja (la primera de la cuenta NVA, las siguientes REA); los datos van en `DATOS_BAJA` (JSON). historia.dbf no trae fecha de retiro ni correos |
| TAB7 | FOLIO | consecutivo de folios |
| PAGTOT | CUENTA, MONT, FE\_PAG, FE\_REG | `dat.PAGO_ARRIBADO` (origen PAGTOT) |
| ETI, DM1 | CUENTA, ETIQUETA | etiquetas (DMP2, DMP1 del SCBSDOS) |
| TOP | CUENTA2, ETIQUETA | etiqueta U1EXT2 |
| STATUS | CUENTA, ESTATUS | etiqueta U1USO4 |
| EXC486 | CUENTA | exclusión de cuentas |
| DIRMAL | CUENTA, DIRECC1 | direcciones malas |
| EMAILMALO | EMAIL, CUENTA | correos malos |
| BLACKLIST | TEL, FE\_AGRE, OS, SOLICITUD | lista negra: OS = requerimiento, FE\_AGRE = fecha, SOLICITUD = quién lo pidió. STATUS X excluye y vacío no; el DBF no trae STATUS, así que todo cuenta como X |

Ya no se migran: **TELBAJ** y **PNC** (se leen de CYBER en cada asignación), **LADA** (ningún proceso la usa), PURGA y DEVOL. El programa de FoxPro exporta solo los campos de esta tabla; si alguno no existe en el DBF lo avisa al final.

### Paso 1. Exportar desde FoxPro

1. Detener los procesos del 486 en FoxPro para que nadie escriba en los DBF.
2. Revisar las rutas de los DBF en `cyber/486/EXPORTAR_MIGRACION.prg`. Vienen de los .prg actuales; si algo cambió, ajustar `laF[n, 2]`.
3. Correr `DO EXPORTAR_MIGRACION.prg` en Visual FoxPro. Escribe 12 CSV en `C:\MIGRA486\` sin los registros borrados y muestra cuántos registros salió de cada uno.
4. Si FoxPro corre en otro equipo, copiar la carpeta al servidor de SQL Server (o a una ruta UNC que la cuenta del servicio pueda leer). `BULK INSERT` lee las rutas desde el servidor, no desde la PC de quien ejecuta.

### Paso 2. Revisar sin escribir

```sql
EXEC ops.sp_migrar_486 @carpeta = N'C:\MIGRA486\';
```

Lee todos los CSV y muestra cuántas filas trae cada uno, cuántas irían a cada destino y los avisos (archivo que falta, columnas que faltan, teléfonos de lista negra que no son de 10 dígitos). No escribe nada. Comparar los conteos con el reporte de FoxPro.

Si los acentos salen mal, probar con `@codepage = '1252'`.

### Paso 3. Cargar

```sql
EXEC ops.sp_migrar_486 @carpeta = N'C:\MIGRA486\', @confirmar = 1;
```

- Carga todo en una sola transacción: si algo falla, no queda nada a medias.
- Si un destino ya tiene datos (por ejemplo, una prueba anterior), se detiene con un error 50910–50914. Para sobrescribir, agregar `@reemplazar = 1`.
- Para cargar solo una parte: `@solo = N'DAT,HISTORIA'` (destinos: DAT, HISTORIA, CONSECUTIVO, PAGOS, ETIQUETAS, EXCLUSIONES, LADA, PNC).
- Las tablas temporales `stg.MIG_*` se borran al terminar, salga bien o mal.

### Paso 4. Verificar

```sql
SELECT COUNT(*) FROM dat.DAT_486;                                   -- = registros de DAT.DBF
SELECT COUNT(*) FROM dat.HISTORIA_FOLIO WHERE CLIENTE = '486';
SELECT COUNT(*) FROM dat.PAGO_ARRIBADO WHERE CLIENTE = '486' AND ORIGEN = 'PAGTOT';
SELECT TIPO, ACTIVO, COUNT(*) FROM cfg.EXCLUSION WHERE CLIENTE = '486' AND ORIGEN = 'MIGRACION DBF' GROUP BY TIPO, ACTIVO;
```

Revisar a ojo unas cuantas cuentas conocidas: saldo, folio, etiqueta y teléfono deben coincidir con FoxPro.

### Paso 5. Limpiar

Borrar `C:\MIGRA486\` en la PC de FoxPro y en el servidor, y vaciar la papelera. Los CSV traen datos de clientes.

## Operación diaria

### Lo que hace el job solo

Cada 30 minutos el job llama `ops.sp_diario_486`. Esto es lo que hace:

1. **Fin de semana:** no hace nada.
2. **Actualización (ACT):** si ya están los archivos de saldos del día, corre `ops.sp_actualizacion_486`. Genera:
   - el plano SCBPAG
   - los scripts de CYBER ACT\_SALDOS, ACT\_VENCIDO, ACT\_PAGMIN y ACT\_PVS\_REE (este último marca PVS/REE en `RCVRY.uda1` y sustituye al SCBSDOS de la actualización)
3. **Asignación (ASIG):** solo después de una ACT en OK y si llegó la base. Corre `ops.sp_asignacion_486`:
   - Manda el correo **INICIO\_ASIG\_486** a Operación.
   - Trae de CYBER las quejas (telbaj del grupo 1) y el plan de numeración vigente.
   - Homologa, valida, asigna folios y aplica exclusiones.
   - Genera SCBSDOS, SCBTEL, sub\_mst, sub\_mail, gescar y la copia del DAT para MIS.
   - Si hay validaciones, manda sus avisos: saldo ≤0 en Consumo, pagos negativos (al equipo de asignaciones) o números cortados por Excel en la base maestra.
   - Con más de 100 cuentas nuevas avisa con ALERTA\_NUEVAS\_486.
4. Si la ACT y la ASIG del día ya están hechas, contesta "DIA COMPLETO" y no repite nada.

Las devoluciones que detecta la asignación **no se aplican solas**: quedan en `ops.DEVOLUCION` para revisión (`@aplicar_retiro = 0`).

Si algo falla, la corrida queda en ERROR, el DAT se regresa solo a como estaba (ver *Respaldo y retroceso*) y el job no vuelve a intentar ese proceso ese día.

### Lo que hace el operador después de cada corrida

**1. Revisar el resultado**

```sql
SELECT TOP 5 ID_CORRIDA, PROCESO, FECHA_PROCESO, ESTATUS, MENSAJE FROM ops.CORRIDA WHERE CLIENTE = '486' ORDER BY ID_CORRIDA DESC;
SELECT PASO, ESTATUS, REGISTROS, MENSAJE FROM ops.BITACORA WHERE ID_CORRIDA = @id ORDER BY ID;
```

**2. Aplicar las devoluciones (si hubo)**

```sql
SELECT * FROM ops.DEVOLUCION WHERE ID_CORRIDA = @id;    -- revisar
EXEC ops.sp_retiro @id;                                  -- aplicar y generar los archivos de retiro
```

**3. Escribir los archivos**

```sql
EXEC ops.sp_exportar_salidas @id, @solo_mostrar = 1;                    -- ver qué se va a escribir
EXEC ops.sp_exportar_salidas @id;                                       -- planos y scripts
EXEC ops.sp_exportar_salidas @id, @zip = 'RETIROS', @enviar_zip = 1;    -- con devolución
```

- Los archivos quedan en `RUTA_SALIDA\<aaaammdd>_corrida<id>\`: los planos en la raíz y los scripts en `cyber\`.
- La copia del DAT se escribe en `RUTA_MIS`.
- Con `@zip`, los archivos de retiro van en `C:\RETIROS_PAG_486_<fecha>.zip`, protegido con contraseña.
- Con `@enviar_zip = 1` sale el **correo único de devolución**: Operación con el ZIP y AEM en copia oculta sin el ZIP. Aplica igual para asignación, actualización y retiro por solicitud.

**4. Arribar a CYBER**

El arribo sigue siendo manual (`cyber/486/ARRIBO_MANUAL.md`): subir los planos y correr los scripts en Oracle. Marcar las horas para el seguimiento de tiempos:

```sql
EXEC ops.sp_marcar_arribo @id, 'SOLICITUD';
EXEC ops.sp_marcar_arribo @id, 'AUTORIZACION';
EXEC ops.sp_marcar_arribo @id, 'FIN';
SELECT * FROM ops.v_TIEMPOS_CORRIDA WHERE ID_CORRIDA = @id;
```

**5. Cerrar la asignación**

```sql
EXEC ops.sp_avisar @id, 'CONFIRMACION_ASIG_486';     -- correo de fin de asignación
```

### Procesos manuales

| Necesidad | Qué correr |
| --- | --- |
| Retiro por solicitud del banco | `EXEC ops.sp_retiro_solicitud @archivo = N'…\cuentas.csv';` revisa. Agregar `@confirmar = 1` para aplicar. Luego exportar con `@zip = 'RETIROS', @enviar_zip = 1`. |
| Cambiar una etiqueta | `EXEC ops.sp_etiquetar_campo @campo = 'ETIQUETA1', @archivo = N'…\etiquetas.csv';` El CSV lleva FOLIO,ETIQUETA (o `@tipo_llave = 'CUENTA'`). Agregar `@confirmar = 1` para aplicar. Genera SCBSDOS. |
| SCBSDOS fuera de proceso | `EXEC ops.sp_regenerar_scbsdos @motivo = N'…';` |
| Blanqueo de STATUS (días 1 a 10) | `EXEC ops.sp_bajar_cyber 'STATUS', @id_corrida = @id;` |
| Correos nuevos desde CYBER | `EXEC ops.sp_bajar_cyber 'CORREOS', @id_corrida = @id;` |
| Gescar de cuentas sin teléfono | `EXEC ops.sp_bajar_cyber 'TELEFONOS', @id_corrida = @id;` |
| Cuadre de pagos | `EXEC ops.sp_bajar_cyber 'PAGOS', @id_corrida = @id, @fecha = '…';` |
| Lista negra o exclusiones | `EXEC cfg.sp_exclusion_cargar @tipo = 'TELEFONO', @archivo = N'…', @req = '…', @solicita = N'…';` Los teléfonos deben tener 10 dígitos. |
| Correr el día a mano | `EXEC ops.sp_diario_486 @fecha = '…', @forzar = 1;` o directamente `ops.sp_actualizacion_486` / `ops.sp_asignacion_486`. |

Después de cualquier proceso que genera archivos, correr `ops.sp_exportar_salidas` con su corrida.

> Todos los procesos que cambian datos tienen modo de revisión (`@confirmar = 0` o `@solo_mostrar = 1`). Úsalo primero.

## Respaldo y retroceso

### Respaldo por corrida

Antes de tocar el DAT, cada corrida (ACT, ASIG, RET, ETI) guarda dos cosas:

- una foto completa del DAT en `ops.RESPALDO_DAT_486`
- el último folio en `ops.RESPALDO_CONTROL`

Se conservan las últimas 15. Para cambiarlo, ajustar el parámetro `RESPALDOS_A_CONSERVAR`.

Revertir una corrida deja el sistema como estaba antes de ella:

- regresa el DAT de la foto
- borra las altas del histórico y reabre las bajas que hizo
- borra sus pagos arribados
- regresa el consecutivo de folios
- vuelve a dejar como vigente la base maestra anterior

### Base maestra: vigente y anterior

Por cada segmento (CONSUMO, TDC, PYME, HIPOTECARIO…) se guardan dos versiones de la base recibida:

- la **vigente** (`VIGENTE = 1`)
- la **anterior** (`VIGENTE = 0`)

Al llegar una base nueva, la anterior se borra, la vigente pasa a anterior y la nueva queda como vigente. Si la corrida se revierte, la anterior vuelve a ser la vigente.

```sql
SELECT CODIGO, ID_CORRIDA, ARCHIVO, FE_CARGA, COUNT(*) AS FILAS
FROM dat.v_BASE_VIGENTE WHERE CLIENTE = '486'
GROUP BY CODIGO, ID_CORRIDA, ARCHIVO, FE_CARGA;
```

### Retroceso automático

Si una corrida falla a la mitad, el `CATCH` del proceso hace esto:

1. Cierra la corrida en ERROR.
2. Llama `ops.sp_retroceso_automatico`, que la revierte sola.
3. La corrida conserva su estatus ERROR (o CANCELADA) y queda marcada con `REVERTIDA_AUTO = 1`. Así el job no la reintenta en bucle.

Si el retroceso también falla, queda anotado en la bitácora como `RETROCESO AUTOMATICO` con estatus ERROR, y hay que revertir a mano.

Para **reintentar** después de corregir la causa (archivo mal formado, parámetro, etc.), correr el proceso a mano:

```sql
EXEC ops.sp_asignacion_486 @fecha = '2026-11-03';      -- o ops.sp_actualizacion_486
```

Para apagar el retroceso automático: `RETROCESO_AUTOMATICO = 0`.

### Retroceso manual

Sirve para deshacer una corrida que terminó OK pero salió mal (base equivocada, etiqueta incorrecta…).

```sql
EXEC ops.sp_revertir_corrida @id;                      -- muestra qué cambiaría
EXEC ops.sp_revertir_corrida @id, @confirmar = 1;      -- revierte; la corrida queda REVERTIDA
```

Reglas:

- Solo se puede revertir la corrida más reciente sin revertir. Para ir más atrás, revertir de la más nueva a la más vieja (error 50304).
- Las corridas revertidas automáticamente no estorban.
- Una corrida en proceso no se revierte (50302).
- Sin respaldo, porque es más vieja que las 15 que se conservan, tampoco (50303).
- Después de revertir una ACT o una ASIG, el job la vuelve a correr en su siguiente vuelta si los archivos siguen ahí.

> **Lo que ya se arribó a CYBER no se revierte.** El retroceso solo deshace lo que hay en SQL Server. Si los planos o scripts ya se subieron, hay que corregir en CYBER por separado, por ejemplo regenerando y subiendo un SCBSDOS correcto.

## Salida a producción

### Corrida en paralelo con FoxPro

Antes de apagar FoxPro, correr **al menos una semana** los dos sistemas sobre los mismos archivos. Solo FoxPro arriba a CYBER; Banbaj solo genera.

1. Deshabilitar el job (`msdb.dbo.sp_update_job @job_name = N'Banbaj 486 diario', @enabled = 0`) y correr cada día a mano con `ops.sp_diario_486 @fecha = '…'`.
2. Para no mandar correos reales, cambiar las listas de `mail.DESTINATARIO` a un correo propio, o usar `@solo_prueba = 1` en `sp_avisar` y `sp_aviso_devolucion`.
3. Escribir los archivos con `ops.sp_exportar_salidas` a una carpeta de pruebas (`@carpeta = N'C:\BANBAJ\PARALELO\'`).
4. Comparar contra lo que generó FoxPro el mismo día:
   - número de líneas por plano
   - SCBPAG, SCBSDOS y SCBTEL línea por línea (por ejemplo, con `fc /n` en Windows)
   - cuentas devueltas
   - folios nuevos
5. Las diferencias esperadas son las que se decidieron, no errores:
   - saldos negativos como cero
   - sin SCBSDOS en la actualización (lo sustituye ACT\_PVS\_REE)
   - sin COVID ni Reestructura
   - lista negra solo de 10 dígitos
6. Cuando los archivos coinciden varios días seguidos, migrar de nuevo con `@reemplazar = 1` justo antes del corte, para tomar el DAT final de FoxPro.

### Lista de verificación

- [ ] Base creada y scripts `sql/` corridos sin error
- [ ] `01_configurar_servidor.sql`: OLE, xp\_cmdshell, Database Mail y correo de prueba recibido
- [ ] 7-Zip instalado en el servidor y `RUTA_7ZIP` correcta
- [ ] Cliente de Oracle y proveedor OraOLEDB instalados, con *Allow inprocess*
- [ ] `03_parametros_y_credenciales.sql`: origen de Oracle, credenciales y prueba de STATUS OK
- [ ] La cuenta del servicio de SQL Server llega a `\\192.168.50.13\q`
- [ ] La cuenta del servicio de SQL Server puede leer las carpetas de entrada y escribir en la salida, en MIS y en C:\\
- [ ] Migración hecha y conteos cuadrados con FoxPro
- [ ] `C:\MIGRA486` borrado
- [ ] Listas de correo con los destinatarios reales (Operación, AEM, Asignaciones)
- [ ] Al menos una semana en paralelo sin diferencias inesperadas
- [ ] Job `Banbaj 486 diario` habilitado
- [ ] Procesos 486 de FoxPro apagados
- [ ] Contraseñas rotadas: `sa` de CYBER y usuario de Oracle que aparecían en los .prg
- [ ] Repo JSON\_FILE hecho privado

### Solución de problemas

| Error | Qué significa | Qué hacer |
| --- | --- | --- |
| 50823 | No existe el servidor vinculado CYBER | Capturar la credencial CYBER\_ORACLE y correr `EXEC cfg.sp_cyber_conectar;` |
| 50801 | No hay credencial para ese sistema | `INSERT INTO cfg.CAPTURA_CREDENCIAL …` |
| 50802 | La contraseña guardada no se puede descifrar | Pasa si la base se restauró en otro servidor. Volver a capturar la credencial |
| 50850 | No se pudo crear la carpeta o escribir un archivo (OLE) | Revisar que la ruta exista para el servidor (UNC, no Q:), los permisos de la cuenta del servicio y que *Ole Automation Procedures* esté activo |
| 50852 | La contraseña del ZIP trae un carácter prohibido | Quitar `" % & \| < > ^` |
| 50853 | 7-Zip no terminó bien | Revisar `RUTA_7ZIP`, que xp\_cmdshell esté activo y que se pueda escribir en `CARPETA_ZIP` |
| 50110 | Falta la actualización OK del día, o no hay consecutivo de folios | Correr primero la ACT. Si falta el consecutivo, migrar CONSECUTIVO |
| 50040 | Una validación canceló la corrida | El mensaje dice cuál. Corregir el archivo y correr el proceso a mano |
| 50300–50304 | Retroceso no permitido | Ver *Retroceso manual* |
| 50900–50906 | A un CSV de migración le faltan columnas | Revisar la exportación de ese DBF |
| 50910–50914 | El destino de la migración ya tiene datos | Agregar `@reemplazar = 1` si de verdad se quiere sobrescribir |
| Error de proveedor OraOLEDB | Sin *Allow inprocess* o sin cliente de Oracle | Ver *Proveedor de Oracle* en la configuración |
| No llegan correos | Falla de Database Mail | `SELECT * FROM msdb.dbo.sysmail_event_log ORDER BY log_date DESC;` y `sysmail_faileditems` |

Para cualquier corrida con problema, el detalle siempre queda en `ops.CORRIDA.MENSAJE` y en `ops.BITACORA` (paso por paso).
