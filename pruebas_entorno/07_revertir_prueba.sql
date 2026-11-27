USE [BNABAJ_486];
/* Pruebas de entorno · 7 de 8 · Revertir la prueba
   Deja el DAT, el histórico, los folios, los pagos y las bases maestras como antes del paso 6.
   Primero corre así para ver qué va a revertir; después cambia @confirmar a 1.

   Validación (26/11): la lista trae las corridas anotadas y también las actualizaciones y asignaciones que
   arrancaron con el modo de prueba encendido aunque no estén anotadas (columna ORIGEN). Revisa que estén
   todas las del paso 6 antes de confirmar. Si falta una (por ejemplo, ya apagaste el modo de prueba),
   agrégala con @anotar_corrida. Una corrida EN_PROCESO se cierra antes:
     EXEC ops.sp_corrida_finalizar <corrida>, 'ERROR', N'Se cortó en la prueba de entorno'; */
EXEC ops.sp_prueba_revertir @confirmar = 0;
-- EXEC ops.sp_prueba_revertir @confirmar = 1;
-- EXEC ops.sp_prueba_revertir @confirmar = 0, @anotar_corrida = <corrida>;   -- si falta una en la lista
