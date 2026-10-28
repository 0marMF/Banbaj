# Scripts SQL Server · Banbaj (cliente 486)

Migración dinámica de la asignación y la actualización del 486. Las únicas tablas fijas del negocio son el **DAT** (`dat.DAT_486`) y el **histórico de folios** (`dat.FOLIO_CONSECUTIVO` + `dat.HISTORIA_FOLIO`). Todo lo demás vive en catálogos (`cfg.*`) y en stored procedures.

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
| `35_sp_respaldo.sql` | Respaldo del DAT por corrida y retroceso (`ops.sp_revertir_corrida`) |
| `40_sp_actualizacion.sql` | Saldos, scripts para CYBER, pagos |
| `50_sp_salidas.sql` | SCBSDOS (y cualquier salida de ancho fijo de `cfg.SALIDA`) |
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

-- Actualización de saldos y pagos
EXEC ops.sp_actualizacion_486 @id_corrida = @id OUTPUT;

-- Retroceso: deja DAT, histórico de folios, consecutivo y pagos como antes de la corrida
EXEC ops.sp_revertir_corrida @id;                 -- vista previa
EXEC ops.sp_revertir_corrida @id, @confirmar = 1; -- revierte (solo la corrida más reciente; no toca CYBER)

-- Qué pasó
SELECT * FROM ops.BITACORA WHERE ID_CORRIDA = @id ORDER BY ID;
SELECT * FROM ops.RECHAZO  WHERE ID_CORRIDA = @id;
```

Exportar los archivos (paso de SQL Agent tipo CmdExec):

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

- `cfg.ARCHIVO.RUTA` real y `mail.PLANTILLA.PERFIL_DBMAIL` real.
- `NEGATIVO_MODO` (hoy igual que el legado: el negativo sale positivo, H-01). `TOPE_DEVOLUCION_PCT` va vacío: la base maestra se trabaja como llega; poner un número solo si se quiere el freno.
- Parámetro `DMSTATUS_RETIRO` (valor de dmstatus para el retiro en CYBER).
- Columnas marcadas POR CONFIRMAR en `cfg.ARCHIVO_COLUMNA` (ENFOQUE, ETIQUETA, REE) y el archivo de Hipotecario.
- Destinatarios de `OPERACION_ASIG_486` (MAIL.prg / correo_486 no están versionados).
- Layout de arribo de pagos (PAGOS.prg) y salida SCBTEL (telbnx.prg): siguientes pasos.
- Carga inicial: DAT.DBF → `dat.DAT_486`, historia / PURGA → `dat.HISTORIA_FOLIO`, último folio de tab7 → `dat.FOLIO_CONSECUTIVO`.

## Codificación de los archivos

Los CSV que guarda Excel vienen en Windows-1252: en el servidor Windows `cfg.ARCHIVO.CODEPAGE = 'ACP'` los lee bien. SQL Server en Linux no admite `CODEPAGE`; por eso las pruebas de GitHub Actions generan los archivos en la página 437.

## Pruebas

`.github/workflows/pruebas-sql.yml` levanta SQL Server 2022 en GitHub Actions, ejecuta estos scripts y `tests/pruebas.sql` con datos ficticios (`tests/generar_datos_prueba.py`). El resultado queda en la rama `ci-resultados` (última corrida: 60 de 60 pruebas OK).
