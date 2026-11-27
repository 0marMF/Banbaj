# Qué volver a ejecutar en el servidor (actualización del 26/11/2026)

Esta guía lleva tu base (`BNABAJ_486` en `STCSVASIGNAC044\MULTISQLSERVER`) a la versión actual de `main`. Vale para una base instalada en cualquier fecha a partir del 03/11. Todos los scripts de `sql/` se pueden volver a correr sobre una base con datos: crean solo lo que falta y reemplazan los procedimientos.

Tiempo aproximado: 20 minutos, sin contar la migración.

## Blanqueo de ETIQUETA6, correos nuevos y limpieza (26/11)

Si ya tienes la versión del 20/11, esto es lo que cambia:

- **Blanqueo de ETIQUETA6 (REE)**, con las reglas del correo "RE: Etiquetado REE" (23/11). El etiquetado sigue saliendo de la base maestra (TDC: `ENFOQUE_PLAN DE PAGOS`; Consumo: `ENFOQUE_REESTRUCTURA`). El REE se quita en dos casos:
  - **Por la base:** la cuenta llega en la base maestra sin la leyenda y ya estaba etiquetada. Se blanquea al actualizar las existentes, queda el registro como `BASE` y la etiqueta vacía sube a CYBER en el SCBSDOS.
  - **Por tramo:** el tramo que manda el banco en el archivo de saldos (`SEG` del DAT, que en el DAT de Operación es `ETIQUETA3`) ya no es elegible. En TDC solo son elegibles `VEN2` y `VEN3` (`VEN4` y `CCAS` lo pierden). En Consumo, de `1-29` a `90+` (`CASTIGADA` lo pierde). Corre en la actualización (el blanqueo sube a CYBER en el script `ACT_PVS_REE` como `u1ext2 = ''`) y en la asignación (va en el SCBSDOS). Una cuenta sin tramo, por ejemplo una nueva que todavía no trae saldos, no se toca. Hipotecario no se revisa.
  - Los tramos elegibles están en los catálogos `ETIQUETA6_SEG_TDC` y `ETIQUETA6_SEG_CONSUMO` (`SI` conserva, `NO` blanquea). Un tramo que no está en el catálogo también blanquea, y queda un AVISO en la bitácora con el valor y cuántas cuentas lo traen. Si el banco manda un tramo nuevo que sí es elegible:

```sql
USE [BNABAJ_486];
EXEC cfg.sp_catalogo_alta @catalogo = 'ETIQUETA6_SEG_TDC', @origen = N'VEN1', @destino = N'SI';
SELECT * FROM ops.ETIQUETA6_BLANQUEO WHERE ID_CORRIDA = <corrida>;          -- qué se blanqueó (TIPO = BASE o TRAMO)
UPDATE cfg.PARAMETRO SET VALOR = '0' WHERE CLIENTE = '486' AND CLAVE = 'ETIQUETA6_BLANQUEO';   -- solo si hay que apagarlo
```

- **ETIQUETA6 inicial desde CYBER al migrar:** FoxPro no trae la ETIQUETA6. Al cargar, `ops.sp_migrar_486` toma el REE que hoy tiene CYBER (`U1EXT2` de `RCVRY.UDA1`) para las cuentas del DAT. Así la primera asignación de un segmento no le borra el REE al otro: el SCBSDOS lleva todo el DAT. Solo toma valores del catálogo (hoy `REE`) y no pisa una etiqueta que ya exista. Si al migrar no hay servidor vinculado, sale un aviso y se corre a mano antes de la primera asignación: `EXEC ops.sp_etiqueta6_desde_cyber;` (vista previa) y luego `@confirmar = 1`.
- **Pruebas de entorno más seguras:** con el modo de prueba encendido, cada actualización o asignación queda anotada en `ops.PRUEBA_CORRIDA` desde que empieza. Así el paso 7 la revierte aunque el script del paso 6 se corte a la mitad.
- **Correos con el formato del equipo** (`Documento1.txt` de Banbaj_banc), con la firma del buzón del 486 (`asig.486.cdmx@sertec.com.mx`) y los colores de BanBajío: encabezado morado `#a54686` y acento rojo `#ed1c24` (los dos colores del logotipo), con los grises del formato de ejemplo. Los correos de alerta (importancia alta) llevan una franja roja y el ícono "!". Las tablas de los correos (hallazgos, archivos listos, validación) usan los mismos colores. La semilla **reemplaza el cuerpo** de las plantillas y la firma. El asunto, la lista y la importancia que hayas cambiado se respetan.
- **Limpieza para dejar la base solo con lo de producción** (scripts nuevos en `sql/instalacion/`, se corren una vez y a mano):
  - `05_limpiar_migracion.sql`: borra `ops.sp_migrar_486`, `ops.sp_llave_riesgo_migrar`, `ops.fn_mig_faltan` y las tablas y vistas de paso `stg.MIG_*` que hayan quedado. No borra `ops.sp_mig_leer` ni `ops.sp_mig_diagnostico`, que se pasaron a `sql/18_sp_lectura_csv.sql` porque las cargas de exclusiones los siguen usando. Se detiene si el DAT está vacío o si falta el cambio de llave por riesgo.
  - `06_limpiar_pruebas.sql`: borra los `ops.sp_prueba_*`, `ops.PRUEBA_PARAM`, `ops.PRUEBA_CORRIDA` y las corridas de lectura de prueba (`PROCESO = 'PRUEBA'`) con lo que dejaron. Se detiene si el modo de prueba sigue encendido o si quedó una asignación de prueba sin revertir.
  - Los dos vienen con `@confirmar = 0` (solo muestran lo que borrarían). Se cambia a `1` y se corren otra vez. Dejan `MIGRACION_LIMPIA = 1` y `PRUEBAS_LIMPIAS = 1`, y con eso `80_sp_migracion.sql` y `85_sp_pruebas_entorno.sql` ya no vuelven a crear nada, así que se sigue pudiendo correr todo `sql/` al actualizar.
- **La semilla ya no borra `LLAVE_RIESGO_MIGRADA`** (ni las dos marcas de limpieza). Antes, cada vez que se corría la semilla se perdía, y con ella el freno que impide revertir corridas de antes del cambio de llave. Si ya corriste `ops.sp_llave_riesgo_migrar` y después la semilla, vuelve a poner la marca con la última corrida de antes del cambio:

```sql
USE [BNABAJ_486];
SELECT CLAVE, VALOR FROM cfg.PARAMETRO WHERE CLIENTE = '486' AND CLAVE = 'LLAVE_RIESGO_MIGRADA';   -- si no sale nada:
INSERT INTO cfg.PARAMETRO (CLIENTE, CLAVE, VALOR, DESCRIPCION)
VALUES ('486', 'LLAVE_RIESGO_MIGRADA', '<última corrida antes del cambio>', N'Corridas hasta esta no se revierten (llave vieja)');
```

