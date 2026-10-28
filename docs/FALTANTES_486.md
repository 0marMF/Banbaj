# 486 · Lo que falta para completar la lógica

Inventario sacado de todos los `.prg` del 486 (`paso`, `asig_bases`, `asi486`, `telbnx`, `saldos`, `prog15`, `status`, `email`, `ges486`, `mail_pagos`): cada programa que se llama con `DO`, cada tabla que se abre y cada `.sql` que se ejecuta, contra lo que hay en el repo.

Formato preferido para compartir:
- **Programas:** el `.prg` tal cual.
- **Tablas:** basta la estructura (lista de campos) y 3 a 5 registros con datos ficticios o tapados. No hace falta el contenido real; la carga real la hace `tools/migrar_dbf.py`.

## 1. Programas que faltan

### Prioridad alta (cambian lo que se arriba a CYBER)

- [ ] **`ACT_PHONE.prg`** (`O:\PRG\MEXGPO1\ASI486\ACT_PHONE\`) — sube los teléfonos a CYBER desde `sub_mst.TXT`. Sin él no se puede cerrar la salida de teléfonos.
- [ ] **`PAGOS.prg`** (`O:\PRG\GPO1\486\PAGOS\`) — arma el TXT de arribo de pagos. Falta el layout de salida (orden, anchos, separador).
- [ ] **`OP9.prg`** (`O:\PRG\GPO1\486\`) — en `paso.prg` aparece como "PEGADOS (PROGRAMA B)" justo antes de agregar las cuentas al DAT. No se sabe qué modifica.
- [ ] **`estructura.prg`** (`O:\PRG\GPO1\486\`) — se corre en la actualización antes de regenerar SCBSDOS.
- [ ] **`baj.sql`** (`O:\PRG\GPO1\486\PAGOS\`) — baja de CYBER los pagos arribados para cuadrarlos (`BAJPAG.TXT`).
- [ ] **`STATUS.SQL`** (`O:\PRG\GPO1\486\CYBER\`) — baja los status de CYBER para el blanqueo (`C:\STATUSBAJ.txt`).

### Prioridad media (gestiones y retiro)

- [ ] **`ges_nuevas_rea.prg`** (`O:\PRG\GPO1\486\GESCAR\`) — gescar de cuentas nuevas y reasignadas (REQ 2021-062065).
- [ ] **`ges_retiro.prg`** (`O:\PRG\GPO1\486\GESCAR\`) — gescar de retiro.
- [ ] **`devfianey.prg`** (`O:\ASIGNA\`) — se llama en el retiro con `DEVOL`; es compartido con otros clientes.
- [ ] **`RESPALDO2.prg`** y **`resdat.prg`** (`O:\PRG\GPO1\486\`) — respaldos. El SQL ya respalda por corrida; solo hace falta confirmar que no hagan algo más.
- [ ] **`ACT_MAIL.prg`** (`O:\PRG\MEXGPO1\ASI486\ACT_MAIL\`) — "depuración de correos" después de subirlos a CYBER.

### Correos (solo hacen falta destinatarios y texto; la lógica ya está en `mail.*`)

- [ ] **`MAIL.prg`** — confirmación de asignación a operación.
- [ ] **`correo_486.prg`** — "correo express".
- [ ] **`correo.prg`** — correo al terminar la actualización.
- [ ] **`correo_486noti.prg`** — notificación de retiros a operación.
- [ ] **`mail_sdo_act_cons.prg`** — aviso de cuentas de Consumo con saldo <= 0.
- [ ] **`aem_alerta.prg`** — alerta por más de 100 cuentas nuevas.

### Macro

- [ ] **`ASIG_486.xlsm`** (`O:\PRG\GPO1\486\bases\`) — genera los CSV del día. Ya sé lo que hace (limpia caracteres, pasa moneda a número con 2 decimales, arma la cuenta TDC). Sirve para confirmar el nombre y el orden de los CSV que deja.

## 2. Tablas de referencia que pasan a SQL Server

Se cargan con `tools/migrar_dbf.py`. Para cada una necesito la **estructura** para confirmar que los campos se llamen como supuse.

| Tabla DBF | Ruta en los .prg | Destino | Campos que supuse | Confirmar |
| --- | --- | --- | --- | --- |
| PURGA | `O:\HISTORIA\GPO1\486\` | `dat.HISTORIA_FOLIO` (bajas) | CUENTA, FOLIO, CUENTA2, SEGMENTO2, SUB_CTE, FE_ASIG y una fecha de baja | [ ] |
| TAB7 | `O:\DAT\GPO1\486\` | `dat.FOLIO_CONSECUTIVO` | FOLIO, CLIENTE, FE_CAPT, TIME | [ ] |
| DEVOL / 486BAJ / DEVOLR | `O:\HISTORIA\GPO1\486\`, `O:\DAT\GPO1\486\` | `dat.HISTORIA_FOLIO` | Igual que el DAT + fecha de captura | [ ] |
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

No son del 486, pero los procesos escriben o leen en ellos. Hay que decidir si el SQL los sigue alimentando.

- [ ] **`cyberdti.flags_cyber2`, `flags_cyber_his`, `flags_cyber_COM`** (SQL Server 192.168.50.53) — banderas de proceso. ¿Alguien las monitorea?
- [ ] **`asignaciones..tiempos`** (bcp) y **`RCVRY.asig`** (Oracle) — bitácora de tiempos de asignación. ¿Quién las consulta? Ahora la bitácora vive en `ops.CORRIDA` y `ops.BITACORA`.
- [ ] **`O:\asigna\asignaciones`** y **`O:\ASIGNA\NUEVAS`** — control de horarios y cuentas nuevas por cliente.
- [ ] **`Q:\MIS\SERTEC98\CLIENTES\486\DAT`** — `prog15.prg` copia ahí el DAT después de cada retiro. ¿Quién lo usa? Si sigue haciendo falta, se reemplaza por una vista o una exportación.
- [ ] **`\\192.168.50.1\Cyber_00\dev\MX_G1MCT_DVBJIG_<fecha>_<hora>`** — archivo de devolución para CYBER (CUENTA2). Ya se genera en `ops.SALIDA_LINEA` (`DEVOL_CYBER`); falta confirmar si es lo único que CYBER necesita para el retiro.
- [ ] **`cyber.reg_serv`** (SQL Server) — de ahí salen usuario y servidor de sqlplus. En el SQL nuevo no se guarda ninguna contraseña: la conexión a CYBER va por linked server o por el paso del job.

## 4. Formatos de archivos (ejemplo con datos ficticios)

- [ ] TXT de arribo de pagos (salida de `PAGOS.prg`).
- [ ] `sub_mst.TXT` que lee `ACT_PHONE` (hoy: CUENTA|AREA|TELEFONO|TIPOTEL).
- [ ] `C:\STATUSBAJ.txt` (salida de `STATUS.SQL`).
- [ ] `BAJPAG.TXT` (salida de `baj.sql`).
- [ ] `SERTEC_Saldos_Hip` (archivo de saldos de Hipotecario; no hay ejemplo).
- [ ] Base maestra de Hipotecario (no hay ejemplo; columnas tomadas de la hoja RAW).

## 5. No hacen falta

Son tablas de trabajo o archivos que el SQL ya genera por su cuenta: `layout1`, `layout_tdc`, `layout_consumo`, `layout_hipo`, `saldos_486`, `tdc486_2*`, `consumo486_2*`, `hipotecario`, `GPO1`, `DATC`, `TEL`, `TELA`, `TELB`, `TELC`, `TELBNX`, `TELSAN`, `oTELSAN`, `nTELSAN`, `bitac`, `bitact`, `bitac_R`, `pagomi`, `pagos486`, `act_tdc`, `act_cons`, `act_hip`, `SALDOS`, `SALDOSINI`, `BSTAT`, `CYBSTATUS`, `mail486`, `ma346`, `TMAIL`, `email`, `DATO1`, `DATO2`, `lio`, `gestion3`, `CYBGES`, `telefonos486`, todos los `C:\…` y los `.sql` que se arman al vuelo (`act486`, `min486`, `pvs486`, `bitac486*`, `BLSTABAJIO`, `DEVCYB`, `LIO`, `email`).

## 6. Preguntas abiertas

- [ ] **TIPOTEL:** qué significa cada valor (hoy TEL1 → 1, TEL2 → 2, el resto → 4, celular → 5).
- [ ] **Teléfonos:** ¿se mandan cada día todos los del DAT (como hoy) o solo los nuevos?
- [ ] **`eti486`:** hoy cambia la mora de 307 cuentas contra lo que trae el banco. ¿Se sigue usando?
- [ ] **GARAN (DMCPHONE) y ETIQUETA/COVID (U1ARCOD2):** vienen de la base maestra, no de las bases eliminadas. ¿Se quedan?
- [ ] **Importes negativos en SCBSDOS:** ¿se mandan en cero o con signo? Hoy salen positivos (H-01).
- [ ] **Pagos negativos:** ¿se cancela toda la actualización (como hoy) o solo se excluyen esos pagos?
- [ ] **Columnas POR CONFIRMAR** de las bases maestras: ENFOQUE (TDC), REE, ETIQUETA.
- [ ] **Quién mantiene** `TELBAJ_G1`, `pnc` y las etiquetas `eti`, `dm1`, `STATUS`, y cada cuánto.

## Ya resuelto

- CYBER sigue aceptando solo el formato actual de teléfonos (044/045 para celular, 01 + lada para fijo): se conserva.
- Estatus de retiro en CYBER: `dmstatus = 'R'` (de `prog15.prg`).
- `covid` y `garantizada` se eliminan; las bases comentadas en `asi486.prg` se omiten.
- `top` la alimenta Asignaciones con folio + etiqueta de operación (`cfg.sp_etiqueta_cargar`).
- La base maestra se trabaja como llega (sin tope de devolución); hay retroceso por corrida.
