# 05 · Arribo a CYBER (depuraciones de correos y teléfonos)

![Arribo a CYBER](img/05_arribo_cyber.png)

Fuente: [`mmd/05_arribo_cyber.mmd`](mmd/05_arribo_cyber.mmd) · Código: `sql/76_sp_arribo_cyber.sql`, `ops.sp_arribo_posterior` y `ops.sp_aviso_archivos` en `sql/78_sp_automatico.sql`, `ops.fn_archivos_diferidos` en `sql/10_funciones.sql`

**Orden (decisiones 17/11 y 19/11).** Primero va la depuración de teléfonos y después se sube el SCBTEL: el SCBTEL da de alta activos los teléfonos que traiga, y la depuración decide qué queda activo. Los planos los sube una persona, y el job se da cuenta solo de cuándo ya están.

**Depuración por diferencia (decisión 19/11, `TEL_DEPURACION = DIFERENCIA`).** En lugar de subir la remesa completa, Banbaj baja una foto de `PHONE` de las cuentas activas del 486 y la compara en SQL Server con nuestros teléfonos (`ops.sp_tel_depura_calcular`). A CYBER solo sube lo que cambia, a `RCVRY.JSP_TAB_TEL_DEPURA_486`:

| Acción | Qué es | Qué hace CYBER |
|---|---|---|
| I | Activo en CYBER que ya no viene en nuestro archivo (incluye lo que agregó un gestor) | `JSP_TELEFONOS_DEPURA_486` lo inactiva (HIAS) |
| A | Inactivo en CYBER que sí viene | Lo activa (HAAS) |
| N | No existe en `PHONE` | Solo se cuenta; va en el SCBTEL y el cargador lo da de alta |

- Los teléfonos de gestores de queja (`TEL_GESTORES_QUEJA`: HOMS, HPHPI, BLACK, ZZZTE) no se tocan. Los nuestros que CYBER tiene con queja se cuentan para el validador.
- **Ventana:** lo que un gestor agregue entre la foto y el store (unos minutos) se queda activo hasta la siguiente asignación.
- **Freno:** si se inactivaría más de `TEL_DEPURA_MAX_INACTIVAR_PCT` (30 %) de los activos de la foto, no se toca CYBER (error 50779, `TEL DIFERENCIA` en ERROR y hallazgo). Protege contra una foto o un archivo incompletos.
- **Bandera:** toda la depuración corre con la bandera de CYBER encendida (`CYBER_BANDERA_TELEFONOS`, 416, la misma de correos) en `RPT_LOG_CYBER_REG` y su bitácora `RPT_LOG_CYBER`. El store deja ahí cada etapa. Se apaga al terminar o si algo falla.
- Si no hay cambios, no se sube nada ni se ejecuta el store. Si no hay nuevos, no sale SCBTEL.

Mientras el DBA no instale la tabla y el store nuevos, `TEL_DEPURACION = ACTUAL` sube la remesa completa a `JSP_TAB_TEL_REMESA_486` y ejecuta `JSP_TELEFONOS_REMESA_486`, con el SCBTEL completo (también con la bandera). `NUEVOS` (18/11) se toma como `DIFERENCIA`.

**Gescar sin teléfono desde antes (19/11).** Después de la depuración, lo activo en CYBER es lo de `ops.TELEFONO`. Por eso `SCBACTH_SINTEL.TXT` sale de nuestros teléfonos: las cuentas nuevas y reasignadas sin renglón en `ops.TELEFONO`, incluidas las que solo tenían un teléfono de queja. Se genera con la asignación y se escribe y avisa junto con los gescar de nuevas y reasignadas cuando suben los saldos. Ya no se baja `PHONE` ni se espera al SCBTEL para esto.

| # | Paso del job | Cuándo | Bitácora |
|---|---|---|---|
| 0 | Al terminar la asignación se escribe el SCBSDOS y se avisa (`ARCHIVOS_LISTOS_486`). El SCBTEL y los gescar todavía no (`ops.fn_archivos_diferidos`) | Corrida OK | `EXPORTAR AUTOMATICO` |
| 1 | Se marcan los saldos arriba y se escriben y avisan los gescar de nuevas, reasignadas y sin teléfono | Cuentas con `DMHOSTUP` del día = cuentas del SCBSDOS | `ARRIBO SALDOS`, `GESCAR SIN TELEFONO` |
| 2 | **Depuración de teléfonos** (con la bandera): foto de `PHONE`, diferencia, solo los cambios a `JSP_TAB_TEL_DEPURA_486`; si cuadran, `JSP_TELEFONOS_DEPURA_486`. Luego escribe el SCBTEL (solo nuevos; si no hay, no sale) y avisa que ya se puede subir | Saldos arriba | `CYBER EJECUTA`, `TEL DIFERENCIA`, `TEL REMESA VALIDADA`, `ARRIBO TELEFONOS` |
| 3 | **Depuración de correos:** correos nuevos en `ADDRESS`, bandera 416, remesa y `JSP_CORREOS_486` | Depuración de teléfonos OK | `ARRIBO CORREOS` |
| 4 | **SCBTEL arriba:** los teléfonos nuevos ya están en `PHONE_G1` | Teléfonos OK en una vuelta anterior y ≥ `ARRIBO_MIN_PCT` de los nuevos en `PHONE_G1` (sin nuevos, de inmediato) | `ARRIBO SCBTEL` |

