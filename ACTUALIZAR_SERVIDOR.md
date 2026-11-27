# Actualizar el servidor (BNABAJ_486)

Esta guía lleva tu base (`BNABAJ_486` en `STCSVASIGNAC044\MULTISQLSERVER`) a la versión actual de `main`. Todos los scripts de `sql/` se pueden volver a correr sobre una base con datos: crean solo lo que falta y reemplazan los procedimientos.

Tiempo aproximado: 20 minutos, sin contar la migración.

## Lo que hace la versión actual

- **Etiqueta 6 (REE).** El etiquetado sale de la base maestra: TDC `ENFOQUE_PLAN DE PAGOS`, Consumo `ENFOQUE_REESTRUCTURA`. Hipotecario todavía no tiene regla. El REE se quita en dos casos:
  - **Por la base:** la cuenta llega en la base maestra sin la leyenda y ya estaba etiquetada. Se blanquea al actualizar las existentes, queda el registro como `BASE` y la etiqueta vacía sube a CYBER en el SCBSDOS.
  - **Por tramo:** el tramo que manda el banco en el archivo de saldos (`SEG` del DAT, que en el DAT de Operación es `ETIQUETA3`) no es elegible. En TDC solo son elegibles `VEN2` y `VEN3` (`VEN4` y `CCAS` pierden el REE). En Consumo, de `1-29` a `90+` (`CASTIGADA` lo pierde). Corre en la actualización (el blanqueo sube a CYBER en `ACT_PVS_REE` como `u1ext2 = ''`) y en la asignación (va en el SCBSDOS). Una cuenta sin tramo, por ejemplo una nueva que todavía no trae saldos, no se toca.
  - Los tramos elegibles están en los catálogos `ETIQUETA6_SEG_TDC` y `ETIQUETA6_SEG_CONSUMO` (`SI` conserva, `NO` blanquea). Un tramo que no está en el catálogo también blanquea, y queda un AVISO en la bitácora con el valor y cuántas cuentas lo traen. Si el banco manda un tramo nuevo que sí es elegible:

```sql
USE [BNABAJ_486];
EXEC cfg.sp_catalogo_alta @catalogo = 'ETIQUETA6_SEG_TDC', @origen = N'VEN1', @destino = N'SI';
SELECT * FROM ops.ETIQUETA6_BLANQUEO WHERE ID_CORRIDA = <corrida>;          -- qué se blanqueó (TIPO = BASE o TRAMO)
UPDATE cfg.PARAMETRO SET VALOR = '0' WHERE CLIENTE = '486' AND CLAVE = 'ETIQUETA6_BLANQUEO';   -- solo si hay que apagarlo
```

- **ETIQUETA6 en el DAT.** La etiqueta vive en `dat.DAT_486.ETIQUETA6`; `ops.ETIQUETA6_BLANQUEO` registra solo a quién se le quitó y por qué. También sale en la tabla de AEM (`aem.DAT_486`, columna `ETIQUETA06`) y en el CSV del DAT para MIS (`DAT486_<aaaammdd>.csv`, última columna `ETIQUETA6`).
- **Correos** con el formato del equipo (`Documento1.txt` de Banbaj_banc), con la firma del buzón del 486 (`asig.486.cdmx@sertec.com.mx`) y los colores de BanBajío: encabezado morado `#a54686` y acento rojo `#ed1c24`, con los grises del formato de ejemplo. Los correos de alerta (importancia alta) llevan una franja roja y el ícono "!". Las tablas de los correos usan los mismos colores. La semilla reemplaza el cuerpo de las plantillas y la firma; el asunto, la lista y la importancia que hayas cambiado se respetan.
- **Pruebas de entorno.** Con el modo de prueba encendido, cada actualización o asignación queda anotada en `ops.PRUEBA_CORRIDA` desde que empieza. Así el paso 7 de `pruebas_entorno/` la revierte aunque el paso 6 se corte a la mitad. El paso 7 también lista las corridas que arrancaron con el modo encendido aunque no estén anotadas, y acepta `@anotar_corrida` para agregar una a mano.
- **La semilla conserva** `LLAVE_RIESGO_MIGRADA`, `MIGRACION_LIMPIA` y `PRUEBAS_LIMPIAS`.
- **Llave única por riesgo.** La llave del DAT y del histórico es el riesgo en todos los segmentos (en TDC, el ACC_NUM). La cuenta armada de TDC queda en `CTA_BANCO` y sigue yendo a CYBER (DMSSNUM, SCBPAG, etiquetas). Consumo e Hipotecario devuelven por riesgo.
- **Validación de la entrada.** Antes de tocar el DAT se revisa el layout y los datos de cada archivo: importes, teléfonos, correos, catálogos, cuentas repetidas, riesgo repetido o con letras, archivo idéntico al de un día anterior, saldos que no cruzan con el DAT y volumen. Si algo no pasa, la corrida se detiene (CANCELADA) y llega `VALIDACION_ENTRADA_486`. Avisos sin parar: riesgo con otro RFC, cambio de segmento y pagos repetidos.
- **Una asignación por segmento.** Si el otro segmento llega más tarde, el job corre otra asignación solo con él; el arribo sigue cada asignación del día.
- **Proceso autónomo.** El job corre actualización y asignación, escribe los archivos, avisa al equipo de asignaciones y corre solo las depuraciones en CYBER cuando detecta que subieron los planos. A mano quedan subir los planos de ancho fijo y copiar la devolución a `Cyber_00`.
- **Teléfonos.** Con `TEL_DEPURACION = ACTUAL` la remesa completa va a CYBER. Con `DIFERENCIA`, Banbaj compara una foto de `PHONE` con nuestro archivo y a CYBER solo sube lo que cambia. Solo van los teléfonos cuya lada y longitud están en `cfg.PHNVAL`, la copia de PHNVAL de CYBER que se renueva sola el día 1 de cada mes.
- **Usuarios AEM y MIS.** Consultan directo su esquema en SQL Server, cada uno con su login. No reciben archivos.

