USE [BNABAJ_486];
/* Pruebas de entorno · 5 de 8 · Lectura de archivos (no toca el DAT)
   Lee y valida cada archivo (layout y reglas de datos, incluidas las de duplicados) como lo haría el proceso, sin
   tocar el DAT. Deja una corrida PRUEBA cancelada en la bitácora. Si algo "DETENDRÍA LA CORRIDA", corrígelo antes
   del paso 6 (archivo, layout con cfg.sp_layout_cambiar o catálogo con cfg.sp_catalogo_alta). */
DECLARE @fecha DATE = CAST(GETDATE() AS DATE);
EXEC ops.sp_prueba_lectura @proceso = 'ACT',  @fecha = @fecha;
EXEC ops.sp_prueba_lectura @proceso = 'ASIG', @fecha = @fecha;
