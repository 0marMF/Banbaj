---
title: "Banbaj 486 · Cómo funciona"
subtitle: "Asignación, actualización y retiro del cliente 486 (Banco Bajío) en SQL Server"
date: "Noviembre 2026"
---

# Para qué sirve

Banbaj sustituye los programas de Visual FoxPro del cliente 486 (Banco Bajío). Recibe los archivos del banco, mantiene el DAT y el histórico de folios, y genera los archivos planos y los scripts que se arriban a CYBER. También manda los correos del proceso.

**Por ahora llega hasta los archivos planos.** Las depuraciones en CYBER (los stores de correos y teléfonos, los scripts de la actualización, el retiro y el blanqueo) se corren a mano; ver *Hasta dónde llega Banbaj*.

En producción todo corre dentro de SQL Server: la carga de archivos, las reglas, la escritura de archivos, el ZIP de retiros, los correos y las consultas a CYBER. No hay Python ni otro lenguaje en la operación.

Este documento explica cómo funciona por dentro. La instalación, la migración y la operación paso a paso están en el *Manual de migración, instalación y operación*.

# Visión general

## Lo que entra y lo que sale

| Entra | De dónde | Cuándo |
|---|---|---|
| Saldos de TDC, Consumo e Hipotecario | Banco, `Q:\CYBER\C_486\<año>\<mes>\<día>\` | Lunes a viernes |
| Pagos del día | Banco, misma carpeta | Lunes a viernes |
| Bases maestras completas de TDC, Consumo e Hipotecario (CSV) | Banco, misma carpeta | Algunos días, siempre después de la actualización |
| Solicitudes de retiro y etiquetas | Operación (CSV) | A mano |
| Quejas de teléfonos y plan de numeración | CYBER (SQL Server) | En cada asignación |
| Status, correos, teléfonos y pagos de CYBER | CYBER (Oracle) | A mano |

`Q:` es `\\192.168.50.13\q`.

| Sale | Para qué |
|---|---|
| Archivos planos (SCBSDOS, SCBTEL, SCBPAG, sub_mst, sub_mail, gescar, devolución) | Arribo manual a CYBER. Quedan en `C:\BANBAJ\486\SALIDA\<aaaammdd>_corrida<id>\` del servidor |
| Scripts de Oracle (saldos, vencido, pago mínimo, PVS y REE, retiro, teléfonos, blanqueo) | Se corren en CYBER. Quedan en la subcarpeta `cyber\` de la corrida |
| `DAT486_<fecha>.csv` | Copia del DAT para MIS |
| ZIP de retiros con contraseña | Correo de devolución a Operación |
| Correos | Operación, AEM y equipo de asignaciones |

## Piezas

| Pieza | Qué es |
|---|---|
| Base de datos `Banbaj` | Todas las tablas, catálogos y procedimientos |
| Job **Banbaj 486 diario** | Agente de SQL Server: cada 30 minutos, lunes a viernes de 07:00 a 22:00, llama `ops.sp_diario_486` |
| Servidor vinculado `[CYBER]` | Oracle de CYBER (proveedor OraOLEDB). Usuario y contraseña cifrados en la base |
| Servidor vinculado `[192.168.50.53]` | SQL Server de CYBER donde están `telbaj`, `telbaj1` y `TENOVA1` |
| `CYBER.dbo.CAT_PNM` | Plan de numeración en la misma instancia |
| Database Mail, perfil `asig.486.cdmx` | Envío de correos |
| Automatización OLE | Escritura de archivos en disco |
| `xp_cmdshell` + 7-Zip | ZIP con contraseña de los retiros |

## Esquemas de la base

| Esquema | Contenido |
|---|---|
| `cfg` | Catálogos y configuración: archivos de entrada, salidas, reglas, homologación, parámetros, exclusiones, etiquetas, plan de numeración, credenciales |
| `dat` | Datos del negocio: DAT, histórico de folios, consecutivo, pagos arribados, bases maestras recibidas |
| `stg` | Tablas de paso donde se cargan los archivos del día |
| `ops` | Procesos: corridas, bitácora, devoluciones, teléfonos, correos, salidas generadas, respaldos y los procedimientos |
| `mail` | Plantillas, listas, destinatarios y envíos de correo |

La idea central es que casi todo es configurable sin tocar código: qué archivos se esperan, qué columnas tienen, qué reglas se aplican, qué salidas se generan y con qué formato, y a quién se mandan los correos.

# Flujo diario

El job llama `ops.sp_diario_486` cada 30 minutos. El procedimiento decide qué hacer:

1. Si es sábado o domingo, no hace nada.
2. Si todavía no corre la **actualización** del día y ya están sus archivos, la corre.
3. Si la actualización no terminó bien, se detiene. La asignación nunca corre sin la actualización OK del mismo día.
4. Si todavía no corre la **asignación** y ya llegaron bases maestras, la corre.
5. Si ya corrieron las dos, contesta "DIA COMPLETO" y no repite nada.

Cada proceso es una **corrida** (`ops.CORRIDA`) con número, tipo (ACT, ASIG, RET, ETI), fecha, estatus y mensaje. Cada paso deja un renglón en `ops.BITACORA`.

## Hasta dónde llega Banbaj (decisión 03/11)

**Por ahora Banbaj genera los archivos planos y los scripts, y hasta ahí.** Todo lo que escribe en CYBER (las depuraciones con los stores de correos y teléfonos, los scripts de la actualización, el retiro y el blanqueo) se corre **a mano**. Ya está programado y probado, y cada parte se prende con un parámetro cuando se decida.

| Paso | Hoy | Cómo |
|---|---|---|
| Correr el proceso del día (actualización y asignación) | **Automático** | Job cada 30 minutos (`ops.sp_diario_486`) |
| Escribir los archivos planos y los scripts en la carpeta de la corrida | **Automático** | `ops.sp_exportar_auto` (`EXPORTAR_AUTOMATICO = 1`) |
| Avisar a asignaciones que ya están los archivos (ARCHIVOS\_LISTOS\_486) | **Automático** | `ops.sp_aviso_archivos` (`AVISO_ARCHIVOS = 1`) |
| Aplicar las devoluciones en el DAT, con tope de 50 % por segmento | **Automático** | `ops.sp_retiro_decidir` (`RETIRO_AUTOMATICO = 1`) |
| Archivos de retiro, ZIP y correo de devolución | **Automático** | `ops.sp_retiro_cerrar` |
| Cuadre de pagos contra CYBER (solo lee y avisa si falta algo a las 17:00) | **Automático** | `ops.sp_cuadre_automatico` (`CUADRE_AUTOMATICO = 1`) |
| Correo de hallazgos al equipo de asignaciones | **Automático** | `mail.sp_hallazgo` |
| Subir a CYBER los archivos de ancho fijo (SCBSDOS, SCBTEL, SCBPAG, gescar) | A mano | Cargador de CYBER |
| Depuración de correos (`JSP_CORREOS_486`, correos nuevos, bandera 416) | A mano | `EXEC ops.sp_arribar_cyber <id>, 'CORREOS';` (`ARRIBO_AUTOMATICO = 0`) |
| Depuración de teléfonos (`JSP_TELEFONOS_REMESA_486`, validador) y gescar sin teléfono | A mano | `EXEC ops.sp_arribar_cyber <id>, 'TELEFONOS';` |
| Scripts de la actualización (`ACT_SALDOS`, `ACT_VENCIDO`, `ACT_PAGMIN`, `ACT_PVS_REE`) | A mano | `EXEC ops.sp_act_cyber <id>;` (`ACT_CYBER_AUTOMATICO = 0`) |
| Retiro en CYBER (`dmstatus = 'R'`) y copia de la devolución a `\\192.168.50.1\Cyber_00\dev\` | A mano | `EXEC ops.sp_retiro_cerrar <id>, @con_cyber = 1;` (`RETIRO_CYBER_AUTOMATICO = 0`) |
| Blanqueo de status (días 1 a 10) | A mano | `EXEC ops.sp_blanqueo_automatico <id>, @forzar = 1;` (`BLANQUEO_AUTOMATICO = 0`) |
| Correo de cierre CONFIRMACION\_ASIG\_486 | A mano | `EXEC ops.sp_avisar <id>, 'CONFIRMACION_ASIG_486';` (`CONFIRMACION_AUTOMATICA = 0`) |

Los procedimientos de a mano ejecutan en CYBER, por el servidor vinculado, las mismas sentencias que quedan en los `.sql` de la carpeta `cyber\` de la corrida, así que también se pueden correr esos archivos en Oracle como antes. Lo que los procedimientos de CYBER hacen por dentro está en *Teléfonos* y *Correos* y en `cyber/486/ARRIBO_MANUAL.md`.

En un día normal: llega ARCHIVOS\_LISTOS\_486 → asignaciones sube los archivos de ancho fijo → corre las depuraciones (correos y teléfonos en la asignación, scripts `ACT_*` en la actualización) → sube el `SCBACTH_SINTEL.TXT` que deja la depuración de teléfonos → manda la confirmación.

## Cuando se prendan las depuraciones automáticas

Con `ARRIBO_AUTOMATICO = 1`, en cada vuelta del job `ops.sp_arribo_automatico` detecta que ya se subieron el SCBSDOS y el SCBTEL y corre las depuraciones solo:

| Detecta | Cómo | Hace |
|---|---|---|
| El SCBSDOS ya subió | Ya llegó al menos el 95 % (`ARRIBO_MIN_PCT`) de lo que le faltaba a `DELQMST` al terminar la asignación: cuentas no activas y domicilios distintos | **Correos:** baja los correos de CYBER, inserta los nuevos en `ADDRESS`, bandera 416, remesa `JSP_TAB_MAIL_REMESA_486`, `JSP_CORREOS_486` y apaga la bandera |
| El SCBTEL ya subió | Ya llegó al menos el 95 % de los teléfonos que le faltaban a `PHONE_G1`, y las cuentas pendientes ya están activas | **Teléfonos:** remesa `JSP_TAB_TEL_REMESA_486`, renglón del validador, `JSP_TELEFONOS_REMESA_486`, y escribe `SCBACTH_SINTEL.TXT` |

Lo pendiente sale de una foto que se toma al terminar la asignación, antes de que existan los TXT (`ops.sp_arribo_base`, tabla `ops.ARRIBO_PENDIENTE`); por eso funciona aunque no haya cuentas nuevas. Cada proceso corre una vez por corrida y, si falla, avisa con el correo de hallazgos. Si la remesa saliera vacía no se ejecuta el procedimiento de CYBER, para no inactivar todo el 486.

Con `ACT_CYBER_AUTOMATICO`, `BLANQUEO_AUTOMATICO`, `CONFIRMACION_AUTOMATICA` y `RETIRO_CYBER_AUTOMATICO` en 1, el job también ejecuta los scripts de la actualización al terminarla, el blanqueo después del arribo de correos, la confirmación al terminar correos y teléfonos, y el retiro en CYBER con la copia de la devolución. Para prender todo:

```sql
UPDATE cfg.PARAMETRO SET VALOR = '1' WHERE CLIENTE = '486'
   AND CLAVE IN ('ARRIBO_AUTOMATICO', 'ACT_CYBER_AUTOMATICO', 'BLANQUEO_AUTOMATICO', 'CONFIRMACION_AUTOMATICA', 'RETIRO_CYBER_AUTOMATICO');
