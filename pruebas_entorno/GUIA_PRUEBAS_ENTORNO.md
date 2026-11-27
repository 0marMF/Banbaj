---
title: "Guía de pruebas de entorno · Banbaj 486"
subtitle: "Dónde dejar los archivos del banco y cómo correr las pruebas antes de producción"
---

# Dónde se depositan los archivos del banco

Banbaj busca los archivos de cada día en **una carpeta por fecha** dentro de la unidad Q:. La ruta se arma así (parámetro `RUTA` de `cfg.ARCHIVO`):

```
\\192.168.50.13\q\CYBER\C_486\{AAAA}\{MES}\{DD}\
```

| Parte | Qué va | Ejemplo |
|---|---|---|
| `{AAAA}` | Año con 4 dígitos | `2026` |
| `{MES}` | Nombre del mes en español, completo y sin acentos (se escribe en minúsculas) | `noviembre` |
| `{DD}` | Día con 2 dígitos (**con cero a la izquierda**) | `23`, `05` |

**Ejemplos de carpetas correctas:**

```
\\192.168.50.13\q\CYBER\C_486\2026\noviembre\23\
\\192.168.50.13\q\CYBER\C_486\2026\diciembre\05\
\\192.168.50.13\q\CYBER\C_486\2027\enero\04\
```

Es lo mismo que `Q:\CYBER\C_486\2026\noviembre\23\` en tu equipo, pero en los parámetros se usa la ruta de red (`\\192.168.50.13\q`) porque el servicio de SQL Server no ve las unidades mapeadas.

**Errores comunes que hacen que el job no encuentre nada:**

- `nov` o `11` en lugar del nombre completo del mes. (Mayúsculas o minúsculas da igual en Windows, pero usa minúsculas para que todas las carpetas se vean iguales.)
- `5` en lugar de `05` en el día.
- Dejar los archivos en la carpeta del mes o en otra fecha: cada día tiene su carpeta.
- Los meses válidos son: enero, febrero, marzo, abril, mayo, junio, julio, agosto, **septiembre** (no "setiembre"), octubre, noviembre, diciembre.

## Nombres de los archivos

Dentro de la carpeta del día, cada archivo se reconoce por el inicio de su nombre y su extensión, sin importar mayúsculas o minúsculas. Lo que venga después del inicio (fecha, consecutivo, etc.) da igual.

| Proceso | Archivo | El nombre debe empezar con | Extensión | Ejemplo válido |
|---|---|---|---|---|
| Asignación | Base maestra TDC | `BASE MAESTRA_TARJETA` | `.csv` | `BASE MAESTRA_TARJETA_23112026.csv` |
| Asignación | Base maestra Consumo | `BASE MAESTRA_CONSUMO` | `.csv` | `BASE MAESTRA_CONSUMO_23112026.csv` |
| Asignación | Base maestra Hipotecario | `BASE MAESTRA_HIPOTECARIO` | `.csv` | `BASE MAESTRA_HIPOTECARIO_23112026.csv` |
| Actualización | Saldos TDC | `SERTEC_Saldos_tdc` | `.txt` | `SERTEC_Saldos_tdc_23112026.txt` |
| Actualización | Saldos Consumo | `SERTEC_Saldos_Cons` | `.txt` | `SERTEC_Saldos_Cons_23112026.txt` |
| Actualización | Saldos Hipotecario (apagado hoy) | `SERTEC_Saldos_Hip` | `.txt` | `SERTEC_Saldos_Hip_23112026.txt` |
| Actualización | Pagos | `SERTEC_Pagos` | `.txt` | `SERTEC_Pagos_23112026.txt` |

Notas:

- Entre `BASE` y `MAESTRA` va un **espacio**; después de `MAESTRA` va un **guion bajo**.
- Las bases maestras van en `.csv` y los de actualización en `.txt` (separados por comas, como los manda el banco).
- No dejes dos archivos que empiecen igual en la misma carpeta (por ejemplo dos `BASE MAESTRA_TARJETA…`): el proceso toma solo uno, el último en orden alfabético, y el otro se ignora.
- Si llega solo un segmento (por ejemplo solo TDC), se asigna ese; cuando llegue el otro se hace otra asignación solo con él.

**Ejemplo de una carpeta completa para el 23 de noviembre de 2026:**

```
\\192.168.50.13\q\CYBER\C_486\2026\noviembre\23\
    BASE MAESTRA_TARJETA_23112026.csv
    BASE MAESTRA_CONSUMO_23112026.csv
    SERTEC_Saldos_tdc_23112026.txt
    SERTEC_Saldos_Cons_23112026.txt
    SERTEC_Pagos_23112026.txt