- **`sql/instalacion/01_configurar_servidor.sql`** tenía en su comentario de arriba un `/*` de más, y SSMS marcaba `Missing end comment mark`. Ya está corregido. Si lo corriste sin error, no hay que hacer nada.

Qué correr:

1. **Apaga el job, respalda la base** (paso 0) y **guarda tus parámetros** (paso 1).
2. **Corre todos los scripts de `sql/` en orden** (paso 2). Incluye el nuevo `18_sp_lectura_csv.sql`.
3. **Repón tus parámetros** (paso 3). El parámetro nuevo es `ETIQUETA6_BLANQUEO = 1`.
4. **Manda un correo de prueba** para ver el formato nuevo: `EXEC ops.sp_prueba_correo;` (o el paso 3 de las pruebas de entorno).
5. Cuando ya estés en producción y no vayas a migrar ni probar otra vez: `sql/instalacion/05_limpiar_migracion.sql` y `06_limpiar_pruebas.sql`, primero con `@confirmar = 0` y después con `1`. Al terminar, borra `C:\MIGRA486\` y `C:\BANBAJ\486\PRUEBA\`.
6. **Prende el job.**

## Rutas de entrada y salida

Las rutas `C:\` son del **servidor de SQL Server**, no de la PC de quien ejecuta. La cuenta del servicio de SQL Server debe poder leer las de entrada y escribir en las de salida.

| Qué | Ruta | Parámetro o dónde se cambia |
|---|---|---|
| **Entrada.** Bases maestras y archivos de actualización del banco | `\\192.168.50.13\q\CYBER\C_486\<año>\<mes>\<día>\` (= `Q:\CYBER\C_486\2026\noviembre\26\`). Mes en español y minúsculas, día con dos dígitos. Asignación: `BASE MAESTRA_TARJETA*.csv`, `BASE MAESTRA_CONSUMO*.csv`, `BASE MAESTRA_HIPOTECARIO*.csv`. Actualización: `SERTEC_Saldos_tdc*.txt`, `SERTEC_Saldos_Cons*.txt`, `SERTEC_Saldos_Hip*.txt` (apagado), `SERTEC_Pagos*.txt` | `cfg.ARCHIVO.RUTA` y `PATRON_NOMBRE` |
| **Entrada.** Tablas de CYBER (DELQMST, PHONE, PHONE_G1, ADDRESS, UDA1, RPT_DAT_486_1, PHNVAL, remesas, bitácora de banderas) | Servidor vinculado `[CYBER]` (Oracle), no es carpeta | `CYBER_LINKED_SERVER`, `cfg.sp_cyber_conectar` |
| **Entrada.** CSV de la migración desde FoxPro (una sola vez) | `C:\MIGRA486\<FUENTE>.csv` en el servidor de SQL Server | `@carpeta` de `ops.sp_migrar_486` |
| **Entrada.** CSV de exclusiones y etiquetas (cargas a mano) | La que indiques, visible para el servicio de SQL Server (ej. `C:\BANBAJ\486\CARGAS\`) | `@archivo` de `cfg.sp_exclusion_cargar` y `cfg.sp_etiqueta_cargar` |
| **Salida.** Archivos planos de cada corrida | `C:\BANBAJ\486\SALIDA\<aaaammdd>_corrida<id>\` (ej. `C:\BANBAJ\486\SALIDA\20261126_corrida125\`) | `RUTA_SALIDA` |
| **Salida.** Scripts de Oracle de esa corrida (ACT_SALDOS, ACT_PVS_REE, retiro, depuraciones) | `C:\BANBAJ\486\SALIDA\<aaaammdd>_corrida<id>\cyber\` | `RUTA_SALIDA` |
| **Salida.** Copia del DAT para MIS | `\\192.168.50.13\q\MIS\SERTEC98\CLIENTES\486\DAT486_<aaaammdd>.csv` | `RUTA_MIS` |
| **Salida.** ZIP de retiros con contraseña | `C:\RETIROS_PAG_486_<mmddaaaahhmmss>.zip` | `CARPETA_ZIP` (contraseña: credencial `ZIP_RETIROS`) |
| **Salida.** Devolución para CYBER (`MX_G1MCT_DVBJIG_<aaaammdd>_<hhmmss>`) | Se escribe en la carpeta de la corrida; se copia a `\\192.168.50.1\Cyber_00\dev\` (a mano mientras el parámetro esté vacío) | `RUTA_DEVOLUCION_CYBER` |
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

## Qué cambió desde el 03/11

| Cambio | Scripts |
|---|---|
| Proceso autónomo: depuraciones de correos y teléfonos, scripts de la actualización, retiro en CYBER, blanqueo y confirmación automáticos (la copia de la devolución a `Cyber_00` sigue a mano) | `90_semilla_486.sql`, `60`, `77`, `78` |
| Saldos del día detectados con la consulta de `val.txt` (`DMHOSTUP` del día = cuentas del SCBSDOS). `DMHOSTUP` quedó confirmado como fecha sin hora (`13/11/26`, 6,855 cuentas) | `01_esquemas_tablas.sql` (tabla `stg.CYBER_HOSTUP`), `76_sp_arribo_cyber.sql`, semilla |
| Archivos de la actualización solo en `.txt`; bases maestras solo en `.csv` | semilla (`cfg.ARCHIVO`) |
| `cfg.sp_cyber_conectar` vuelve a crear el servidor vinculado y avisa si el origen de Oracle trae solo la IP | `74_sp_cyber.sql` |
| Histórico migrado sin fechas; PURGA sin usarse | `01_esquemas_tablas.sql`, `80_sp_migracion.sql` |
| Arribo en el orden del equipo (17/11 en la noche): al subir los saldos salen los gescar de nuevas y reasignadas y corre la depuración de teléfonos (la remesa debe tener los mismos renglones que nuestro archivo, error 50776 si no); después sale el SCBTEL y corren los correos; al subir el SCBTEL sale el gescar sin teléfono | `10_funciones.sql`, `52`, `76`, `77`, `78`, semilla (parámetros `ARCHIVOS_DESPUES_SALDOS` y `ARCHIVOS_DESPUES_DEPURACION_TEL`) |
| Migración (17/11 en la noche): si un CSV no se puede leer, el error 50905 dice qué ve el servidor y `ops.sp_mig_diagnostico` muestra el renglón enmascarado; fechas `AAAA/MM/DD`; el `.prg` limpia también las comillas tipográficas | `80_sp_migracion.sql`, `EXPORTAR_MIGRACION.prg` |
| Exportación de FoxPro sin comillas dobles ni caracteres de control (nulos, tabuladores, saltos de línea) en los campos de texto `C` y `V`: el error de `HISTORIA.csv`, renglón 151946, columna 29 (`DIRECC2`) | `cyber/486/EXPORTAR_MIGRACION.prg` (versión del 15/11 en la tarde) |
| Accesos: se saltan `sa`, los sysadmin, el dueño de la base y quien corre el script | `sql/instalacion/04_accesos_remotos.sql` |
| Layout nuevo de las bases maestras (11/11): TDC con 100 columnas y Consumo con 115; `SALDO2` sin la leyenda `<= 6`. Las columnas que solo cambiaron de lugar no requieren nada | semilla (`cfg.ARCHIVO` y `cfg.ARCHIVO_COLUMNA`) |
| Todos los scripts de `sql/`, el `03` de instalación y cada bloque de esta guía empiezan con `USE [BNABAJ_486];`: ya no se van a `master` si se abren en una ventana nueva de SSMS. `@base` de los scripts 02 y 04 ya dice `BNABAJ_486` | todos los de `sql/`, `sql/instalacion/02`, `03` y `04` |
| `10_funciones.sql` ya se puede volver a correr sobre una base existente (antes daba `Msg 3729 … referenced by object 'fn_fecha'`) | `10_funciones.sql` |
| **Validación de la entrada (17/11):** antes de tocar el DAT se revisa el layout (que estén todos los campos que se usan) y los datos de cada archivo (importes, teléfonos, correos, catálogos, cuentas repetidas, volumen). Si algo no pasa, la corrida se detiene (CANCELADA), se avisa al equipo de asignaciones (`VALIDACION_ENTRADA_486`) y se vuelve a correr a mano | `01`, `02`, `10`, `20`, **`22_sp_validacion_entrada.sql` (nuevo)**, `25`, `60`, semilla |
| **Layout editable por tabla:** el equipo cambia un encabezado con `cfg.sp_layout_cambiar` o en `cfg.ARCHIVO_COLUMNA`; queda historial y la semilla lo respeta. El número de columnas se cuenta en el archivo (ya no hay que cambiar `NUM_COLUMNAS`) | `02`, `20`, `22`, semilla |
| **Etiquetado por catálogos estáticos:** estatus, tramo, cartera, tipo de crédito, enfoque, garantía y cosecha salen de `cfg.CATALOGO` (`cfg.sp_catalogo_alta`) | `02`, `10`, `22`, semilla |
| Con el layout real de TDC: el saldo actualizado vacío (VEN2 y VEN3) ya no rechaza el renglón y toma el saldo PRIME; el tramo como rango (`30-59`) y el enfoque con acento (`LIQUIDACIÓN`) ya dan estatus | semilla |

## Si ya instalaste la versión del 17/11 por la tarde

Si ya corriste los pasos 0 a 5 con la versión de esta tarde (validación de la entrada y catálogos), no hace falta repetir todo. Cambió el orden del arribo de la asignación y la migración, y hay que volver a correr **siete scripts**:

| Script | Qué cambió |
|---|---|
| `sql/10_funciones.sql` | `ops.fn_archivos_diferidos`: qué archivos esperan a los saldos y cuáles a la depuración de teléfonos |
| `sql/52_sp_exportar.sql` | `ops.sp_exportar_salidas` puede dejar archivos sin escribir (`@excluir`) |
| `sql/76_sp_arribo_cyber.sql` | El arribo en el orden del equipo: `ops.sp_tel_remesa_validar` (conteo de la remesa, error 50776), `ops.sp_arribo_gescar_sintel` y `ops.sp_arribo_automatico` |
| `sql/77_sp_retiro_automatico.sql` | Al cerrar la asignación no escribe ni avisa los gescar ni el SCBTEL antes de tiempo |
| `sql/78_sp_automatico.sql` | Avisos de archivos con lo que sigue en cada momento; la confirmación espera al gescar sin teléfono |
| `sql/80_sp_migracion.sql` | Error 50905 con el diagnóstico del CSV, `ops.sp_mig_diagnostico` y fechas `AAAA/MM/DD` |
| `sql/90_semilla_486.sql` | Parámetros nuevos `ARCHIVOS_DESPUES_SALDOS` y `ARCHIVOS_DESPUES_DEPURACION_TEL` |

1. **Apaga el job** y respalda la base (paso 0).
2. **Guarda tus parámetros** (paso 1): la semilla los vuelve a escribir.
3. **Corre los siete scripts en este orden.** En SSMS uno por uno, o desde PowerShell en la carpeta del repositorio:

```powershell
'10_funciones', '52_sp_exportar', '76_sp_arribo_cyber', '77_sp_retiro_automatico', '78_sp_automatico', '80_sp_migracion', '90_semilla_486' | ForEach-Object {
    Write-Host $_
    sqlcmd -S "STCSVASIGNAC044\MULTISQLSERVER" -d BNABAJ_486 -E -b -I -f 65001 -i ".\sql\$_.sql"
    if ($LASTEXITCODE -ne 0) { throw "Falló $_" }
}
```

4. **Repón tus parámetros** (paso 3).
5. **Comprueba** que quedó la versión nueva:

```sql
USE [BNABAJ_486];
SELECT name, modify_date FROM sys.procedures
 WHERE name IN ('sp_tel_remesa_validar', 'sp_arribo_gescar_sintel', 'sp_arribo_automatico', 'sp_aviso_archivos',
                'sp_retiro_cerrar', 'sp_exportar_salidas', 'sp_mig_leer', 'sp_mig_diagnostico');                         -- ocho, con fecha de hoy