```

Si una corrida falla, se revierte sola (ver *Respaldo y retroceso*) y el job no la vuelve a intentar ese día. Para reintentar se corre a mano.

# Actualización (ACT)

Sustituye a `saldos.prg`, `pagos.prg` y `estructura.prg`. Llegan de lunes a viernes los archivos de saldos y pagos.

| Paso | Procedimiento | Qué hace |
|---|---|---|
| 1 | `sp_respaldo` | Foto del DAT antes de tocarlo |
| 2 | `sp_cargar_proceso` | Busca los archivos del día en la carpeta y los carga a `stg` (saldos TDC, Consumo, Hipotecario y pagos) |
| 3 | `sp_homologar_entradas` | Limpia importes (`$`, comas), fechas y textos |
| 4 | `sp_validar 'POST_CARGA'` | Pagos negativos: no se arriban y se avisa al equipo de asignaciones. Pagos del día hábil anterior: solo bitácora |
| 5 | `sp_act_preparar` | Cruza saldos con el DAT (TDC por crédito, Consumo por número de CYBER) y arma los scripts de saldos, vencido y pago mínimo |
| 6 | `sp_validar 'RETIRO'` | Criterios de retiro: TDC cerrada o normalizada, Consumo sin tramo, saldo actual menor o igual a cero |
| 7 | `sp_act_aplicar` | Actualiza saldos en el DAT |
| 8 | `sp_act_pagos` | Arma el SCBPAG con los pagos nuevos (quita los que ya se arribaron) y los guarda en `dat.PAGO_ARRIBADO` |
| 9 | `sp_homologar` sobre el DAT | REE por segmento, tramo y tipo (`estructura.prg`) |
| 10 | `sp_act_script_pvs_ree` | Script `ACT_PVS_REE` que sube PVS y REE a `RCVRY.uda1` (sustituye al SCBSDOS de la actualización) |
| 11 | `sp_generar_salidas 'ACT'` | Genera SCBPAG y la copia del DAT para MIS |

**Saldos negativos:** suben a CYBER como cero (`NEGATIVO_MODO = CERO`). Una cuenta con saldo menor o igual a cero se va a retiro, así que antes de retirarse CYBER recibe 0 y no un negativo.

**Pagos:** se arriban todos. Si la cuenta no está en el DAT se busca en el histórico (cuentas retiradas) y, si no aparece, se arriba con el crédito tal como llegó.

# Asignación (ASIG)

Sustituye a `paso.prg`, `asig_bases.prg`, `asi486.prg`, `telbnx.prg`, `email.PRG` y los programas de gescar. Se trabaja siempre con la **base maestra completa** de cada segmento que llegó.

| Paso | Procedimiento | Qué hace |
|---|---|---|
| 1 | Correo `INICIO_ASIG_486` | Aviso de inicio a Operación |
| 2 | `sp_respaldo` | Foto del DAT |
| 3 | `sp_cargar_proceso` | Carga las bases maestras (CSV) y guarda una copia completa de cada una |
| 4 | `sp_validar 'POST_CARGA'` | Números cortados por Excel (notación científica): cancela. Consumo con saldo menor o igual a cero: avisa |
| 5 | `sp_asig_unir_layout` | Une las bases en un solo layout con la estructura del DAT. Las cuentas repetidas van a rechazos |
| 6 | `sp_homologar` | Reglas de homologación: cuenta TDC, NAME2 vacío → NAME1, direcciones malas, etc. |
| 7 | `sp_asig_devolucion` | Cuentas del DAT del segmento que **no** vienen en la base de hoy → `ops.DEVOLUCION`. Solo para los segmentos cuya base llegó |
| 8 | `sp_asig_existentes` | Cuentas que ya están en el DAT: se actualizan los campos configurados |
| 9 | `sp_telefonos_refrescar_cyber` | Trae de CYBER las quejas (telbaj del grupo 1) y el plan de numeración vigente |
| 10 | `sp_asig_normalizar_telefonos` | Teléfonos de cuentas nuevas y reasignadas guardados como área + número (`op9.prg`) |
| 11 | `sp_validar 'PRE_ALTA'` | Cuentas en la lista de exclusión (`exc486`) no entran |
| 12 | `sp_asig_alta` | Altas: **REA** si la cuenta tuvo folio antes (se reutiliza), **NVA** con folio consecutivo. Alta en DAT e histórico. Más de 100 nuevas: correo de alerta |
| 13 | `sp_telefonos` | Teléfonos para CYBER (ver *Teléfonos*) |
| 14 | `sp_correos` | Correos para CYBER (minúsculas, con @, sin "no tiene", sin correos malos, uno por cuenta). En CYBER, `JSP_CORREOS_486` solo activa e inactiva; los correos nuevos entran con `sp_bajar_cyber 'CORREOS'`. Domicilios: en CYBER solo queda activo el de la última base maestra (versión nueva del procedimiento, `cyber/486/oracle/JSP_CORREOS_486.sql`) |
| 15 | `sp_generar_salidas 'ASIG'` | SCBSDOS, SCBTEL, sub_mst, sub_mail, gescar de nuevas y reasignadas, copia para MIS |

**Nuevas y reasignadas:** se comparan contra el DAT. Una cuenta que viene en la base y no está en el DAT entra: como REA si tiene historial (incluye las que se retiraron por saldo o por solicitud), como NVA si nunca tuvo folio.

**Devoluciones:** se aplican solas salvo que superen el tope (ver *Retiro*).

# Retiro

`ops.sp_retiro` aplica las devoluciones de una corrida (asignación, actualización o solicitud):

- Da de baja las cuentas en el DAT y cierra su periodo en el histórico con una foto del registro (`DATOS_BAJA`).
- Arma el script de retiro para CYBER (`dmstatus = 'R'`).
- Genera el archivo de devolución para CYBER, el gescar de retiro y la lista de folios retirados.

El retiro por solicitud del banco entra con `ops.sp_retiro_solicitud` (lista de cuentas, folios o créditos en CSV).

## Retiro automático (desde el 02/11)

Con `RETIRO_AUTOMATICO = 1`:

1. **Decide** (`ops.sp_retiro_decidir`), justo después de detectar las devoluciones y con el DAT todavía como estaba: por segmento, compara las cuentas a retirar contra las que ese segmento tiene en el DAT. Si ninguno supera el tope (50 % en la asignación, `RETIRO_TOPE_PCT_ASIG`; 50 % en la actualización, `RETIRO_TOPE_PCT_ACT`), se aplica `ops.sp_retiro` dentro de la corrida. Si alguno lo supera, no se aplica nada y se manda el correo de hallazgos.
2. **Cierra** (`ops.sp_retiro_cerrar`), con la corrida ya en OK: escribe los archivos, arma el ZIP y manda el correo único de devolución. El script `RETIRO` en CYBER (`dmstatus = 'R'`) y la copia de `MX_G1MCT_DVBJIG_*` a `RUTA_DEVOLUCION_CYBER` **por ahora son a mano**: `EXEC ops.sp_retiro_cerrar <id>, @con_cyber = 1;` (automáticos con `RETIRO_CYBER_AUTOMATICO = 1`). Cada paso queda en la bitácora y solo corre una vez; si uno falla, llega el correo de hallazgos y se repite a mano con el mismo procedimiento.

El retiro por solicitud también se cierra solo al confirmarlo. Lo que ya se escribió en CYBER no se revierte con el retroceso.

# Correo de hallazgos

`mail.sp_hallazgo` manda la plantilla `HALLAZGO_486` **solo al equipo de asignaciones** (lista `ASIGNACIONES_486`) cuando el proceso automático encuentra algo que no puede resolver solo:

| Hallazgo | Cuándo |
|---|---|
| Retiro detenido: supera el tope | La devolución de un segmento supera el 50 % de sus cuentas en el DAT |
| Retiro con pasos pendientes | Falló escribir los archivos o el ZIP o el correo, el retiro en CYBER o la copia de la devolución |
| Arribo de correos / teléfonos a CYBER con error | CYBER rechazó el arribo automático |
| Actualización en CYBER con error | Oracle rechazó un script `ACT_*` |
| Pagos que no subieron a CYBER | A la hora límite (17:00) hay pagos del SCBPAG que no están en CYBER |
| Blanqueo de status con error | Falló bajar los status o ejecutar el blanqueo |
| No se pudieron escribir los archivos | Falló escribir en `RUTA_SALIDA` |

El correo dice qué pasó, trae una tabla con el detalle (por ejemplo, cada segmento con sus cuentas, las que se iban a retirar y el porcentaje) y la instrucción exacta para resolverlo. El mismo hallazgo no se repite en la misma corrida y queda registrado en la bitácora (paso `HALLAZGO`).

Al exportar con `@zip = 'RETIROS'` los archivos van en `C:\RETIROS_PAG_486_<fecha>.zip` con contraseña, y con `@enviar_zip = 1` sale el **correo único de devolución**: Operación con el ZIP y AEM en copia oculta sin el ZIP.

# Teléfonos

Reglas de `telbnx.prg` con los ajustes del 01/11, que siguen el procedimiento `G4_025_TELEFONOS`:

1. De TEL1 a TEL16 de cada cuenta se quitan espacios y símbolos y se toman los últimos 10 dígitos.
2. Se descartan: menos de 10 dígitos, con letras, los que empiezan con 0 y los números basura (`TEL_INVALIDOS`: 1000000000, 9999999999, 0999999999, 1111111111, 4444444444, 5555555555, 5000000000).
3. Lista negra y teléfonos del banco (exclusiones sin cuenta) se quitan.
4. Un teléfono por cuenta: si se repite, gana el primero de TEL1 a TEL16.
5. Quejas: teléfono dado de baja para esa cuenta, migrado o leído de CYBER en la misma corrida.
6. Lada de 2 dígitos para 33, 55, 56 y 81; de 3 para las demás. Con lada, serie y número se busca en el plan de numeración:
   - **Celular:** área 044 si la lada es 55 o 56, 045 en las demás; 10 dígitos; tipo 5.
   - **Fijo:** área 01 + lada; 8 o 7 dígitos; tipo 1 (TEL1), 2 (TEL2) o 4 (resto).
   - **No está en el plan:** se descarta (`TEL_EXIGIR_PNM = 1`).

Salen en SCBTEL (ancho fijo) y en sub_mst (CUENTA|AREA|TELEFONO|TIPOTEL). En CYBER, `RCVRY.JSP_TELEFONOS_REMESA_486` inserta los teléfonos nuevos (los que dejó el arribo del SCBTEL en `PHONE_G1`), inactiva los activos que no vienen en la remesa y activa los de la remesa que estaban inactivos. Respeta los gestores de queja (`HOMS`, `HPHPI`, `BLACK`, `ZZZTE`): esos no se tocan. Por eso el SCBTEL se arriba antes de la remesa: el job espera a ver los teléfonos en `PHONE_G1` antes de cargarla. El script `TEL_BORRA` también inserta el renglón del día en `RCVRY.JSP_VALIDADOR_TELEFONOS` con el total enviado, y el procedimiento lo completa (diferencia contra lo cargado, activados, inactivados y nuevos).

# Exclusiones

Todas viven en `cfg.EXCLUSION`, con tipo, valor, requerimiento (OS), fecha, si está activa y origen.

| Tipo | Valor | Efecto |
|---|---|---|
| CUENTA | crédito | La cuenta no se da de alta (`exc486`) |
| TELEFONO sin cuenta | teléfono de 10 dígitos | Lista negra o teléfono del banco: nunca sale |
| TELEFONO con cuenta | teléfono + cuenta | Queja: no sale para esa cuenta |
| DIRECCION | cuenta + DIRECC1 | Se borra la dirección (`dirmal`) |
| CORREO | correo + cuenta | No sale en sub_mail (`EMAILMALO`) |

**Lista negra:** columnas TEL, FE\_AGRE, OS y SOLICITUD (como `BLACKLIST_486.DBF`) más STATUS. STATUS **X** excluye; **vacío** no excluye, y si el teléfono estaba activo se desactiva. Un archivo sin columna STATUS cuenta todo como X. Se carga con `cfg.sp_exclusion_cargar`.

# Etiquetas

- **Etiquetado del DAT:** `ops.sp_etiquetar_campo` cambia cualquier campo de etiqueta del DAT con un CSV FOLIO,ETIQUETA (o por cuenta). Acepta el nombre de columna de Operación. Genera su propio SCBSDOS.
- **Etiquetas por cuenta** (`cfg.ETIQUETA`): ETI, DM1, TOP y STATUS, que salen en campos del SCBSDOS (DMP2, DMP1, U1EXT2, U1USO4).

# Archivos y scripts que se generan

## Dónde quedan los archivos

Todo lo escribe `ops.sp_exportar_salidas`, con la cuenta del servicio de SQL Server. Las rutas `C:\` son del **servidor de SQL Server**, no de la PC de quien ejecuta.

| Qué | Ruta | Parámetro |
|---|---|---|
| Archivos del banco (entrada) | `\\192.168.50.13\q\CYBER\C_486\<año>\<mes>\<día>\` (ej. `...\2026\noviembre\03\`) | `cfg.ARCHIVO.RUTA` |
| Archivos planos de cada corrida | `C:\BANBAJ\486\SALIDA\<aaaammdd>_corrida<id>\` | `RUTA_SALIDA` |
| Scripts de Oracle de esa corrida | `C:\BANBAJ\486\SALIDA\<aaaammdd>_corrida<id>\cyber\` | `RUTA_SALIDA` |
| Copia del DAT para MIS | `\\192.168.50.13\q\MIS\SERTEC98\CLIENTES\486\DAT486_<aaaammdd>.csv` | `RUTA_MIS` |
| ZIP de retiros con contraseña | `C:\RETIROS_PAG_486_<mmddaaaahhmmss>.zip` | `CARPETA_ZIP` |

Los archivos planos de ancho fijo (TXT) quedan todos en la carpeta de su corrida, `C:\BANBAJ\486\SALIDA\<aaaammdd>_corrida<id>\`:

| Archivo TXT | Qué es | Lo genera | Ruta de ejemplo |
|---|---|---|---|
| `SCBSDOS.TXT` | Cuentas del DAT para CYBER | Asignación y etiquetado | `C:\BANBAJ\486\SALIDA\20261103_corrida125\SCBSDOS.TXT` |
| `SCBTEL.TXT` | Teléfonos | Asignación | `C:\BANBAJ\486\SALIDA\20261103_corrida125\SCBTEL.TXT` |
| `SCBACTH_486NU.TXT` | Gescar de cuentas nuevas | Asignación | `C:\BANBAJ\486\SALIDA\20261103_corrida125\SCBACTH_486NU.TXT` |
| `SCBACTH_486REA.TXT` | Gescar de cuentas reasignadas | Asignación | `C:\BANBAJ\486\SALIDA\20261103_corrida125\SCBACTH_486REA.TXT` |
| `SCBACTH_SINTEL.TXT` | Gescar de cuentas sin teléfono en CYBER | El arribo automático de teléfonos (o `ops.sp_bajar_cyber 'TELEFONOS'` a mano); se escribe solo | `C:\BANBAJ\486\SALIDA\20261103_corrida125\SCBACTH_SINTEL.TXT` |
| `SCBACTH_486.TXT` | Gescar de retiro | Retiro (`ops.sp_retiro`) | `C:\BANBAJ\486\SALIDA\20261103_corrida125\SCBACTH_486.TXT` |
| `SCBPAG.TXT` | Arribo de pagos | Actualización | `C:\BANBAJ\486\SALIDA\20261103_corrida124\SCBPAG.TXT` |
| `sub_mst.TXT`, `sub_mail.TXT` | Remesas de teléfonos y correos (separadas por `\|`) | Asignación | misma carpeta |

Cada corrida tiene su propia carpeta, así que un SCBSDOS de la asignación y otro de un etiquetado del mismo día no se pisan. Los archivos se escriben cuando se corre `EXEC ops.sp_exportar_salidas <id corrida>;`, no antes: hasta entonces solo están en la base (`ops.SALIDA_LINEA`).

Ejemplo de una asignación del 3 de noviembre, corrida 125:

```
C:\BANBAJ\486\SALIDA\
└── 20261103_corrida125\
    ├── SCBSDOS.TXT
    ├── SCBTEL.TXT
    ├── sub_mst.TXT
    ├── sub_mail.TXT
    ├── SCBACTH_486NU.TXT
    ├── SCBACTH_486REA.TXT
    ├── DAT486_20261103.csv
    └── cyber\
        ├── TEL_BORRA.sql
        ├── TEL_ACTUALIZA.sql
        ├── MAIL_ACTIVA_BANDERA.sql
        ├── MAIL_BORRA.sql
        ├── MAIL_ACTUALIZA.sql
        └── MAIL_INACTIVA_BANDERA.sql