## Rutas de entrada y salida

Las rutas `C:\` son del **servidor de SQL Server**, no de la PC de quien ejecuta. La cuenta del servicio de SQL Server debe poder leer las de entrada y escribir en las de salida.

| Qué | Ruta | Parámetro o dónde se cambia |
|---|---|---|
| **Entrada.** Bases maestras y archivos de actualización del banco | `\\192.168.50.13\q\CYBER\C_486\<año>\<mes>\<día>\` (ej. `Q:\CYBER\C_486\2026\noviembre\26\`). Mes en español y minúsculas, día con dos dígitos. Asignación: `BASE MAESTRA_TARJETA*.csv`, `BASE MAESTRA_CONSUMO*.csv`, `BASE MAESTRA_HIPOTECARIO*.csv`. Actualización: `SERTEC_Saldos_tdc*.txt`, `SERTEC_Saldos_Cons*.txt`, `SERTEC_Saldos_Hip*.txt` (apagado), `SERTEC_Pagos*.txt` | `cfg.ARCHIVO.RUTA` y `PATRON_NOMBRE` |
| **Entrada.** Tablas de CYBER (DELQMST, PHONE, PHONE_G1, ADDRESS, UDA1, RPT_DAT_486_1, PHNVAL, remesas, bitácora de banderas) | Servidor vinculado `[CYBER]` (Oracle), no es carpeta | `CYBER_LINKED_SERVER`, `cfg.sp_cyber_conectar` |
| **Entrada.** CSV de la migración desde FoxPro (una sola vez) | `C:\MIGRA486\<FUENTE>.csv` en el servidor de SQL Server | `@carpeta` de `ops.sp_migrar_486` |
| **Entrada.** CSV de exclusiones y etiquetas (cargas a mano) | La que indiques, visible para el servicio de SQL Server (ej. `C:\BANBAJ\486\CARGAS\`) | `@archivo` de `cfg.sp_exclusion_cargar` y `cfg.sp_etiqueta_cargar` |
| **Salida.** Archivos planos de cada corrida | `C:\BANBAJ\486\SALIDA\<aaaammdd>_corrida<id>\` (ej. `C:\BANBAJ\486\SALIDA\20261126_corrida125\`) | `RUTA_SALIDA` |
| **Salida.** Scripts de Oracle de esa corrida (ACT_SALDOS, ACT_PVS_REE, retiro, depuraciones) | `C:\BANBAJ\486\SALIDA\<aaaammdd>_corrida<id>\cyber\` | `RUTA_SALIDA` |
| **Salida.** Copia del DAT para MIS | `\\192.168.50.13\q\MIS\SERTEC98\CLIENTES\486\DAT486_<aaaammdd>.csv` | `RUTA_MIS` |
| **Salida.** ZIP de retiros con contraseña | `C:\RETIROS_PAG_486_<mmddaaaahhmmss>.zip` | `CARPETA_ZIP` (contraseña: credencial `ZIP_RETIROS`) |
| **Salida.** Devolución para CYBER (`MX_G1MCT_DVBJIG_<aaaammdd>_<hhmmss>`) | Se escribe en la carpeta de la corrida; se copia a `\\192.168.50.1\Cyber_00\dev\` a mano mientras el parámetro esté vacío | `RUTA_DEVOLUCION_CYBER` |
| Programa para el ZIP | `C:\Program Files\7-Zip\7z.exe` | `RUTA_7ZIP` |
| Carpeta de las pruebas de entorno | `C:\BANBAJ\486\PRUEBA\` (se borra al terminar) | `@carpeta` de `ops.sp_prueba_modo` |
| Respaldo de la base antes de actualizar | `C:\BANBAJ\respaldo_BNABAJ_486_<aaaammdd>.bak` | Comando `BACKUP` del paso 0 |

Archivos que deja cada proceso en la carpeta de su corrida:

| Proceso | Archivos |
|---|---|
| Asignación | `SCBSDOS.TXT`, `SCBTEL.TXT`, `sub_mst.TXT`, `sub_mail.TXT`, `SCBACTH_486NU.TXT`, `SCBACTH_486REA.TXT`, `SCBACTH_SINTEL.TXT` (al subir los saldos), `DAT486_<aaaammdd>.csv` |
| Actualización | `SCBPAG.TXT`, `DAT486_<aaaammdd>.csv` y en `cyber\` los scripts `ACT_SALDOS`, `ACT_VENCIDO`, `ACT_PAGMIN` y `ACT_PVS_REE` (este último lleva también el blanqueo de ETIQUETA6) |
| Retiro | `SCBACTH_486.TXT`, `RETIROS_486_<aaaammdd>.csv`, `MX_G1MCT_DVBJIG_<aaaammdd>_<hhmmss>`, `DAT486_<aaaammdd>.csv` y el ZIP en `CARPETA_ZIP` |
| Etiquetado | `SCBSDOS.TXT`, `DAT486_<aaaammdd>.csv` |
| Blanqueo de status | `BLANQUEA_486_<aaaammdd>.csv` |

Para ver las rutas que tiene el servidor:

```sql
USE [BNABAJ_486];
SELECT CODIGO, PROCESO, RUTA, PATRON_NOMBRE, ACTIVO FROM cfg.ARCHIVO WHERE CLIENTE = '486' ORDER BY PROCESO, ORDEN;
SELECT CLAVE, VALOR FROM cfg.PARAMETRO WHERE CLIENTE = '486'
  AND CLAVE IN ('RUTA_SALIDA', 'RUTA_MIS', 'CARPETA_ZIP', 'RUTA_DEVOLUCION_CYBER', 'RUTA_7ZIP', 'CYBER_LINKED_SERVER');