SELECT OBJECT_ID('ops.fn_archivos_diferidos') AS FN_ARCHIVOS_DIFERIDOS;                                                   -- no NULL
SELECT CLAVE, VALOR FROM cfg.PARAMETRO WHERE CLIENTE = '486'
 AND CLAVE IN ('ARCHIVOS_DESPUES_SALDOS', 'ARCHIVOS_DESPUES_DEPURACION_TEL', 'ARRIBO_AUTOMATICO');                        -- GESCAR_NVA,GESCAR_REA · SCBTEL · el tuyo
```

6. **Permisos en Oracle:** además de los de antes, el usuario de `CYBER_ORACLE` debe poder hacer `SELECT` en `RCVRY.JSP_TAB_TEL_REMESA_486`, porque el job cuenta sus renglones antes de ejecutar `JSP_TELEFONOS_REMESA_486`.
7. **Avisa al equipo de asignaciones del orden nuevo:**
   - El primer correo de archivos listos solo trae el SCBSDOS (y el SCBPAG).
   - Cuando suben los saldos, llega otro aviso con los gescar de nuevas y reasignadas.
   - Enseguida corre la depuración de teléfonos. Si la remesa en CYBER tiene los mismos renglones que nuestro archivo, llega el aviso del SCBTEL. **El SCBTEL no se sube antes de ese aviso.** Si no cuadra, llega un hallazgo y no sale el SCBTEL.
   - Cuando suben el SCBTEL, llega el aviso del gescar sin teléfono (`SCBACTH_SINTEL.TXT`).
8. Sigue con la **migración** (paso 6) y enciende el job cuando corresponda (paso 7).

Detalle del arribo: *Flujo y diagramas*, sección 05.

## Llave por riesgo, validaciones y asignación por segmento (20/11)

Si ya tienes la versión del 19/11 (o la de la noche del 19/11), esto es lo que cambia:

- **Llave única por riesgo:** la llave del DAT y del histórico es el riesgo en todos los segmentos (en TDC el ACC_NUM). La cuenta armada de TDC queda en `CTA_BANCO` y sigue yendo a CYBER (DMSSNUM, SCBPAG, etiquetas). Consumo e Hipotecario devuelven por riesgo.
- **Validaciones nuevas que paran:** riesgo repetido en los saldos o entre segmentos, riesgo con letras o de más de 20 dígitos, archivo idéntico al de un día anterior y saldos que no cruzan con el DAT. **Avisos sin parar:** riesgo con otro RFC, cambio de segmento y pagos repetidos.
- **Una asignación por segmento:** si el otro segmento llega más tarde, el job corre otra asignación solo con él; el arribo sigue cada asignación del día.
- **Pruebas de entorno:** `sql/85_sp_pruebas_entorno.sql` y la carpeta `pruebas_entorno/`.
- **Tabla de ABAN_SR por parámetro:** las vistas toman ABAN_SR / ABAN_CR de `CYBER_TABLA_ABANDONO` (de fábrica `RCVRY.RPT_DAT_486_1`), cruzando por `CYBER_LLAVE_ABANDONO` (`CUENTA`). Si después hay que apuntarla a otra tabla, se cambian esos dos parámetros (y la `EXPRESION` de `cfg.CYBER_CAMPO` si la columna se llama distinto); no hay que tocar código:

```sql
USE [BNABAJ_486];
UPDATE cfg.PARAMETRO SET VALOR = 'RCVRY.OTRA_TABLA' WHERE CLIENTE = '486' AND CLAVE = 'CYBER_TABLA_ABANDONO';   -- tabla (esquema.tabla)
UPDATE cfg.PARAMETRO SET VALOR = 'CUENTA'           WHERE CLIENTE = '486' AND CLAVE = 'CYBER_LLAVE_ABANDONO';   -- su columna con la cuenta 486-folio
UPDATE cfg.CYBER_CAMPO SET EXPRESION = 'r.ABAN_SR'  WHERE CAMPO = 'ABAN_SR';                                    -- solo si la columna se llama distinto
EXEC ops.sp_dat_cyber_bajar @id_corrida = <última corrida OK>, @solo_mostrar = 1;                               -- ver la consulta que se manda a Oracle
```

- **Lo que necesita el DBA de CYBER** (sin esto todo sigue funcionando en modo `ACTUAL`):
  - instalar `cyber/486/oracle/JSP_TELEFONOS_DEPURA_486.sql`: crea la tabla `RCVRY.JSP_TAB_TEL_DEPURA_486` (los cambios que manda Banbaj: I = inactivar, A = activar, N = nuevo) y el store, que revisa que estén completos, inactiva y activa sin tocar gestores de queja, llena `JSP_VALIDADOR_TELEFONOS` y anota cada etapa en `RPT_LOG_CYBER` con la bandera 416;
  - los `GRANT` del encabezado del archivo, `SELECT` en `RCVRY.PHONE` (la foto) y, si cambia la tabla de abandono, `SELECT` en la nueva;
  - después: `UPDATE cfg.PARAMETRO SET VALOR = 'DIFERENCIA' WHERE CLIENTE = '486' AND CLAVE = 'TEL_DEPURACION';`

Como cambian muchos scripts, corre **todos** los de `sql/`:

1. **Apaga el job, respalda la base** (paso 0) y **guarda tus parámetros** (paso 1).
2. **Corre todos los scripts de `sql/` en orden** (paso 2). Incluye el nuevo `85_sp_pruebas_entorno.sql`.
3. **Repón tus parámetros** (paso 3). Los parámetros nuevos (`CORREO_PRUEBA_PARA` vacío y `CYBER_SOLO_LECTURA = 0`) deben quedar así en producción.
4. **Pasa a la llave por riesgo** lo que ya está cargado. Primero revisa, después aplica:

```sql
USE [BNABAJ_486];
EXEC ops.sp_llave_riesgo_migrar;                    -- cuántas cuentas TDC cambian de llave y cuántas se quedan
EXEC ops.sp_llave_riesgo_migrar @confirmar = 1;     -- aplica
```

   - Si todavía no has migrado desde FoxPro, sáltate este paso: `ops.sp_migrar_486` lo hace solo al final.
   - Las cuentas TDC que "se quedan" (sin RIESGO, de más de 20 o repetido) no se van a reconocer en la siguiente base: revísalas con el equipo.
   - Las corridas de antes de este paso ya no se pueden revertir (su respaldo trae la llave vieja).

5. **Corre las pruebas de entorno** (`pruebas_entorno/`, en orden; ver su `LEEME.md`) y termina con `08_modo_prueba_apagar.sql`.
6. **Prende el job.**
7. **Avisa al equipo de asignaciones:**
   - Se pueden recibir dos asignaciones el mismo día (una por segmento), cada una con su aviso de archivos y su confirmación.
   - Una base con riesgos repetidos, idéntica a la del día anterior o con riesgos con letras se detiene con `VALIDACION_ENTRADA_486`.

## Teléfonos por diferencia, bandera y vistas sin stores (19/11 en la noche)

Si ya tienes la versión de ladas y ETIQUETA6 (19/11), corre solo esto. Cambia:

- **Vistas de AEM y MIS:** ya no se ejecuta `PROC_DAT_486`. ESTATUS se lee de `DELQMST` y ABAN_SR de `RPT_DAT_486_1`, tal como la dejó CYBER. Los campos posibles quedan en `cfg.CYBER_CAMPO`.
- **Bandera de teléfonos:** la depuración de teléfonos corre con la bandera 416 encendida en `RPT_LOG_CYBER_REG` / `RPT_LOG_CYBER`, igual que la de correos.
- **Depuración por diferencia** (`TEL_DEPURACION = DIFERENCIA`, apagada hasta que el DBA instale lo de CYBER): se baja una foto de `PHONE`, se compara aquí y a CYBER solo sube lo que cambia.
- **Gescar sin teléfono:** sale de nuestro archivo de teléfonos y se escribe junto con los de nuevas y reasignadas al subir los saldos. La confirmación ahora espera a que suba el SCBTEL (`ARRIBO SCBTEL`).

1. **Apaga el job, respalda la base** (paso 0) y **guarda tus parámetros** (paso 1).
2. **Corre en este orden:**
   - `sql/01_esquemas_tablas.sql`: tablas `stg.CYBER_PHONE_FOTO` y `ops.TEL_DEPURA`; quita `stg.CYBER_TEL_NUEVOS`;
   - `sql/02_catalogos.sql`: tabla `cfg.CYBER_CAMPO`;
   - `sql/10_funciones.sql`: el gescar sin teléfono espera a los saldos;
   - `sql/45_sp_telefonos.sql`: scripts de la bandera (`ops.sp_tel_bandera_script`);
   - `sql/60_sp_orquestadores.sql`, `sql/70_sp_procesos_manuales.sql`;
   - `sql/76_sp_arribo_cyber.sql`: `ops.sp_tel_depura_calcular`, bandera y paso `ARRIBO SCBTEL`;
   - `sql/78_sp_automatico.sql`: avisos y confirmación;
   - `sql/79_sp_vistas_usuario.sql`: bajada de CYBER sin store;
   - `sql/90_semilla_486.sql`: `GESCAR_SINTEL` en la asignación, `cfg.CYBER_CAMPO` y parámetros nuevos (`CYBER_BANDERA_TELEFONOS`, `TEL_GESTORES_QUEJA`, `TEL_DEPURA_MAX_INACTIVAR_PCT`).
3. **Repón tus parámetros** (paso 3). Los parámetros que ya existen no cambian solos; si quieres ver el gescar sin teléfono en la lista:

```sql
USE [BNABAJ_486];
UPDATE cfg.PARAMETRO SET VALOR = 'GESCAR_NVA,GESCAR_REA,GESCAR_SINTEL' WHERE CLIENTE = '486' AND CLAVE = 'ARCHIVOS_DESPUES_SALDOS';
```

   No es obligatorio: el gescar sin teléfono espera a los saldos aunque no esté en la lista.

4. **Permisos en Oracle** del usuario de `CYBER_ORACLE`: `SELECT` en `RCVRY.DELQMST`, `RCVRY.RPT_DAT_486_1` y `RCVRY.UDA1` (vistas); `UPDATE` en `RPT_LOG_CYBER_REG` e `INSERT` en `RPT_LOG_CYBER` (ya los tiene por correos). Ya no necesita `EXECUTE` en `PROC_DAT_486`.
5. **Comprueba:**

```sql
USE [BNABAJ_486];
SELECT * FROM cfg.CYBER_CAMPO;                                                      -- ESTATUS, ABAN_SR, ABAN_CR, SDO_CYBER
EXEC ops.sp_vistas_usuario_refrescar @id_corrida = <última corrida OK>, @forzar = 1;
SELECT CLAVE, VALOR FROM cfg.PARAMETRO WHERE CLIENTE = '486'
 AND CLAVE IN ('TEL_DEPURACION', 'CYBER_BANDERA_TELEFONOS', 'TEL_GESTORES_QUEJA', 'TEL_DEPURA_MAX_INACTIVAR_PCT');
