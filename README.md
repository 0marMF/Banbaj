# Banbaj – Cliente 486 (Banco Bajío)

Levantamiento de requerimientos de los procesos de **asignación** y **actualización** del cliente 486, como base para migrarlos a SQL Server con catálogos y stored procedures.

## Documentación (Word)

- [`docs/Como funciona Banbaj 486.docx`](docs/) — cómo funciona por dentro: flujo diario, actualización, asignación, retiro, teléfonos, exclusiones, salidas, correos, respaldo, tablas y procedimientos.
- [`docs/Migracion paso a paso Banbaj 486.docx`](docs/) — cómo ejecutar la migración desde FoxPro, con lo que hay que revisar en cada paso.
- [`docs/Manual de migracion, instalacion y operacion Banbaj 486.docx`](docs/) — requisitos, instalación de la base, configuración del servidor, migración desde FoxPro, operación diaria, respaldo y retroceso, salida a producción.

Al abrirlos, Word pide actualizar los campos: di que sí para que se llene el índice. Los `.md` de `docs/` son la fuente; los `.docx` se regeneran con `tools/generar_docs_word.sh`.

## Contenido

| Archivo | Proceso | Hojas principales |
| --- | --- | --- |
| `mapeos/mapeo_486.xlsx` | Asignación | MAPEOS (DAT y SCBSDOS), REGLAS, SCBTEL, CAT_CP_ESTADO, FLUJO_ASIGNACION, HALLAZGOS |
| `mapeos/ACT_PAGOS_486.xlsx` | Actualización | ACT_PAGOS_486 (archivos del banco), RETIROS_ACT, FLUJO_ACTUALIZACION, HALLAZGOS |

Fuente: programas Visual FoxPro de la carpeta 486 (`paso.prg`, `asig_bases.prg`, `asi486.prg`, `telbnx.prg`, `saldos.prg`, `prog15.prg`) y el documento de actualización de saldos y pagos.

> Repositorio privado: los mapeos incluyen ejemplos con datos de clientes.
