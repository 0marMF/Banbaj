# Correos del cliente 486

Decisiones del 29 y 30/10. Cada correo es una plantilla (`mail.PLANTILLA`) con su lista de destinatarios (`mail.LISTA` / `mail.DESTINATARIO`). Para cambiar a quién le llega un correo se edita la lista; no hay que tocar código.

Todos llevan la firma de Asignaciones y el aviso de confidencialidad.

## Los que se quedan

### Asignación

| Correo | Plantilla | Cuándo | Para | Copia oculta |
|---|---|---|---|---|
| **Inicio de asignación** (nuevo) | `INICIO_ASIG_486` | Solo, al arrancar la asignación. Dice la hora en que llegó la base | erika.ramos, administrativo.mc4, administrativo.mc5, supervisor.mc4, supervisorbackoffice.mc | asignaciones.cdmx1, asignaciones3, asig.cdmx |
| **Fin de asignación** (antes MAIL.prg) | `CONFIRMACION_ASIG_486` | A mano, después de arribar a CYBER: `EXEC ops.sp_avisar @id, 'CONFIRMACION_ASIG_486'` | Los mismos del inicio | Los mismos del inicio |
| **Asignación grande** (antes aem_alerta.prg) | `ALERTA_NUEVAS_486` | Solo, si llegan más de 100 cuentas nuevas (parámetro) | supervisor.aem.cdmx4, aem.control1, aem.proyectos1, aem.consultoria1, supervisor.aem.cdmx2 | asig.cdmx |

### Devolución (un solo correo)

Uno para cualquier retiro: asignación, actualización o retiro por solicitud. Sustituye a devfianey.prg, a "Retiros actualizacion" de saldos.prg y a la notificación de devolución en la actualización.

| Copia | Plantilla | Para | Copia oculta | Adjunto |
|---|---|---|---|---|
| Operación | `DEVOLUCION_486` | soluciones.486, supervisor.mc, supervisor.mc3, supervisorbackoffice.mc, soluciones_banbajio | asignaciones.cdmx1, asignaciones3, asig.cdmx | ZIP con contraseña `C:\RETIROS_PAG_486_<fecha><hora>.zip` |
| AEM | `DEVOLUCION_486_AEM` | — | aem.control1, supervisor.aem.cdmx, supervisor.aem.cdmx2, supervisor.aem.cdmx3, supervisor.aem.cdmx4, aem.operativa1, aem.operativa2, aem.entregables1 | Sin ZIP |

- **Asunto:** `Devolucion del cliente BANCO BAJIO dd/mm/aaaa`
- **Texto:** "Archivo de devolución actualizado (asignación / actualización / retiro por solicitud), favor de verificar." Incluye cuántas cuentas se devolvieron.
- **Por qué son dos envíos:** el correo de SQL Server (Database Mail) manda el mismo adjunto a todos los destinatarios de un correo. Para que AEM no reciba el ZIP, sale una copia igual sin adjunto y con AEM solo en copia oculta.
- **Cómo se manda:** al exportar los archivos de la corrida: `EXEC ops.sp_exportar_salidas @id, @zip = 'RETIROS', @enviar_zip = 1`. O suelto: `EXEC ops.sp_aviso_devolucion @id, N'C:\RETIROS_PAG_486_….zip'`.

### Validaciones (salen solas)

| Correo | Plantilla | Cuándo | Para |
|---|---|---|---|
| Consumo con saldo actual ≤ 0 (antes mail_sdo_act_cons.prg) | `ALERTA_SDO_ACT_CONS_486` | La base maestra de Consumo trae cuentas con SDO_ACT ≤ 0. El proceso sigue | Lista de Operación (la del inicio) |
| Pagos negativos | `PAGOS_NEGATIVOS_486` | Llegan pagos negativos: no se arriban, se manda la lista y el proceso sigue | Equipo de asignaciones: buzón asig.486.cdmx, con copia oculta a asignaciones.cdmx1, asignaciones3 y asig.cdmx |
| Base maestra con números cortados por Excel | `MAESTRA_NUMEROS_EXCEL_486` | La base se guardó con cuentas en notación científica (1.23457E+15). La asignación se detiene | Buzón asig.486.cdmx + equipo de asignaciones |

## Retirados

| Correo | Motivo |
|---|---|
| Asignación Express (correo_486.prg) | Decisión 30/10 |
| Pagos no actualizados a T-1 (mail_pagos.prg) | Decisión 29/10. La revisión sigue y queda en la bitácora, sin correo |
| Retiros por actualización (saldos.prg) | Se junta en el correo único de devolución |
| Devolución del cliente (devfianey.prg), en asignación y en actualización | Se junta en el correo único de devolución |
| Notificación de actualización a Operación (correo_486noti.prg) | Decisión 30/10 |
| Actualización terminada (correo.prg) | Decisión 30/10 |
| Error del proceso | Decisión 29/10. El error queda en `ops.CORRIDA` y `ops.BITACORA` |
| Devolución masiva (tope de devolución) | Decisión 29/10. Si se pone un tope, la asignación se detiene sin correo |
| Saldos no actualizados, saldos iguales al último DAT, pagos que no subieron | Decisión 29/10: los saldos siempre se actualizan y los pagos siempre suben |
