USE [BNABAJ_486];
/* Pruebas de entorno · 4 de 8 · Detección de archivos
   Para la fecha indicada: la carpeta del día de cada archivo, si el servicio de SQL Server la puede leer, qué archivo
   encuentra con su patrón y qué haría el job. Al final, si existe la carpeta de salida.
   Usa una fecha cuya carpeta ya tenga los archivos del banco (actualización y, si quieres probar la asignación, bases maestras). */
DECLARE @fecha DATE = CAST(GETDATE() AS DATE);
EXEC ops.sp_prueba_archivos @fecha = @fecha;