```

6. **Prende el job.**
7. **Cuando el DBA de CYBER instale lo de teléfonos:** pásale `cyber/486/oracle/JSP_TELEFONOS_DEPURA_486.sql` (versión del 19/11; reemplaza la del 18/11). Crea la tabla `RCVRY.JSP_TAB_TEL_DEPURA_486` y el store, y en el encabezado vienen los `GRANT`. El usuario de `CYBER_ORACLE` además necesita `SELECT` en `RCVRY.PHONE` para la foto. Después prende el modo:

```sql
USE [BNABAJ_486];
UPDATE cfg.PARAMETRO SET VALOR = 'DIFERENCIA' WHERE CLIENTE = '486' AND CLAVE = 'TEL_DEPURACION';
```

   La primera vez conviene verlo sin tocar CYBER: después de la asignación, con los saldos arriba, corre `EXEC ops.sp_tel_depura_calcular <corrida>;` y revisa el renglón `TEL DIFERENCIA` de la bitácora (cuántos se inactivan, activan y son nuevos). Si los números se ven bien, deja que el job siga. Para regresar a la remesa completa: `VALOR = 'ACTUAL'`.

8. **Avisa al equipo de asignaciones:**
   - El gescar sin teléfono llega junto con los de nuevas y reasignadas, en cuanto suben los saldos.
   - La confirmación llega cuando el job ve el SCBTEL arriba.
   - Con `DIFERENCIA`, el SCBTEL trae solo los teléfonos nuevos; si no hay, no llega aviso de SCBTEL.

## Ladas válidas y ETIQUETA6 (19/11)

Si ya tienes la versión del 18/11, corre solo esto.

1. **Apaga el job, respalda la base** (paso 0) y **guarda tus parámetros** (paso 1).
2. **Corre en este orden:**
   - `sql/02_catalogos.sql`: tablas `cfg.PHNVAL` y su historial;
   - `sql/05_tabla_dat_486.sql`: columna `ETIQUETA6` en el DAT y en su respaldo;
   - `sql/45_sp_telefonos.sql`: filtro de ladas;
   - `sql/47_sp_ladas.sql` (nuevo);
   - `sql/70_sp_procesos_manuales.sql`;
   - `sql/90_semilla_486.sql`: llena `cfg.PHNVAL` la primera vez, catálogos `ETIQUETA6_TDC` / `ETIQUETA6_CONSUMO`, layout de las bases y SCBSDOS.
3. **Repón tus parámetros** (paso 3) y revisa que `CAMPOS_ACTUALIZA_EXISTENTES` termine en `ETIQUETA6`. Si repones la lista anterior, la etiqueta solo se pone en las cuentas nuevas.
4. **Crea el job mensual:** corre `sql/instalacion/02_crear_job_486.sql`. Vuelve a crear también el job diario, sin cambios.
5. **Comprueba:**

```sql
USE [BNABAJ_486];
SELECT COUNT(*) AS LADAS FROM cfg.PHNVAL;                                             -- 459 la primera vez
EXEC ops.sp_phnval_actualizar;                                                        -- prueba la copia desde CYBER (RCVRY.PHNVAL)
SELECT TOP (3) * FROM cfg.PHNVAL_CARGA ORDER BY ID DESC;
SELECT VALOR FROM cfg.PARAMETRO WHERE CLIENTE = '486' AND CLAVE = 'CAMPOS_ACTUALIZA_EXISTENTES';
SELECT * FROM cfg.v_CATALOGO WHERE CATALOGO LIKE 'ETIQUETA6%';
```

   Si `ops.sp_phnval_actualizar` falla porque no encuentra la tabla, cambia `CYBER_TABLA_LADAS` al esquema correcto. Si falla por permiso, pide `SELECT` para el usuario de `CYBER_ORACLE`.

6. **Avisa al equipo de asignaciones:**
   - La lista TOP ya no se carga: U1EXT2 sale de la base maestra (`REE`).
   - Los teléfonos con ladas que el cargador no admite ya no van en el SCBTEL.
   - Las bases maestras deben traer `ENFOQUE_PLAN DE PAGOS` (TDC) y `ENFOQUE_REESTRUCTURA` (Consumo). Si no vienen, la asignación se detiene con `VALIDACION_ENTRADA_486`.

## Usuarios AEM y MIS (18/11)

Si ya tienes instalada la versión del 17/11 en la noche, solo hay que correr esto.

1. **Apaga el job y respalda la base** (paso 0). **Guarda tus parámetros** (paso 1).
2. **Corre en este orden:**
   - `sql/01_esquemas_tablas.sql` y `sql/02_catalogos.sql`: tablas nuevas, sin tocar las existentes;
   - `sql/20_sp_comunes.sql`: guarda el último renglón de la base maestra por cuenta;
   - `sql/35_sp_respaldo.sql`, `sql/60_sp_orquestadores.sql` y `sql/76_sp_arribo_cyber.sql`;
   - `sql/79_sp_vistas_usuario.sql` (nuevo);
   - `sql/90_semilla_486.sql`.
3. **Repón tus parámetros** (paso 3).
4. **Arma las tablas por primera vez y crea el login de AEM:**

```sql
USE [BNABAJ_486];
EXEC ops.sp_vistas_usuario_refrescar @id_corrida = <última corrida OK>, @forzar = 1;     -- bajada de CYBER y tablas
SELECT TOP (10) * FROM aem.DAT_486;
SELECT COUNT(*) AS RETIROS_HOY FROM aem.RETIROS_HOY;
EXEC cfg.sp_vista_usuario_login 'AEM', 'aem_banbaj', N'<contraseña>';                       -- la contraseña no se guarda
```

   La columna MAESTRA (para MIS) empieza a llenarse con la siguiente asignación, que es cuando se guarda la base maestra por cuenta.

5. **MIS:** el equipo de asignaciones agrega sus columnas y lo activa; después creas su login:

```sql
USE [BNABAJ_486];
EXEC cfg.sp_vista_columna_alta 'MIS', N'CUENTA', 'DAT', N'CUENTA2';
EXEC cfg.sp_vista_columna_alta 'MIS', N'<ENCABEZADO>', 'MAESTRA', N'<encabezado de la base maestra>';
UPDATE cfg.VISTA_USUARIO SET ACTIVO = 1 WHERE CLIENTE = '486' AND VISTA = 'MIS';
EXEC ops.sp_vistas_usuario_armar;
EXEC cfg.sp_vista_usuario_login 'MIS', 'mis_banbaj', N'<contraseña>';
```

6. **Avisa a AEM** que ya no se deja `MX_G1MCT_DVBJIG_*` en Cyber_00: las cuentas retiradas del día están en `aem.RETIROS_HOY`.

### SCBTEL solo con los teléfonos nuevos (18/11)

Reemplazado por la depuración por diferencia: ver *Teléfonos por diferencia, bandera y vistas sin stores (19/11 en la noche)*. No prendas `NUEVOS`; si ya estaba, se toma como `DIFERENCIA`.

## 0. Antes de empezar

1. Baja la última versión de `main` del repositorio (o descarga el ZIP).
2. Apaga el job y respalda la base:

```sql
EXEC msdb.dbo.sp_update_job @job_name = N'Banbaj 486 diario', @enabled = 0;   -- si ya lo creaste
BACKUP DATABASE [BNABAJ_486] TO DISK = N'C:\BANBAJ\respaldo_BNABAJ_486_20261115.bak' WITH COPY_ONLY, INIT;
```

## 1. Guardar los parámetros que ya ajustaste

La semilla (`90_semilla_486.sql`) borra y vuelve a escribir los parámetros, los archivos de entrada y las plantillas del 486. Guarda los valores actuales para reponer los tuyos:

```sql
USE [BNABAJ_486];
IF OBJECT_ID('dbo.PARAMETRO_ANTES_20261115') IS NOT NULL DROP TABLE dbo.PARAMETRO_ANTES_20261115;
SELECT CLAVE, VALOR INTO dbo.PARAMETRO_ANTES_20261115 FROM cfg.PARAMETRO WHERE CLIENTE = '486';
```

Las credenciales (Oracle y ZIP) **no** se borran: viven cifradas en otra tabla.

## 2. Correr todos los scripts de `sql/` en orden

En SSMS abre y ejecuta uno por uno (cada uno empieza con `USE [BNABAJ_486];`), en orden de nombre, todos los `.sql` de la carpeta `sql/` (de `01_esquemas_tablas.sql` a `90_semilla_486.sql`). **No** los de `sql/instalacion/`. Los archivos están en UTF-8: si al abrir uno en SSMS los acentos se ven raros (por ejemplo `Ã©`), ciérralo sin guardar y usa el comando de PowerShell de abajo, que los lee bien.

O, desde PowerShell en la carpeta del repositorio (se detiene en el primer error):

```powershell
Get-ChildItem .\sql\*.sql | Sort-Object Name | ForEach-Object {
    Write-Host $_.Name
    sqlcmd -S "STCSVASIGNAC044\MULTISQLSERVER" -d BNABAJ_486 -E -b -I -f 65001 -i $_.FullName
    if ($LASTEXITCODE -ne 0) { throw "Falló $($_.Name)" }
}
```

Si un script marca error, el ciclo se detiene ahí y **los siguientes no se instalan**: corrige y vuelve a correr el ciclo completo (todos se pueden repetir). Si te sale `Msg 3729 … fn_texto … referenced by object 'fn_fecha'`, tienes una copia vieja de `10_funciones.sql`: baja otra vez `main`.

Al terminar, comprueba que quedó la versión nueva:

```sql
USE [BNABAJ_486];
SELECT COUNT(*) AS PROCEDIMIENTOS FROM sys.procedures;                                       -- al menos 74
SELECT VALOR FROM cfg.PARAMETRO WHERE CLIENTE = '486' AND CLAVE = 'CYBER_HOSTUP_EXPR';       -- to_char(DMHOSTUP, 'YYYYMMDD')
SELECT CASE WHEN OBJECT_DEFINITION(OBJECT_ID('ops.sp_arribo_bajar')) LIKE '%CYBER_HOSTUP%' THEN 'nuevo' ELSE 'VIEJO' END AS SP_ARRIBO_BAJAR;
```

## 3. Reponer tus parámetros

Revisa qué valores tuyos cambió la semilla:

```sql
USE [BNABAJ_486];
SELECT a.CLAVE, a.VALOR AS TUYO, p.VALOR AS NUEVO
FROM dbo.PARAMETRO_ANTES_20261115 a
JOIN cfg.PARAMETRO p ON p.CLIENTE = '486' AND p.CLAVE = a.CLAVE
WHERE ISNULL(a.VALOR, N'') <> ISNULL(p.VALOR, N'')
ORDER BY a.CLAVE;
```

- **Siempre repón `CYBER_ORACLE_ORIGEN`**, ahora con puerto y servicio: `192.168.90.10:1521/NOMBRE_SERVICIO` (sale del `tnsnames.ora` de la PC donde corre sqlldr, o te lo da el DBA con `lsnrctl status`).
- Repón también cualquier otro parámetro que hayas ajustado a mano, como rutas o tu correo de prueba.
- **No** repongas `ARRIBO_AUTOMATICO`, `ACT_CYBER_AUTOMATICO`, `RETIRO_CYBER_AUTOMATICO`, `BLANQUEO_AUTOMATICO`, `CONFIRMACION_AUTOMATICA` ni `RUTA_DEVOLUCION_CYBER`: sus valores nuevos (1, 1, 1, 1, 1 y vacío) son el proceso autónomo.
- `VALIDAR_LAYOUT` y `VALIDAR_DATOS` son nuevos y vienen en 1. No escriben en CYBER, solo detienen y avisan al equipo de asignaciones, así que conviene dejarlos prendidos también durante el paralelo.

```sql
USE [BNABAJ_486];
UPDATE cfg.PARAMETRO SET VALOR = N'192.168.90.10:1521/NOMBRE_SERVICIO' WHERE CLIENTE = '486' AND CLAVE = 'CYBER_ORACLE_ORIGEN';
-- UPDATE cfg.PARAMETRO SET VALOR = N'<tu valor>' WHERE CLIENTE = '486' AND CLAVE = N'<clave>';   -- uno por cada parámetro tuyo
```

Si habías cambiado la carpeta de entrada de algún archivo (`cfg.ARCHIVO.RUTA`), vuelve a cambiarla esta última vez: de fábrica es `\\192.168.50.13\q\CYBER\C_486\{AAAA}\{MES}\{DD}\`. Desde esta versión, lo que cambies en `cfg.ARCHIVO` (carpeta, nombre) y en `cfg.ARCHIVO_COLUMNA` (encabezados), en los catálogos y en las reglas de datos **se conserva** cuando vuelvas a correr la semilla.

## 4. Cambiar las contraseñas y conectar CYBER

La contraseña de Oracle de SACASIG y la del ZIP salieron en una foto, así que conviene cambiarlas con el DBA y Operación. Con las nuevas:

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

- Si sale vacío, revisa primero el final del paso 2: con el parámetro vacío o el procedimiento viejo no se baja nada.
- Debe mostrar lo mismo que `val.txt` (por ejemplo `20261113` con 6,855 cuentas): `DMHOSTUP` es fecha sin hora (confirmado el 15/11) y no hay que hacer nada.
- Si `ops.sp_arribo_bajar` marcara error en `to_char`, pon `UPDATE cfg.PARAMETRO SET VALOR = N'DMHOSTUP' WHERE CLIENTE = '486' AND CLAVE = 'CYBER_HOSTUP_EXPR';` y repite (también se leen fechas `DD/MM/AA`).

## 5. Accesos

Quita a `sa` y a `acfvm` de la lista de `sql/instalacion/04_accesos_remotos.sql` (o déjalos: ahora solo se saltan con un aviso), revisa que `@base` diga `BNABAJ_486` y córrelo.

## 6. Migración

Si ya hiciste los pasos 0 a 5, retoma aquí. Para la migración solo hay que actualizar su procedimiento; no hace falta volver a correr los demás scripts.

**6.1 Actualizar el procedimiento de migración.** Abre `sql/80_sp_migracion.sql` (versión del 17/11 en la noche) y córrelo completo. Solo reemplaza procedimientos y no toca datos. Revisa que haya quedado:

```sql
USE [BNABAJ_486];
SELECT name, modify_date FROM sys.procedures
 WHERE name IN ('sp_migrar_486', 'sp_mig_leer', 'sp_mig_diagnostico');   -- tres renglones, con la fecha de hoy
