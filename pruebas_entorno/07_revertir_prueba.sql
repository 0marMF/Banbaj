USE [BNABAJ_486];
/* Pruebas de entorno · 7 de 8 · Revertir la prueba
   Deja el DAT, el histórico, los folios, los pagos y las bases maestras como antes del paso 6.
   Primero corre así para ver qué va a revertir; después cambia @confirmar a 1. */
EXEC ops.sp_prueba_revertir @confirmar = 0;
-- EXEC ops.sp_prueba_revertir @confirmar = 1;