```

## Pasos

### 0. Antes de empezar

1. Baja la última versión de `main` del repositorio (o descarga el ZIP).
2. Apaga el job y respalda la base:

```sql
EXEC msdb.dbo.sp_update_job @job_name = N'Banbaj 486 diario', @enabled = 0;   -- si ya lo creaste
BACKUP DATABASE [BNABAJ_486] TO DISK = N'C:\BANBAJ\respaldo_BNABAJ_486_<aaaammdd>.bak' WITH COPY_ONLY, INIT;
```

### 1. Guardar los parámetros que ya ajustaste

La semilla (`90_semilla_486.sql`) borra y vuelve a escribir los parámetros, los archivos de entrada y las plantillas del 486. Guarda los valores actuales para reponer los tuyos:

```sql
USE [BNABAJ_486];
IF OBJECT_ID('dbo.PARAMETRO_ANTES') IS NOT NULL DROP TABLE dbo.PARAMETRO_ANTES;
SELECT CLAVE, VALOR INTO dbo.PARAMETRO_ANTES FROM cfg.PARAMETRO WHERE CLIENTE = '486';
```

Las credenciales (Oracle y ZIP) no se borran: viven cifradas en otra tabla.

### 2. Correr todos los scripts de `sql/` en orden

En SSMS abre y ejecuta uno por uno (cada uno empieza con `USE [BNABAJ_486];`), en orden de nombre, todos los `.sql` de la carpeta `sql/` (de `01_esquemas_tablas.sql` a `90_semilla_486.sql`). No los de `sql/instalacion/`. Los archivos están en UTF-8: si al abrir uno en SSMS los acentos se ven raros (por ejemplo `Ã©`), ciérralo sin guardar y usa el comando de PowerShell de abajo, que los lee bien.

O, desde PowerShell en la carpeta del repositorio (se detiene en el primer error):

```powershell
Get-ChildItem .\sql\*.sql | Sort-Object Name | ForEach-Object {
    Write-Host $_.Name
    sqlcmd -S "STCSVASIGNAC044\MULTISQLSERVER" -d BNABAJ_486 -E -b -I -f 65001 -i $_.FullName
    if ($LASTEXITCODE -ne 0) { throw "Falló $($_.Name)" }
}
```

Si un script marca error, el ciclo se detiene ahí y los siguientes no se instalan: corrige y vuelve a correr el ciclo completo (todos se pueden repetir). Si sale `Msg 3729 … fn_texto … referenced by object 'fn_fecha'`, tienes una copia vieja de `10_funciones.sql`: baja otra vez `main`.

Al terminar, comprueba:

```sql
USE [BNABAJ_486];
SELECT COUNT(*) AS PROCEDIMIENTOS FROM sys.procedures;                                       -- al menos 74
SELECT VALOR FROM cfg.PARAMETRO WHERE CLIENTE = '486' AND CLAVE = 'CYBER_HOSTUP_EXPR';       -- to_char(DMHOSTUP, 'YYYYMMDD')
SELECT CASE WHEN OBJECT_DEFINITION(OBJECT_ID('ops.sp_arribo_bajar')) LIKE '%CYBER_HOSTUP%' THEN 'nuevo' ELSE 'VIEJO' END AS SP_ARRIBO_BAJAR;
```

### 3. Reponer tus parámetros

Revisa qué valores tuyos cambió la semilla:

```sql
USE [BNABAJ_486];
SELECT a.CLAVE, a.VALOR AS TUYO, p.VALOR AS NUEVO
FROM dbo.PARAMETRO_ANTES a
JOIN cfg.PARAMETRO p ON p.CLIENTE = '486' AND p.CLAVE = a.CLAVE
WHERE ISNULL(a.VALOR, N'') <> ISNULL(p.VALOR, N'')
ORDER BY a.CLAVE;
```

- Repón siempre `CYBER_ORACLE_ORIGEN`, con puerto y servicio: `192.168.90.10:1521/NOMBRE_SERVICIO` (sale del `tnsnames.ora` de la PC donde corre sqlldr, o te lo da el DBA con `lsnrctl status`).
- Repón también cualquier otro parámetro que hayas ajustado a mano, como rutas o tu correo de prueba.
- **No** repongas `ARRIBO_AUTOMATICO`, `ACT_CYBER_AUTOMATICO`, `RETIRO_CYBER_AUTOMATICO`, `BLANQUEO_AUTOMATICO`, `CONFIRMACION_AUTOMATICA` ni `RUTA_DEVOLUCION_CYBER`: sus valores de la semilla (1, 1, 1, 1, 1 y vacío) son el proceso autónomo.
- `VALIDAR_LAYOUT` y `VALIDAR_DATOS` vienen en 1. No escriben en CYBER, solo detienen y avisan al equipo de asignaciones, así que conviene dejarlos prendidos también durante el paralelo.
- Lo que cambies en `cfg.ARCHIVO` (carpeta, nombre), en `cfg.ARCHIVO_COLUMNA` (encabezados), en los catálogos y en las reglas de datos se conserva cuando vuelvas a correr la semilla. Si habías cambiado la carpeta de entrada de algún archivo, vuelve a dejar la de fábrica: `\\192.168.50.13\q\CYBER\C_486\{AAAA}\{MES}\{DD}\`.

```sql
USE [BNABAJ_486];
UPDATE cfg.PARAMETRO SET VALOR = N'192.168.90.10:1521/NOMBRE_SERVICIO' WHERE CLIENTE = '486' AND CLAVE = 'CYBER_ORACLE_ORIGEN';
-- UPDATE cfg.PARAMETRO SET VALOR = N'<tu valor>' WHERE CLIENTE = '486' AND CLAVE = N'<clave>';   -- uno por cada parámetro tuyo
```

### 4. Contraseñas y conexión a CYBER

Conviene cambiar la contraseña de Oracle de SACASIG y la del ZIP con el DBA y Operación. Con las nuevas:

1. Edita en tu equipo `sql/instalacion/03_parametros_y_credenciales.sql`: origen con puerto y servicio, usuario, contraseña de Oracle y contraseña del ZIP.
2. Córrelo. Al terminar, bórralo o deja otra vez los `<<…>>`; no lo subas con los valores.

Ese script guarda las credenciales cifradas, corre `EXEC cfg.sp_cyber_conectar;` y baja los status como prueba. Si no quieres cambiar las contraseñas todavía, solo corre `EXEC cfg.sp_cyber_conectar;`.

Prueba la conexión y la validación de saldos:

```sql
USE [BNABAJ_486];
EXEC ops.sp_bajar_cyber 'STATUS', @solo_bajar = 1;      -- debe decir "STATUS: n registros bajados"
EXEC ops.sp_arribo_bajar;                                -- baja DELQMST, DMHOSTUP y PHONE_G1
SELECT FECHA, CUENTAS FROM stg.CYBER_HOSTUP ORDER BY FECHA DESC;   -- lo mismo que val.txt, con la fecha en AAAAMMDD
```

- Si sale vacío, revisa primero el paso 2: con el parámetro vacío o el procedimiento viejo no se baja nada.
- Debe mostrar lo mismo que `val.txt`: `DMHOSTUP` es fecha sin hora y no hay que hacer nada.
- Si `ops.sp_arribo_bajar` marcara error en `to_char`, pon `UPDATE cfg.PARAMETRO SET VALOR = N'DMHOSTUP' WHERE CLIENTE = '486' AND CLAVE = 'CYBER_HOSTUP_EXPR';` y repite (también se leen fechas `DD/MM/AA`).

### 5. Accesos

Revisa que `@base` en `sql/instalacion/04_accesos_remotos.sql` diga `BNABAJ_486` y córrelo. Se saltan `sa`, los sysadmin, el dueño de la base y quien corre el script.

### 6. Migración (cuando corresponda)

Solo si todavía no se ha migrado desde FoxPro. Si ya está migrado, sáltala.

**6.1 Actualizar el procedimiento de migración.** Abre `sql/80_sp_migracion.sql` y córrelo completo. Solo reemplaza procedimientos y no toca datos. Revisa:

```sql
USE [BNABAJ_486];
SELECT name, modify_date FROM sys.procedures
 WHERE name IN ('sp_migrar_486', 'sp_mig_leer', 'sp_mig_diagnostico');   -- tres renglones, con la fecha de hoy
