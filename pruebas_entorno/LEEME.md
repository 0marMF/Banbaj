# Pruebas de entorno (antes de producción)

Guía en Word (dónde dejar los archivos del banco y cada paso): `Guia de pruebas de entorno Banbaj 486.docx`.

Scripts para probar en el servidor que todo lo de afuera responde antes de prender el job: CYBER, correo, carpetas del banco, lectura de archivos y una asignación completa que después se revierte. Se corren en SSMS, en orden, sobre `BNABAJ_486`, con los scripts de `sql/` ya instalados (incluido `sql/85_sp_pruebas_entorno.sql`).

| # | Script | Qué prueba | ¿Toca algo? |
|---|---|---|---|
| 1 | `01_modo_prueba_encender.sql` | Enciende el modo de prueba | Parámetros y jobs (se reponen en el 8) |
| 2 | `02_bajada_cyber.sql` | Servidor vinculado y cada tabla de CYBER que usa Banbaj; las bajadas reales | Solo tablas de paso de SQL Server |
| 3 | `03_correos.sql` | Perfil de Database Mail, plantillas y un correo real | Un correo a tu dirección |
| 4 | `04_deteccion_archivos.sql` | Carpeta del día, archivo que encuentra cada patrón, qué haría el job | Nada |
| 5 | `05_lectura_archivos.sql` | Lectura y validación de cada archivo (layout, datos, duplicados) | Una corrida PRUEBA cancelada; no toca el DAT |
| 6 | `06_asignacion_prueba.sql` | Actualización y asignación completas con los archivos reales | El DAT (se revierte en el 7) |
| 7 | `07_revertir_prueba.sql` | Revierte lo del paso 6 | Deja el DAT como estaba |
| 8 | `08_modo_prueba_apagar.sql` | Repone parámetros y jobs | — |

**Qué hace el modo de prueba** (`ops.sp_prueba_modo`):

- `CORREO_PRUEBA_PARA`: todos los correos van solo a tu dirección, con `[PRUEBA]` en el asunto.
- `CYBER_SOLO_LECTURA = 1`: ningún script se ejecuta en CYBER (retiro, actualización, depuraciones, banderas). Queda en la bitácora como `CYBER EJECUTA` en AVISO. Las consultas a CYBER sí se hacen.
- `RUTA_SALIDA`, `RUTA_MIS` y `CARPETA_ZIP` apuntan a la carpeta de prueba: no se escribe en SALIDA ni en la carpeta de MIS.
- Apaga los jobs y recuerda cuáles estaban prendidos.

**Cuidado:**

- No dejes el modo de prueba encendido: el paso 8 lo apaga. Si lo olvidas, en producción no saldría ningún correo a asignaciones ni se escribiría nada en CYBER.
- Con el modo de prueba encendido, cada actualización o asignación queda anotada al empezar (`ops.PRUEBA_CORRIDA`). Así el paso 7 la revierte aunque el paso 6 se corte.
- La reversión del paso 7 solo funciona si después de la prueba no corrió otra asignación o actualización.
- Ninguna prueba imprime cuentas, nombres, teléfonos ni correos: solo conteos, nombres de archivo y mensajes de la bitácora (enmascarados). Al terminar borra la carpeta de prueba.
- El paso 6 hace la asignación de esa fecha. Si ya hay una actualización OK de ese día, la usa y no la revierte.
- Ya en producción, `sql/instalacion/06_limpiar_pruebas.sql` borra los stores y tablas de estas pruebas (primero con `@confirmar = 0`).
