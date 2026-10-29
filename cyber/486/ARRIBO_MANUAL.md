# 486 · Arribo manual a CYBER

Los procesos de SQL Server no escriben en CYBER. Cada corrida deja los archivos planos en `ops.SALIDA_LINEA` y los scripts de Oracle en `ops.CYBER_SCRIPT`. Para arribar:

```
python tools/exportar_salidas.py --conexion "<ODBC>" --corrida <ID> --carpeta "D:\Banbaj\486\salida"
```

Eso crea `D:\Banbaj\486\salida\<AAAAMMDD>_corrida<ID>\` con los archivos y la carpeta `cyber\` con los `.sql`.

## Asignación (`ops.sp_asignacion_486`)

| Archivo | Qué es | Programa que reemplaza |
| --- | --- | --- |
| `SCBSDOS.TXT` | Cuentas del DAT, 1559 posiciones | asi486.prg |
| `SCBTEL.TXT` | Teléfonos, 137 posiciones | telbnx.prg (TELSAN) |
| `sub_mst.TXT` | Teléfonos `CUENTA\|AREA\|TELEFONO\|TIPOTEL` | telbnx.prg → act_phone.prg |
| `SCBACTH_486NU.TXT` | Gescar de cuentas nuevas, 119 posiciones | ges_nuevas_rea.prg |
| `SCBACTH_486REA.TXT` | Gescar de reasignadas, 119 posiciones | ges_nuevas_rea.prg |

**Teléfonos (solo en la asignación).** Se mandan todos los del DAT; CYBER purga y agrega.
1. `cyber\TEL_BORRA.sql` (vacía la remesa).
2. Cargar `sub_mst.TXT` en `RCVRY.JSP_TAB_TEL_REMESA_486` con `LOAD_TEL_REMESA.CTL` (sqlldr, igual que hoy) y revisar que la tabla tenga la información.
3. Ejecutar `cyber\TEL_ACTUALIZA.sql` (`EXECUTE RCVRY.JSP_TELEFONOS_REMESA_486`).

La bitácora `RCVRY.JSP_VALIDADOR_TELEFONOS` ya no se alimenta: la bitácora es `ops.BITACORA` (paso `TELEFONOS`, con capturados, inválidos, repetidos, quejas y enviados).

**Correos (solo en la asignación).** Como hoy (email.PRG + act_mail.prg):
1. `python tools/bajar_cyber.py correos --corrida <ID> …` baja los correos que ya tiene CYBER (sin archivos) y arma `cyber\MAIL_INSERTA_NUEVOS.sql`; volver a exportar la corrida.
2. Correr `cyber\MAIL_INSERTA_NUEVOS.sql` (INSERT en `RCVRY.ADDRESS` de los nuevos).
3. Depuración: `cyber\MAIL_ACTIVA_BANDERA.sql` → `cyber\MAIL_BORRA.sql` → cargar `sub_mail.TXT` con `LOAD_MAIL_REMESA.CTL` → revisar la tabla → `cyber\MAIL_ACTUALIZA.sql` (`JSP_CORREOS_486` purga lo que ya no llega) → `cyber\MAIL_INACTIVA_BANDERA.sql`.

**Gescar de cuentas sin teléfono.** Después de arribar los teléfonos: `python tools/bajar_cyber.py telefonos --corrida <ID> …`, volver a exportar y arribar `SCBACTH_SINTEL.TXT`.

**Después de arribar:** `EXEC ops.sp_avisar <corrida>, 'CONFIRMACION_ASIG_486'` (y `ASIG_EXPRESS_486` si aplica).

**Blanqueo de status (día 1 al 10).** `python tools/bajar_cyber.py status --corrida <ID> …` (sin archivos), volver a exportar, revisar `BLANQUEA_486_<fecha>.csv` y correr `cyber\BLANQUEO_STATUS.sql`.

**DAT para MIS.** En cada proceso sale `DAT486_<fecha>.csv` (CUENTA = 486-folio, CUENTA3 = crédito), con encabezado.

## Actualización (`ops.sp_actualizacion_486`)

| Archivo | Qué es |
| --- | --- |
| `SCBSDOS.TXT` | Cuentas del DAT actualizadas |
| `SCBPAG.TXT` | Arribo de pagos, 104 posiciones (pagos.prg) |
| `cyber\ACT_SALDOS.sql`, `ACT_VENCIDO.sql`, `ACT_PAGMIN.sql` | Saldos, vencido y pago mínimo |

Después de arribar: `EXEC ops.sp_avisar <corrida>, 'CONFIRMACION_ACT_486'` y, si hubo retiro, `'NOTIFICACION_RETIRO_486'`.

Los pagos negativos no salen en `SCBPAG.TXT`: quedan en `ops.RECHAZO` (origen `PAGOS_NEGATIVOS`) y se avisa a Operación con la plantilla `PAGOS_NEGATIVOS_486`.

## Retiro (`ops.sp_retiro`, también desde `ops.sp_retiro_solicitud`)

| Archivo | Qué es |
| --- | --- |
| `MX_G1MCT_DVBJIG_<AAAAMMDD>_<HHMMSS>` | Devolución para CYBER, una CUENTA2 por línea (antes se copiaba a `\\192.168.50.1\Cyber_00\dev`) |
| `SCBACTH_486.TXT` | Gescar de retiro, 119 posiciones (ges_retiro.prg) |
| `RETIROS_486_<AAAAMMDD>.csv` | Folios retirados para operación |
| `cyber\RETIRO.sql` | `dmstatus = 'R'` en `RCVRY.delqmst` |
