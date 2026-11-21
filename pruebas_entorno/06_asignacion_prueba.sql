USE [BNABAJ_486];
/* Pruebas de entorno · 6 de 8 · Actualización y asignación de prueba
   Con el modo de prueba encendido corre la actualización (si ese día no hay una OK) y la asignación de la fecha,
   con los archivos reales de su carpeta. CYBER no se toca, los correos llegan solo a la dirección de prueba y los
   archivos quedan en la carpeta de prueba. Muestra un resumen de cada corrida (solo conteos).
   Revisa: estatus OK, altas NVA y REA, retiros, líneas de cada archivo, scripts de CYBER armados, correos.
   Si llegó solo un segmento, también puedes probar el segundo: deja su base en la carpeta y vuelve a correr
   EXEC ops.sp_prueba_asignacion (hace otra asignación solo con ese segmento). */
DECLARE @fecha DATE = CAST(GETDATE() AS DATE);
EXEC ops.sp_prueba_asignacion @fecha = @fecha;

/* Las corridas de la prueba y el detalle de cualquiera:
SELECT * FROM ops.PRUEBA_CORRIDA;
EXEC ops.sp_prueba_resumen <corrida>;
SELECT PASO, ESTATUS, REGISTROS, MENSAJE FROM ops.BITACORA WHERE ID_CORRIDA = <corrida> ORDER BY ID;
*/
