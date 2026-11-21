# 03 · Asignación

![Asignación](img/03_asignacion.png)

Fuente: [`mmd/03_asignacion.mmd`](mmd/03_asignacion.mmd) · Código: `ops.sp_asignacion_486` en `sql/60_sp_orquestadores.sql`

**Llave única por riesgo (20/11).** La llave del DAT y del histórico (`CUENTA`) es el riesgo en todos los segmentos: en TDC el ACC_NUM, en Consumo e Hipotecario el crédito. Con ella se reparten folios, se reconocen reasignadas y se decide la devolución. La cuenta que va a CYBER como cuenta del banco (DMSSNUM del SCBSDOS, SCBPAG, listas de etiquetas) queda en `CTA_BANCO`: en TDC la armada (últimos 4 dígitos de PRIME+4DIG + RFC), en los demás el crédito. Lo cargado antes del cambio se pasa con `ops.sp_llave_riesgo_migrar` (también al final de la migración).

**Una asignación por segmento (20/11).** El job corre la asignación en cuanto llega una base maestra. Si después llega la de otro segmento, corre otra asignación solo con ese segmento (`ops.sp_cargar_proceso` no vuelve a tomar la base de un segmento que ya se asignó ese día). Cada asignación tiene sus propios archivos, su retiro y su arribo a CYBER; el SCBSDOS, los teléfonos y los correos de cada una llevan todo el DAT.

**Dentro de la corrida** (si cualquier paso falla, la corrida queda en ERROR y `ops.sp_retroceso_automatico` restaura el DAT):

| Paso | Procedimiento (archivo) | Qué hace |
|---|---|---|
| Respaldo | `ops.sp_respaldo` (35) | Copia el DAT antes de tocarlo |
| Carga y validación de la entrada | `ops.sp_cargar_proceso` (20), `ops.sp_validar_datos_archivo` (22) | Lee las bases maestras de Q: (`cfg.ARCHIVO`, proceso ASIG) y revisa layout y datos; si algo no pasa, detiene antes de tocar el DAT y avisa (`VALIDACION_ENTRADA_486`). Ver [09](09_validacion_entrada.md) |
| Homologar y validar | `ops.sp_homologar_entradas` (60), `ops.sp_validar 'POST_CARGA'` (20) | Etiquetas desde los catálogos estáticos (`cfg.CATALOGO`: estatus, tramo, tipo de crédito, cartera, enfoque…), números cortados por Excel (`MAESTRA_NUMEROS_EXCEL_486`), saldos ≤ 0 en Consumo |
| Unir layout | `ops.sp_asig_unir_layout`, `ops.sp_asig_avisos_llave`, `ops.sp_homologar 'stg.LAYOUT_486'` (30, 20) | Junta los segmentos en `stg.LAYOUT_486`. El mismo riesgo en dos segmentos detiene y avisa; riesgo con otro RFC y cambio de segmento solo avisan |
| Devoluciones | `ops.sp_asig_devolucion` (30) | Cuentas del DAT del segmento que no vienen en su base maestra (por riesgo) → `ops.DEVOLUCION`. `TOPE_DEVOLUCION_PCT` cancela la asignación si son demasiadas |
| Decidir retiro | `ops.sp_retiro_decidir` (77) | Tope de 50 % por segmento (diagrama 06) |
| Existentes | `ops.sp_asig_existentes` (30) | Actualiza las que siguen; sus teléfonos se quedan como llegan |
| Teléfonos | `ops.sp_telefonos_refrescar_cyber`, `ops.sp_asig_normalizar_telefonos` (45) | Quejas y plan de numeración de CYBER; normaliza los de nuevas y reasignadas |
| Alta | `ops.sp_validar 'PRE_ALTA'`, `ops.sp_asig_alta` (30) | REA si el riesgo tuvo folio antes (`dat.HISTORIA_FOLIO`); NVA con folio nuevo (`dat.FOLIO_CONSECUTIVO`) |
| Retiro | `ops.sp_retiro` (30) | Solo si se decidió aplicarlo |
| Teléfonos y correos | `ops.sp_telefonos` (45), `ops.sp_correos` (46) | Arman lo que se manda a CYBER (`ops.TELEFONO`, `ops.CORREO`) |
| Salidas | `ops.sp_generar_salidas 'ASIG'` (50) | SCBSDOS, SCBTEL, sub_mst, sub_mail, gescar NVA, REA y SINTEL (de `ops.TELEFONO`), scripts de remesas y bandera |

**Al terminar OK** (fuera de la corrida; si falla queda en la bitácora y llega un hallazgo):

1. `ops.sp_arribo_base`: foto de lo que le falta a CYBER (diagrama 05). Se toma antes de escribir los archivos, así el operador todavía no pudo subir nada.
2. Si hubo retiro, `ops.sp_retiro_cerrar` (archivos, ZIP, correo de devolución y RETIRO en CYBER). Si no, `ops.sp_exportar_auto` (archivos).
3. `ops.sp_aviso_archivos`: correo `ARCHIVOS_LISTOS_486` a asignaciones.

**Parámetros:** `ASIG_REQUIERE_ACT`, `TOPE_DEVOLUCION_PCT`, `RETIRO_AUTOMATICO`, `RETIRO_TOPE_PCT_ASIG`, `ARRIBO_AUTOMATICO`, `EXPORTAR_AUTOMATICO`, `AVISO_ARCHIVOS`, `ALERTA_NUEVAS`.

**Para cambiar:** un paso nuevo dentro de la corrida va entre los `EXEC` del `TRY` (si toca el DAT, el retroceso lo cubre). Un paso que escriba fuera de SQL Server (CYBER, disco, correo) va después del `CATCH`, en su propio `TRY/CATCH`. Pruebas: el escenario de asignación de `tests/pruebas.sql` (corridas 1 y 2 sobre los datos de `tests/generar_datos_prueba.py`).
