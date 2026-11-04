# 486 · Arribo manual a CYBER

Cada corrida deja los archivos planos en `ops.SALIDA_LINEA` y los scripts de Oracle en `ops.CYBER_SCRIPT`. Para tenerlos en disco:

```sql
EXEC ops.sp_exportar_salidas <ID>;
```

Eso crea `RUTA_SALIDA\<AAAAMMDD>_corrida<ID>\` (de fábrica `C:\BANBAJ\486\SALIDA\`) con los archivos y la carpeta `cyber\` con los `.sql`.

## Qué hace Banbaj y qué se hace a mano (03/11)

**Por ahora Banbaj genera los archivos planos y los scripts, y hasta ahí.** En cuanto están escritos llega al equipo de asignaciones el correo **ARCHIVOS_LISTOS_486** con la carpeta, la lista de archivos y los comandos exactos de la corrida. Las depuraciones en CYBER se corren a mano.

| Qué | Quién | Cómo |
| --- | --- | --- |
| Generar y escribir los archivos y scripts | **Job** | Al terminar cada corrida |
| Aviso de archivos listos | **Job** | ARCHIVOS_LISTOS_486 a asignaciones |
| Subir SCBSDOS, SCBTEL, SCBPAG y gescar | Asignaciones | Cargador de CYBER |
| Depuración de correos (correos nuevos, bandera 416, remesa, `JSP_CORREOS_486`) | Asignaciones | `EXEC ops.sp_arribar_cyber <ID>, 'CORREOS';` |
| Depuración de teléfonos (remesa, validador, `JSP_TELEFONOS_REMESA_486`) y `SCBACTH_SINTEL.TXT` | Asignaciones | `EXEC ops.sp_arribar_cyber <ID>, 'TELEFONOS';` |
| Scripts de la actualización (`ACT_*`) | Asignaciones | `EXEC ops.sp_act_cyber <ID>;` |
| Retiro en CYBER | Asignaciones | `EXEC ops.sp_retiro_cerrar <ID>, @con_cyber = 1;` |
| Copiar `MX_G1MCT_DVBJIG_*` a `\\192.168.50.1\Cyber_00\dev\` | Asignaciones | A mano: el servidor no tiene acceso a esa carpeta |
| Blanqueo de status (días 1 a 10) | Asignaciones | `EXEC ops.sp_blanqueo_automatico <ID>, @forzar = 1;` |
| Confirmación de la asignación | Asignaciones | `EXEC ops.sp_avisar <ID>, 'CONFIRMACION_ASIG_486';` |
| Cuadre de pagos (solo lee y avisa) | **Job** | Hallazgo si a las 17:00 falta algún pago |

Los procedimientos ejecutan en CYBER, por el servidor vinculado `[CYBER]`, las mismas sentencias que quedan en la carpeta `cyber\` (`sql/76_sp_arribo_cyber.sql`), sin sqlldr. Si se prefiere, los `.sql` se pueden seguir corriendo en Oracle como se describe abajo. `@solo_mostrar = 1` enseña los bloques sin ejecutar. Si algo falla queda `ERROR` en la bitácora y se repite con el mismo comando.

**Cuando se automaticen** (`ARRIBO_AUTOMATICO = 1`): al terminar la asignación se toma una foto de lo que le falta a CYBER (`ops.sp_arribo_base`: cuentas del SCBSDOS no activas en `DELQMST`, domicilios distintos en `DMADDR1` y teléfonos del SCBTEL que no están en `PHONE_G1`) y, cada 30 minutos, el job da por subido cada archivo cuando ya llegó al menos el 95 % (`ARRIBO_MIN_PCT`) de lo pendiente y corre la depuración sola, una vez por corrida. Funciona aunque no haya cuentas nuevas. Con `ACT_CYBER_AUTOMATICO`, `BLANQUEO_AUTOMATICO`, `CONFIRMACION_AUTOMATICA` y `RETIRO_CYBER_AUTOMATICO` en 1 también corren solos los scripts de la actualización, el blanqueo, la confirmación y el retiro en CYBER.


**Permisos del usuario de Oracle** (el de la credencial `CYBER_ORACLE`): `TRUNCATE`/`INSERT` en `RCVRY.JSP_TAB_TEL_REMESA_486` y `RCVRY.JSP_TAB_MAIL_REMESA_486`, `INSERT` en `RCVRY.ADDRESS` y `RCVRY.JSP_VALIDADOR_TELEFONOS`, `UPDATE` en `RCVRY.RPT_LOG_CYBER_REG` y `EXECUTE` de `RCVRY.JSP_TELEFONOS_REMESA_486` y `RCVRY.JSP_CORREOS_486`. Sin ellos el arribo queda en `ERROR` con el mensaje de Oracle.

## Asignación (`ops.sp_asignacion_486`)

| Archivo | Qué es | Programa que reemplaza |
| --- | --- | --- |
| `SCBSDOS.TXT` | Cuentas del DAT, 1559 posiciones | asi486.prg |
| `SCBTEL.TXT` | Teléfonos, 137 posiciones | telbnx.prg (TELSAN) |
| `sub_mst.TXT` | Teléfonos `CUENTA\|AREA\|TELEFONO\|TIPOTEL` | telbnx.prg → act_phone.prg |
| `SCBACTH_486NU.TXT` | Gescar de cuentas nuevas, 119 posiciones | ges_nuevas_rea.prg |
| `SCBACTH_486REA.TXT` | Gescar de reasignadas, 119 posiciones | ges_nuevas_rea.prg |

Los pasos de teléfonos, correos y gescar sin teléfono que siguen son **lo que hace el job solo** (ver arriba). Quedan documentados para entenderlos y para el arribo manual si se apaga `ARRIBO_AUTOMATICO`.

**Teléfonos (solo en la asignación).** Se mandan todos los del DAT; CYBER purga y agrega. El orden importa:
1. Arribar `SCBTEL.TXT` **primero**. `RCVRY.JSP_TELEFONOS_REMESA_486` solo inserta en `PHONE` los teléfonos que ya están en `PHONE_G1` (lo que deja el arribo del SCBTEL) y que vienen en la remesa.
2. `cyber\TEL_BORRA.sql` (vacía la remesa).
3. Cargar `sub_mst.TXT` en `RCVRY.JSP_TAB_TEL_REMESA_486` con `LOAD_TEL_REMESA.CTL` (sqlldr, igual que hoy) y revisar que la tabla tenga la información.
4. Ejecutar `cyber\TEL_ACTUALIZA.sql` (`EXECUTE RCVRY.JSP_TELEFONOS_REMESA_486`).

Qué hace el procedimiento de CYBER (revisado 02/11, versión del 27/12/2025; la versión optimizada para instalar está en `cyber/486/oracle/JSP_TELEFONOS_REMESA_486.sql`):
- Inserta en `PHONE` los teléfonos de la remesa que están en `PHONE_G1` y no en `PHONE`, solo de cuentas activas del 486 (`dmstatus` nulo).
- **Inactiva** (`HIAS`) los teléfonos activos del 486 que no vienen en la remesa, salvo los marcados con gestor de queja (`HOMS`, `HPHPI`, `BLACK`, `ZZZTE`).
- **Activa** (`HAAS`) los teléfonos de la remesa que estaban inactivos, salvo esos mismos gestores de queja: aunque Banbaj mandara un teléfono con queja, CYBER no lo reactiva.
- Compara por cuenta, área y teléfono exactos, así que el área de sub_mst debe coincidir con la de SCBTEL (Banbaj saca los dos de la misma tabla).
- Al final completa el renglón del día de `RCVRY.JSP_VALIDADOR_TELEFONOS`. Ese renglón lo inserta `cyber\TEL_BORRA.sql` con el total de teléfonos que mandó Banbaj (parámetro `CYBER_VALIDADOR_TELEFONOS`), así que la diferencia contra lo que cargó sqlldr sigue sirviendo.

**Correos (solo en la asignación).** Como hoy (email.PRG + act_mail.prg):
1. `EXEC ops.sp_bajar_cyber 'CORREOS', @id_corrida = <ID>;` baja los correos que ya tiene CYBER y arma `cyber\MAIL_INSERTA_NUEVOS.sql`; volver a exportar la corrida. **No es opcional:** `JSP_CORREOS_486` solo activa e inactiva correos que ya existen en `ADDRESS`; los correos nuevos solo entran con este INSERT.
2. Correr `cyber\MAIL_INSERTA_NUEVOS.sql` (INSERT en `RCVRY.ADDRESS` de los nuevos).
3. Depuración: `cyber\MAIL_ACTIVA_BANDERA.sql` → `cyber\MAIL_BORRA.sql` → cargar `sub_mail.TXT` con `LOAD_MAIL_REMESA.CTL` → revisar la tabla → `cyber\MAIL_ACTUALIZA.sql` (`JSP_CORREOS_486` purga lo que ya no llega) → `cyber\MAIL_INACTIVA_BANDERA.sql`.

Qué hace `JSP_CORREOS_486` (revisado 02/11): inactiva (`HIAS`) lo que está en `ADDRESS` de cuentas activas del 486 y no viene en la remesa, y activa (`HAAS`) lo de la remesa que estaba inactivo, salvo gestores `HOMS` y `HPHPI`. **Ojo:** la versión actual (`cyber/486/oracle/JSP_CORREOS_486_actual.sql`) toma desde el 24/07/2026 `adtype` 3 **y 1**; como la remesa solo trae correos, inactiva todos los domicilios del 486 en cada corrida. La regla acordada (02/11) es que solo quede activo el domicilio que llegó en la última base maestra. **Antes de la primera corrida hay que instalar en CYBER `cyber/486/oracle/JSP_CORREOS_486.sql`**: trata los correos igual que hoy y deja activo solo el domicilio vigente de cada cuenta (el de `DELQMST.DMADDR1`, que sube con el SCBSDOS).

**Gescar de cuentas sin teléfono.** Después de arribar los teléfonos: `EXEC ops.sp_bajar_cyber 'TELEFONOS', @id_corrida = <ID>;`, volver a exportar y arribar `SCBACTH_SINTEL.TXT`. Con el arribo automático este archivo aparece solo en la carpeta de la corrida; solo falta subirlo.

**Después de arribar:** `EXEC ops.sp_avisar <corrida>, 'CONFIRMACION_ASIG_486'` (sale solo si se prende `CONFIRMACION_AUTOMATICA`; el correo Express se retiró el 30/10).

**Blanqueo de status (día 1 al 10).** Por ahora a mano: `EXEC ops.sp_blanqueo_automatico <ID>, @forzar = 1;` baja los status, ejecuta el blanqueo en CYBER y deja `BLANQUEA_486_<fecha>.csv` en la carpeta de la corrida. Como antes: `EXEC ops.sp_bajar_cyber 'STATUS', @id_corrida = <ID>;`, volver a exportar, revisar el CSV y correr `cyber\BLANQUEO_STATUS.sql`. Con `BLANQUEO_AUTOMATICO = 1` corre solo después del arribo de correos.

**DAT para MIS.** En cada proceso sale `DAT486_<fecha>.csv` (CUENTA = 486-folio, CUENTA3 = crédito), con encabezado.

## Actualización (`ops.sp_actualizacion_486`)

| Archivo | Qué es |
| --- | --- |
| `SCBPAG.TXT` | Arribo de pagos, 104 posiciones (pagos.prg) |
| `cyber\ACT_SALDOS.sql`, `ACT_VENCIDO.sql`, `ACT_PAGMIN.sql` | Saldos y etiqueta (SEG), vencido y pago mínimo |
| `cyber\ACT_PVS_REE.sql` | Días de mora (PVS → U1ARCOD1) y REE (→ U1ARCOD3) de todas las cuentas del DAT |

Ya no se genera ni se arriba SCBSDOS en la actualización (decisión 30/10): lo que sólo subía por el SCBSDOS (PVS y REE) va en `ACT_PVS_REE.sql`.

Por ahora los cuatro scripts se corren a mano: `EXEC ops.sp_act_cyber <corrida>;` (o los `.sql` en Oracle); con `ACT_CYBER_AUTOMATICO = 1` los ejecuta el job al terminar la actualización. El operador sube `SCBPAG.TXT`. El cuadre de pagos sí es automático: en cada vuelta compara contra `RCVRY.pmtfil` y, si a las 17:00 falta alguno, lo manda en el correo de hallazgos. `ops.sp_act_cyber` solo repite lo pendiente.

Si hubo retiro: `EXEC ops.sp_exportar_salidas <corrida>, @zip = 'RETIROS', @enviar_zip = 1` (correo único de devolución).

Los pagos negativos no salen en `SCBPAG.TXT`: quedan en `ops.RECHAZO` (origen `PAGOS_NEGATIVOS`) y se avisa al equipo de asignaciones con la plantilla `PAGOS_NEGATIVOS_486`.

## Retiro (`ops.sp_retiro`, también desde `ops.sp_retiro_solicitud`)

**Automático desde el 02/11** (`sql/77_sp_retiro_automatico.sql`, parámetro `RETIRO_AUTOMATICO = 1`):
- La asignación y la actualización aplican solas sus devoluciones, salvo que en algún segmento superen el 50 % de las cuentas que ese segmento tiene en el DAT (`RETIRO_TOPE_PCT_ASIG` y `RETIRO_TOPE_PCT_ACT`). En ese caso no se aplica nada, quedan en `ops.DEVOLUCION` y llega el correo de hallazgos al equipo de asignaciones con la tabla por segmento.
- Después de aplicar, `ops.sp_retiro_cerrar` escribe los archivos de la corrida, arma el ZIP y manda el correo único de devolución. Por ahora el retiro en CYBER (`cyber\RETIRO.sql`) y la copia de `MX_G1MCT_DVBJIG_*` a `RUTA_DEVOLUCION_CYBER` (`\\192.168.50.1\Cyber_00\dev\`) se hacen a mano con `EXEC ops.sp_retiro_cerrar <ID>, @con_cyber = 1;` (automáticos con `RETIRO_CYBER_AUTOMATICO = 1`).
- El retiro por solicitud hace lo mismo al confirmarlo (`@confirmar = 1`).
- El operador sube `SCBACTH_486.TXT` (gescar de retiro).
- Si un paso falla, queda `ERROR` en la bitácora (`RETIRO ARCHIVOS`, `RETIRO CYBER`, `RETIRO DEVOL CYBER`), llega el correo de hallazgos y se repite con `EXEC ops.sp_retiro_cerrar <ID>;` (solo repite lo que no quedó OK; `@solo_mostrar = 1` muestra qué falta).
- Si el retiro quedó detenido por el tope y es correcto: `EXEC ops.sp_retiro <ID>; EXEC ops.sp_retiro_cerrar <ID>;`.


| Archivo | Qué es |
| --- | --- |
| `MX_G1MCT_DVBJIG_<AAAAMMDD>_<HHMMSS>` | Devolución para CYBER, una CUENTA2 por línea (antes se copiaba a `\\192.168.50.1\Cyber_00\dev`) |
| `SCBACTH_486.TXT` | Gescar de retiro, 119 posiciones (ges_retiro.prg) |
| `RETIROS_486_<AAAAMMDD>.csv` | Folios retirados para operación |
| `cyber\RETIRO.sql` | `dmstatus = 'R'` en `RCVRY.delqmst` |