```

Si el equipo que arriba no entra al disco `C:` del servidor, hay dos opciones: compartir `C:\BANBAJ\486\SALIDA\` en la red, o cambiar `RUTA_SALIDA` a una carpeta de red (por ejemplo, una carpeta en `\\192.168.50.13\q\`). La cuenta del servicio de SQL Server necesita permiso de escritura ahí.

```sql
UPDATE cfg.PARAMETRO SET VALOR = N'\\192.168.50.13\q\BANBAJ\486\SALIDA\' WHERE CLIENTE = '486' AND CLAVE = 'RUTA_SALIDA';
EXEC ops.sp_exportar_salidas @id, @carpeta = N'D:\otra\carpeta\';   -- solo para una vez
```

## Qué se genera

Las salidas se definen en `cfg.SALIDA_ARCHIVO` (archivo, proceso, origen, nombre, separador) y `cfg.SALIDA` (campos, ancho y formato). Cada corrida guarda sus líneas en `ops.SALIDA_LINEA` y sus scripts en `ops.CYBER_SCRIPT`. `ops.sp_exportar_salidas` los escribe a disco en `RUTA_SALIDA\<aaaammdd>_corrida<id>\` (planos en la raíz, scripts en `cyber\`).

| Proceso | Archivo | Contenido |
|---|---|---|
| ASIG | SCBSDOS.TXT | Cuentas del DAT para CYBER |
| ASIG | SCBTEL.TXT | Teléfonos de ancho fijo |
| ASIG | sub_mst.TXT | Teléfonos para la remesa de CYBER |
| ASIG | sub_mail.TXT | Correos para la remesa de CYBER |
| ASIG | SCBACTH_486NU.TXT / SCBACTH_486REA.TXT | Gescar de nuevas y reasignadas |
| ACT | SCBPAG.TXT | Arribo de pagos |
| ACT | scripts ACT_SALDOS, ACT_VENCIDO, ACT_PAGMIN, ACT_PVS_REE | Saldos y PVS/REE en CYBER |
| RETIRO | MX_G1MCT_DVBJIG_<fecha>_<hora> | Devolución para CYBER |
| RETIRO | SCBACTH_486.TXT, RETIROS_486_<fecha>.csv | Gescar de retiro y folios retirados |
| ETI | SCBSDOS.TXT | SCBSDOS de etiquetado |
| Todos | DAT486_<fecha>.csv | Copia del DAT para MIS (también en `RUTA_MIS`) |

# Correos

Se mandan con `mail.sp_enviar` usando plantillas de `mail.PLANTILLA` y listas de `mail.DESTINATARIO`. Para cambiar destinatarios no hay que tocar código.

| Plantilla | Cuándo | A quién |
|---|---|---|
| INICIO_ASIG_486 | Al iniciar la asignación (automático) | Operación |
| CONFIRMACION_ASIG_486 | Fin de asignación, después del arribo (`sp_avisar`) | Operación |
| ALERTA_NUEVAS_486 | Más de 100 cuentas nuevas | AEM |
| DEVOLUCION_486 | Devolución (asignación, actualización o solicitud) | Operación, con el ZIP |
| DEVOLUCION_486_AEM | La misma devolución | AEM en copia oculta, sin ZIP |
| ALERTA_SDO_ACT_CONS_486 | Consumo con saldo menor o igual a cero en la base | Operación |
| PAGOS_NEGATIVOS_486 | Llegaron pagos negativos | Equipo de asignaciones |
| MAESTRA_NUMEROS_EXCEL_486 | Excel cortó números en la base maestra | Equipo de asignaciones |
| ARCHIVOS_LISTOS_486 | En cuanto se escriben los planos que se suben a CYBER (asignación, actualización, retiro, etiquetado y SCBACTH_SINTEL): carpeta, archivos con sus líneas y qué sigue (`ops.sp_aviso_archivos`) | Equipo de asignaciones |
| HALLAZGO_486 | Retiro que supera el tope, pagos que no subieron y cualquier paso automático con error (`mail.sp_hallazgo`) | Equipo de asignaciones |

# Respaldo y retroceso

- Antes de tocar el DAT, cada corrida guarda una foto completa del DAT y el último folio. Se conservan las últimas 15 (`RESPALDOS_A_CONSERVAR`).
- De cada base maestra se guardan dos versiones por segmento: la vigente y la anterior (`dat.v_BASE_VIGENTE`).
- **Retroceso automático:** si una corrida falla, se revierte sola y queda marcada (`REVERTIDA_AUTO = 1`) conservando su estatus de error, para que el job no la reintente en bucle.
- **Retroceso manual:** `ops.sp_revertir_corrida @id, @confirmar = 1` regresa el DAT, el histórico, los pagos, el consecutivo y la base maestra vigente. Solo la corrida más reciente.
- Lo que ya se arribó a CYBER no se revierte.

# Tablas principales

| Tabla | Para qué |
|---|---|
| `dat.DAT_486` | Cuentas activas del 486 (70 campos) |
| `dat.HISTORIA_FOLIO` | Cada periodo de cada cuenta: folio, cuenta en CYBER, alta, baja, motivo y foto al darse de baja |
| `dat.FOLIO_CONSECUTIVO` | Último folio usado |
| `dat.PAGO_ARRIBADO` | Pagos ya arribados (para no repetirlos) |
| `dat.BASE_RECIBIDA` / `_ARCHIVO` | Bases maestras completas (vigente y anterior por segmento) |
| `cfg.ARCHIVO` | Archivos de entrada: ruta, patrón de nombre, columnas, tabla de paso |
| `cfg.SALIDA_ARCHIVO`, `cfg.SALIDA` | Archivos de salida y sus campos |
| `cfg.REGLA`, `cfg.HOMOLOGACION` | Validaciones y transformaciones |
| `cfg.PARAMETRO` | Parámetros del cliente |
| `cfg.EXCLUSION`, `cfg.ETIQUETA` | Exclusiones y etiquetas |
| `cfg.PLAN_NUMERACION`, `cfg.TEL_QUEJA_CYBER` | Plan de numeración y quejas leídas de CYBER |
| `cfg.CREDENCIAL` | Usuario y contraseña de Oracle y del ZIP, cifrados |
| `ops.CORRIDA`, `ops.BITACORA` | Corridas y su bitácora paso a paso |
| `ops.DEVOLUCION`, `ops.RECHAZO` | Cuentas a retirar y registros rechazados |
| `ops.TELEFONO`, `ops.CORREO` | Teléfonos y correos generados por corrida |
| `ops.SALIDA_LINEA`, `ops.CYBER_SCRIPT` | Líneas de archivos y sentencias de scripts por corrida |

# Procedimientos que se usan a mano

| Procedimiento | Para qué |
|---|---|
| `ops.sp_diario_486` | Correr el día (lo hace el job) |
| `ops.sp_actualizacion_486`, `ops.sp_asignacion_486` | Correr un proceso a mano |
| `ops.sp_retiro` | Aplicar las devoluciones de una corrida (lo hace solo el retiro automático) |
| `ops.sp_act_cyber` | Ejecutar en CYBER los scripts de la actualización (lo hace el job) |
| `ops.sp_blanqueo_automatico` | Blanqueo de status (lo hace el job; `@forzar = 1` para repetir) |
| `ops.sp_cuadre_automatico` | Cuadre de pagos contra CYBER (lo hace el job) |
| `ops.sp_retiro_cerrar` | Archivos, ZIP y correo, retiro en CYBER y copia de la devolución; repite lo que falló |
| `mail.sp_hallazgo` | Correo de hallazgos al equipo de asignaciones |
| `ops.sp_retiro_solicitud` | Retiro por solicitud del banco |
| `ops.sp_exportar_salidas` | Escribir archivos y scripts; ZIP y correo de devolución |
| `ops.sp_marcar_arribo` | Horas de solicitud, autorización y fin del arribo |
| `ops.sp_avisar` | Correo de fin de asignación |
| `ops.sp_etiquetar_campo` | Etiquetado del DAT |
| `ops.sp_regenerar_scbsdos` | SCBSDOS fuera de proceso |
| `ops.sp_bajar_cyber` | Status (blanqueo), correos, teléfonos y pagos desde CYBER |
| `ops.sp_arribo_automatico` | Revisa si ya subieron SCBSDOS y SCBTEL y arriba correos y teléfonos (lo hace el job) |
| `ops.sp_arribar_cyber` | Arribar a mano correos o teléfonos de una asignación (`@solo_mostrar = 1` para ver los bloques) |
| `cfg.sp_exclusion_cargar` | Lista negra y otras exclusiones |
| `ops.sp_revertir_corrida` | Retroceso manual |
| `ops.sp_migrar_486` | Migración desde FoxPro (una sola vez) |

Todos los que cambian datos tienen modo de revisión (`@confirmar = 0` o `@solo_mostrar = 1`).

# Parámetros principales

| Parámetro | Valor | Qué controla |
|---|---|---|
| RUTA\_SALIDA | `C:\BANBAJ\486\SALIDA\` | Dónde se escriben archivos y scripts |
| RUTA\_MIS | `\\192.168.50.13\q\MIS\SERTEC98\CLIENTES\486\` | Copia del DAT para MIS |
| CARPETA\_ZIP | `C:\` | ZIP de retiros |
| ASIG\_REQUIERE\_ACT | 1 | La asignación exige la actualización OK del día |
| ALERTA\_NUEVAS | 100 | Umbral del correo de nuevas |
| NEGATIVO\_MODO | CERO | Importes negativos suben en cero |
| RETROCESO\_AUTOMATICO | 1 | Revertir sola una corrida que falla |
| RESPALDOS\_A\_CONSERVAR | 15 | Respaldos del DAT |
| TEL\_EXIGIR\_PNM | 1 | Descartar teléfonos fuera del plan de numeración |
| TELBAJ\_GRUPO | 1 | Grupo del 486 en telbaj |
| PERFIL\_DBMAIL | asig.486.cdmx | Perfil de correo |
| ARRIBO\_MIN\_PCT | 95 | Porcentaje de lo pendiente que ya debe estar en CYBER para dar por subido un archivo |
| CYBER\_COLUMNA\_DOMICILIO | DMADDR1 | Domicilio en `DELQMST` para detectar el SCBSDOS |
| RETIRO\_AUTOMATICO | 1 | Aplicar solas las devoluciones en el DAT (dentro del tope) |
| RETIRO\_TOPE\_PCT\_ASIG / \_ACT | 50 / 50 | Tope por segmento para aplicar el retiro solo |
| EXPORTAR\_AUTOMATICO, AVISO\_ARCHIVOS, RETIRO\_AUTOMATICO, CUADRE\_AUTOMATICO | 1 | Archivos, aviso, retiro en el DAT y cuadre automáticos |
| ARRIBO\_AUTOMATICO, ACT\_CYBER\_AUTOMATICO, RETIRO\_CYBER\_AUTOMATICO, BLANQUEO\_AUTOMATICO, CONFIRMACION\_AUTOMATICA | 0 | Depuraciones y escrituras en CYBER: a mano por ahora (1 = automáticas) |
| CUADRE\_PAGOS\_HORA\_LIMITE | 17:00 | Hora a la que el cuadre avisa lo que no subió |
| RUTA\_DEVOLUCION\_CYBER | `\\192.168.50.1\Cyber_00\dev\` | Copia de la devolución para CYBER |
| CYBER\_REMESA\_TEL\_COLUMNAS / \_MAIL\_COLUMNAS | CUENTA,AREA,TELEFONO,TIPOTEL / CUENTA,CORREO | Columnas de las remesas en CYBER |
| CYBER\_SENTENCIAS\_POR\_BLOQUE | 200 | Tamaño de cada bloque PL/SQL |

# Seguridad

- Las contraseñas de Oracle y del ZIP se guardan cifradas (certificado y llave AES-256 de la base). La vista de captura nunca las muestra y solo los procesos las leen.
- Los archivos de los clientes no se guardan en repositorios. Las tablas de paso de la migración se borran al terminar.
- Accesos por niveles (CONSULTA, OPERADOR, ADMIN) con `sql/instalacion/04_accesos_remotos.sql`. Ningún nivel fuera de ADMIN puede leer las credenciales.
- Las pruebas automáticas del repo usan datos ficticios.

# Dónde ver qué pasó

```sql
SELECT TOP 10 ID_CORRIDA, PROCESO, FECHA_PROCESO, ESTATUS, MENSAJE FROM ops.CORRIDA ORDER BY ID_CORRIDA DESC;
SELECT PASO, ESTATUS, REGISTROS, MENSAJE FROM ops.BITACORA WHERE ID_CORRIDA = @id ORDER BY ID;
SELECT * FROM ops.DEVOLUCION WHERE ID_CORRIDA = @id;
SELECT * FROM ops.RECHAZO WHERE ID_CORRIDA = @id;
SELECT * FROM ops.v_TIEMPOS_CORRIDA WHERE ID_CORRIDA = @id;
```