```

**6.2 Exportar los DBF.** Copia el `cyber/486/EXPORTAR_MIGRACION.prg` a la PC de FoxPro y córrelo (`DO EXPORTAR_MIGRACION.prg`).

- En la ventana final no debe aparecer PURGA, y en BLACKLIST no deben faltar TELEFONO ni FECHA.
- El programa cambia por apóstrofo las comillas dobles y las tipográficas (‘ ’ “ ” ´ `), y por espacio los caracteres de control y los bytes que no existen en Windows-1252.
- Exporta todo de nuevo: los CSV anteriores no sirven.

**6.3 Copiar los CSV al servidor.** Cópialos a `C:\MIGRA486\` **del servidor** y reemplaza los que ya estaban. SQL Server lee esa carpeta del servidor, no la de la PC de FoxPro: si ahí quedó un CSV viejo, falla aunque el nuevo esté bien.

**6.4 Revisar sin escribir:**

```sql
USE [BNABAJ_486];
EXEC ops.sp_migrar_486 @carpeta = N'C:\MIGRA486\';
```

Detalle de cada aviso: *Migración paso a paso Banbaj 486*.

**6.5 Si un CSV no se puede leer.** Sale el error 50905 con lo que ve el servidor, sin datos del banco:

```
C:\MIGRA486\HISTORIA.csv: SQL Server no pudo leer el CSV (…). El servidor ve 1804214 renglones, modificado el 2026-11-17 20:40, … bytes.
Casi todos traen 62 comillas; con otro número: 1 (renglones 151946: comillas dentro de un campo). Caracteres raros: U+2019 en 3 renglones (primero el 151946).
```

- **Fecha de modificación anterior a la última exportación:** el servidor tiene un CSV viejo; repite el 6.3.
- **Comillas con otro número:** el CSV salió con un programa anterior; repite el 6.2 y el 6.3.
- **Caracteres raros:** mándame los códigos `U+…` y los agrego a la limpieza del programa.
- Para ver un renglón y sus vecinos enmascarados (letra = `x`, dígito = `9`, raros = `<U+…>`), con cuántas comillas y campos tiene cada uno:

```sql
USE [BNABAJ_486];
EXEC ops.sp_mig_diagnostico N'C:\MIGRA486\HISTORIA.csv', 151946;
```

El renglón 1 es el encabezado, igual que en el Bloc de notas. Con HISTORIA el diagnóstico tarda un par de minutos.

**6.6 Cargar.** Si los avisos están bien (si ya cargaste algo, agrega `@reemplazar = 1`):

```sql
USE [BNABAJ_486];
EXEC ops.sp_migrar_486 @carpeta = N'C:\MIGRA486\', @confirmar = 1;
```

Carga todo en una sola transacción: si algo falla, no queda nada a medias. Al final pasa lo cargado a la llave por riesgo (`ops.sp_llave_riesgo_migrar`): en TDC la llave deja de ser la cuenta armada y pasa a ser el ACC_NUM; la armada queda en `CTA_BANCO`. Muestra cuántas cuentas cambiaron y cuántas se quedaron con la llave de antes (TDC sin RIESGO, con RIESGO de más de 20 caracteres o repetido). Esas no se van a reconocer en la siguiente base: revísalas.

La ETIQUETA6 (REE) no viene de FoxPro: al cargar se toma de CYBER (`U1EXT2`) con `ops.sp_etiqueta6_desde_cyber`. Si el servidor vinculado todavía no está, sale un aviso; córrelo a mano antes de la primera asignación (`EXEC ops.sp_etiqueta6_desde_cyber @confirmar = 1;`).

**6.7 Revisar lo cargado:**

```sql
USE [BNABAJ_486];
SELECT COUNT(*) AS CUENTAS, MIN(FE_ASIG) AS PRIMERA, MAX(FE_ASIG) AS ULTIMA,
       SUM(CASE WHEN FE_ASIG IS NULL THEN 1 ELSE 0 END) AS SIN_FECHA FROM dat.DAT_486;    -- SIN_FECHA debe ser 0 (fechas AAAA/MM/DD)
