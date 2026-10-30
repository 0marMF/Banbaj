# Correos del cliente 486: ¿cuáles se quedan?

Esta lista incluye todos los correos que mandan hoy los programas de FoxPro del 486, más los avisos nuevos que agrega Banbaj.
Marca con una **x** lo que decidas en cada uno (`[x] Mantener` o `[x] Eliminar`). Si un correo se queda pero quieres cambiar algo (destinatarios, texto, si se manda solo o a mano), anótalo en **Cambios**.

Hoy todos salen por CDO (SMTP 192.168.50.7) y casi todos esperan un "¿Deseas enviar…?" antes de mandarse. En Banbaj cada correo es una plantilla (`mail.PLANTILLA`) con su lista de destinatarios (`mail.LISTA`). Un correo que elimines se apaga en el catálogo, sin tocar código.

---

## A. Asignación (paso.prg)

### 1. Confirmación de asignación a Operación
| | |
|---|---|
| **Programa hoy** | `mail.prg`, llamado desde `paso.prg` |
| **Cuándo** | Al final de la asignación, si contestas "Sí" a *"¿Deseas enviar correo de confirmación de asignación a Operación?"* |
| **Asunto** | `Asignación BANCO BAJIO del día dd/mm/aaaa` |
| **Texto** | Se realiza asignación BANCO BAJIO. Favor de revisar y confirmar misma vía. |
| **Para** | erika.ramos, administrativo.mc4, administrativo.mc5, supervisor.mc4, supervisorbackoffice.mc |
| **CCO** | asignaciones.cdmx1, asignaciones3, asig.cdmx |
| **En Banbaj** | `CONFIRMACION_ASIG_486`, lista `OPERACION_ASIG_486`. Se manda a mano con `ops.sp_avisar` después de arribar a CYBER |

- [ ] Mantener  - [ ] Eliminar  · **Cambios:**

### 2. Asignación Express
| | |
|---|---|
| **Programa hoy** | `correo_486.prg`, llamado desde `paso.prg` |
| **Cuándo** | Al final de la asignación, si contestas "Sí" a *"¿Deseas enviar correo express?"* |
| **Asunto** | `Se realiza Asignacion Express Banco Bajio, dd/mm/aaaa` |
| **Texto** | Asignacion Banco Bajio en Cyber; dat actualizado en ftp, FAVOR DE CONSTRUIR. |
| **Para** | supervisor.mc5, erika.ramos |
| **CC** | carlos.landa, aem.control1, aem.consultoria1, aem.consultoria2, aem.consultoria3, aem.entregables1, supervisor.aem.cdmx, supervisor.aem.cdmx2, supervisor.aem.cdmx3, aem.operativa1, aem.operativa2 |
| **CCO** | asignaciones.cdmx1, asignaciones3, asig.cdmx |
| **En Banbaj** | `ASIG_EXPRESS_486`, lista `ASIG_EXPRESS_486`. A mano con `ops.sp_avisar` |

- [ ] Mantener  - [ ] Eliminar  · **Cambios:**

### 3. Alerta de asignación grande (más de 100 nuevas)
| | |
|---|---|
| **Programa hoy** | `aem_alerta.prg`, llamado desde `paso.prg` |
| **Cuándo** | Automático, si la asignación trae más de 100 cuentas nuevas (NVA) |
| **Asunto** | `Asignaciones grande de 486 dd/mm/aaaa` |
| **Texto** | Se recibe una asignacion con mas de 100 registros nuevos, favor de construir al finalizar. |
| **Para** | supervisor.aem.cdmx4, aem.control1, aem.proyectos1, aem.consultoria1, supervisor.aem.cdmx2 |
| **CCO** | asig.cdmx |
| **En Banbaj** | `ALERTA_NUEVAS_486`, lista `AEM_486`. Automático (el umbral de 100 es un parámetro) |

- [ ] Mantener  - [ ] Eliminar  · **Cambios:**

