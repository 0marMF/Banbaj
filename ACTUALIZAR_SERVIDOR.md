# Qué volver a ejecutar en el servidor (actualización del 15/11/2026)

Esta guía lleva tu base (`BNABAJ_486` en `STCSVASIGNAC044\MULTISQLSERVER`) a la versión actual de `main`. Vale para una base instalada en cualquier fecha a partir del 03/11. Todos los scripts de `sql/` se pueden volver a correr sobre una base con datos: crean solo lo que falta y reemplazan los procedimientos.

Tiempo aproximado: 20 minutos, sin contar la migración.

## Qué cambió desde el 03/11

| Cambio | Scripts |
|---|---|
| Proceso autónomo: depuraciones de correos y teléfonos, scripts de la actualización, retiro en CYBER, blanqueo y confirmación automáticos (la copia de la devolución a `Cyber_00` sigue a mano) | `90_semilla_486.sql`, `60`, `77`, `78` |
| Saldos del día detectados con la consulta de `val.txt` (`DMHOSTUP` del día = cuentas del SCBSDOS). `DMHOSTUP` quedó confirmado como fecha sin hora (`13/11/26`, 6,855 cuentas) | `01_esquemas_tablas.sql` (tabla `stg.CYBER_HOSTUP`), `76_sp_arribo_cyber.sql`, semilla |
| Archivos de la actualización solo en `.txt`; bases maestras solo en `.csv` | semilla (`cfg.ARCHIVO`) |
| `cfg.sp_cyber_conectar` vuelve a crear el servidor vinculado y avisa si el origen de Oracle trae solo la IP | `74_sp_cyber.sql` |
| Histórico migrado sin fechas; PURGA sin usarse | `01_esquemas_tablas.sql`, `80_sp_migracion.sql` |
| Exportación de FoxPro sin comillas dobles (el error de `HISTORIA.csv`, renglón 151946) | `cyber/486/EXPORTAR_MIGRACION.prg` |
| Accesos: se saltan `sa`, los sysadmin, el dueño de la base y quien corre el script | `sql/instalacion/04_accesos_remotos.sql` |
| `10_funciones.sql` ya se puede volver a correr sobre una base existente (antes daba `Msg 3729 … referenced by object 'fn_fecha'`) | `10_funciones.sql` |

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

En SSMS, conectado a `BNABAJ_486`, abre y ejecuta uno por uno, en orden de nombre, todos los `.sql` de la carpeta `sql/` (de `01_esquemas_tablas.sql` a `90_semilla_486.sql`). **No** los de `sql/instalacion/`. Los archivos están en UTF-8: si al abrir uno en SSMS los acentos se ven raros (por ejemplo `Ã©`), ciérralo sin guardar y usa el comando de PowerShell de abajo, que los lee bien.

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
SELECT COUNT(*) AS PROCEDIMIENTOS FROM sys.procedures;                                       -- al menos 74
SELECT VALOR FROM cfg.PARAMETRO WHERE CLIENTE = '486' AND CLAVE = 'CYBER_HOSTUP_EXPR';       -- to_char(DMHOSTUP, 'YYYYMMDD')
SELECT CASE WHEN OBJECT_DEFINITION(OBJECT_ID('ops.sp_arribo_bajar')) LIKE '%CYBER_HOSTUP%' THEN 'nuevo' ELSE 'VIEJO' END AS SP_ARRIBO_BAJAR;
```

## 3. Reponer tus parámetros

Revisa qué valores tuyos cambió la semilla:

```sql
SELECT a.CLAVE, a.VALOR AS TUYO, p.VALOR AS NUEVO
FROM dbo.PARAMETRO_ANTES_20261115 a
JOIN cfg.PARAMETRO p ON p.CLIENTE = '486' AND p.CLAVE = a.CLAVE
WHERE ISNULL(a.VALOR, N'') <> ISNULL(p.VALOR, N'')
ORDER BY a.CLAVE;
```

- **Siempre repón `CYBER_ORACLE_ORIGEN`**, ahora con puerto y servicio: `192.168.90.10:1521/NOMBRE_SERVICIO` (sale del `tnsnames.ora` de la PC donde corre sqlldr, o te lo da el DBA con `lsnrctl status`).
- Repón también cualquier otro parámetro que hayas ajustado a mano, como rutas o tu correo de prueba.
- **No** repongas `ARRIBO_AUTOMATICO`, `ACT_CYBER_AUTOMATICO`, `RETIRO_CYBER_AUTOMATICO`, `BLANQUEO_AUTOMATICO`, `CONFIRMACION_AUTOMATICA` ni `RUTA_DEVOLUCION_CYBER`: sus valores nuevos (1, 1, 1, 1, 1 y vacío) son el proceso autónomo.

```sql
UPDATE cfg.PARAMETRO SET VALOR = N'192.168.90.10:1521/NOMBRE_SERVICIO' WHERE CLIENTE = '486' AND CLAVE = 'CYBER_ORACLE_ORIGEN';
-- UPDATE cfg.PARAMETRO SET VALOR = N'<tu valor>' WHERE CLIENTE = '486' AND CLAVE = N'<clave>';   -- uno por cada parámetro tuyo
```

Si habías cambiado la carpeta de entrada de algún archivo (`cfg.ARCHIVO.RUTA`), vuelve a cambiarla: de fábrica es `\\192.168.50.13\q\CYBER\C_486\{AAAA}\{MES}\{DD}\`.

## 4. Cambiar las contraseñas y conectar CYBER

La contraseña de Oracle de SACASIG y la del ZIP salieron en una foto, así que conviene cambiarlas con el DBA y Operación. Con las nuevas:

1. Edita en tu equipo `sql/instalacion/03_parametros_y_credenciales.sql`: origen con puerto y servicio, usuario, contraseña de Oracle y contraseña del ZIP.
2. Córrelo. Al terminar, bórralo o deja otra vez los `<<…>>`; no lo subas con los valores.

Ese script guarda las credenciales cifradas, corre `EXEC cfg.sp_cyber_conectar;` y baja los status como prueba. Si no quieres cambiar las contraseñas todavía, solo corre `EXEC cfg.sp_cyber_conectar;`.

Prueba la conexión y la validación de saldos:

```sql
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