```

## Cómo comprobar que la ruta está bien

Sin correr nada del proceso, en SSMS:

```sql
USE [BNABAJ_486];
DECLARE @fecha DATE = '2026-11-23';     -- la fecha de la carpeta
EXEC ops.sp_prueba_archivos @fecha = @fecha;
```

Muestra, por cada archivo, la carpeta que buscó, si el servicio de SQL Server la puede leer y qué archivo encontró. Si dice que no puede leer la carpeta, revisa que exista y que la cuenta del servicio de SQL Server tenga permiso de lectura en `\\192.168.50.13\q`.

Para ver la ruta y los patrones que tiene configurados el servidor:

```sql
SELECT CODIGO, PROCESO, RUTA, PATRON_NOMBRE, ACTIVO FROM cfg.ARCHIVO WHERE CLIENTE = '486' ORDER BY PROCESO, ORDEN;
```

En `PATRON_NOMBRE`, `[_]` significa un guion bajo y `%` significa "cualquier cosa".

# Todas las rutas de entrada y salida

Las rutas `C:\` son del servidor de SQL Server. En las pruebas, las de salida (`RUTA_SALIDA`, `RUTA_MIS` y `CARPETA_ZIP`) apuntan a la carpeta de prueba mientras el modo de prueba está encendido; las de entrada no cambian.

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

# Pruebas de entorno antes de producción

Son 8 scripts en la carpeta `pruebas_entorno` del repositorio. Se abren en SSMS y se corren **en orden** sobre `BNABAJ_486`, con todos los scripts de `sql/` ya instalados (incluido `sql/85_sp_pruebas_entorno.sql`).

Para las pruebas 4 a 6 usa una fecha cuya carpeta ya tenga los archivos del banco. Puedes usar una fecha pasada: crea su carpeta con la ruta de arriba, copia ahí los archivos y pon esa fecha en `@fecha` de los scripts 4, 5 y 6.

| # | Script | Qué prueba | ¿Toca algo? |
|---|---|---|---|
| 1 | `01_modo_prueba_encender.sql` | Enciende el modo de prueba | Parámetros y jobs (se reponen en el 8) |
| 2 | `02_bajada_cyber.sql` | Servidor vinculado y cada tabla de CYBER; las bajadas reales | Solo tablas de paso de SQL Server |
| 3 | `03_correos.sql` | Database Mail, plantillas y un correo real | Un correo a tu dirección |
| 4 | `04_deteccion_archivos.sql` | Carpeta del día y archivo que encuentra cada patrón | Nada |
| 5 | `05_lectura_archivos.sql` | Lectura y validación de cada archivo | Una corrida PRUEBA cancelada; no toca el DAT |
| 6 | `06_asignacion_prueba.sql` | Actualización y asignación completas | El DAT (se revierte en el 7) |
| 7 | `07_revertir_prueba.sql` | Revierte lo del paso 6 | Deja el DAT como estaba |
| 8 | `08_modo_prueba_apagar.sql` | Repone parámetros y jobs | — |

## Paso 1 · Encender el modo de prueba

Antes de correrlo:

- Crea la carpeta de prueba, por ejemplo `C:\BANBAJ\486\PRUEBA\` (en el servidor de SQL Server). No uses SALIDA ni la carpeta de MIS.
- En el script cambia `@correo` por tu dirección y, si quieres, `@carpeta`.

```sql
DECLARE @correo  NVARCHAR(400) = N'tu.correo@sertec.com.mx',
        @carpeta NVARCHAR(400) = N'C:\BANBAJ\486\PRUEBA\';