```

**6.2 Exportar los DBF.** Copia el `cyber/486/EXPORTAR_MIGRACION.prg` nuevo a la PC de FoxPro y córrelo (`DO EXPORTAR_MIGRACION.prg`).

- En la ventana final ya no debe aparecer PURGA, y en BLACKLIST ya no debe decir que faltan TELEFONO ni FECHA.
- Esta versión cambia por apóstrofo las comillas dobles y las tipográficas (‘ ’ “ ” ´ `), y por espacio los caracteres de control y los bytes que no existen en Windows-1252.
- **Vuelve a exportar todo**: los CSV anteriores no sirven.

**6.3 Copiar los CSV al servidor.** Cópialos a `C:\MIGRA486\` **del servidor** y reemplaza los que ya estaban. SQL Server lee esa carpeta del servidor, no la de la PC de FoxPro: si ahí quedó un CSV viejo, sigue fallando aunque el nuevo esté bien.

**6.4 Revisar sin escribir:**

```sql
USE [BNABAJ_486];
EXEC ops.sp_migrar_486 @carpeta = N'C:\MIGRA486\';
```

Detalle de cada aviso: *Migración paso a paso Banbaj 486*.

**6.5 Si un CSV no se puede leer.** Antes salía `Bulk load failed due to invalid column value… row 151946, column 29`. Ahora sale el error 50905 con lo que ve el servidor, sin datos del banco:

```
C:\MIGRA486\HISTORIA.csv: SQL Server no pudo leer el CSV (…). El servidor ve 1804214 renglones, modificado el 2026-11-17 20:40, … bytes.
Casi todos traen 62 comillas; con otro número: 1 (renglones 151946: comillas dentro de un campo). Caracteres raros: U+2019 en 3 renglones (primero el 151946).
```

- **Fecha de modificación anterior a la última exportación:** el servidor tiene un CSV viejo; repite el 6.3.
- **Comillas con otro número:** el CSV salió con un programa anterior; repite el 6.2 y el 6.3.
- **Caracteres raros:** mándame los códigos `U+…` y los agrego a la limpieza del programa.
- Para ver un renglón y sus vecinos enmascarados (letra = `x`, dígito = `9`, raros = `<U+…>`), con cuántas comillas y campos tiene cada uno, y mandármelo:

```sql
USE [BNABAJ_486];
EXEC ops.sp_mig_diagnostico N'C:\MIGRA486\HISTORIA.csv', 151946;
```

El renglón 1 es el encabezado, igual que en el Bloc de notas. Con HISTORIA el diagnóstico tarda un par de minutos.

**6.6 Cargar.** Si los avisos están bien (si ya habías cargado algo, agrega `@reemplazar = 1`):

```sql
USE [BNABAJ_486];
EXEC ops.sp_migrar_486 @carpeta = N'C:\MIGRA486\', @confirmar = 1;
```

Carga todo en una sola transacción: si algo falla, no queda nada a medias.

**6.7 Revisar lo cargado:**

```sql
USE [BNABAJ_486];
SELECT COUNT(*) AS CUENTAS, MIN(FE_ASIG) AS PRIMERA, MAX(FE_ASIG) AS ULTIMA,
       SUM(CASE WHEN FE_ASIG IS NULL THEN 1 ELSE 0 END) AS SIN_FECHA FROM dat.DAT_486;    -- SIN_FECHA debe ser 0 (fechas AAAA/MM/DD)