### 4. Cuentas nuevas de Consumo con saldo actual ≤ 0
| | |
|---|---|
| **Programa hoy** | `mail_sdo_act_cons.prg`, llamado desde `asig_bases.prg` |
| **Cuándo** | Automático, si la base maestra de Consumo trae cuentas con SDO_ACT ≤ 0 |
| **Asunto** | `EXISTEN CUENTAS NUEVAS DE CONSUMO CON SDO_ACT MENORES O IGUALES A CERO dd/mm/aaaa` |
| **Texto hoy** | *"Se realiza asignación BANCO BAJIO. Favor de revisar y confirmar misma vía."* (es el texto de mail.prg copiado: no dice nada del saldo) |
| **Para** | erika.ramos, administrativo.mc4, administrativo.mc5, supervisor.mc4, supervisorbackoffice.mc |
| **CCO** | asignaciones.cdmx1, asignaciones3, asig.cdmx |
| **En Banbaj** | `ALERTA_SDO_ACT_CONS_486`, lista `OPERACION_ASIG_486`. Automático; el texto ya explica el problema y trae el número de cuentas |

- [ ] Mantener  - [ ] Eliminar  · **Cambios:**

### 5. Devolución del cliente (en la asignación)
| | |
|---|---|
| **Programa hoy** | `devfianey.prg` (O:\ASIGNA), llamado por `prog15.prg`, que a su vez llama `paso.prg` |
| **Cuándo** | Automático, al terminar el retiro dentro de la asignación |
| **Asunto** | `Devolucion del cliente BANCO BAJIO <fecha>` |
| **Texto** | ARCHIVO DE DEVOLUCION ACTUALIZADO, FAVOR DE VERIFICAR. |
| **Para** | aem.control1, supervisor.aem.cdmx, supervisor.aem.cdmx2, supervisor.aem.cdmx3, supervisor.aem.cdmx4, aem.operativa1, aem.operativa2, aem.entregables1 |
| **CC** | asignaciones3, asignaciones.cdmx1, asig.cdmx |
| **En Banbaj** | `AVISO_DEVOLUCION_486`, lista `DEVOLUCION_AEM_486`. Recién agregado; a mano con `ops.sp_avisar` |

- [ ] Mantener  - [ ] Eliminar  · **Cambios:**

---

## B. Actualización de saldos y pagos (saldos.prg)

### 6. Los pagos no están actualizados (T-1)
| | |
|---|---|
| **Programa hoy** | `mail_pagos.prg`, llamado desde `saldos.prg` |
| **Cuándo** | Si el archivo de pagos no trae pagos del día anterior y contestas "Sí" a *"¿Deseas mandar correo de aviso?"* |
| **Asunto** | `Los pagos de la Boveda no estan actualizados dd/mm/aaaa` |
| **Texto hoy** | *"Se realiza asignación BANCO BAJIO…"* (mismo texto copiado de mail.prg) |
| **Para** | erika.ramos, administrativo.mc4, administrativo.mc5, supervisor.mc4, supervisorbackoffice.mc |
| **CCO** | asignaciones.cdmx1, asignaciones3, asig.cdmx |
| **En Banbaj** | `PAGOS_NO_ACTUALIZADOS_486`. Automático (regla `PAGOS_T1`, el lunes revisa el viernes), con texto corregido |

- [ ] Mantener  - [ ] Eliminar  · **Cambios:**

### 7. Retiros por actualización (con archivo adjunto)
| | |
|---|---|
| **Programa hoy** | Dentro de `saldos.prg` |
| **Cuándo** | Automático, después de generar los retiros de la actualización |
| **Asunto** | `Retiros actualizacion, dd/mm/aaaa` |
| **Texto** | Se comparte archivo retiro por actualizacion, FAVOR DE REVISAR. |
| **Adjunto** | `RETIROS_PAG_486_<fecha><hora>.zip` |
| **Para** | soluciones.486, supervisor.mc, supervisor.mc3, supervisorbackoffice.mc, soluciones_banbajio |
| **CCO** | asignaciones3, asig.cdmx, asignaciones.cdmx1 |
| **En Banbaj** | `RETIROS_ACT_486`. **Pendiente:** el correo de SQL Server puede adjuntar el archivo, pero falta decidir si va el .zip o el .txt directo |

- [ ] Mantener  - [ ] Eliminar  · **Cambios:**

### 8. Devolución del cliente (en la actualización)
Es el mismo correo que el **5** (`devfianey.prg` por medio de `prog15.prg`), pero llamado desde `saldos.prg` cuando contestas "Sí" a *"Devolución: revisa que tengas el archivo en C:\DEVOLUCION"*.

- [ ] Mantener  - [ ] Eliminar  · **Cambios:**

