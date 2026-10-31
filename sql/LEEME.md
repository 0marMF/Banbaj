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
| `45_sp_telefonos.sql` | Teléfonos de cuentas nuevas en el DAT (op9.prg) y teléfonos para CYBER (telbnx.prg) |
| `46_sp_correos_cyber.sql` | Correos para CYBER en la asignación (email.PRG + act_mail.prg) |
| `50_sp_salidas.sql` | Archivos planos de `cfg.SALIDA_ARCHIVO` + `cfg.SALIDA` (ancho fijo o delimitados) |
| `60_sp_orquestadores.sql` | `ops.sp_asignacion_486` y `ops.sp_actualizacion_486` |
| `70_sp_procesos_manuales.sql` | Etiquetado del DAT, SCBSDOS fuera de proceso, blanqueo de status, exclusiones, avisos a Operación |
| `90_semilla_486.sql` | Configuración del 486 (generada con `tools/generar_sql_486.py`) |

Con `sqlcmd` usar siempre `-I` (QUOTED_IDENTIFIER ON) y `-f 65001` (los scripts están en UTF-8; sin esto los acentos de la semilla se dañan). SSMS ya maneja ambos.

## Uso diario

De lunes a viernes llega la actualización de saldos y pagos; la asignación puede o no llegar y siempre llega después. Un job de SQL Agent llama cada 30 minutos (lunes a viernes) a:

```sql
EXEC ops.sp_diario_486;   -- corre la actualización cuando llegan sus archivos y después la asignación si llegó; no repite lo que ya corrió
```

La asignación no corre si la actualización del día no terminó OK (`ASIG_REQUIERE_ACT`). Los avisos de pagos a T-1 usan el día hábil anterior (el lunes revisa el viernes). También se pueden correr a mano:

