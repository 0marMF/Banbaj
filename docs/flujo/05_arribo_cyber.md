# 05 · Arribo a CYBER (depuraciones de correos y teléfonos)

![Arribo a CYBER](img/05_arribo_cyber.png)

Fuente: [`mmd/05_arribo_cyber.mmd`](mmd/05_arribo_cyber.mmd) · Código: `sql/76_sp_arribo_cyber.sql`, `ops.sp_arribo_posterior` y `ops.sp_aviso_archivos` en `sql/78_sp_automatico.sql`, `ops.fn_archivos_diferidos` en `sql/10_funciones.sql`

**Orden (decisión 17/11).** Lo marcan los stores de CYBER: `JSP_TELEFONOS_REMESA_486` inactiva todo lo que no está en la remesa y el SCBTEL activa nuestros teléfonos, así que primero va la depuración de teléfonos y después se sube el SCBTEL. Los planos los sube una persona, y el job se da cuenta solo de cuándo ya están.

| # | Paso del job | Cuándo | Bitácora |
|---|---|---|---|
| 0 | Al terminar la asignación se escribe el SCBSDOS y se avisa (`ARCHIVOS_LISTOS_486`). El SCBTEL y los gescar todavía no (`ops.fn_archivos_diferidos`) | Corrida OK | `EXPORTAR AUTOMATICO` |
| 1 | Se marcan los saldos arriba y se escriben y avisan los gescar de nuevas y reasignadas | Cuentas con `DMHOSTUP` del día = cuentas del SCBSDOS | `ARRIBO SALDOS` |
| 2 | **Depuración de teléfonos:** vacía y carga `RCVRY.JSP_TAB_TEL_REMESA_486`; si tiene los mismos renglones que nuestro archivo de teléfonos (`ops.TELEFONO`, lo que va en `sub_mst.TXT`), ejecuta `JSP_TELEFONOS_REMESA_486`. Luego escribe el SCBTEL y avisa que ya se puede subir | Saldos arriba | `TEL REMESA VALIDADA`, `ARRIBO TELEFONOS` |
| 3 | **Depuración de correos:** correos nuevos en `ADDRESS`, bandera 416, remesa y `JSP_CORREOS_486` | Depuración de teléfonos OK | `ARRIBO CORREOS` |
| 4 | **Gescar sin teléfono:** baja los teléfonos activos y escribe `SCBACTH_SINTEL.TXT` con su aviso (`ops.sp_arribo_gescar_sintel`) | Teléfonos OK y el SCBTEL ya subió (≥ `ARRIBO_MIN_PCT` de los teléfonos que faltaban ya están en `PHONE_G1`) | `GESCAR SIN TELEFONO` |

**Foto de pendientes** (`ops.sp_arribo_base`, al terminar la asignación). Compara lo que se manda con lo que CYBER ya tiene y guarda en `ops.ARRIBO_PENDIENTE` lo que falta:

| Tipo | Qué falta |
|---|---|
| CUENTA | Cuentas del SCBSDOS que no están activas en `DELQMST` (nuevas y reasignadas) |
| DOMICILIO | Cuentas activas cuyo `DMADDR1` en CYBER es distinto al del SCBSDOS (`CYBER_COLUMNA_DOMICILIO`) |
| TELEFONO | Teléfonos del SCBTEL, de todas las cuentas, que no están en `PHONE_G1` |

**Detección** (`ops.sp_arribo_automatico`, en cada vuelta con el día completo). Baja de CYBER el estado actual (`ops.sp_arribo_bajar` → `stg.CYBER_HOSTUP`, `stg.CYBER_DELQMST_ACT`, `stg.CYBER_PHONE_G1`):

- **Saldos arriba:** la validación del equipo (`val.txt`): `select dmhostup, count(*) from rcvry.delqmst where dmacctg='1' and dmcompany='486' and dmstatus is null group by dmhostup`. Si las cuentas con `DMHOSTUP` del día son tantas como las del SCBSDOS (`ARRIBO_SDOS_MIN_PCT`, 100 = que coincidan), ya subieron. Con `CYBER_HOSTUP_EXPR` vacío se usa lo pendiente: al menos `ARRIBO_MIN_PCT` (95 %) de las cuentas y los domicilios.
- **SCBTEL arriba:** al menos 95 % de los teléfonos pendientes ya están en `PHONE_G1`. Solo cuenta después de la depuración de teléfonos.
- El resultado dice en qué va: `ESPERANDO SALDOS`, `DEPURACION DE TELEFONOS CON ERROR`, `ESPERANDO SCBTEL` o lo que hizo en esa vuelta. `EXEC ops.sp_marcar_arribo <id>, 'FIN';` da todo por subido.

**Guardas:** sin remesa no se ejecuta ningún store (inactivaría todo el 486), ni dentro de una transacción. Si la remesa de teléfonos no cuadra (error 50776), no se ejecuta `JSP_TELEFONOS_REMESA_486`, no sale el SCBTEL y los correos esperan. Si falla con la bandera 416 encendida, intenta apagarla.

**Después** (`ops.sp_arribo_posterior`):

- Con correos OK, el blanqueo de status (`ops.sp_blanqueo_automatico`, días `DIAS_BLANQUEO_STATUS`).
- Con teléfonos y correos OK, el gescar sin teléfono ya intentado (el SCBTEL subió) y el blanqueo intentado, `ops.sp_confirmar_asignacion` marca `ARRIBO FIN` y manda `CONFIRMACION_ASIG_486`.

**Errores:** quedan `ARRIBO TELEFONOS`, `ARRIBO CORREOS` o `GESCAR SIN TELEFONO` en ERROR con el mensaje (de Oracle, o las dos cifras si la remesa no cuadró) y llega un hallazgo. No se reintenta solo; se corrige y se corre `EXEC ops.sp_arribar_cyber <id>, 'TELEFONOS';` (o `'CORREOS'`, con `@solo_mostrar = 1` se ven los bloques sin ejecutar) o `EXEC ops.sp_arribo_gescar_sintel <id>;`.

**Parámetros:** `ARRIBO_AUTOMATICO`, `ARCHIVOS_DESPUES_SALDOS` (gescar NVA y REA), `ARCHIVOS_DESPUES_DEPURACION_TEL` (SCBTEL), `CYBER_HOSTUP_EXPR`, `ARRIBO_SDOS_MIN_PCT`, `ARRIBO_MIN_PCT`, `CYBER_COLUMNA_DOMICILIO`, `CYBER_REMESA_TEL_COLUMNAS`, `CYBER_REMESA_MAIL_COLUMNAS`, `CYBER_SENTENCIAS_POR_BLOQUE`, `CYBER_VALIDADOR_TELEFONOS`, `BLANQUEO_AUTOMATICO`, `CONFIRMACION_AUTOMATICA`.

**Para cambiar:** la regla de detección está en `ops.sp_arribo_automatico` (variables `@listo_s`, `@listo_g`, `@tel_ok` y los pasos 1 a 4); lo que se manda a CYBER, en los scripts que arma la asignación (`sql/45_sp_telefonos.sql`, `sql/46_sp_correos_cyber.sql`) y en `ops.sp_arribar_cyber`. Los stores de Oracle están en `cyber/486/oracle/`. Pruebas: `ARRIBO BASE: …`, `ARRIBO AUTO …`, `ARRIBO TEL: …`, `ARRIBO: …` y `CONFIRMACION AUTO: …` en `tests/pruebas.sql`.