1. Copia el `cyber/486/EXPORTAR_MIGRACION.prg` nuevo a la PC de FoxPro y córrelo (`DO EXPORTAR_MIGRACION.prg`). En la ventana final ya no debe aparecer PURGA, y en BLACKLIST ya no debe decir que faltan TELEFONO ni FECHA. Si todavía aparecen, corriste el `.prg` viejo, y sus CSV vuelven a dar el error de `HISTORIA.csv` en el renglón 151946: el nuevo cambia las comillas dobles de los textos por sencillas. **Vuelve a exportar siempre con el nuevo**; los CSV anteriores no sirven.
2. Copia los CSV a `C:\MIGRA486\` del servidor y revisa sin escribir:

```sql
EXEC ops.sp_migrar_486 @carpeta = N'C:\MIGRA486\';
```

3. Si los avisos están bien, carga (si ya habías cargado algo, agrega `@reemplazar = 1`):

```sql
EXEC ops.sp_migrar_486 @carpeta = N'C:\MIGRA486\', @confirmar = 1;
```

4. Borra `C:\MIGRA486\` en los dos equipos.

Detalle de cada aviso: *Migración paso a paso Banbaj 486*.

## 7. El job

- Si todavía no lo creas, corre `sql/instalacion/02_crear_job_486.sql` con `@base = N'BNABAJ_486'`.
- **Durante el paralelo con FoxPro, o mientras no funcione la conexión a CYBER del paso 4,** apaga lo que escribe en CYBER o manda correos, para que solo FoxPro toque CYBER y no lleguen hallazgos por falta de conexión:

```sql
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
SELECT CLAVE, VALOR FROM cfg.PARAMETRO WHERE CLIENTE = '486'
 AND CLAVE IN ('CYBER_ORACLE_ORIGEN', 'CYBER_HOSTUP_EXPR', 'ARRIBO_SDOS_MIN_PCT', 'ARRIBO_AUTOMATICO', 'ACT_CYBER_AUTOMATICO',
               'RETIRO_AUTOMATICO', 'RETIRO_CYBER_AUTOMATICO', 'BLANQUEO_AUTOMATICO', 'CONFIRMACION_AUTOMATICA',
               'CUADRE_AUTOMATICO', 'EXPORTAR_AUTOMATICO', 'AVISO_ARCHIVOS', 'RUTA_DEVOLUCION_CYBER')
 ORDER BY CLAVE;
SELECT PROCESO, CODIGO, PATRON_NOMBRE FROM cfg.ARCHIVO WHERE CLIENTE = '486' AND ACTIVO = 1 ORDER BY PROCESO, ORDEN;   -- ACT en .txt, ASIG en .csv
EXEC ops.sp_diario_486 @fecha = '2026-11-14';   -- sábado: debe contestar FIN DE SEMANA sin hacer nada
```

Cuando todo cuadre, borra el respaldo de parámetros: `DROP TABLE dbo.PARAMETRO_ANTES_20261115;`.