EXEC ops.sp_prueba_modo @activar = 1, @correo = @correo, @carpeta = @carpeta;
```

Qué hace:

- Todos los correos van solo a tu dirección, con `[PRUEBA]` en el asunto.
- Ningún script se ejecuta en CYBER (retiro, actualización, depuraciones, banderas); las consultas sí se hacen. En la bitácora queda `CYBER EJECUTA` como AVISO.
- Los archivos de salida, de MIS y el ZIP se escriben en la carpeta de prueba.
- Apaga los jobs "Banbaj 486 diario" y "Banbaj 486 ladas" y recuerda cuáles estaban prendidos.
- La carpeta de entrada **no cambia**: los archivos del banco se leen de su carpeta del día en Q: (solo se leen).

Qué revisar: el resultado dice `MODO PRUEBA ENCENDIDO` con tu correo y la carpeta.

## Paso 2 · Bajada de información de CYBER

Revisa el servidor vinculado y que cada tabla que usa Banbaj se pueda consultar (DELQMST, PHONE, PHONE_G1, ADDRESS, UDA1, RPT_DAT_486_1, PHNVAL, la bandera 416, las tablas de remesa y los stores). Después corre las bajadas reales, que solo escriben en tablas de SQL Server. Solo regresa conteos.

Qué revisar: todo en OK. Una FALLA en `JSP_TAB_TEL_DEPURA_486` o en los stores es normal mientras el DBA no instale `cyber/486/oracle/JSP_TELEFONOS_DEPURA_486.sql`.

## Paso 3 · Envío de correos

Revisa el perfil de Database Mail, arma todas las plantillas y manda un correo real solo a tu dirección.

Qué revisar: que te llegue el correo. Si no llega, el mismo script trae consultas a `mail.ENVIO` y a los registros de Database Mail (`msdb`) para ver el error.

## Paso 4 · Detección de archivos

Para la fecha que pongas en `@fecha`, muestra la carpeta del día de cada archivo, si el servicio de SQL Server la puede leer, qué archivo encuentra con su patrón y qué haría el job. Al final dice si existe la carpeta de salida.

Qué revisar: que cada archivo que dejaste aparezca encontrado. Si no, revisa la ruta y los nombres con la primera parte de esta guía.

## Paso 5 · Lectura de archivos

Lee y valida cada archivo (layout, reglas de datos, duplicados) como lo haría el proceso, primero los de actualización y después las bases maestras, sin tocar el DAT. Deja una corrida PRUEBA cancelada en la bitácora.

Qué revisar: si algo dice "DETENDRÍA LA CORRIDA", corrígelo antes del paso 6: el archivo, el layout (`cfg.sp_layout_cambiar`) o el catálogo (`cfg.sp_catalogo_alta`).

## Paso 6 · Actualización y asignación de prueba

Corre la actualización (si ese día no hay una OK) y la asignación de la fecha con los archivos reales. CYBER no se toca, los correos llegan solo a ti y los archivos quedan en la carpeta de prueba. Muestra un resumen por corrida (solo conteos).

Qué revisar: estatus OK, altas NVA y REA, retiros, líneas de cada archivo, scripts de CYBER armados y correos recibidos.

Si llegó solo un segmento, puedes probar el segundo: deja su base en la carpeta y vuelve a correr `EXEC ops.sp_prueba_asignacion @fecha = @fecha;` (hace otra asignación solo con ese segmento).

Para ver el detalle de una corrida:

```sql
SELECT * FROM ops.PRUEBA_CORRIDA;
EXEC ops.sp_prueba_resumen <corrida>;
SELECT PASO, ESTATUS, REGISTROS, MENSAJE FROM ops.BITACORA WHERE ID_CORRIDA = <corrida> ORDER BY ID;
```

## Paso 7 · Revertir la prueba

Deja el DAT, el histórico, los folios, los pagos y las bases maestras como antes del paso 6.

1. Córrelo primero con `@confirmar = 0`: solo muestra lo que va a revertir.
2. Si está bien, córrelo con `@confirmar = 1`.

```sql
EXEC ops.sp_prueba_revertir @confirmar = 0;
-- EXEC ops.sp_prueba_revertir @confirmar = 1;
```

Con el modo de prueba encendido, cada actualización o asignación queda anotada desde que empieza. Así el paso 7 la revierte aunque el paso 6 se haya cortado con un error.

Si ese día ya había una actualización OK antes de la prueba, el paso 6 la usó y esta no se revierte.

## Paso 8 · Apagar el modo de prueba

Repone los parámetros (correos, CYBER, carpetas) y vuelve a prender los jobs que estaban prendidos.

Qué revisar: en la comprobación del script, `CORREO_PRUEBA_PARA` vacío, `CYBER_SOLO_LECTURA` en 0 y los jobs de Banbaj 486 prendidos.

# Cuidados

- **Siempre corre el paso 8.** Si el modo de prueba se queda encendido, en producción no saldría ningún correo a asignaciones ni se escribiría nada en CYBER.
- La reversión del paso 7 solo funciona si después de la prueba no corrió otra asignación o actualización. No prendas el job entre el paso 6 y el 7.
- Ninguna prueba imprime cuentas, nombres, teléfonos ni correos: solo conteos, nombres de archivo y mensajes de la bitácora enmascarados.
- Al terminar **borra la carpeta de prueba** (`C:\BANBAJ\486\PRUEBA\`): trae datos de clientes. Si copiaste archivos del banco a una carpeta de fecha pasada solo para la prueba, bórralos también.

# Al pasar a producción: limpiar

Cuando las pruebas salgan bien y ya no se vayan a repetir, sistemas borra lo que se instaló para probar con `sql/instalacion/06_limpiar_pruebas.sql`. Borra los stores `ops.sp_prueba_*`, las tablas `ops.PRUEBA_PARAM` y `ops.PRUEBA_CORRIDA` y las corridas de lectura de prueba del paso 5.

1. Córrelo como viene (`@confirmar = 0`): solo muestra lo que borraría.
2. Cambia `@confirmar` a `1` y córrelo otra vez.

No borra nada si el modo de prueba sigue encendido (falta el paso 8) o si quedó una asignación de prueba sin revertir (falta el paso 7). Después ya no se instalan otra vez al actualizar el servidor. Para volver a probar, borra el parámetro `PRUEBAS_LIMPIAS` y corre `sql/85_sp_pruebas_entorno.sql`.

Lo de la migración desde FoxPro se limpia igual con `sql/instalacion/05_limpiar_migracion.sql`.