SELECT ESTATUS, COUNT(*) FROM dat.HISTORIA_FOLIO WHERE CLIENTE = '486' GROUP BY ESTATUS;   -- A = activas del DAT, B = periodos anteriores
SELECT COUNT(*) FROM dat.HISTORIA_FOLIO WHERE CLIENTE = '486' AND ESTATUS = 'B' AND FE_ALTA IS NULL;   -- periodos anteriores, sin fechas
```

**6.8 Borrar** `C:\MIGRA486\` en los dos equipos (trae datos de clientes).

### 7. Job

- Si todavía no lo creas, corre `sql/instalacion/02_crear_job_486.sql` con `@base = N'BNABAJ_486'`.
- **Durante el paralelo con FoxPro, o mientras no funcione la conexión a CYBER del paso 4,** apaga lo que escribe en CYBER o manda correos, para que solo FoxPro toque CYBER:

```sql
USE [BNABAJ_486];
UPDATE cfg.PARAMETRO SET VALOR = '0' WHERE CLIENTE = '486'
   AND CLAVE IN ('ARRIBO_AUTOMATICO', 'RETIRO_AUTOMATICO', 'RETIRO_CYBER_AUTOMATICO', 'ACT_CYBER_AUTOMATICO',
                 'BLANQUEO_AUTOMATICO', 'CONFIRMACION_AUTOMATICA', 'CUADRE_AUTOMATICO');
