USE [BNABAJ_486];
/* Pruebas de entorno · 1 de 8 · Encender el modo de prueba
   - Todos los correos van solo a @correo, con [PRUEBA] en el asunto.
   - Ningún script se ejecuta en CYBER (las consultas sí).
   - Los archivos se escriben en @carpeta (créala antes; no uses SALIDA ni la carpeta de MIS).
   - Se apagan los jobs "Banbaj 486 diario" y "Banbaj 486 ladas".
   Cambia @correo y, si quieres, @carpeta. */
DECLARE @correo  NVARCHAR(400) = N'tu.correo@sertec.com.mx',
        @carpeta NVARCHAR(400) = N'C:\BANBAJ\486\PRUEBA\';
EXEC ops.sp_prueba_modo @activar = 1, @correo = @correo, @carpeta = @carpeta;