### 9. Notificación de actualización a Operación
| | |
|---|---|
| **Programa hoy** | `correo_486noti.prg`, llamado desde `saldos.prg` |
| **Cuándo** | Después de la devolución, si contestas "Sí" a *"Notificación para operación"* |
| **Asunto** | `Actualización de Banco Bajio, dd/mm/aaaa` |
| **Texto** | Se realiza actualización de Saldos, pagos y devolución del cliente 486. |
| **Para** | supervisor.mc4, erika.ramos |
| **CC** | supervisorbackoffice.mc3, **dministrativo.mc6** (le falta la "a": hoy ese correo rebota), supervisorbackoffice.mc2, supervisorbackoffice.mc, administrativo.mc4 |
| **CCO** | asignaciones.cdmx1, asignaciones3, asig.cdmx |
| **En Banbaj** | `NOTIFICACION_RETIRO_486`, lista `RETIROS_OPERACION_486` (ya con administrativo.mc6 bien escrito). A mano con `ops.sp_avisar` |

- [ ] Mantener  - [ ] Eliminar  · **Cambios:**

### 10. Actualización terminada
| | |
|---|---|
| **Programa hoy** | `correo.prg`, llamado desde `saldos.prg` |
| **Cuándo** | Al final, si contestas "Sí" a *"¿Deseas enviar correo?"* |
| **Asunto** | `Se realiza Actualizacion de Banco Bajio, dd/mm/aaaa` |
| **Texto** | Actualizacion de Banco Bajio en Cyber; dat actualizado en ftp, FAVOR DE REVISAR. |
| **Para** | administrativo.mc, administrativo.mc2, administrativo.mc3, supervisor.mc, supervisor.mc2, supervisor.mc3, supervisor.mc4, erika.ramos |
| **CC** | administrativo.mc6, supervisor.mc6, supervisorbackoffice.mc, administrativo.mc4 |
| **CCO** | asignaciones.cdmx1, asignaciones3, asig.cdmx |
| **En Banbaj** | `CONFIRMACION_ACT_486`, lista `ACTUALIZACION_486`. A mano con `ops.sp_avisar` |

- [ ] Mantener  - [ ] Eliminar  · **Cambios:**

> Los correos **9** y **10** salen el mismo día y a casi la misma gente. Si los juntas en uno, se ahorra un correo diario.

---

## C. Avisos nuevos de Banbaj (hoy no existen como correo)

Todos van a la lista `ASIGNACIONES_486` (buzón asig.486.cdmx con CCO al equipo), salvo el 11.

| # | Plantilla | Cuándo se manda | Hoy qué pasa | Decisión |
|---|---|---|---|---|
| 11 | `PAGOS_NEGATIVOS_486` | Llegan pagos negativos: no se arriban y se avisa a Operación con la lista | Aparece un mensaje en pantalla y se cancela el proceso; al cliente se le avisa a mano. **Falta definir los destinatarios** (hoy va al buzón) | [ ] Mantener [ ] Eliminar |
| 12 | `ERROR_PROCESO_486` | Cualquier proceso termina con error | Mensaje en pantalla | [ ] Mantener [ ] Eliminar |
| 13 | `DEVOLUCION_MASIVA_486` | La base maestra dejaría fuera más del % de `TOPE_DEVOLUCION_PCT` (hoy sin tope: no se dispara) | No existe | [ ] Mantener [ ] Eliminar |
| 14 | `MAESTRA_NUMEROS_EXCEL_486` | La base maestra se guardó como CSV con cuentas en notación científica (1.23457E+15) y se detiene la asignación | No existe (la macro lo evitaba) | [ ] Mantener [ ] Eliminar |

**Cambios / comentarios:**

---

## Notas para decidir

- **Automático o a mano.** Los correos que confirman algo a Operación (1, 2, 5/8, 9, 10) salen hoy solo si contestas "Sí", después de arribar a CYBER. Como Banbaj no arriba a CYBER, se quedan a mano con `ops.sp_avisar @id_corrida, '<PLANTILLA>'`. Las alertas (3, 4, 6, 11 a 14) salen solas.
- **Destinatarios.** Cada lista se edita en `mail.DESTINATARIO`. Si quieres cambiar a quién le llega, anótalo en **Cambios** y lo paso a la semilla.
- **Firma.** Todos llevan la firma de Asignaciones y el aviso de confidencialidad. La imagen de fondo de hoy (`C:\TOCAYO\IMAGE\F1.jpg`) no se ve fuera de las máquinas de SERTEC, así que no se migró.