```

- **En producción** ponlos en `'1'` con la misma consulta y enciende el job:

```sql
EXEC msdb.dbo.sp_update_job @job_name = N'Banbaj 486 diario', @enabled = 1;
```

### 8. Pruebas de entorno (antes del paralelo)

Corre en SSMS, en orden, los scripts de `pruebas_entorno/` (ver su `LEEME.md`). Prueban con los archivos reales del día, sin escribir en CYBER y con los correos redirigidos a tu dirección. Termina con `08_modo_prueba_apagar.sql`.

### 9. Verificar

```sql
USE [BNABAJ_486];
SELECT CLAVE, VALOR FROM cfg.PARAMETRO WHERE CLIENTE = '486'
 AND CLAVE IN ('CYBER_ORACLE_ORIGEN', 'CYBER_HOSTUP_EXPR', 'ARRIBO_SDOS_MIN_PCT', 'ARRIBO_AUTOMATICO', 'ACT_CYBER_AUTOMATICO',
               'RETIRO_AUTOMATICO', 'RETIRO_CYBER_AUTOMATICO', 'BLANQUEO_AUTOMATICO', 'CONFIRMACION_AUTOMATICA',
               'CUADRE_AUTOMATICO', 'EXPORTAR_AUTOMATICO', 'AVISO_ARCHIVOS', 'RUTA_DEVOLUCION_CYBER',
               'VALIDAR_LAYOUT', 'VALIDAR_DATOS', 'ETIQUETA6_BLANQUEO', 'LLAVE_RIESGO_MIGRADA', 'TEL_DEPURACION')
 ORDER BY CLAVE;
