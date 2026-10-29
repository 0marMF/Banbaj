# 486 · A qué programa pertenece cada .sql y .ctl

En el repo hay varios scripts con el mismo nombre porque cada programa los busca en **su propia carpeta** (`borra.sql`, `borlio.sql`, `cydel.sql`, `LOAD_ORACLE.CTL`). Al subirlos juntos quedaron como `(2)` y `(3)`. El cruce se hizo por lo que hace cada script (tabla que toca, ruta que lee o escribe) contra la ruta con la que lo llama cada `.prg`.

## Scripts con el mismo nombre

| Archivo en el repo | Carpeta original | Programa | Qué hace |
| --- | --- | --- | --- |
| `borra.sql` | `O:\PRG\GPO1\486\` | `ges486.prg` | `delete from rcvry.BANA` (antes de cargar las cuentas del día) |
| `borra (2).sql` | `O:\PRG\MEXGPO1\ASI486\ACT_MAIL\` | `act_mail.prg` | `TRUNCATE TABLE RCVRY.JSP_TAB_MAIL_REMESA_486` |
| — (no está) | `O:\PRG\MEXGPO1\ASI486\ACT_PHONE\` | `act_phone.prg` | Vacía `RCVRY.JSP_TAB_TEL_REMESA_486` para volver a insertar (confirmado): `cyber/TEL_BORRA.sql` |
| `LOAD_ORACLE.CTL` | `O:\PRG\GPO1\486\` | `ges486.prg` | `sub_mst.TXT` (CUENTA2@@1@) → `rcvry.bana` |
| `LOAD_ORACLE (2).CTL` | `O:\PRG\MEXGPO1\ASI486\ACT_PHONE\` | `act_phone.prg` | `sub_mst.TXT` (CUENTA\|AREA\|TELEFONO\|TIPOTEL) → `RCVRY.JSP_TAB_TEL_REMESA_486` |
| `LOAD_ORACLE (3).CTL` | `O:\PRG\GPO1\486\PAGOS\` | `pagos.prg` | `PAGOS\sub_mst.TXT` → `rcvry.Amex` (créditos sin folio) |
| `borlio.sql` | `O:\PRG\GPO1\486\MAIL\` | `email.PRG` | `Delete From RCVRY.Lio` |
| `borlio (2).sql` | `O:\PRG\GPO1\486\PAGOS\` | `pagos.prg` | `Delete From RCVRY.amex` |
| `cydel.sql` | `O:\PRG\GPO1\486\MAIL\` | `email.PRG` | Baja `MAIL\bade.txt`: dmacct y dmssnum de las cuentas en `RCVRY.Lio` |
| `cydel (2).sql` | `O:\PRG\GPO1\486\PAGOS\` | `pagos.prg` | Baja `PAGOS\bade.txt`: dmacct, dmssnum y folio de los créditos en `Amex` |
| `TELs_486.sql` | `O:\PRG\GPO1\486\` | `ges486.prg` | Baja `GESCAR\tel486.txt`: teléfonos activos en CYBER de las cuentas en `bana` |
| `TEL_486.sql` = `TEL_4862.sql` | `O:\PRG\GPO1\486\` | `tel486.prg` (comentado en paso.prg) | Igual que el anterior a otra ruta. **No se usa** |
| `BAJ.sql` | `O:\PRG\GPO1\486\PAGOS\` | `saldos.prg` | Pagos del día en `RCVRY.pmtfil` (cuadre de pagos arribados) |
| `baja.sql` | ? | ninguno | Teléfonos del grupo **4** (HOSK/HOHI) a `j:\BAJ_TEL_HIG.TXT`. **No es del 486** |

## Resto de scripts

| Archivo | Programa | Qué hace | En SQL Server |
| --- | --- | --- | --- |
| `ACTUALIZA_PHONE.SQL` | act_phone.prg | `EXECUTE RCVRY.JSP_TELEFONOS_REMESA_486` | `cyber/TEL_ACTUALIZA.sql` por corrida |
| `INSERTA_PHONE.SQL` | ninguno | `RCVRY.RPT_INSERTA_PHONE('1','486')` | **No se usa** (ningún .prg lo llama) |
| `BITAC.SQL` | act_phone.prg (lo genera) | Bitácora `RCVRY.JSP_VALIDADOR_TELEFONOS` | Descartado (bitácora propia) |
| `ACTIVA_BANDERA.SQL` / `INACTIVA_BANDERA.SQL` | act_mail.prg | Bandera en `RCVRY.RPT_LOG_CYBER_REG` (id_proc 416) y log en `rpt_log_cyber` | Se mantienen: `cyber/MAIL_ACTIVA_BANDERA.sql` y `MAIL_INACTIVA_BANDERA.sql` |
| `LOAD_ORACLE_MAIL.CTL` | act_mail.prg | `sub_mail.TXT` → `RCVRY.JSP_TAB_MAIL_REMESA_486` | `cyber/486/LOAD_MAIL_REMESA.CTL` |
| `INSERTA_MAIL.sql` | act_mail.prg | `EXECUTE RCVRY.JSP_CORREOS_486` | `cyber/MAIL_ACTUALIZA.sql` por corrida |
| `cyadd.sql` | email.PRG | Baja `MAIL\baad.txt`: correos que ya tiene CYBER (`RCVRY.Address` tipo 3) | `tools/bajar_cyber.py correos` → `stg.CYBER_CORREO` |
| `email.sql` | email.PRG (lo genera) | `INSERT INTO RCVRY.ADDRESS` de los correos nuevos | `ops.sp_correos_nuevos` → `cyber/MAIL_INSERTA_NUEVOS.sql` (mismo formato) |
| `STATUS.SQL` | status.prg | Baja status de CYBER a `C:\STATUSBAJ.txt` | `tools/bajar_cyber.py status` → `stg.CYBER_STATUS` → `ops.sp_blanqueo_status` |
| `PROMESA.SQL` | status.prg (comentado) | Promesas de pago vigentes | **No se usa** |
| `LOAD_ORACLE_AMEX.CTL`, `BORRA_AMX.SQL` | ninguno del 486 | Tabla `rcvry.AMEX` de otro cliente | **No se usan** |
| `TELADICIONAL.SQL` | ninguno | "TELEFONOS DE AMEX" a `tel.txt` | **No se usa** |
| `SQLQuery1.sql` | — | Ejemplo de query dinámica (cliente 526) | Referencia |

## Programas nuevos revisados

| Programa | Qué hace | En SQL Server |
| --- | --- | --- |
| `op9.prg` + `limpia.PRG` | Normaliza TEL1..16 de las cuentas que entran al DAT (AREA + TELEFONO; inválidos se borran) | `ops.sp_asig_normalizar_telefonos` |
| `estructura.prg` | REE = 'REEST' o vacío según segmento, tramo, tipo, COVID y garantizada (actualización) | Reglas de `cfg.HOMOLOGACION` sobre `dat.DAT_486` (proceso ACT) |
| `email.PRG` + `act_mail.prg` | Correos del DAT a CYBER | `ops.sp_correos` → `sub_mail.TXT` + scripts |
| `ges486.prg` | Gescar "CUENTA SIN NUMERO TELEFONICO" para nuevas sin teléfono en CYBER | `tools/bajar_cyber.py telefonos` → `ops.sp_gescar_sin_telefono` |
| `status.prg` | Blanqueo de status del día 1 al 10 | `ops.sp_blanqueo_status` |
| `eti486.prg` | Etiquetado del DAT desde archivo de Operación | `ops.sp_etiquetado_dat` |
| `moraeti.prg` | Mora (eti486) por folio o crédito; '-' = vacío | `cfg.sp_etiqueta_cargar … 'FOLIO_O_CUENTA'` + `ops.sp_regenerar_scbsdos` |
| `blacklist_486.prg` | Lista negra de teléfonos con requerimiento | `cfg.sp_exclusion_cargar` |
| `respaldo2.prg` | Copia del DAT antes de cada proceso | `ops.sp_respaldo` (por corrida) |
| `resdat.PRG` | Copia el DAT a `Q:\MIS` y `B:\asignaciones\dats` con CUENTA = 486-folio | `DAT486_<fecha>.csv` (vista `ops.v_DAT_486_MIS`) |
| `mail.prg`, `correo_486.prg`, `correo.prg`, `correo_486noti.prg` | Avisos a Operación (manuales, al final) | `ops.sp_avisar` con las plantillas y listas de cada uno |
| `mail_sdo_act_cons.prg`, `aem_alerta.prg` | Alertas automáticas | Plantillas `ALERTA_SDO_ACT_CONS_486` y `ALERTA_NUEVAS_486` con sus destinatarios |
| `prog15.prg` (cambio) | El retiro por solicitud ahora acepta riesgo o folio (`retiro_val`) | `ops.sp_retiro_solicitud` (ya lo hacía) |
