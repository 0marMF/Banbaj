---
title: "Banbaj 486 · Migración paso a paso"
subtitle: "Cómo pasar los datos de Visual FoxPro a SQL Server (una sola vez)"
date: "Noviembre 2026"
---

# Antes de empezar

La migración se hace **una sola vez**, justo antes de la primera corrida en SQL Server. Si se hace una prueba antes, se repite al final con `@reemplazar = 1` para tomar los datos del último día de FoxPro.

Qué se necesita:

| Requisito | Cómo saberlo |
|---|---|
| Base `Banbaj` instalada (todos los scripts de `sql/`) | `SELECT COUNT(*) FROM sys.procedures;` da más de 60 |
| Visual FoxPro en una PC con acceso a `O:\` y a `\\192.168.50.108\T\` | Se abren los DBF |
| El programa `cyber/486/EXPORTAR_MIGRACION.prg` del repo | Última versión de `main` |
| Una carpeta que vea el servidor de SQL Server para dejar los CSV | `C:\MIGRA486\` en el servidor o una carpeta de red |
| El job **Banbaj 486 diario** apagado | No debe correr mientras se migra |

Apagar el job:

```sql
EXEC msdb.dbo.sp_update_job @job_name = N'Banbaj 486 diario', @enabled = 0;
```

Los CSV traen datos de clientes. No se mandan por correo ni se suben a ningún repositorio, y se borran al terminar.

# Paso 1. Detener FoxPro

Avisar al equipo y detener los procesos del 486 en FoxPro para que nadie escriba en los DBF mientras se exportan.

# Paso 2. Exportar los DBF a CSV

1. Copiar `EXPORTAR_MIGRACION.prg` a la PC de FoxPro.
2. Revisar las rutas de los DBF dentro del programa (`laF[n, 2]`). Vienen de los `.prg` actuales; si alguna cambió, corregirla.
3. En Visual FoxPro: `DO EXPORTAR_MIGRACION.prg`.
4. Al terminar aparece una ventana con los registros que salieron de cada archivo y los campos que no existen. Tomar captura.

El programa escribe 13 archivos en `C:\MIGRA486\`, solo con los campos que se usan:

| CSV | DBF de origen | Campos | Registros de referencia (02/11) |
|---|---|---|---|
| DAT | `O:\DAT\GPO1\486\DAT.DBF` | todos | 6,851 |
| TAB7 | `O:\DAT\GPO1\486\TAB7.DBF` | FOLIO | 880 |
| HISTORIA | `O:\HISTORIA\GPO1\486\HISTORIA.DBF` | CUENTA, FOLIO, CUENTA2, RIESGO, SEGMENTO, STATUS, TRAMO, ETIQUETA, FE\_ASIG, SDO\_ACT, CAPITAL, TEL1-TEL16, DIRECC1-DIRECC5, ESTADO, EDO | 1,804,213 |
| PURGA | `O:\HISTORIA\GPO1\486\PURGA.DBF` | CUENTA, FOLIO, fecha de retiro, MOTIVO | — |
| PAGTOT | `O:\PRG\GPO1\486\PAGOS\PAGTOT.DBF` | CUENTA, MONT, FE\_PAG, FE\_REG | 543,700 |
| ETI | `O:\PRG\MEXGPO1\ASI486\ETI.DBF` | CUENTA, ETIQUETA | 25,423 |
| DM1 | `O:\PRG\MEXGPO1\ASI486\DM1.DBF` | CUENTA, ETIQUETA | 1,368 |
| TOP | `O:\PRG\MEXGPO1\ASI486\TOP.DBF` | CUENTA2, ETIQUETA | 2,244 |
| STATUS | `O:\PRG\MEXGPO1\ASI486\STATUS.DBF` | CUENTA, ESTATUS | 22 |
| EXC486 | `O:\PRG\GPO1\486\EXC486.DBF` | CUENTA | 19 |
| DIRMAL | `O:\ASIGNA\DIRMAL.DBF` | CUENTA, DIRECC1 | 1,083 |
| EMAILMALO | `O:\ASIGNA\EMAILMALO.DBF` | EMAIL, CUENTA | 1,206,965 |
| BLACKLIST | `O:\PRG\MEXGPO1\ASI486\BLACKLIST_486.DBF` | TEL, FE\_AGRE, OS, SOLICITUD | 7,820 |

Los conteos de referencia son de la exportación de prueba; el día de la migración real van a variar un poco.

**Qué revisar en la ventana:**

- Que ningún archivo diga "NO SE ENCONTRÓ". Si pasa, corregir su ruta en el programa y volver a correr.
- En HISTORIA es normal que diga que no existen campos como SEGMENTO2 o FE\_REA: historia.dbf no los tiene.
- En BLACKLIST es normal que diga que no existe STATUS: el DBF no lo tiene y todo cuenta como X.
- En PURGA, anotar qué campo de fecha sí existe (FE\_BAJA, FE\_PURGA, FE\_RET, FECHA…).

No se exportan DEVOL, TELBAJ, PNC ni LADA. TELBAJ y PNC se leen de CYBER en cada asignación.

# Paso 3. Dejar los CSV donde los vea SQL Server

`BULK INSERT` lee las rutas **desde el servidor de SQL Server**, no desde la PC de quien ejecuta. Hay que hacer una de estas dos cosas:

- Copiar la carpeta `C:\MIGRA486\` completa al servidor de SQL Server, en la misma ruta.
- Dejarla en una carpeta de red que la cuenta del servicio de SQL Server pueda leer (por ejemplo, `\\192.168.50.13\q\MIGRA486\`) y usar esa ruta en `@carpeta`.

# Paso 4. Revisar sin escribir

En SSMS, conectado a la base `Banbaj`:

```sql
EXEC ops.sp_migrar_486 @carpeta = N'C:\MIGRA486\';
```

No escribe nada. Regresa tres resultados:

1. **Archivos leídos:** cada CSV con sus filas. Deben coincidir con la ventana de FoxPro.
2. **Destinos:** cuántas filas irían a cada tabla (DAT, HISTORIA, CONSECUTIVO, PAGOS, ETIQUETAS, EXCLUSIONES).
3. **Avisos:** lo que conviene saber antes de cargar.

| Aviso | Qué significa | Qué hacer |
|---|---|---|
| `X.csv no se encontró en …` | Falta ese archivo en la carpeta | Copiarlo o corregir la ruta |
| `DAT: columnas del archivo que no existen en dat.DAT_486 (se ignoran)` | Campos del DAT de FoxPro que Banbaj no usa | Nada, es informativo |
| `DAT: n registros sin CUENTA omitidos` / `con CUENTA repetida` | Registros del DAT que no se cargan | Revisar en FoxPro si es correcto |
| `HISTORIA: n asignaciones anteriores quedan como baja…` | Cuántos periodos anteriores entran al histórico | Debe ser cercano a los renglones de historia.dbf |
| `HISTORIA: fecha de asignación = FE_ASIG · se conservan: …` | Qué campos se guardan de cada periodo | Revisar que salgan saldos, teléfonos y dirección |
| `PURGA: n periodos del histórico con fecha de retiro` | Cuántos periodos quedan con fecha de retiro | Si es 0, revisar el campo de fecha de PURGA |
| `CONSECUTIVO: TAB7 (x) es menor que el folio más alto usado (y)` | El último folio de TAB7 está atrasado | Se toma el más alto; nada que hacer |
| `PAGTOT: n registros omitidos por FE_PAG incompleta…` | Pagos viejos con fecha mal capturada | Nada, nunca coincidirían con un pago nuevo |
| `EMAILMALO: n de m registros aplican al 486` | Solo se guardan los de cuentas del 486 | Nada, es informativo |
| `BLACKLIST: n teléfonos omitidos por no tener 10 dígitos` | La lista negra solo acepta 10 dígitos | Nada (decisión) |
| `BLACKLIST: n con estatus X…` | Cuántos teléfonos se van a excluir | Debe ser casi toda la lista |

Si los acentos se ven mal en algún resultado, repetir con `@codepage = '1252'`.

# Paso 5. Cargar

```sql
EXEC ops.sp_migrar_486 @carpeta = N'C:\MIGRA486\', @confirmar = 1;
```

- Carga todo en una sola transacción. Si algo falla, no queda nada a medias.
- Con HISTORIA y EMAILMALO (más de un millón de renglones cada uno) puede tardar varios minutos. No cancelar.
- Si la base ya tiene datos (por ejemplo, de una prueba), se detiene con un error 50910 a 50914 y no carga nada. Para sobrescribir:

```sql
EXEC ops.sp_migrar_486 @carpeta = N'C:\MIGRA486\', @confirmar = 1, @reemplazar = 1;
```

- Para cargar solo una parte: `@solo = N'DAT,HISTORIA'`. Destinos posibles: DAT, HISTORIA, CONSECUTIVO, PAGOS, ETIQUETAS, EXCLUSIONES.
- Las tablas de paso (`stg.MIG_*`) se borran solas al terminar, salga bien o mal.

# Paso 6. Verificar

```sql
SELECT COUNT(*) AS DAT FROM dat.DAT_486;                                   -- ≈ registros de DAT.DBF
SELECT ESTATUS, COUNT(*) FROM dat.HISTORIA_FOLIO WHERE CLIENTE = '486' GROUP BY ESTATUS;   -- A = activas del DAT, B = periodos anteriores
SELECT COUNT(*) FROM dat.HISTORIA_FOLIO WHERE CLIENTE = '486' AND FE_BAJA IS NOT NULL;     -- periodos con fecha de retiro (PURGA)
SELECT ULTIMO_FOLIO FROM dat.FOLIO_CONSECUTIVO WHERE CLIENTE = '486';     -- ≥ último folio de TAB7
SELECT COUNT(*) FROM dat.PAGO_ARRIBADO WHERE CLIENTE = '486' AND ORIGEN = 'PAGTOT';
SELECT TIPO, COUNT(*) FROM cfg.ETIQUETA WHERE CLIENTE = '486' GROUP BY TIPO;
SELECT TIPO, ACTIVO, COUNT(*) FROM cfg.EXCLUSION WHERE CLIENTE = '486' AND ORIGEN = 'MIGRACION DBF' GROUP BY TIPO, ACTIVO;
```

Revisar también a mano tres o cuatro cuentas conocidas, comparando con FoxPro: folio, saldo, etiqueta y teléfono en el DAT, y sus periodos anteriores en el histórico.

```sql
SELECT FOLIO, CUENTA2, SDO_ACT, ETIQUETA1, TEL1 FROM dat.DAT_486 WHERE CUENTA = '<crédito>';
SELECT FOLIO, SUB_CTE, ESTATUS, FE_ALTA, FE_BAJA, MOTIVO_BAJA FROM dat.HISTORIA_FOLIO WHERE CUENTA = '<crédito>' ORDER BY FE_ALTA;
```

# Paso 7. Limpiar

1. Borrar `C:\MIGRA486\` en la PC de FoxPro y en el servidor (o la carpeta de red que se usó).
2. Vaciar la papelera de los dos equipos.

# Paso 8. Primera corrida

1. Correr la semana en paralelo con FoxPro, como dice el manual (*Salida a producción*).
2. Justo antes del corte, repetir los pasos 1 a 7 con `@reemplazar = 1` para tomar el último día de FoxPro.
3. Encender el job:

```sql
EXEC msdb.dbo.sp_update_job @job_name = N'Banbaj 486 diario', @enabled = 1;
```

# Si algo sale mal

| Situación | Qué hacer |
|---|---|
| Error 50900 a 50908 (`X.csv: faltan las columnas …`) | El CSV no trae un campo obligatorio. Revisar la ventana de FoxPro y la ruta del DBF |
| Error 50910 a 50914 (`… ya tiene registros`) | Ya hay datos. Si se quiere sobrescribir, agregar `@reemplazar = 1` |
| Aviso `X.csv no se encontró` aunque el archivo sí está | SQL Server no ve la carpeta desde el servidor. Ver el paso 3 |
| Se cargó y algo no cuadra | Corregir el origen y volver a correr con `@reemplazar = 1`; reemplaza todo lo migrado |
| Solo una tabla salió mal | Volver a correr con `@solo = N'<destino>', @reemplazar = 1` |