SELECT ESTATUS, COUNT(*) FROM dat.HISTORIA_FOLIO WHERE CLIENTE = '486' GROUP BY ESTATUS;   -- A = activas del DAT, B = periodos anteriores
```

**6.8 Borrar** `C:\MIGRA486\` en los dos equipos (trae datos de clientes).

## 7. El job

- Si todavía no lo creas, corre `sql/instalacion/02_crear_job_486.sql` con `@base = N'BNABAJ_486'`.
- **Durante el paralelo con FoxPro, o mientras no funcione la conexión a CYBER del paso 4,** apaga lo que escribe en CYBER o manda correos, para que solo FoxPro toque CYBER y no lleguen hallazgos por falta de conexión:

```sql
USE [BNABAJ_486];
UPDATE cfg.PARAMETRO SET VALOR = '0' WHERE CLIENTE = '486'
   AND CLAVE IN ('ARRIBO_AUTOMATICO', 'RETIRO_AUTOMATICO', 'RETIRO_CYBER_AUTOMATICO', 'ACT_CYBER_AUTOMATICO',
                 'BLANQUEO_AUTOMATICO', 'CONFIRMACION_AUTOMATICA', 'CUADRE_AUTOMATICO');
```

- **Al salir a producción** ponlos en `'1'` con la misma consulta y enciende el job:

```sql
EXEC msdb.dbo.sp_update_job @job_name = N'Banbaj 486 diario', @enabled = 1;
```

## 8. Verificar

```sql
USE [BNABAJ_486];
SELECT CLAVE, VALOR FROM cfg.PARAMETRO WHERE CLIENTE = '486'
 AND CLAVE IN ('CYBER_ORACLE_ORIGEN', 'CYBER_HOSTUP_EXPR', 'ARRIBO_SDOS_MIN_PCT', 'ARRIBO_AUTOMATICO', 'ACT_CYBER_AUTOMATICO',
               'RETIRO_AUTOMATICO', 'RETIRO_CYBER_AUTOMATICO', 'BLANQUEO_AUTOMATICO', 'CONFIRMACION_AUTOMATICA',
               'CUADRE_AUTOMATICO', 'EXPORTAR_AUTOMATICO', 'AVISO_ARCHIVOS', 'RUTA_DEVOLUCION_CYBER')
 ORDER BY CLAVE;
