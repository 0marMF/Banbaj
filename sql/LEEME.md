# Scripts SQL Server · Banbaj (cliente 486)

Migración dinámica de la asignación y la actualización del 486. Las únicas tablas fijas del negocio son el **DAT** (`dat.DAT_486`), el **histórico de folios** (`dat.FOLIO_CONSECUTIVO` + `dat.HISTORIA_FOLIO`) y los **pagos arribados** (`dat.PAGO_ARRIBADO`, antes PAGTOT). Todo lo demás vive en catálogos (`cfg.*`) y en stored procedures.

Requiere SQL Server 2017 o superior y Database Mail configurado.

## Orden de ejecución

| Archivo | Contenido |
| --- | --- |
| `01_esquemas_tablas.sql` | Esquemas `dat`, `cfg`, `stg`, `ops`, `mail`; histórico de folios; tablas de operación |
| `02_catalogos.sql` | Catálogos: archivos, columnas, homologación, reglas, salidas, etiquetas, exclusiones, parámetros |
| `03_correo.sql` | Listas de distribución, destinatarios, plantillas y bitácora de envíos |
| `05_tabla_dat_486.sql` | Tabla fija DAT del 486 (generada desde el mapeo) |
| `10_funciones.sql` | Limpieza de importes y fechas, formato de ancho fijo, CP → estado |
| `20_sp_comunes.sql` | Corrida, bitácora, carga dinámica de archivos, homologación, validación |
| `25_sp_correo.sql` | Envío de correo dinámico y alta / baja de destinatarios |
| `27_sp_etiquetas.sql` | Carga de etiquetas externas (TOP: folio + etiqueta de Operación) |
| `30_sp_asignacion.sql` | Unión de bases, devolución, existentes, folios y alta, retiro |
| `32_sp_retiro_solicitud.sql` | Retiro por solicitud con folio o riesgo (`ops.sp_retiro_solicitud`) |
| `35_sp_respaldo.sql` | Respaldo del DAT por corrida y retroceso (`ops.sp_revertir_corrida`) |
| `40_sp_actualizacion.sql` | Saldos, scripts para CYBER, pagos |
| `45_sp_telefonos.sql` | Teléfonos para CYBER en la asignación (`ops.sp_telefonos`, antes telbnx.prg) |
| `50_sp_salidas.sql` | Archivos planos de `cfg.SALIDA_ARCHIVO` + `cfg.SALIDA` (ancho fijo o delimitados) |
| `60_sp_orquestadores.sql` | `ops.sp_asignacion_486` y `ops.sp_actualizacion_486` |
| `90_semilla_486.sql` | Configuración del 486 (generada con `tools/generar_sql_486.py`) |

Con `sqlcmd` usar siempre `-I` (QUOTED_IDENTIFIER ON) y `-f 65001` (los scripts están en UTF-8; sin esto los acentos de la semilla se dañan). SSMS ya maneja ambos.

## Uso diario

```sql
-- Asignación (las bases maestras se dejan como CSV en la carpeta de cfg.ARCHIVO.RUTA)
DECLARE @id INT;
EXEC ops.sp_asignacion_486 @hora_llegada = '09:15', @id_corrida = @id OUTPUT;

-- Revisar lo que se va a retirar y aplicarlo
SELECT * FROM ops.DEVOLUCION WHERE ID_CORRIDA = @id;
EXEC ops.sp_retiro @id;

-- Actualización de saldos y pagos (los pagos negativos se excluyen y se avisa a Operación)
EXEC ops.sp_actualizacion_486 @id_corrida = @id OUTPUT;

-- Retiro por solicitud: folio (con o sin 486-) o riesgo; primero vista previa
EXEC ops.sp_retiro_solicitud @valores = N'486-100001, 1000000004';
EXEC ops.sp_retiro_solicitud @valores = N'486-100001, 1000000004', @motivo = N'SOLICITUD BANCO', @confirmar = 1;
EXEC ops.sp_retiro_solicitud @archivo = N'D:\Banbaj\486\retiros\solicitud.csv', @confirmar = 1;

-- Retroceso: deja DAT, histórico de folios, consecutivo y pagos como antes de la corrida
EXEC ops.sp_revertir_corrida @id;                 -- vista previa
EXEC ops.sp_revertir_corrida @id, @confirmar = 1; -- revierte (solo la corrida más reciente; no toca CYBER)

-- Qué pasó
SELECT * FROM ops.BITACORA WHERE ID_CORRIDA = @id ORDER BY ID;
SELECT * FROM ops.RECHAZO  WHERE ID_CORRIDA = @id;
```

Escribir los archivos planos y los scripts de CYBER para el arribo manual (ver `cyber/486/ARRIBO_MANUAL.md`):

```
python tools/exportar_salidas.py --conexion "DRIVER={ODBC Driver 18 for SQL Server};SERVER=<servidor>;DATABASE=Banbaj;Trusted_Connection=yes;TrustServerCertificate=yes" --corrida 123 --carpeta D:\Banbaj\486\salida
```

| Proceso | Archivos |
| --- | --- |
| Asignación | `SCBSDOS.TXT`, `SCBTEL.TXT`, `sub_mst.TXT`, `SCBACTH_486NU.TXT`, `SCBACTH_486REA.TXT`, `cyber/TEL_ACTUALIZA.sql` |
| Actualización | `SCBSDOS.TXT`, `SCBPAG.TXT`, `cyber/ACT_SALDOS.sql`, `ACT_VENCIDO.sql`, `ACT_PAGMIN.sql` |
| Retiro | `MX_G1MCT_DVBJIG_<fecha>_<hora>`, `SCBACTH_486.TXT`, `RETIROS_486_<fecha>.csv`, `cyber/RETIRO.sql` |