```sql
-- Asignación y actualización toman los archivos de Q:\CYBER\C_486\<año>\<mes>\<día>\ (cfg.ARCHIVO.RUTA con {AAAA}\{MES}\{DD})
DECLARE @id INT;
EXEC ops.sp_asignacion_486 @hora_llegada = '09:15', @id_corrida = @id OUTPUT;

-- Revisar lo que se va a retirar y aplicarlo
SELECT * FROM ops.DEVOLUCION WHERE ID_CORRIDA = @id;
EXEC ops.sp_retiro @id;

-- Actualización de saldos y pagos (los pagos negativos se excluyen y se avisa a Operación)
EXEC ops.sp_actualizacion_486 @id_corrida = @id OUTPUT;

-- Después de arribar a CYBER: avisos a Operación (antes MAIL, correo_486, correo, correo_486noti)
EXEC ops.sp_avisar @id, 'CONFIRMACION_ASIG_486';     -- fin de asignación (el inicio sale solo)
-- Correo único de devolución (Operación con el ZIP, AEM en copia oculta sin él)
EXEC ops.sp_exportar_salidas @id_corrida = @id, @zip = 'RETIROS', @enviar_zip = 1;

-- Cruces con CYBER (todo en SQL Server, por servidor vinculado a Oracle)
--   Una vez: depositar usuario y contraseña (se guardan cifrados) y armar el vínculo
INSERT INTO cfg.CAPTURA_CREDENCIAL (SISTEMA, USUARIO, CLAVE) VALUES ('CYBER_ORACLE', N'<usuario>', N'<contraseña>');
EXEC cfg.sp_cyber_conectar;
--   Cuando toque (baja a stg.CYBER_* y ejecuta el procedimiento que sigue)
EXEC ops.sp_bajar_cyber 'STATUS',    @id_corrida = @id;   -- blanqueo, día 1 al 10
EXEC ops.sp_bajar_cyber 'CORREOS',   @id_corrida = @id;   -- INSERT de correos nuevos
EXEC ops.sp_bajar_cyber 'TELEFONOS', @id_corrida = @id;   -- gescar de cuentas sin teléfono

-- Bases maestras completas (todas las columnas)
SELECT JSON_VALUE(DATOS, '$."ACC_NUM"') FROM dat.BASE_RECIBIDA WHERE ID_CORRIDA = @id AND CODIGO = 'MAESTRA_TDC';

-- Etiquetado de un campo del DAT: CSV con encabezado FOLIO,ETIQUETA ('-' = dejar en blanco).
-- @campo: nombre del DAT (SALDO1, TRAMO…) o de Operación (MORA, SEG_CICLO, LEYENDA… ver ETIQUETADO_ALIAS)
EXEC ops.sp_etiquetar_campo @campo = 'MORA', @archivo = N'D:\Banbaj\486\etiquetas\mora.csv';                 -- vista previa
EXEC ops.sp_etiquetar_campo @campo = 'MORA', @archivo = N'D:\Banbaj\486\etiquetas\mora.csv', @confirmar = 1; -- DAT + SCBSDOS
-- TOP (ETIQUETA6) no es columna del DAT:
EXEC cfg.sp_etiqueta_cargar '486', 'TOP', N'D:\Banbaj\486\etiquetas\top.csv', 'AGREGAR';

-- Horas del arribo a CYBER (antes bitac/bitact): solicitud, autorización y fin
EXEC ops.sp_marcar_arribo @id_corrida = 130, @evento = 'SOLICITUD';
EXEC ops.sp_marcar_arribo @id_corrida = 130, @evento = 'AUTORIZACION';
EXEC ops.sp_marcar_arribo @id_corrida = 130, @evento = 'FIN';
SELECT * FROM ops.v_TIEMPOS_CORRIDA ORDER BY ID_CORRIDA DESC;

-- Cuadre de pagos después de arribar SCBPAG (antes BAJ.sql + C:\NO_SUBIERON486)
EXEC ops.sp_bajar_cyber 'PAGOS', @id_corrida = 130;

-- Retiros por actualización: ZIP con contraseña y correo con el adjunto
--   La contraseña se deposita una vez (acepta {MM} y {AAAA}):
--   INSERT INTO cfg.CAPTURA_CREDENCIAL (SISTEMA, USUARIO, CLAVE) VALUES ('ZIP_RETIROS', N'zip', N'<contraseña>');
EXEC ops.sp_exportar_salidas @id_corrida = 130, @zip = 'RETIROS', @enviar_zip = 1;   -- C:\RETIROS_PAG_486_<mmddaaaahhmmss>.zip

-- Lista negra de teléfonos con requerimiento (solo 10 dígitos; los demás se cuentan y se omiten)
EXEC cfg.sp_exclusion_cargar @tipo = 'TELEFONO', @archivo = N'D:\Banbaj\486\blacklist.csv', @req = 'REQ 2026-…', @solicita = N'…';

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

```sql
EXEC ops.sp_exportar_salidas @id_corrida = 123;                     -- en RUTA_SALIDA\<AAAAMMDD>_corrida123\
EXEC ops.sp_exportar_salidas @id_corrida = 123, @solo_mostrar = 1;  -- vista previa
```
Requiere `Ole Automation Procedures` activado (y `xp_cmdshell` solo para el ZIP de retiros).

| Proceso | Archivos |
| --- | --- |
| Asignación | `SCBSDOS.TXT`, `SCBTEL.TXT`, `sub_mst.TXT`, `sub_mail.TXT`, `SCBACTH_486NU.TXT`, `SCBACTH_486REA.TXT`, `cyber/TEL_ACTUALIZA.sql`, `cyber/MAIL_BORRA.sql`, `cyber/MAIL_ACTUALIZA.sql` |
| Blanqueo de status | `BLANQUEA_486_<fecha>.csv`, `cyber/BLANQUEO_STATUS.sql` |
| Etiquetado / mora | `SCBSDOS.TXT` |
| Actualización | `SCBPAG.TXT`, `cyber/ACT_SALDOS.sql`, `ACT_VENCIDO.sql`, `ACT_PAGMIN.sql`, `ACT_PVS_REE.sql` (PVS y REE; ya no se arriba SCBSDOS) |
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
EXEC mail.sp_destinatario_alta 'DEVOLUCION_OPERACION_486', 'persona@sertec.com.mx', 'TO';
EXEC mail.sp_destinatario_baja 'DEVOLUCION_OPERACION_486', 'persona@sertec.com.mx';
SELECT * FROM mail.v_LISTA_RESUELTA;          -- cómo queda cada lista
EXEC ops.sp_aviso_devolucion @id, @solo_prueba = 1;   -- ver los correos sin enviarlos
```

