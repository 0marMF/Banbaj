# 486 · Lo que falta para completar la lógica

Inventario sacado de todos los `.prg` del 486 (`paso`, `asig_bases`, `asi486`, `telbnx`, `saldos`, `prog15`, `status`, `email`, `ges486`, `mail_pagos`): cada programa que se llama con `DO`, cada tabla que se abre y cada `.sql` que se ejecuta, contra lo que hay en el repo.

Formato preferido para compartir:
- **Programas:** el `.prg` tal cual.
- **Tablas:** basta la estructura (lista de campos) y 3 a 5 registros con datos ficticios o tapados. No hace falta el contenido real; la carga real la hace `tools/migrar_dbf.py`.

## 1. Programas que faltan

### Prioridad alta (cambian lo que se arriba a CYBER)

- [x] **`ACT_PHONE.prg`** — recibido. Carga `sub_mst.TXT` (CUENTA2|AREA|TELEFONO|TIPOTEL) en `RCVRY.JSP_TAB_TEL_REMESA_486` y ejecuta `RCVRY.JSP_TELEFONOS_REMESA_486`. **La lógica real está en ese procedimiento de Oracle** (ver sección 7).
- [x] **`PAGOS.prg`** — recibido. SCBPAG de 104 posiciones: IDE '500', GRUPO '1', CUENTA (crédito del banco, 25), FE_PAG MMDDAAAA, MONT (15, con punto), SEGMENTO 'pbank', AGEN 'SERTEC', FE_REG, TRAN 'PAGO', MOREAL. Quita lo que ya está en PAGTOT (CUENTA + FE_PAG + monto).
- [x] **`OP9.prg`** + `limpia.PRG` — recibidos. Normaliza los teléfonos de las cuentas que entran al DAT (`ops.sp_asig_normalizar_telefonos`).
- [x] **`estructura.prg`** — recibido. REE por segmento/tramo/tipo en la actualización (reglas sobre `dat.DAT_486`).
- [x] **`baj.sql`** — recibido (pagos del día en `RCVRY.pmtfil` de la compañía 486).
- [x] **`STATUS.SQL`** + `status.prg` — recibidos. Blanqueo de status: `ops.sp_blanqueo_status`.

### Prioridad media (gestiones y retiro)

