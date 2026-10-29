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
1. Cargar `sub_mst.TXT` en `RCVRY.JSP_TAB_TEL_REMESA_486` con `LOAD_TEL_REMESA.CTL` (sqlldr, igual que hoy).
2. Revisar que la tabla tenga la información.
3. Ejecutar `cyber\TEL_ACTUALIZA.sql` (`EXECUTE RCVRY.JSP_TELEFONOS_REMESA_486`).

La bitácora `RCVRY.JSP_VALIDADOR_TELEFONOS` ya no se alimenta: la bitácora es `ops.BITACORA` (paso `TELEFONOS`, con capturados, inválidos, repetidos, quejas y enviados).

## Actualización (`ops.sp_actualizacion_486`)

| Archivo | Qué es |
| --- | --- |
| `SCBSDOS.TXT` | Cuentas del DAT actualizadas |
| `SCBPAG.TXT` | Arribo de pagos, 104 posiciones (pagos.prg) |
| `cyber\ACT_SALDOS.sql`, `ACT_VENCIDO.sql`, `ACT_PAGMIN.sql` | Saldos, vencido y pago mínimo |

Los pagos negativos no salen en `SCBPAG.TXT`: quedan en `ops.RECHAZO` (origen `PAGOS_NEGATIVOS`) y se avisa a Operación con la plantilla `PAGOS_NEGATIVOS_486`.

## Retiro (`ops.sp_retiro`, también desde `ops.sp_retiro_solicitud`)

| Archivo | Qué es |
| --- | --- |
| `MX_G1MCT_DVBJIG_<AAAAMMDD>_<HHMMSS>` | Devolución para CYBER, una CUENTA2 por línea (antes se copiaba a `\\192.168.50.1\Cyber_00\dev`) |
| `SCBACTH_486.TXT` | Gescar de retiro, 119 posiciones (ges_retiro.prg) |
| `RETIROS_486_<AAAAMMDD>.csv` | Folios retirados para operación |
| `cyber\RETIRO.sql` | `dmstatus = 'R'` en `RCVRY.delqmst` |