SELECT PROCESO, CODIGO, PATRON_NOMBRE, NUM_COLUMNAS FROM cfg.ARCHIVO WHERE CLIENTE = '486' AND ACTIVO = 1 ORDER BY PROCESO, ORDEN;   -- ACT en .txt, ASIG en .csv; TDC 100 y Consumo 115
SELECT a.CODIGO, c.PATRON_ENCABEZADO FROM cfg.ARCHIVO_COLUMNA c JOIN cfg.ARCHIVO a ON a.ID_ARCHIVO = c.ID_ARCHIVO
 WHERE a.CLIENTE = '486' AND c.CAMPO_DESTINO = 'SALDO2';                                                -- sin '<= 6'
SELECT CATALOGO, COUNT(*) AS VALORES FROM cfg.CATALOGO WHERE CLIENTE = '486' GROUP BY CATALOGO;              -- 10 catálogos
SELECT CODIGO, COUNT(*) AS REGLAS FROM cfg.VALIDACION_DATO WHERE CLIENTE = '486' GROUP BY CODIGO;             -- reglas por archivo
SELECT ARCHIVO, CAMPO, PATRON_ENCABEZADO, ESTADO FROM cfg.v_LAYOUT WHERE ESTADO NOT IN ('OK', 'DERIVADO', 'SIN ARCHIVO');   -- vacío, o lo que el último archivo no traía
SELECT * FROM cfg.CYBER_CAMPO;                                                                         -- ESTATUS, ABAN_SR, ABAN_CR, SDO_CYBER
SELECT * FROM cfg.v_CATALOGO WHERE CATALOGO LIKE 'ETIQUETA6%';
SELECT COUNT(*) AS LADAS FROM cfg.PHNVAL;                                                             -- 459 al cargarla
EXEC ops.sp_diario_486 @fecha = '2026-11-14';   -- sábado: debe contestar FIN DE SEMANA sin hacer nada
```

Para AEM y MIS (si aún no tienen login):

```sql
USE [BNABAJ_486];
EXEC ops.sp_vistas_usuario_refrescar @id_corrida = <última corrida OK>, @forzar = 1;     -- bajada de CYBER y tablas
SELECT TOP (10) * FROM aem.DAT_486;
SELECT COUNT(*) AS RETIROS_HOY FROM aem.RETIROS_HOY;
EXEC cfg.sp_vista_usuario_login 'AEM', 'aem_banbaj', N'<contraseña>';                       -- la contraseña no se guarda
EXEC cfg.sp_vista_columna_alta 'MIS', N'CUENTA', 'DAT', N'CUENTA2';
EXEC cfg.sp_vista_columna_alta 'MIS', N'<ENCABEZADO>', 'MAESTRA', N'<encabezado de la base maestra>';
UPDATE cfg.VISTA_USUARIO SET ACTIVO = 1 WHERE CLIENTE = '486' AND VISTA = 'MIS';
EXEC ops.sp_vistas_usuario_armar;
EXEC cfg.sp_vista_usuario_login 'MIS', 'mis_banbaj', N'<contraseña>';
```

La columna MAESTRA (para MIS) se llena con cada asignación, que es cuando se guarda la base maestra por cuenta.

Permisos de Oracle del usuario de `CYBER_ORACLE`: la lista completa está en `cyber/486/ARRIBO_MANUAL.md`.

Cuando todo cuadre, borra el respaldo de parámetros: `DROP TABLE dbo.PARAMETRO_ANTES;`.

### 10. Limpieza (cuando ya estés en producción)

Dos scripts de `sql/instalacion/`, se corren una vez y a mano. Cada uno viene con `@confirmar = 0` (solo muestra lo que borraría): se revisa la lista, se cambia a `1` y se corre otra vez.

- `05_limpiar_migracion.sql`: borra `ops.sp_migrar_486`, `ops.sp_llave_riesgo_migrar`, `ops.fn_mig_faltan` y las tablas y vistas de paso `stg.MIG_*`. No borra `ops.sp_mig_leer` ni `ops.sp_mig_diagnostico` (`sql/18_sp_lectura_csv.sql`), que siguen usando las cargas de exclusiones. No toca el DAT, el histórico, los pagos, las etiquetas ni las exclusiones.
- `06_limpiar_pruebas.sql`: borra los `ops.sp_prueba_*`, `ops.PRUEBA_PARAM`, `ops.PRUEBA_CORRIDA` y las corridas de lectura de prueba (`PROCESO = 'PRUEBA'`) con lo que dejaron. No borra las corridas ACT y ASIG del paso 7 de las pruebas: quedan en la bitácora como REVERTIDA. Los parámetros `CORREO_PRUEBA_PARA` y `CYBER_SOLO_LECTURA` se quedan (vacío y 0).

Se detienen sin borrar nada si: hay una corrida en proceso; el DAT está vacío; hay TDC sin `CTA_BANCO` y no se ha corrido el cambio de llave por riesgo (`05`); el modo de prueba sigue encendido; `CORREO_PRUEBA_PARA` tiene una dirección o `CYBER_SOLO_LECTURA` está en 1; o hay asignaciones de prueba sin revertir (`06`).

Dejan `MIGRACION_LIMPIA = 1` y `PRUEBAS_LIMPIAS = 1`: `sql/80_sp_migracion.sql` y `sql/85_sp_pruebas_entorno.sql` no vuelven a crear nada, así que se puede seguir corriendo todo `sql/` al actualizar. Para volver a probar, borra `PRUEBAS_LIMPIAS` y corre `sql/85_sp_pruebas_entorno.sql`.

Al terminar, borra `C:\MIGRA486\` y `C:\BANBAJ\486\PRUEBA\`: traen datos de clientes.

### 11. Si llega el correo de validación de la entrada

Cuando llega un archivo que no cuadra (por ejemplo, un Hipotecario), la corrida se detiene antes de tocar el DAT y llega `VALIDACION_ENTRADA_486` con qué falta y qué hacer. Lo usual:

```sql
USE [BNABAJ_486];
EXEC cfg.sp_layout_cambiar 'MAESTRA_HIPO', 'SDO_ACT', N'encabezado como viene en el archivo';   -- encabezado que cambió
EXEC cfg.sp_catalogo_alta 'ESTATUS_TDC', N'VEN1', N'';                                           -- estatus nuevo válido
SELECT * FROM ops.VALIDACION_ENTRADA WHERE ID_CORRIDA = <corrida> ORDER BY DETIENE DESC;          -- todo lo que encontró
EXEC ops.sp_asignacion_486 @fecha = '<AAAA-MM-DD>';                                               -- volver a correr
```

Detalle: *Flujo y diagramas*, sección 09.

## Teléfonos por diferencia

Para pasar a `TEL_DEPURACION = DIFERENCIA`, el DBA de CYBER instala primero `cyber/486/oracle/JSP_TELEFONOS_DEPURA_486.sql`: crea la tabla `RCVRY.JSP_TAB_TEL_DEPURA_486` (los cambios que manda Banbaj: I = inactivar, A = activar, N = nuevo) y el store, que revisa que estén completos, inactiva y activa sin tocar gestores de queja, llena `JSP_VALIDADOR_TELEFONOS` y anota cada etapa en `RPT_LOG_CYBER` con la bandera 416. En el encabezado vienen los `GRANT`; el usuario de `CYBER_ORACLE` además necesita `SELECT` en `RCVRY.PHONE` para la foto. Después:

```sql
USE [BNABAJ_486];
UPDATE cfg.PARAMETRO SET VALOR = 'DIFERENCIA' WHERE CLIENTE = '486' AND CLAVE = 'TEL_DEPURACION';
```

La primera vez conviene verlo sin tocar CYBER: después de la asignación, con los saldos arriba, corre `EXEC ops.sp_tel_depura_calcular <corrida>;` y revisa el renglón `TEL DIFERENCIA` de la bitácora (cuántos se inactivan, activan y son nuevos). Si los números se ven bien, deja que el job siga. Para regresar a la remesa completa: `VALOR = 'ACTUAL'`.

Con `DIFERENCIA`, el SCBTEL trae solo los teléfonos nuevos; si no hay, no llega aviso de SCBTEL.

## Avisos al equipo de asignaciones

- El primer correo de archivos listos trae solo el SCBSDOS (y el SCBPAG).
- Cuando suben los saldos, llega otro aviso con los gescar de nuevas, reasignadas y sin teléfono (`SCBACTH_SINTEL.TXT`).
- Enseguida corre la depuración de teléfonos. Si la remesa en CYBER tiene los mismos renglones que nuestro archivo, llega el aviso del SCBTEL. **El SCBTEL no se sube antes de ese aviso.** Si no cuadra, llega un hallazgo y no sale el SCBTEL.
- Puede haber dos asignaciones el mismo día (una por segmento), cada una con su aviso de archivos y su confirmación.
- Una base con riesgos repetidos, idéntica a la del día anterior o con riesgos con letras se detiene con `VALIDACION_ENTRADA_486`.
- AEM no recibe `MX_G1MCT_DVBJIG_*` en Cyber_00: las cuentas retiradas del día están en `aem.RETIROS_HOY`.
