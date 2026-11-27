# 486 · Arribo manual a CYBER

Cada corrida deja los archivos planos en `ops.SALIDA_LINEA` y los scripts de Oracle en `ops.CYBER_SCRIPT`. Para tenerlos en disco:

```sql
USE [BNABAJ_486];
EXEC ops.sp_exportar_salidas <ID>;
```

Eso crea `RUTA_SALIDA\<AAAAMMDD>_corrida<ID>\` (de fábrica `C:\BANBAJ\486\SALIDA\`) con los archivos y la carpeta `cyber\` con los `.sql`.

## Qué es automático y qué sigue a mano

Diagrama: `docs/flujo/05_arribo_cyber.md` (y su imagen en `docs/flujo/img/`).

| Qué | Quién | Cómo |
| --- | --- | --- |
| Generar y escribir los archivos y scripts | **Job** | Al terminar cada corrida |
| Aviso de archivos listos | **Job** | ARCHIVOS_LISTOS_486 a asignaciones |
| Subir SCBSDOS, SCBTEL, SCBPAG y gescar | Asignaciones | Cargador de CYBER |
| Gescar de nuevas, reasignadas y sin teléfono (escribir y avisar) | **Job** | En cuanto detecta que subió el SCBSDOS |
| Depuración de teléfonos con la bandera 416 (con `DIFERENCIA`: foto de `PHONE`, solo los cambios a `JSP_TAB_TEL_DEPURA_486` y `JSP_TELEFONOS_DEPURA_486`; con `ACTUAL`: remesa completa y `JSP_TELEFONOS_REMESA_486`) y después escribir y avisar el SCBTEL | **Job** | En cuanto detecta que subió el SCBSDOS |
| Depuración de correos (correos nuevos, bandera 416, remesa, `JSP_CORREOS_486`) | **Job** | Después de la depuración de teléfonos OK |
| Blanqueo de status (días 1 a 10) | **Job** | Después de la depuración de correos |
| Fin del arribo y `CONFIRMACION_ASIG_486` | **Job** | Con correos y teléfonos OK, el gescar sin teléfono hecho y el SCBTEL arriba |
| Scripts de la actualización (`ACT_*`) | **Job** | Al terminar la actualización |
| Retiro en CYBER | **Job** | Al cerrar el retiro |
| Copiar `MX_G1MCT_DVBJIG_*` a `\\192.168.50.1\Cyber_00\dev\` | Asignaciones | A mano: el servidor no tiene acceso a esa carpeta |
| Cuadre de pagos (solo lee y avisa) | **Job** | Hallazgo si a las 17:00 falta algún pago |

**Cómo detecta que ya subieron los planos:** los saldos (SCBSDOS), con la validación que hace el equipo (`val.txt`): cada 30 minutos baja `select dmhostup, count(*) from rcvry.delqmst where dmacctg='1' and dmcompany='486' and dmstatus is null group by dmhostup` y, si las cuentas con `DMHOSTUP` del día son tantas como las del SCBSDOS (`ARRIBO_SDOS_MIN_PCT` = 100), da los saldos por subidos: escribe los gescar de nuevas, reasignadas y sin teléfono y corre la depuración de teléfonos; si lo que sube a CYBER cuadra con lo que mandamos, escribe el SCBTEL y corre la de correos. Los teléfonos (SCBTEL), con la foto que se toma al terminar la asignación (`ops.sp_arribo_base`, y con `DIFERENCIA` los nuevos): cuando ya están en `PHONE_G1` al menos el 95 % (`ARRIBO_MIN_PCT`), marca `ARRIBO SCBTEL` y manda la confirmación. Cada una corre una sola vez por corrida, y funciona aunque no haya cuentas nuevas.

Los procedimientos ejecutan en CYBER, por el servidor vinculado `[CYBER]`, las mismas sentencias que quedan en la carpeta `cyber\` (`sql/76_sp_arribo_cyber.sql`), sin sqlldr. Si algo falla queda `ERROR` en la bitácora, llega el correo de hallazgos y no se reintenta solo. Se corrige y se corre a mano:

```sql
USE [BNABAJ_486];
EXEC ops.sp_arribar_cyber <ID>, 'CORREOS', @solo_mostrar = 1;   -- ver los bloques sin ejecutar
EXEC ops.sp_arribar_cyber <ID>, 'TELEFONOS';                    -- primero teléfonos, luego 'CORREOS'
EXEC ops.sp_arribo_gescar_sintel <ID>;                          -- cuando ya subió el SCBTEL
EXEC ops.sp_act_cyber <ID>;                                     -- scripts de la actualización
EXEC ops.sp_retiro_cerrar <ID>;                                 -- pasos del retiro
EXEC ops.sp_blanqueo_automatico <ID>, @forzar = 1;              -- blanqueo
```

Para volver a correr todo a mano: `UPDATE cfg.PARAMETRO SET VALOR = '0' WHERE CLIENTE = '486' AND CLAVE IN ('ARRIBO_AUTOMATICO', 'ACT_CYBER_AUTOMATICO', 'BLANQUEO_AUTOMATICO', 'CONFIRMACION_AUTOMATICA', 'RETIRO_CYBER_AUTOMATICO');`. Los pasos de abajo explican qué hace cada script y sirven para correrlos en Oracle si hiciera falta.



**Permisos del usuario de Oracle** (el de la credencial `CYBER_ORACLE`): `TRUNCATE`/`INSERT`/`SELECT` en `RCVRY.JSP_TAB_TEL_REMESA_486` (el `SELECT` cuenta la remesa antes de la depuración) y `RCVRY.JSP_TAB_MAIL_REMESA_486`, `INSERT` en `RCVRY.ADDRESS` y `RCVRY.JSP_VALIDADOR_TELEFONOS`, `UPDATE` en `RCVRY.RPT_LOG_CYBER_REG` y `EXECUTE` de `RCVRY.JSP_TELEFONOS_REMESA_486` y `RCVRY.JSP_CORREOS_486`. Sin ellos el arribo queda en `ERROR` con el mensaje de Oracle.

## Asignación (`ops.sp_asignacion_486`)

| Archivo | Qué es | Programa que reemplaza |
| --- | --- | --- |
| `SCBSDOS.TXT` | Cuentas del DAT, 1559 posiciones | asi486.prg |
| `SCBTEL.TXT` | Teléfonos, 137 posiciones | telbnx.prg (TELSAN) |
| `sub_mst.TXT` | Teléfonos `CUENTA\|AREA\|TELEFONO\|TIPOTEL` | telbnx.prg → act_phone.prg |
| `SCBACTH_486NU.TXT` | Gescar de cuentas nuevas, 119 posiciones | ges_nuevas_rea.prg |
| `SCBACTH_486REA.TXT` | Gescar de reasignadas, 119 posiciones | ges_nuevas_rea.prg |

Los pasos de teléfonos, correos y gescar sin teléfono que siguen son **lo que hace el job solo** (ver arriba). Quedan documentados para entenderlos y para el arribo manual si se apaga `ARRIBO_AUTOMATICO`.

**Teléfonos (solo en la asignación).** Con `TEL_DEPURACION = DIFERENCIA` no se carga la remesa completa: el job baja la foto de `PHONE`, la compara con `ops.TELEFONO` (`ops.sp_tel_depura_calcular`) y solo sube los cambios (`I`, `A`, `N`) a `RCVRY.JSP_TAB_TEL_DEPURA_486`. A mano, con la bandera encendida (`cyber\TEL_ACTIVA_BANDERA.sql`): `EXEC ops.sp_tel_depura_calcular <ID>;`, volver a exportar, `cyber\TEL_BORRA.sql`, `cyber\TEL_DEPURA.sql`, revisar que la tabla tenga los renglones de `TEL_DEPURA.sql`, `cyber\TEL_ACTUALIZA.sql` (`EXECUTE RCVRY.JSP_TELEFONOS_DEPURA_486(416, <esperados>, <quejas>)`), `cyber\TEL_INACTIVA_BANDERA.sql` y subir el SCBTEL (solo nuevos). O simplemente `EXEC ops.sp_arribar_cyber <ID>, 'TELEFONOS';`.

Con `ACTUAL` se mandan todos los del DAT; CYBER purga y agrega. El orden es el del equipo:
1. Que ya hayan subido los saldos (SCBSDOS).
2. `cyber\TEL_ACTIVA_BANDERA.sql` y `cyber\TEL_BORRA.sql` (vacía la remesa).
3. Cargar `sub_mst.TXT` en `RCVRY.JSP_TAB_TEL_REMESA_486` con `LOAD_TEL_REMESA.CTL` (sqlldr, igual que hoy) y revisar que la tabla tenga **los mismos renglones que `sub_mst.TXT`**. Si no, no seguir.
4. Ejecutar `cyber\TEL_ACTUALIZA.sql` (`EXECUTE RCVRY.JSP_TELEFONOS_REMESA_486`) y `cyber\TEL_INACTIVA_BANDERA.sql`.
5. Subir `SCBTEL.TXT`: activa nuestros teléfonos, también los nuevos. Después, los correos.

Qué hace el procedimiento de CYBER (la versión optimizada para instalar está en `cyber/486/oracle/JSP_TELEFONOS_REMESA_486.sql`):
- Inserta en `PHONE` los teléfonos de la remesa que están en `PHONE_G1` y no en `PHONE`, solo de cuentas activas del 486 (`dmstatus` nulo).
- **Inactiva** (`HIAS`) los teléfonos activos del 486 que no vienen en la remesa, salvo los marcados con gestor de queja (`HOMS`, `HPHPI`, `BLACK`, `ZZZTE`).
- **Activa** (`HAAS`) los teléfonos de la remesa que estaban inactivos, salvo esos mismos gestores de queja: aunque Banbaj mandara un teléfono con queja, CYBER no lo reactiva.
- Compara por cuenta, área y teléfono exactos, así que el área de sub_mst debe coincidir con la de SCBTEL (Banbaj saca los dos de la misma tabla).
- Al final completa el renglón del día de `RCVRY.JSP_VALIDADOR_TELEFONOS`. Ese renglón lo inserta `cyber\TEL_BORRA.sql` con el total de teléfonos que mandó Banbaj (parámetro `CYBER_VALIDADOR_TELEFONOS`), así que la diferencia contra lo que cargó sqlldr sigue sirviendo.

**Correos (solo en la asignación).** Como hoy (email.PRG + act_mail.prg):
1. `EXEC ops.sp_bajar_cyber 'CORREOS', @id_corrida = <ID>;` baja los correos que ya tiene CYBER y arma `cyber\MAIL_INSERTA_NUEVOS.sql`; volver a exportar la corrida. **No es opcional:** `JSP_CORREOS_486` solo activa e inactiva correos que ya existen en `ADDRESS`; los correos nuevos solo entran con este INSERT.
2. Correr `cyber\MAIL_INSERTA_NUEVOS.sql` (INSERT en `RCVRY.ADDRESS` de los nuevos).
3. Depuración: `cyber\MAIL_ACTIVA_BANDERA.sql` → `cyber\MAIL_BORRA.sql` → cargar `sub_mail.TXT` con `LOAD_MAIL_REMESA.CTL` → revisar la tabla → `cyber\MAIL_ACTUALIZA.sql` (`JSP_CORREOS_486` purga lo que ya no llega) → `cyber\MAIL_INACTIVA_BANDERA.sql`.

Qué hace `JSP_CORREOS_486`: inactiva (`HIAS`) lo que está en `ADDRESS` de cuentas activas del 486 y no viene en la remesa, y activa (`HAAS`) lo de la remesa que estaba inactivo, salvo gestores `HOMS` y `HPHPI`. Solo queda activo el domicilio de la última base maestra: el de `DELQMST.DMADDR1`, que sube con el SCBSDOS. **Antes de la primera corrida hay que instalar en CYBER `cyber/486/oracle/JSP_CORREOS_486.sql`.**

**Gescar de cuentas sin teléfono.** Sale de nuestro archivo de teléfonos (las nuevas y reasignadas sin renglón en `ops.TELEFONO`), así que no hay que esperar al SCBTEL: se genera con la asignación y el job lo escribe junto con los gescar de nuevas y reasignadas al subir los saldos. A mano: `EXEC ops.sp_arribo_gescar_sintel <ID>;` (lo vuelve a generar, lo escribe y avisa).

**Después de arribar:** `EXEC ops.sp_avisar <corrida>, 'CONFIRMACION_ASIG_486'` (sale solo al terminar las depuraciones, `CONFIRMACION_AUTOMATICA`).

**Blanqueo de status (día 1 al 10).** Automático después de la depuración de correos (`BLANQUEO_AUTOMATICO`): baja los status, ejecuta el blanqueo en CYBER y deja `BLANQUEA_486_<fecha>.csv` en la carpeta de la corrida. A mano: `EXEC ops.sp_blanqueo_automatico <ID>, @forzar = 1;`. Paso a paso: `EXEC ops.sp_bajar_cyber 'STATUS', @id_corrida = <ID>;`, volver a exportar, revisar el CSV y correr `cyber\BLANQUEO_STATUS.sql`. 

**DAT para MIS.** En cada proceso sale `DAT486_<fecha>.csv` (CUENTA = 486-folio, CUENTA3 = crédito), con encabezado.

## Actualización (`ops.sp_actualizacion_486`)

| Archivo | Qué es |
| --- | --- |
| `SCBPAG.TXT` | Arribo de pagos, 104 posiciones (pagos.prg) |
| `cyber\ACT_SALDOS.sql`, `ACT_VENCIDO.sql`, `ACT_PAGMIN.sql` | Saldos y etiqueta (SEG), vencido y pago mínimo |
| `cyber\ACT_PVS_REE.sql` | Días de mora (PVS → U1ARCOD1) y REE (→ U1ARCOD3) de todas las cuentas del DAT |

La actualización no genera ni arriba SCBSDOS: lo que sólo subía por el SCBSDOS (PVS y REE) va en `ACT_PVS_REE.sql`.

Los cuatro scripts los ejecuta el job en CYBER al terminar la actualización (`ops.sp_act_cyber`, `ACT_CYBER_AUTOMATICO`); a mano: `EXEC ops.sp_act_cyber <corrida>;` o los `.sql` en Oracle. El operador sube `SCBPAG.TXT`. El cuadre de pagos sí es automático: en cada vuelta compara contra `RCVRY.pmtfil` y, si a las 17:00 falta alguno, lo manda en el correo de hallazgos. `ops.sp_act_cyber` solo repite lo pendiente.

Si hubo retiro: `EXEC ops.sp_exportar_salidas <corrida>, @zip = 'RETIROS', @enviar_zip = 1` (correo único de devolución).

Los pagos negativos no salen en `SCBPAG.TXT`: quedan en `ops.RECHAZO` (origen `PAGOS_NEGATIVOS`) y se avisa al equipo de asignaciones con la plantilla `PAGOS_NEGATIVOS_486`.

## Retiro (`ops.sp_retiro`, también desde `ops.sp_retiro_solicitud`)

**Automático** (`sql/77_sp_retiro_automatico.sql`, parámetro `RETIRO_AUTOMATICO = 1`):
- La asignación y la actualización aplican solas sus devoluciones, salvo que en algún segmento superen el 50 % de las cuentas que ese segmento tiene en el DAT (`RETIRO_TOPE_PCT_ASIG` y `RETIRO_TOPE_PCT_ACT`). En ese caso no se aplica nada, quedan en `ops.DEVOLUCION` y llega el correo de hallazgos al equipo de asignaciones con la tabla por segmento.
- Después de aplicar, `ops.sp_retiro_cerrar` escribe los archivos de la corrida, arma el ZIP y manda el correo único de devolución. También ejecuta el retiro en CYBER (`cyber\RETIRO.sql`, `RETIRO_CYBER_AUTOMATICO`). La copia de `MX_G1MCT_DVBJIG_*` a `\\192.168.50.1\Cyber_00\dev\` se hace a mano porque el servidor no tiene acceso (`RUTA_DEVOLUCION_CYBER` vacío).
- El retiro por solicitud hace lo mismo al confirmarlo (`@confirmar = 1`).
- El operador sube `SCBACTH_486.TXT` (gescar de retiro).
- Si un paso falla, queda `ERROR` en la bitácora (`RETIRO ARCHIVOS`, `RETIRO CYBER`, `RETIRO DEVOL CYBER`), llega el correo de hallazgos y se repite con `EXEC ops.sp_retiro_cerrar <ID>;` (solo repite lo que no quedó OK; `@solo_mostrar = 1` muestra qué falta).
- Si el retiro quedó detenido por el tope y es correcto: `EXEC ops.sp_retiro <ID>; EXEC ops.sp_retiro_cerrar <ID>;`.


| Archivo | Qué es |
| --- | --- |
| `MX_G1MCT_DVBJIG_<AAAAMMDD>_<HHMMSS>` | Devolución para CYBER, una CUENTA2 por línea |
| `SCBACTH_486.TXT` | Gescar de retiro, 119 posiciones (ges_retiro.prg) |
| `RETIROS_486_<AAAAMMDD>.csv` | Folios retirados para operación |
| `cyber\RETIRO.sql` | `dmstatus = 'R'` en `RCVRY.delqmst` |
