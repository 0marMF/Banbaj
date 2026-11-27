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

/* Validación (26/11): cada actualización y asignación de la prueba queda anotada desde que empieza.
   Las corridas del día y si están anotadas (si alguna sale "NO", el paso 7 la agrega igual; revisa que esté en su lista): */
SELECT c.ID_CORRIDA, c.PROCESO, c.ESTATUS, c.INICIO, c.FIN,
       CASE WHEN p.ID_CORRIDA IS NULL THEN 'NO' ELSE 'SI' END AS ANOTADA_PARA_REVERTIR
FROM ops.CORRIDA c LEFT JOIN ops.PRUEBA_CORRIDA p ON p.ID_CORRIDA = c.ID_CORRIDA
WHERE c.CLIENTE = '486' AND c.FECHA_PROCESO = @fecha ORDER BY c.ID_CORRIDA;

/* Si este script se corta (por ejemplo "A severe error occurred"), corre esto y guarda el resultado (solo conteos y mensajes):
SELECT ID_CORRIDA, PROCESO, ESTATUS, INICIO, FIN, LEFT(MENSAJE, 200) AS MENSAJE FROM ops.CORRIDA WHERE FECHA_PROCESO = CAST(GETDATE() AS DATE) ORDER BY ID_CORRIDA;
SELECT TOP (20) ID_CORRIDA, PASO, ESTATUS, REGISTROS, LEFT(MENSAJE, 300) AS MENSAJE, FECHA FROM ops.BITACORA ORDER BY ID DESC;
SELECT TOP (5) ID, PLANTILLA, ESTATUS, LEFT(ERROR, 300) AS ERROR, FECHA FROM mail.ENVIO ORDER BY ID DESC;
EXEC xp_readerrorlog 0, 1, N'Stack Dump';
EXEC xp_readerrorlog 0, 1, N'exception';
   Una corrida que quedó EN_PROCESO se cierra antes del paso 7:
EXEC ops.sp_corrida_finalizar <corrida>, 'ERROR', N'Se cortó en la prueba de entorno';
*/

/* Las corridas de la prueba y el detalle de cualquiera:
SELECT * FROM ops.PRUEBA_CORRIDA;
EXEC ops.sp_prueba_resumen <corrida>;
SELECT PASO, ESTATUS, REGISTROS, MENSAJE FROM ops.BITACORA WHERE ID_CORRIDA = <corrida> ORDER BY ID;
*/