- [x] **`ges_nuevas_rea.prg`** — recibido. SCBACTH de 119 posiciones, RS/R1, origen 'aaxrh', "CUENTA NUEVA ASIGNADA." / "CUENTA REASIGNADA.".
- [x] **`ges_retiro.prg`** — recibido. Mismo layout, "RETIRO DE CUENTA.", sale de `cybdev`.
- [ ] **`devfianey.prg`** (`O:\ASIGNA\`) — se llama en el retiro con `DEVOL`; es compartido con otros clientes.
- [x] **`RESPALDO2.prg`** y **`resdat.prg`** — recibidos. Respaldo por corrida; la copia a MIS queda como vista `ops.v_DAT_486_MIS`.
- [x] **`ACT_MAIL.prg`** + `email.PRG` — recibidos. Correos a CYBER: `ops.sp_correos` → `sub_mail.TXT`.

### Correos (solo hacen falta destinatarios y texto; la lógica ya está en `mail.*`)

- [x] **`MAIL.prg`** — `CONFIRMACION_ASIG_486`.
- [x] **`correo_486.prg`** — `ASIG_EXPRESS_486`.
- [x] **`correo.prg`** — `CONFIRMACION_ACT_486`.
- [x] **`correo_486noti.prg`** — `NOTIFICACION_RETIRO_486`.
- [x] **`mail_sdo_act_cons.prg`** — `ALERTA_SDO_ACT_CONS_486`.
- [x] **`aem_alerta.prg`** — `ALERTA_NUEVAS_486`.

### Macro

- [ ] **`ASIG_486.xlsm`** (`O:\PRG\GPO1\486\bases\`) — genera los CSV del día. Ya sé lo que hace (limpia caracteres, pasa moneda a número con 2 decimales, arma la cuenta TDC). Sirve para confirmar el nombre y el orden de los CSV que deja.

## 2. Tablas de referencia que pasan a SQL Server

Se cargan con `tools/migrar_dbf.py`. Para cada una necesito la **estructura** para confirmar que los campos se llamen como supuse.

| Tabla DBF | Ruta en los .prg | Destino | Campos que supuse | Confirmar |
| --- | --- | --- | --- | --- |
| PURGA | `O:\HISTORIA\GPO1\486\` | `dat.HISTORIA_FOLIO` (bajas) | Falta. `prog15` le agrega lo mismo que a DEVOL (486BAJ). ¿Es igual a DEVOL? | [ ] |
| historia | `O:\HISTORIA\GPO1\486\` | `dat.HISTORIA_FOLIO` | Recibida: 1.8 M filas (una por cada asignación desde 2016), folio máx. 179,688 | Lista |
| DEVOL | `O:\HISTORIA\GPO1\486\` | `dat.HISTORIA_FOLIO` (bajas) | Recibida: 580 mil retiros con FE_DEV | Lista |
| PAGTOT | `O:\PRG\GPO1\486\PAGOS\` | `dat.PAGO_ARRIBADO` (tabla fija) | Recibida: 543 mil pagos. Solo se guardan CUENTA + FE_PAG + importe (lo que usa la validación); 12,865 renglones viejos con FE_PAG incompleta no pueden coincidir y se omiten | Lista |
| TELSAN | `O:\PRG\MEXGPO1\ASI486\` | `ops.TELEFONO` (se arma en cada asignación) | Recibida: la regla nueva reproduce sus 15,353 teléfonos; no se migra | Lista |
| TAB7 | `O:\DAT\GPO1\486\` | `dat.FOLIO_CONSECUTIVO` | FOLIO, CLIENTE, FE_CAPT, TIME | [ ] |
| eti486 | `O:\PRG\MEXGPO1\ASI486\` | `cfg.ETIQUETA` (ETI486) | CUENTA2, MORA | [ ] |
| eti | `O:\PRG\MEXGPO1\ASI486\` | `cfg.ETIQUETA` (ETI) | CUENTA, ETIQUETA | [ ] |
| dm1 | `O:\PRG\MEXGPO1\ASI486\` | `cfg.ETIQUETA` (DM1) | CUENTA, ETIQUETA | [ ] |
| top | `O:\PRG\MEXGPO1\ASI486\` | `cfg.ETIQUETA` (TOP) | CUENTA2, ETIQUETA | [ ] |
| STATUS | `O:\PRG\MEXGPO1\ASI486\` | `cfg.ETIQUETA` (STATUS) | CUENTA, ESTATUS | [ ] |
| exc486 | `O:\PRG\GPO1\486\` | `cfg.EXCLUSION` (CUENTA) | CUENTA | [ ] |
| dirmal | `O:\ASIGNA\` | `cfg.EXCLUSION` (DIRECCION) | CUENTA, DIRECC1 | [ ] |
| EMAILMALO | `O:\ASIGNA\` | `cfg.EXCLUSION` (CORREO) | CUENTA, EMAIL | [ ] |
| blacklist_486 | `O:\PRG\MEXGPO1\ASI486\` | `cfg.EXCLUSION` (TELEFONO) | TEL | [ ] |
| TELBAJ_G1 | `\\192.168.50.108\T\CYBER_SISTEMAS\CYBER\TELEFONOS\` | `cfg.EXCLUSION` (TELEFONO por cuenta) | CUENTA, TEL | [ ] |
| LADA | `O:\PRG\MEXGPO1\ASI486\` | `cfg.LADA` | CP, LADA | [ ] |
| PNC | `\\192.168.50.108\T\CYBER_SISTEMAS\CYBER\PNM\` | `cfg.PLAN_NUMERACION` | Ya revisada (repo): LADA, SERIE, N_INI, N_FIN, TIPORED | Lista |
| DAT | `O:\DAT\GPO1\486\` | `dat.DAT_486` | Ya revisada (repo): 70 campos, 6,800 cuentas | Lista |

## 3. Tablas y archivos compartidos con otros procesos

Las bitácoras que se subían a Oracle y a server (`RCVRY.JSP_VALIDADOR_TELEFONOS`, `RCVRY.asig`, `asignaciones..tiempos`, `cyberdti.flags_cyber*`) **se descartan**: la bitácora es `ops.CORRIDA` + `ops.BITACORA`.

- [ ] **`O:\asigna\asignaciones`** y **`O:\ASIGNA\NUEVAS`** — control de horarios y cuentas nuevas por cliente. ¿Se descartan también?
- [ ] **`Q:\MIS\SERTEC98\CLIENTES\486\DAT`** — `prog15.prg` copia ahí el DAT después de cada retiro. ¿Quién lo usa? Si sigue haciendo falta, se reemplaza por una vista o una exportación.
- [x] **Devolución para CYBER** (`MX_G1MCT_DVBJIG_<fecha>_<hora>`) — se genera como archivo plano para arribo manual.
- [x] **`cyber.reg_serv`** — ya no hace falta: el arribo es manual con los archivos y scripts que deja `tools/exportar_salidas.py`.

## 4. Formatos de archivos (ejemplo con datos ficticios)

- [x] TXT de arribo de pagos (`SCBPAG.TXT`).
- [x] `sub_mst.TXT` de `ACT_PHONE`: CUENTA2|AREA|TELEFONO|TIPOTEL (confirmado con TELSAN).
- [x] `C:\STATUSBAJ.txt`: CLIENTE|FOLIO|CUENTA|STATUS|ACCION|FECHA|PESO|DMSSNUM.
- [x] `BAJPAG.TXT`: cuenta|monto|fecha.
- [ ] `SERTEC_Saldos_Hip` (archivo de saldos de Hipotecario; no hay ejemplo).
- [ ] Base maestra de Hipotecario (no hay ejemplo; columnas tomadas de la hoja RAW).

## 5. No hacen falta

Son tablas de trabajo o archivos que el SQL ya genera por su cuenta: `layout1`, `layout_tdc`, `layout_consumo`, `layout_hipo`, `saldos_486`, `tdc486_2*`, `consumo486_2*`, `hipotecario`, `GPO1`, `DATC`, `TEL`, `TELA`, `TELB`, `TELC`, `TELBNX`, `TELSAN`, `oTELSAN`, `nTELSAN`, `bitac`, `bitact`, `bitac_R`, `pagomi`, `pagos486`, `act_tdc`, `act_cons`, `act_hip`, `SALDOS`, `SALDOSINI`, `BSTAT`, `CYBSTATUS`, `mail486`, `ma346`, `TMAIL`, `email`, `DATO1`, `DATO2`, `lio`, `gestion3`, `CYBGES`, `telefonos486`, todos los `C:\…` y los `.sql` que se arman al vuelo (`act486`, `min486`, `pvs486`, `bitac486*`, `BLSTABAJIO`, `DEVCYB`, `LIO`, `email`).

## 6. Preguntas abiertas

- [ ] **`eti486`:** hoy cambia la mora de 307 cuentas contra lo que trae el banco. ¿Se sigue usando?
- [ ] **GARAN (DMCPHONE) y ETIQUETA/COVID (U1ARCOD2):** vienen de la base maestra, no de las bases eliminadas. ¿Se quedan?
- [ ] **Importes negativos en SCBSDOS:** ¿se mandan en cero o con signo? Hoy salen positivos (H-01).
- [ ] **Pagos de cuentas que ya no están en el DAT:** en `pagos.prg` solo se arriban los que cruzan contra DAT.RIESGO (la búsqueda en PURGA y en CYBER nunca encuentra nada porque `pagos486` no trae CUENTA). Así quedó. ¿Se deberían arribar los de cuentas retiradas?
- [ ] **Destinatarios de Operación** para el aviso de pagos negativos (lista `OPERACION_PAGOS_486`, hoy solo el buzón de asignaciones).
- [ ] **Copia del DAT para MIS** (`Q:\MIS\…\DAT` y `B:\asignaciones\dats\dat486`, resdat.PRG): ¿quién la usa y en qué formato la necesita? Hoy queda la vista `ops.v_DAT_486_MIS`.
- [ ] **correo_486noti.prg** trae `dministrativo.mc6@sertec.com.mx` (sin la a). Lo puse como `administrativo.mc6@`. ¿Correcto?
- [ ] **Columnas POR CONFIRMAR** de las bases maestras: ENFOQUE (TDC), REE, ETIQUETA.
- [ ] **Quién mantiene** `TELBAJ_G1`, `pnc` y las etiquetas `eti`, `dm1`, `STATUS`, y cada cuánto.

## 7. CYBER (Oracle)

El procedimiento `RCVRY.JSP_TELEFONOS_REMESA_486` no se puede compartir (política de CYBER): se trata como caja negra. SQL Server le entrega `sub_mst.TXT` completo en cada asignación y él purga y agrega.

- [ ] **`borra.sql` de ACT_PHONE:** sigue faltando. El `borra.sql` del repo es el de `ges486.prg` (BANA) y `borra (2).sql` el de `act_mail.prg`. ¿El de ACT_PHONE vacía `RCVRY.JSP_TAB_TEL_REMESA_486` como el de correos? (ver `docs/SCRIPTS_486.md`)
- [ ] **`INSERTA_PHONE.SQL`**, `PROMESA.SQL`, `TEL_486.sql`, `TELADICIONAL.SQL`, `baja.sql`, `LOAD_ORACLE_AMEX.CTL`, `BORRA_AMX.SQL`: ningún programa activo los llama. ¿Se pueden dejar fuera?
- [ ] **Banderas `ACTIVA_BANDERA` / `INACTIVA_BANDERA`** (`RCVRY.RPT_LOG_CYBER_REG`, id_proc 416): las quité como bitácora. ¿CYBER las usa como candado mientras se actualizan los correos?
- [ ] **Correos directos (`email.sql`):** hoy, además de la remesa, se insertan en `RCVRY.ADDRESS` los correos nuevos. Lo dejé solo con la remesa + `JSP_CORREOS_486` (como teléfonos). ¿Es suficiente?
- [ ] **EMAILMALO en la remesa:** hoy `sub_mail.TXT` sale sin quitar EMAILMALO. Lo dejé igual (`CORREOS_EXCLUIR_MALOS = 0`). ¿Se quitan?
- [ ] **Gescar de cuentas sin teléfono (ges486.prg):** cruza contra los teléfonos activos que ya tiene CYBER (`TELs_486.sql`). Sin acceso a CYBER solo puedo cruzar contra los que mandamos, y saldrían cuentas que en CYBER sí tienen teléfono. Lo dejé inactivo. ¿Se arma con un archivo que bajen de CYBER (como el blanqueo) o se quita?

## Ya resuelto

- Los archivos planos se siguen arribando a mano: `tools/exportar_salidas.py` los escribe con su nombre, Windows-1252 y CRLF (ver `cyber/486/ARRIBO_MANUAL.md`).
- Teléfonos: solo en la asignación, completos, para que CYBER purgue y agregue.
- Pagos negativos: no salen en SCBPAG, quedan en rechazos y se avisa a Operación (ya no cancelan la actualización).
- PAGTOT pasa a tabla fija con solo los campos de la validación.
- Retiro por solicitud con folio o riesgo: `ops.sp_retiro_solicitud` (vista previa, retroceso).
- TIPOTEL: 1 = TEL1, 2 = TEL2, 4 = otro fijo, 5 = celular (según telbnx.prg).
- Formato de teléfonos confirmado con TELSAN: celular AREA 044/045 + 10 dígitos (TIPOTEL 5); fijo AREA 01+lada + 7 u 8 dígitos (TIPOTEL 4); TIPOTEL 1 y 2 para TEL1/TEL2.
- CYBER sigue aceptando solo el formato actual de teléfonos (044/045 para celular, 01 + lada para fijo): se conserva.
- Estatus de retiro en CYBER: `dmstatus = 'R'` (de `prog15.prg`).
- `covid` y `garantizada` se eliminan; las bases comentadas en `asi486.prg` se omiten.
- `top` la alimenta Asignaciones con folio + etiqueta de operación (`cfg.sp_etiqueta_cargar`).
- La base maestra se trabaja como llega (sin tope de devolución); hay retroceso por corrida.
