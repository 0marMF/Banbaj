USE [BNABAJ_486];
/* Pruebas de entorno · 8 de 8 · Apagar el modo de prueba
   Repone los parámetros (correos, CYBER, carpetas) y vuelve a prender los jobs que estaban prendidos.
   Después borra la carpeta de prueba: trae datos de clientes. */
EXEC ops.sp_prueba_modo @activar = 0;

/* Comprobación: en producción CORREO_PRUEBA_PARA va vacío y CYBER_SOLO_LECTURA en 0 */
SELECT CLAVE, VALOR FROM cfg.PARAMETRO WHERE CLIENTE = '486' AND CLAVE IN ('CORREO_PRUEBA_PARA', 'CYBER_SOLO_LECTURA');
SELECT name, enabled FROM msdb.dbo.sysjobs WHERE name LIKE N'Banbaj 486%';
