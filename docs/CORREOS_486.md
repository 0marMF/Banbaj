# Correos del cliente 486

Cada correo es una plantilla (`mail.PLANTILLA`) con su lista de destinatarios (`mail.LISTA` / `mail.DESTINATARIO`). Para cambiar a quién le llega un correo se edita la lista; no hay que tocar código.

Todos llevan la firma de Asignaciones y el aviso de confidencialidad.

**Formato:** el del ejemplo que compartió el equipo (`Documento1.txt` en Banbaj_banc), con el buzón del 486 en la firma (`asig.486.cdmx@sertec.com.mx`, Tel. (0155) 7099 0104, Ext. 1416). Usa los colores de BanBajío:

| Uso | Color |
|---|---|
| Encabezado del correo y de las tablas | Morado del logotipo `#a54686` |
| Franja de los correos de alerta (importancia alta) y línea de la firma | Rojo del logotipo `#ed1c24` |
| Enlaces secundarios | Morado oscuro `#7d3466` |
| Fondo, tarjeta, texto y bordes | Grises del formato de ejemplo (`#f0f2f5`, `#f8fafc`, `#475569`, `#e2e8f0`) |

Cada correo tiene un título en el encabezado (por ejemplo "Asignación realizada" o el tipo de hallazgo), el texto principal y una tarjeta con el detalle. El cuerpo lo arma el código (`tools/generar_sql_486.py`, función `cuerpo_correo`) y la semilla lo actualiza en cada instalación. El asunto, la lista y la importancia los puede cambiar el equipo sin que la semilla los pise.

## Asignación

| Correo | Plantilla | Cuándo | Para | Copia oculta |
|---|---|---|---|---|
| **Inicio de asignación** | `INICIO_ASIG_486` | Solo, al arrancar la asignación. Dice la hora en que llegó la base | erika.ramos, administrativo.mc4, administrativo.mc5, supervisor.mc4, supervisorbackoffice.mc | asignaciones.cdmx1, asignaciones3, asig.cdmx |
| **Fin de asignación** | `CONFIRMACION_ASIG_486` | Solo, al terminar OK la depuración de correos y teléfonos en CYBER (`ops.sp_confirmar_asignacion`). A mano: `EXEC ops.sp_avisar @id, 'CONFIRMACION_ASIG_486'` | Los mismos del inicio | Los mismos del inicio |
| **Asignación grande** | `ALERTA_NUEVAS_486` | Solo, si llegan más de 100 cuentas nuevas (parámetro) | supervisor.aem.cdmx4, aem.control1, aem.proyectos1, aem.consultoria1, supervisor.aem.cdmx2 | asig.cdmx |

## Devolución (un solo correo)

Uno para cualquier retiro: asignación, actualización o retiro por solicitud.

| Copia | Plantilla | Para | Copia oculta | Adjunto |
|---|---|---|---|---|
| Operación | `DEVOLUCION_486` | soluciones.486, supervisor.mc, supervisor.mc3, supervisorbackoffice.mc, soluciones_banbajio | asignaciones.cdmx1, asignaciones3, asig.cdmx | ZIP con contraseña `C:\RETIROS_PAG_486_<fecha><hora>.zip` |
| AEM | `DEVOLUCION_486_AEM` | — | aem.control1, supervisor.aem.cdmx, supervisor.aem.cdmx2, supervisor.aem.cdmx3, supervisor.aem.cdmx4, aem.operativa1, aem.operativa2, aem.entregables1 | Sin ZIP |

- **Asunto:** `Devolucion del cliente BANCO BAJIO dd/mm/aaaa`
- **Texto:** "Archivo de devolución actualizado (asignación / actualización / retiro por solicitud), favor de verificar." Incluye cuántas cuentas se devolvieron.
- **Por qué son dos envíos:** el correo de SQL Server (Database Mail) manda el mismo adjunto a todos los destinatarios de un correo. Para que AEM no reciba el ZIP, sale una copia igual sin adjunto y con AEM solo en copia oculta.
- **Cómo se manda:** solo, al cerrar el retiro (`ops.sp_retiro_cerrar`). A mano: `EXEC ops.sp_exportar_salidas @id, @zip = 'RETIROS', @enviar_zip = 1`. O suelto: `EXEC ops.sp_aviso_devolucion @id, N'C:\RETIROS_PAG_486_….zip'`.

## Al equipo de asignaciones (salen solos)

| Correo | Plantilla | Cuándo |
|---|---|---|
| Archivos listos para arribar | `ARCHIVOS_LISTOS_486` | En cuanto se escriben los planos que se suben a CYBER: carpeta, archivos con sus líneas y qué sigue. Otro aviso cuando aparece `SCBACTH_SINTEL.TXT` |
| Hallazgos | `HALLAZGO_486` | Lo que el proceso no resolvió solo: retiro sobre el tope de 50 %, pagos que no subieron a las 17:00, cualquier paso automático con error. Trae una tabla con el detalle y el comando para resolverlo |
| Validación de la entrada | `VALIDACION_ENTRADA_486` | La actualización o la asignación se detuvo antes de tocar el DAT: falta un encabezado (cambió el layout), un valor no está en el catálogo o una regla de datos superó su tolerancia. Trae los encabezados que faltan, los encabezados nuevos del archivo, las anomalías con ejemplos enmascarados, qué hacer y el comando para volver a correr |

Diagrama de todos los correos: `docs/flujo/07_correos.md`.

## Validaciones (salen solas)

| Correo | Plantilla | Cuándo | Para |
|---|---|---|---|
| Consumo con saldo actual ≤ 0 | `ALERTA_SDO_ACT_CONS_486` | La base maestra de Consumo trae cuentas con SDO_ACT ≤ 0. El proceso sigue | Lista de Operación (la del inicio) |
| Pagos negativos | `PAGOS_NEGATIVOS_486` | Llegan pagos negativos: no se arriban, se manda la lista y el proceso sigue | Equipo de asignaciones: buzón asig.486.cdmx, con copia oculta a asignaciones.cdmx1, asignaciones3 y asig.cdmx |
| Base maestra con números cortados por Excel | `MAESTRA_NUMEROS_EXCEL_486` | La base se guardó con cuentas en notación científica (1.23457E+15). La asignación se detiene | Buzón asig.486.cdmx + equipo de asignaciones |
