# Banbaj · guía para Claude Code

Migración a SQL Server de los procesos de Visual FoxPro del cliente **486 (Banco Bajío)** de SERTEC CDMX. En producción todo corre en SQL Server (procedimientos y un job del Agente); Python solo se usa para generar la semilla, los datos de prueba y los documentos.

Antes de cambiar un proceso, lee su diagrama en `docs/flujo/` (índice en `docs/flujo/README.md`). Cada diagrama dice qué procedimientos intervienen, qué tablas toca, qué parámetros lo controlan, qué pasos deja en la bitácora y qué pruebas lo cubren.

## Reglas que no se rompen

- **Datos de clientes:** el repositorio es privado y no lleva datos reales. No subas CSV, DBF ni TXT del banco. Al probar, nunca imprimas cuentas, nombres, teléfonos ni correos: solo conteos o valores enmascarados. Borra las copias temporales al terminar.
- **Contraseñas:** nunca en el repositorio. Las credenciales van cifradas en `cfg.CREDENCIAL` (`cfg.CAPTURA_CREDENCIAL` / `cfg.sp_credencial_leer`). `sql/instalacion/03_parametros_y_credenciales.sql` se edita en el servidor y no se sube con valores.
- **Commits:** autor `0marMF <omar13mor@gmail.com>`. Se trabaja en una rama y se sube a `main` solo cuando Omar lo pide. No se reescribe el historial publicado.
- **Idioma:** código, comentarios, mensajes y documentos en español (México).

## Mapa del código

| Carpeta / archivo | Qué es |
|---|---|
| `sql/01…90_*.sql` | Esquema y procedimientos. Se instalan en orden numérico (`for f in sql/*.sql`) |
| `sql/90_semilla_486.sql` | **Generado** por `tools/generar_sql_486.py`: parámetros, archivos de entrada y salida, layouts, plantillas y listas de correo. No se edita a mano |
| `sql/instalacion/01…04` | Instalación en un servidor nuevo: Database Mail y opciones, job, parámetros y credenciales, accesos |
| `cyber/486/oracle/` | Procedimientos de CYBER (Oracle): versión actual y versión propuesta |
| `cyber/486/EXPORTAR_MIGRACION.prg` | Exporta los DBF de FoxPro a CSV (cp1252 con CRLF: edítalo con `newline=''`) |
| `tests/pruebas.sql`, `tests/prueba_migracion.sql` | Pruebas de punta a punta; `tests/generar_datos_prueba.py` genera datos ficticios |
| `docs/*.md` → `docs/*.docx` | Manual, funcionamiento, migración. El equipo lee los Word |
| `docs/flujo/` | Diagramas (`mmd/` fuente Mermaid, `img/` generadas) y su explicación |
| `tools/` | `generar_sql_486.py` (semilla), `generar_diagramas.sh`, `generar_docs_word.sh` |

| SQL | Procedimientos principales |
|---|---|
| `10_funciones` | `cfg.fn_param`, `cfg.fn_texto`, `cfg.fn_importe`, `cfg.fn_fecha`… |
| `20_sp_comunes` | `ops.sp_log`, `ops.sp_corrida_iniciar/finalizar`, `ops.sp_cargar_proceso`, `ops.sp_homologar`, `ops.sp_validar` |
| `25_sp_correo` | `mail.sp_enviar`, `mail.sp_hallazgo`, `mail.fn_tabla_html` |
| `30_sp_asignacion` | `ops.sp_asig_unir_layout`, `ops.sp_asig_devolucion`, `ops.sp_asig_existentes`, `ops.sp_asig_alta`, `ops.sp_retiro` |
| `35_sp_respaldo` | `ops.sp_respaldo`, `ops.sp_revertir_corrida`, `ops.sp_retroceso_automatico` |
| `40_sp_actualizacion` | `ops.sp_act_preparar`, `ops.sp_act_aplicar`, `ops.sp_act_pagos`, `ops.sp_act_script_pvs_ree` |
| `45_sp_telefonos`, `46_sp_correos_cyber` | Teléfonos y correos de la asignación |
| `50_sp_salidas`, `52_sp_exportar` | Arman los planos (`ops.SALIDA_LINEA`) y los escriben a disco (OLE + 7-Zip) |
| `60_sp_orquestadores` | `ops.sp_diario_486`, `ops.sp_asignacion_486`, `ops.sp_actualizacion_486` |
| `70_sp_procesos_manuales`, `72_sp_seguimiento` | Etiquetado, blanqueo, exclusiones, avisos, marcas de tiempo, cuadre |
| `74_sp_cyber`, `76_sp_arribo_cyber` | Servidor vinculado, bajadas de CYBER, ejecución en CYBER y arribo automático |
| `77_sp_retiro_automatico`, `78_sp_automatico` | Retiro automático, exportación, scripts ACT en CYBER, blanqueo, confirmación, cuadre, aviso de archivos |
| `80_sp_migracion` | `ops.sp_migrar_486` y `ops.sp_mig_leer` |

## Convenciones

