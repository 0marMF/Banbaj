# 486 · Pendientes

Lo que falta para cerrar el 486. Lo que ya está hecho no se lista aquí; su detalle está en los demás documentos de `docs/`.

## Antes de migrar

- [ ] **Riesgos duplicados en el DAT de FoxPro:** se corrigen en FoxPro y después se hace la migración.
- [ ] **Cuentas TDC sin RIESGO:** al migrar se quedan con la llave de antes y no se reconocen en la siguiente base (salen como devolución y entran como nuevas). Revisar el resumen de `ops.sp_llave_riesgo_migrar` antes de aplicarlo.
- [ ] **Largo del ACC_NUM:** la llave mide 20. Si algún ACC_NUM real pasa de 20 dígitos o trae letras, la regla `DIGITOS` detiene la asignación; confirmar con una base real (prueba de lectura, `pruebas_entorno/05`).

## Instalación en CYBER (DBA)

- [ ] Instalar `cyber/486/oracle/JSP_CORREOS_486.sql`.
- [ ] Instalar `cyber/486/oracle/JSP_TELEFONOS_REMESA_486.sql`.
- [ ] Instalar `cyber/486/oracle/JSP_TELEFONOS_DEPURA_486.sql` (tabla `RCVRY.JSP_TAB_TEL_DEPURA_486` y store) y dar `SELECT` en `RCVRY.PHONE` al usuario de `CYBER_ORACLE`. Mientras tanto, `TEL_DEPURACION = ACTUAL`.
- [ ] Confirmar que `RCVRY.PHNVAL` es el esquema que copia el job (`CYBER_TABLA_LADAS`) y que el usuario de `CYBER_ORACLE` tiene `SELECT`.
- [ ] Confirmar que `RCVRY.JSP_VALIDADOR_TELEFONOS` no tiene más columnas obligatorias que CLIENTE, FECHA y TOTAL_TELS.

## Arribo a CYBER

- [ ] Confirmar las columnas de las remesas contra `LOAD_TEL_REMESA.CTL` y `LOAD_MAIL_REMESA.CTL` (parámetros `CYBER_REMESA_TEL_COLUMNAS` y `CYBER_REMESA_MAIL_COLUMNAS`).
- [ ] Probar en CYBER con `@solo_mostrar = 1` y luego una corrida real con el arribo automático encendido.
- [ ] Primera corrida con `DIFERENCIA`: revisar el renglón `TEL DIFERENCIA` antes de dejar seguir al job. Si el freno de 30 % (`TEL_DEPURA_MAX_INACTIVAR_PCT`) detiene la primera corrida por lo acumulado de días anteriores, revisarlo y ajustarlo solo esa vez.
- [ ] Vigilar `CRUCE_DAT` (30 %) con unas semanas de archivos reales; si el banco manda saldos de cuentas que no son nuestras, subir la tolerancia.
- [ ] Vigilar los primeros días con dos asignaciones: el arribo da los saldos por subidos cuando las cuentas con `DMHOSTUP` del día igualan las del SCBSDOS, y en la segunda asignación eso podría pasar antes de tiempo.
- [ ] Confirmar con el equipo de asignaciones que los dos SCBSDOS del mismo día no estorban.
- [ ] Opcional: estructura de `PHONE_G1` para usar el sello de fecha y hora del SCBTEL (`FECHA_G`, `FECHA_A`) como señal, o insertar ahí directamente y dejar de subir el SCBTEL.

## Limitaciones conocidas

- Un teléfono que un gestor agregue entre la foto y el store (minutos) se queda activo hasta la siguiente asignación.
- `ABAN_SR` se lee de `RPT_DAT_486_1` como la deja la última corrida de `PROC_DAT_486` en CYBER; si nadie la corre, el dato se queda viejo.
- Los archivos de ancho fijo (SCBSDOS, SCBTEL, SCBPAG, gescar) se suben a mano.
- La copia de `MX_G1MCT_DVBJIG_*` a `\\192.168.50.1\Cyber_00\dev\` se hace a mano: el servidor no tiene acceso.

## Bases de entrada

- [ ] **Hipotecario:** no hay archivo de ejemplo. Como cualquier encabezado que falte detiene la corrida, el primer archivo probablemente va a parar la asignación hasta que el equipo ajuste la matriz con `cfg.sp_layout_cambiar`. Conviene pasar un ejemplo antes.
- [ ] **Hipotecario, ETIQUETA6:** el banco dio solo la regla de TDC y Consumo. La base de Hipotecario trae `ENFOQUE_RESTRUCTURA` (sin la segunda E). Cuando la confirmen, se agrega el catálogo `ETIQUETA6_HIPO` y la columna en el layout.
- [ ] **Saldos de Hipotecario** (`SERTEC_Saldos_Hip`): todavía no se recibe del banco; la carga queda apagada hasta tener un ejemplo.
- [ ] **Catálogos de TDC:** solo se conocen los estatus CCAS, VEN2, VEN3, VEN4 (y BCOB, BOPE, FALL de reestructura). Si llega otro (por ejemplo VEN1), la asignación se detiene hasta agregarlo con `cfg.sp_catalogo_alta 'ESTATUS_TDC', N'VEN1', N''`.
- [ ] **Tolerancias de `cfg.VALIDACION_DATO`:** revisarlas con el equipo después de unas semanas (`SELECT * FROM ops.VALIDACION_ENTRADA ORDER BY ID DESC;`).

## ETIQUETA6

- [ ] **Primer blanqueo real:** el primer día puede blanquear muchas cuentas que ya traían el REE puesto a mano con un tramo que ya no es elegible. Revisar el renglón `ETIQUETA6 BLANQUEO` de la bitácora y `ops.ETIQUETA6_BLANQUEO` con Jesús Vargas antes de subir el `ACT_PVS_REE`.
- [ ] **Tramos nuevos del banco:** un tramo que no está en `ETIQUETA6_SEG_*` blanquea y deja un AVISO. Si es elegible, darlo de alta con destino `SI`.

## Correos y formato

- [ ] **Teléfono de la firma:** el formato del equipo trae (0155) 7099 0104 Ext. 1416; la firma anterior tenía (55) 5276 8513. Confirmar cuál va.
- [ ] **Colores:** morado `#a54686` y rojo `#ed1c24` salen de fuentes públicas del logotipo de BanBajío; si el banco o SERTEC tienen un manual de marca, ajustar `COLOR` en `tools/generar_sql_486.py`.

## Operación

- [ ] **Días festivos:** el T-1 de pagos solo distingue fin de semana. ¿Se agrega un calendario de días inhábiles (después de un festivo, T-1 sería el último día hábil)?
- [ ] **Limpieza:** correr `sql/instalacion/05_limpiar_migracion.sql` y `06_limpiar_pruebas.sql` cuando ya no se vaya a migrar ni probar.