## Pendientes antes de producción

Lista completa de programas, tablas y preguntas en [`docs/FALTANTES_486.md`](../docs/FALTANTES_486.md).


- `mail.PLANTILLA.PERFIL_DBMAIL` real. La ruta de entrada ya es `Q:\CYBER\C_486\{AAAA}\{MES}\{DD}\` (ej. `Q:\CYBER\C_486\2026\octubre\28\`); la cuenta de servicio de SQL Server necesita lectura en `Q:` (mejor por ruta UNC, porque las unidades mapeadas no existen para el servicio).
- `NEGATIVO_MODO` (hoy igual que el legado: el negativo sale positivo, H-01). `TOPE_DEVOLUCION_PCT` va vacío: la base maestra se trabaja como llega; poner un número solo si se quiere el freno.
- Columnas marcadas POR CONFIRMAR en `cfg.ARCHIVO_COLUMNA` (ENFOQUE, ETIQUETA, REE) y el archivo de Hipotecario.
- Destinatarios: el equipo de Operación (`OPERACION_ASIG_486`) recibe el inicio y fin de asignación, el saldo <= 0 en Consumo y los pagos negativos.
- Carga inicial desde los DBF: CSV exportados con FoxPro + `ops.sp_migrar_486` (ver abajo).

## Migración de los DBF (una sola vez)

Los DBF dejan de usarse. Todo se carga desde SQL Server, en una sola transacción:

1. En FoxPro, correr `cyber/486/EXPORTAR_MIGRACION.prg`: deja `C:\MIGRA486\<FUENTE>.csv` (COPY TO … TYPE CSV). La carpeta debe ser visible para el servicio de SQL Server.
2. Revisar y cargar:

```sql
EXEC ops.sp_migrar_486 @carpeta = N'C:\MIGRA486\';                    -- revisa: filas leídas, filas por destino y avisos
EXEC ops.sp_migrar_486 @carpeta = N'C:\MIGRA486\', @confirmar = 1;    -- carga (si ya hay datos: @reemplazar = 1)
```

3. Borrar `C:\MIGRA486` (trae datos de clientes). Las tablas de paso `stg.MIG_*` se borran solas.

| CSV | Tabla |
| --- | --- |
| DAT | `dat.DAT_486` |
| DAT (activas) | `dat.HISTORIA_FOLIO` (PURGA y DEVOL no se migran) |
| TAB7 (máximo folio, comparado con DAT e HISTORIA) | `dat.FOLIO_CONSECUTIVO` |
| PAGTOT (solo CUENTA + FE_PAG + MONT) | `dat.PAGO_ARRIBADO` |
| ETI, DM1, TOP, STATUS | `cfg.ETIQUETA` |
| EXC486, DIRMAL, EMAILMALO, BLACKLIST (10 dígitos), TELBAJ | `cfg.EXCLUSION` (solo lo que aplica al 486; los 3 teléfonos del banco van en la semilla) |
| LADA, PNC | `cfg.LADA`, `cfg.PLAN_NUMERACION` |

## Codificación de los archivos

Los CSV que guarda Excel vienen en Windows-1252: en el servidor Windows `cfg.ARCHIVO.CODEPAGE = 'ACP'` los lee bien. SQL Server en Linux no admite `CODEPAGE`; por eso las pruebas de GitHub Actions generan los archivos en la página 437.

## Pruebas

En producción todo corre en SQL Server. Python solo se usa aquí, para desarrollo: `tools/generar_sql_486.py` arma la semilla desde el mapeo y `tests/generar_datos_prueba.py` crea datos ficticios.
`.github/workflows/pruebas-sql.yml` levanta SQL Server 2022 en GitHub Actions y ejecuta estos scripts, `tests/pruebas.sql` y `tests/prueba_migracion.sql`. El resultado queda en la rama `ci-resultados`. La escritura real de archivos (automatización OLE), el ZIP (xp_cmdshell) y el servidor vinculado a Oracle no existen en SQL Server para Linux: las pruebas revisan lo que se escribiría (`@solo_mostrar = 1`).