SELECT PROCESO, CODIGO, PATRON_NOMBRE, NUM_COLUMNAS FROM cfg.ARCHIVO WHERE CLIENTE = '486' AND ACTIVO = 1 ORDER BY PROCESO, ORDEN;   -- ACT en .txt, ASIG en .csv; TDC 100 y Consumo 115
SELECT a.CODIGO, c.PATRON_ENCABEZADO FROM cfg.ARCHIVO_COLUMNA c JOIN cfg.ARCHIVO a ON a.ID_ARCHIVO = c.ID_ARCHIVO
 WHERE a.CLIENTE = '486' AND c.CAMPO_DESTINO = 'SALDO2';                                                -- sin '<= 6'
SELECT CLAVE, VALOR FROM cfg.PARAMETRO WHERE CLIENTE = '486' AND CLAVE IN ('VALIDAR_LAYOUT', 'VALIDAR_DATOS');   -- 1 y 1
SELECT CATALOGO, COUNT(*) AS VALORES FROM cfg.CATALOGO WHERE CLIENTE = '486' GROUP BY CATALOGO;              -- 10 catálogos
SELECT CODIGO, COUNT(*) AS REGLAS FROM cfg.VALIDACION_DATO WHERE CLIENTE = '486' GROUP BY CODIGO;             -- reglas por archivo
SELECT ARCHIVO, CAMPO, PATRON_ENCABEZADO, ESTADO FROM cfg.v_LAYOUT WHERE ESTADO NOT IN ('OK', 'DERIVADO', 'SIN ARCHIVO');   -- vacío, o lo que el último archivo no traía
EXEC ops.sp_diario_486 @fecha = '2026-11-14';   -- sábado: debe contestar FIN DE SEMANA sin hacer nada
```

Cuando todo cuadre, borra el respaldo de parámetros: `DROP TABLE dbo.PARAMETRO_ANTES_20261115;`.

## 9. Si llega el correo de validación de la entrada

La primera vez que llegue un archivo que no cuadre (por ejemplo, el primer Hipotecario, del que no hay ejemplo), la corrida se detiene antes de tocar el DAT y llega `VALIDACION_ENTRADA_486` con qué falta y qué hacer. Lo usual:

```sql
USE [BNABAJ_486];
EXEC cfg.sp_layout_cambiar 'MAESTRA_HIPO', 'SDO_ACT', N'encabezado como viene en el archivo';   -- encabezado que cambió
EXEC cfg.sp_catalogo_alta 'ESTATUS_TDC', N'VEN1', N'';                                           -- estatus nuevo válido
SELECT * FROM ops.VALIDACION_ENTRADA WHERE ID_CORRIDA = <corrida> ORDER BY DETIENE DESC;          -- todo lo que encontró
EXEC ops.sp_asignacion_486 @fecha = '<AAAA-MM-DD>';                                               -- volver a correr
```

Detalle: *Flujo y diagramas*, sección 09.