**Foto de pendientes** (`ops.sp_arribo_base`, al terminar la asignación). Compara lo que se manda con lo que CYBER ya tiene y guarda en `ops.ARRIBO_PENDIENTE` lo que falta:

| Tipo | Qué falta |
|---|---|
| CUENTA | Cuentas del SCBSDOS que no están activas en `DELQMST` (nuevas y reasignadas) |
| DOMICILIO | Cuentas activas cuyo `DMADDR1` en CYBER es distinto al del SCBSDOS (`CYBER_COLUMNA_DOMICILIO`) |
| TELEFONO | Teléfonos del SCBTEL, de todas las cuentas, que no están en `PHONE_G1`. Con `DIFERENCIA`, al depurar se cambian por los teléfonos nuevos |

**Detección** (`ops.sp_arribo_automatico`, en cada vuelta con el día completo). Baja de CYBER el estado actual (`ops.sp_arribo_bajar` → `stg.CYBER_HOSTUP`, `stg.CYBER_DELQMST_ACT`, `stg.CYBER_PHONE_G1`):

- **Saldos arriba:** la validación del equipo (`val.txt`): `select dmhostup, count(*) from rcvry.delqmst where dmacctg='1' and dmcompany='486' and dmstatus is null group by dmhostup`. Si las cuentas con `DMHOSTUP` del día son tantas como las del SCBSDOS (`ARRIBO_SDOS_MIN_PCT`, 100 = que coincidan), ya subieron. Con `CYBER_HOSTUP_EXPR` vacío se usa lo pendiente: al menos `ARRIBO_MIN_PCT` (95 %) de las cuentas y los domicilios.
- **SCBTEL arriba:** al menos 95 % de los teléfonos pendientes ya están en `PHONE_G1`. Solo cuenta después de la depuración de teléfonos.
- El resultado dice en qué va: `ESPERANDO SALDOS`, `DEPURACION DE TELEFONOS CON ERROR`, `ESPERANDO SCBTEL` o lo que hizo en esa vuelta. `EXEC ops.sp_marcar_arribo <id>, 'FIN';` da todo por subido.

**Guardas:** sin teléfonos o correos nuestros no se ejecuta ningún store (inactivaría todo el 486), ni dentro de una transacción. Si lo que quedó en CYBER no cuadra con lo que mandamos (error 50776), no se ejecuta el store, no sale el SCBTEL y los correos esperan. Si algo falla con la bandera 416 encendida, se apaga.

**Después** (`ops.sp_arribo_posterior`):

- Con correos OK, el blanqueo de status (`ops.sp_blanqueo_automatico`, días `DIAS_BLANQUEO_STATUS`).
- Con teléfonos y correos OK, el gescar sin teléfono ya intentado, el SCBTEL arriba (`ARRIBO SCBTEL`) y el blanqueo intentado, `ops.sp_confirmar_asignacion` marca `ARRIBO FIN` y manda `CONFIRMACION_ASIG_486`.

**Errores:** quedan `ARRIBO TELEFONOS` (y `TEL DIFERENCIA` si fue el freno), `ARRIBO CORREOS` o `GESCAR SIN TELEFONO` en ERROR con el mensaje (de Oracle, o las dos cifras si no cuadró) y llega un hallazgo. No se reintenta solo; se corrige y se corre `EXEC ops.sp_arribar_cyber <id>, 'TELEFONOS';` (o `'CORREOS'`, con `@solo_mostrar = 1` se ven los bloques sin ejecutar) o `EXEC ops.sp_arribo_gescar_sintel <id>;`.

**Parámetros:** `ARRIBO_AUTOMATICO`, `ARCHIVOS_DESPUES_SALDOS` (gescar NVA, REA y SINTEL; SINTEL siempre espera a los saldos), `ARCHIVOS_DESPUES_DEPURACION_TEL` (SCBTEL), `CYBER_HOSTUP_EXPR`, `ARRIBO_SDOS_MIN_PCT`, `ARRIBO_MIN_PCT`, `CYBER_COLUMNA_DOMICILIO`, `CYBER_REMESA_TEL_COLUMNAS`, `CYBER_REMESA_MAIL_COLUMNAS`, `CYBER_SENTENCIAS_POR_BLOQUE`, `CYBER_VALIDADOR_TELEFONOS`, `TEL_DEPURACION`, `CYBER_PROC_TEL_DEPURA`, `CYBER_PROC_TELEFONOS`, `CYBER_BANDERA_TELEFONOS`, `TEL_GESTORES_QUEJA`, `TEL_DEPURA_MAX_INACTIVAR_PCT`, `BLANQUEO_AUTOMATICO`, `CONFIRMACION_AUTOMATICA`.

**Para cambiar:** la regla de detección está en `ops.sp_arribo_automatico` (variables `@listo_s`, `@tel_ok`, `@ok_t` y los pasos 1 a 4); la comparación, en `ops.sp_tel_depura_calcular`; lo que se manda a CYBER, en los scripts que arma la asignación (`sql/45_sp_telefonos.sql`, `sql/46_sp_correos_cyber.sql`) y en `ops.sp_arribar_cyber`. Los stores de Oracle están en `cyber/486/oracle/`. Pruebas: `ARRIBO BASE: …`, `ARRIBO AUTO …`, `ARRIBO TEL: …`, `TEL DIFERENCIA: …`, `TEL ACTUAL: …`, `GESCAR sin teléfono: …`, `ARRIBO: …` y `CONFIRMACION AUTO: …` en `tests/pruebas.sql`.