- SQL Server 2017 o superior: `CREATE OR ALTER`, `TRY/CATCH` con `THROW`, `STRING_AGG`, `OPENJSON`. Las tablas se crean con `IF OBJECT_ID(...) IS NULL`, y las columnas nuevas con `IF COL_LENGTH(...) IS NULL ALTER TABLE`, para que todo se pueda volver a correr sobre una base existente.
- **Corrida:** cada proceso es una corrida (`ops.sp_corrida_iniciar` / `ops.sp_corrida_finalizar`). Cada paso deja un renglón con `EXEC ops.sp_log @id, '<PASO>', 'OK|AVISO|ERROR', @registros, @mensaje`. Si la corrida falla, `ops.sp_retroceso_automatico` restaura el DAT.
- **Lo que pasa después de la corrida** (archivos, CYBER, correos) va fuera del `TRY` principal y en su propio `TRY/CATCH`: si falla no cambia el estatus de la corrida, queda `ERROR` en la bitácora y se avisa con `mail.sp_hallazgo`.
- **Pasos automáticos idempotentes:** antes de actuar revisan en `ops.BITACORA` si su paso ya quedó `OK` (o `OK`/`ERROR` cuando no deben reintentarse solos). Se pueden correr a mano con el número de corrida y solo repiten lo pendiente.
- **Todo lo configurable es un parámetro:** se lee con `cfg.fn_param('486', 'CLAVE')`. Para agregar uno, se agrega en `PARAMETROS` de `tools/generar_sql_486.py`, se corre `python3 tools/generar_sql_486.py` y se documenta en el manual.
- **Correos:** plantilla y lista en `PLANTILLAS` de `tools/generar_sql_486.py`; se mandan con `mail.sp_enviar @plantilla, @id_corrida, @valores (JSON)`. Las llaves `HTML_*` van sin escapar (ya armadas con `mail.fn_tabla_html`).
- **Escribir en CYBER:** siempre con `ops.sp_cyber_ejecutar @id, '<SCRIPT>'`, que toma las líneas de `ops.CYBER_SCRIPT` (las mismas que se escriben en `cyber\*.sql`) y las manda en bloques PL/SQL por el servidor vinculado. No abras otra conexión.
- **Errores:** `THROW 50xxx`, con rango por archivo (20: 50010-50040, 30: 50100-50110, 35: 50300s, 50: 50200s, 70: 50600s, 72: 50700s, 74/76/77/78: 50760-50823, 52: 50850s, 80: 50900s). Antes de usar un número, búscalo con `grep -rn "5xxxx" sql/`.
- `EXEC proc` no acepta expresiones como parámetro (`CONCAT`, subconsultas): asigna primero a una variable. Un agregado no puede contener una subconsulta (`SUM(CASE WHEN EXISTS…)`): usa `LEFT JOIN`.

## Probar

No hay SQL Server en el entorno de desarrollo. Las pruebas corren en GitHub Actions (`.github/workflows/pruebas-sql.yml`) con SQL Server 2022 en Linux, en cada push a cualquier rama. Instalan todo `sql/`, generan datos ficticios y corren `tests/pruebas.sql`, `tests/prueba_migracion.sql` y el script de accesos. El resultado se publica en la rama `ci-resultados`:

```bash
git fetch origin +refs/heads/ci-resultados:refs/remotes/origin/ci-resultados
git show origin/ci-resultados:resultado.txt | grep -E "commit|PRUEBAS:|MIGRACION:|ACCESOS:|FALLA"
```

Cada cambio de comportamiento lleva su prueba en `tests/pruebas.sql` (`INSERT INTO pru.RESULTADO` o `EXEC pru.sp_igual N'nombre', N'esperado', @obtenido`). En CI no hay servidor vinculado a CYBER ni Database Mail: los pasos que escriben en CYBER se prueban con `@solo_mostrar = 1` o verificando que dejen `ERROR` y hallazgo; las bajadas se simulan llenando las tablas `stg.CYBER_*` y usando `@sin_bajar = 1`. Las pruebas apagan al inicio los parámetros automáticos y los prenden solo donde los prueban.

## Documentar

1. Cambia el `.md` que corresponda (`docs/FUNCIONAMIENTO_486.md`, `docs/MANUAL_INSTALACION_486.md`, `cyber/486/ARRIBO_MANUAL.md`, `docs/FALTANTES_486.md`).
2. Si cambió un flujo, actualiza su diagrama en `docs/flujo/mmd/*.mmd` y su explicación en `docs/flujo/*.md`, y corre `./tools/generar_diagramas.sh`.
3. Regenera los Word: `./tools/generar_docs_word.sh` (pandoc con `tools/plantilla_word.docx`).

## Estado actual (07/11/2026)

- **Proceso autónomo:** el job corre la actualización y la asignación, escribe los archivos, avisa a asignaciones (`ARCHIVOS_LISTOS_486`), aplica las devoluciones con tope de 50 % por segmento, ejecuta en CYBER los scripts de la actualización, detecta cuándo se subieron el SCBSDOS y el SCBTEL para correr las depuraciones de correos y teléfonos, hace el blanqueo de status, manda la confirmación y cuadra los pagos.
- **Sigue a mano:** subir los planos de ancho fijo con el cargador de CYBER (SCBSDOS, SCBTEL, SCBPAG, gescar), copiar `MX_G1MCT_DVBJIG_*` a `\\192.168.50.1\Cyber_00\dev\` (el servidor no tiene acceso; `RUTA_DEVOLUCION_CYBER` vacío) y atender el correo de hallazgos.
- Cada parte automática se apaga con su parámetro: `ARRIBO_AUTOMATICO`, `ACT_CYBER_AUTOMATICO`, `RETIRO_AUTOMATICO`, `RETIRO_CYBER_AUTOMATICO`, `BLANQUEO_AUTOMATICO`, `CONFIRMACION_AUTOMATICA`, `CUADRE_AUTOMATICO`, `EXPORTAR_AUTOMATICO`, `AVISO_ARCHIVOS`.
- Pendientes con el equipo: `docs/FALTANTES_486.md`.