Un archivo nuevo o un cambio de layout se configura en `cfg.SALIDA_ARCHIVO` (origen, nombre, separador) y `cfg.SALIDA` (campos), sin tocar los procedimientos. Alternativa con bcp:

```
bcp "SELECT LINEA FROM Banbaj.ops.SALIDA_LINEA WHERE ID_CORRIDA = 123 AND ARCHIVO = 'SCBSDOS' ORDER BY NUM" queryout SCBSDOS.TXT -c -C 1252 -T -S <servidor>
bcp "SELECT SENTENCIA FROM Banbaj.ops.CYBER_SCRIPT WHERE ID_CORRIDA = 123 AND SCRIPT = 'ACT_SALDOS' ORDER BY NUM" queryout act486.sql -c -C 1252 -T -S <servidor>
```

## Etiquetas TOP

Operación comparte folio y etiqueta; Asignaciones las carga:

```sql
EXEC cfg.sp_etiqueta_cargar '486', 'TOP', 'D:\Banbaj\486\etiquetas\TOP.csv';   -- CSV FOLIO,ETIQUETA; reemplaza la lista
EXEC cfg.sp_etiqueta_cargar '486', 'TOP', 'D:\Banbaj\486\etiquetas\TOP.csv', 'AGREGAR';
EXEC cfg.sp_etiqueta_alta '486', 'TOP', '100146', 'REE';      -- folio con o sin '486-'
EXEC cfg.sp_etiqueta_baja '486', 'TOP', '100146';
```

La salida SCBSDOS toma la etiqueta en U1EXT2 por CUENTA2 (`486-` + folio).

## Listas de correo

Para cambiar a quién le llega un correo no se toca código:

```sql
EXEC mail.sp_destinatario_alta 'RETIROS_ACT_486', 'persona@sertec.com.mx', 'TO';
EXEC mail.sp_destinatario_baja 'RETIROS_ACT_486', 'persona@sertec.com.mx';
SELECT * FROM mail.v_LISTA_RESUELTA;          -- cómo queda cada lista
EXEC mail.sp_enviar 'RETIROS_ACT_486', @solo_prueba = 1;   -- ver el correo sin enviarlo
```

## Pendientes antes de producción

Lista completa de programas, tablas y preguntas en [`docs/FALTANTES_486.md`](../docs/FALTANTES_486.md).


- `cfg.ARCHIVO.RUTA` real y `mail.PLANTILLA.PERFIL_DBMAIL` real.
- `NEGATIVO_MODO` (hoy igual que el legado: el negativo sale positivo, H-01). `TOPE_DEVOLUCION_PCT` va vacío: la base maestra se trabaja como llega; poner un número solo si se quiere el freno.
- Columnas marcadas POR CONFIRMAR en `cfg.ARCHIVO_COLUMNA` (ENFOQUE, ETIQUETA, REE) y el archivo de Hipotecario.
- Destinatarios de `OPERACION_ASIG_486` (MAIL.prg / correo_486 no están versionados) y de `OPERACION_PAGOS_486` (aviso de pagos negativos).
- Carga inicial desde los DBF: `tools/migrar_dbf.py` (ver abajo).

## Migración de los DBF

Los DBF dejan de usarse. `tools/migrar_dbf.py` pasa todo a tablas en una sola transacción:

| DBF | Tabla |
| --- | --- |
| DAT | `dat.DAT_486` |
| DAT (activas) + PURGA (bajas; si no hay PURGA, DEVOL) | `dat.HISTORIA_FOLIO` |
| TAB7 (máximo folio, comparado con DAT, PURGA, DEVOL e HISTORIA) | `dat.FOLIO_CONSECUTIVO` |
| PAGTOT (solo CUENTA + FE_PAG + MONT) | `dat.PAGO_ARRIBADO` |
| ETI486, ETI, DM1, TOP, STATUS | `cfg.ETIQUETA` |
| EXC486, DIRMAL, EMAILMALO, BLACKLIST_486, TELBAJ_G1 | `cfg.EXCLUSION` (solo lo que aplica al 486; los 3 teléfonos del banco van en la semilla) |
| LADA, PNC | `cfg.LADA`, `cfg.PLAN_NUMERACION` |

```
pip install dbfread pyodbc
python tools/migrar_dbf.py --config tools/migracion_486.json            # revisa, no escribe
python tools/migrar_dbf.py --config tools/migracion_486.json --conexion "DRIVER={ODBC Driver 18 for SQL Server};SERVER=<srv>;DATABASE=Banbaj;Trusted_Connection=yes;TrustServerCertificate=yes"
```

Las rutas de `tools/migracion_486.json` son las que usan hoy los .prg. Si una tabla destino ya tiene datos, pide `--reemplazar`.

## Codificación de los archivos

Los CSV que guarda Excel vienen en Windows-1252: en el servidor Windows `cfg.ARCHIVO.CODEPAGE = 'ACP'` los lee bien. SQL Server en Linux no admite `CODEPAGE`; por eso las pruebas de GitHub Actions generan los archivos en la página 437.

## Pruebas

`.github/workflows/pruebas-sql.yml` levanta SQL Server 2022 en GitHub Actions, ejecuta estos scripts y `tests/pruebas.sql` con datos ficticios (`tests/generar_datos_prueba.py`). También prueba la migración DBF (`tests/prueba_migracion.py`) y la escritura de los archivos planos (`tests/prueba_exportar.py`). El resultado queda en la rama `ci-resultados` (última corrida: 75 de 75 pruebas SQL, 12 de 12 de migración y 14 de 14 de exportación).
