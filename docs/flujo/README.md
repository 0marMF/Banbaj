---
title: "Banbaj 486 · Flujo y diagramas"
subtitle: "Cómo corre el proceso de punta a punta y dónde se cambia cada parte"
date: "Noviembre 2026"
---

# Cómo usar estos diagramas

Cada diagrama tiene tres partes:

- **La fuente**, en `docs/flujo/mmd/<nombre>.mmd` (texto Mermaid). Es lo que se edita.
- **La imagen**, en `docs/flujo/img/<nombre>.png` y `.svg`. Se genera con `./tools/generar_diagramas.sh`; no se edita a mano.
- **La explicación**, en `docs/flujo/<nombre>.md`: qué hace cada caja, qué procedimiento y archivo SQL la implementa, qué parámetros la controlan, qué deja en la bitácora, qué prueba la cubre y qué tocar para cambiarla.

| # | Diagrama | Para entender |
|---|---|---|
| 01 | [Vista general](01_vista_general.md) | De dónde llegan los archivos, qué hace SQL Server, qué se sube a CYBER y quién lo hace |
| 02 | [Flujo diario](02_flujo_diario.md) | Qué decide el job en cada vuelta de 30 minutos |
| 03 | [Asignación](03_asignacion.md) | Pasos de `ops.sp_asignacion_486` y lo que pasa al terminar |
| 04 | [Actualización](04_actualizacion.md) | Pasos de `ops.sp_actualizacion_486`, scripts en CYBER y cuadre |
| 05 | [Arribo a CYBER](05_arribo_cyber.md) | Cómo se detecta que subieron los planos y cómo corren las depuraciones |
| 06 | [Retiro](06_retiro.md) | Tope de 50 %, aplicación y cierre del retiro |
| 07 | [Correos](07_correos.md) | Qué correo sale, cuándo y a quién |
| 08 | [Migración](08_migracion.md) | De los DBF de FoxPro a las tablas de Banbaj |

# Cómo modificar un flujo con Claude Code

1. Pídele a Claude Code el cambio nombrando el flujo, por ejemplo: *"en el arribo a CYBER, que la confirmación espere también a que se suba el gescar"*. Claude Code lee `CLAUDE.md` en la raíz y, desde ahí, este índice y el diagrama del flujo.
2. El cambio se hace en el procedimiento que indica la explicación del diagrama, con su prueba en `tests/pruebas.sql`.
3. Se actualizan el `.mmd` y el `.md` del diagrama, y se regeneran las imágenes y los Word:

   ```bash
   ./tools/generar_diagramas.sh
   ./tools/generar_docs_word.sh
   ```

4. Se sube a una rama y se revisa que pasen las pruebas automáticas antes de pasarlo a `main`.

Para ver un diagrama mientras se edita, sin instalar nada: pegar el `.mmd` en <https://mermaid.live>. GitHub también muestra las imágenes en estos `.md`.

# Pasos de la bitácora

Cada caja de los diagramas deja un renglón en `ops.BITACORA` (columna `PASO`). Para seguir una corrida:

```sql
SELECT ID, PASO, ESTATUS, REGISTROS, MENSAJE FROM ops.BITACORA WHERE ID_CORRIDA = @id ORDER BY ID;
```

| Paso | Diagrama |
|---|---|
| CORRIDA, RESPALDO, HOMOLOGACION, ASIG UNIR LAYOUT, ASIG DEVOLUCION, ASIG EXISTENTES, ASIG TELEFONOS DAT, ASIG ALTA, TELEFONOS, TELEFONOS CYBER, CORREOS, SALIDA | 03 Asignación |
| ACT PREPARAR, ACT APLICAR, ACT PAGOS, SCRIPT PVS REE, ACT CYBER *script*, CUADRE AUTOMATICO, CUADRE PAGOS | 04 Actualización |
| ARRIBO BASE, ARRIBO CORREOS, ARRIBO TELEFONOS, CORREOS NUEVOS, CYBER BAJADA, CYBER EJECUTA, BLANQUEO AUTOMATICO, BLANQUEO STATUS, CONFIRMACION AUTOMATICA, ARRIBO FIN | 05 Arribo a CYBER |
| RETIRO AUTOMATICO, RETIRO, RETIRO ARCHIVOS, RETIRO CYBER, RETIRO DEVOL CYBER, RETIRO CERRAR | 06 Retiro |
| EXPORTAR ARCHIVOS, EXPORTAR AUTOMATICO, AVISO ARCHIVOS, CORREO, HALLAZGO | 07 Correos |
| RETROCESO, RETROCESO AUTOMATICO | Cualquier corrida que falla |
