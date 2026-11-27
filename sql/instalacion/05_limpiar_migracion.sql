USE [BNABAJ_486];
/* =====================================================================
   Limpieza de la migración (una sola vez, cuando ya se está en producción)
   ---------------------------------------------------------------------
   Borra las tablas y stores que solo sirvieron para pasar los DBF de
   FoxPro a SQL Server (sql/80_sp_migracion.sql):

     ops.sp_migrar_486            carga de los CSV exportados de FoxPro
     ops.sp_llave_riesgo_migrar   cambio de llave de TDC a riesgo (20/11)
     ops.fn_mig_faltan            revisión de columnas de los CSV
     stg.MIG_* y stg.vMIG_*       tablas y vistas de paso que hayan quedado

   No borra ops.sp_mig_leer ni ops.sp_mig_diagnostico (sql/18_sp_lectura_csv.sql):
   las cargas de exclusiones los siguen usando. Tampoco toca el DAT, el
   histórico, los pagos, las etiquetas ni las exclusiones que se migraron.

   Deja MIGRACION_LIMPIA = 1: sql/80_sp_migracion.sql ya no vuelve a crear
   nada, así que se puede seguir corriendo todos los scripts de sql/ al actualizar.

   Cómo se corre:
     1. Con @confirmar = 0 (como viene): solo muestra lo que borraría.
     2. Cambia @confirmar a 1 y vuelve a correrlo.
     3. Borra la carpeta de los CSV de la migración (C:\MIGRA486\): traen datos de clientes.

   Se detiene sin borrar nada si:
     - hay una corrida en proceso;
     - el DAT está vacío (la migración no se ha hecho);
     - todavía hay TDC sin cuenta del banco y no se ha corrido el cambio de llave
       por riesgo (EXEC ops.sp_llave_riesgo_migrar @confirmar = 1;).
   Errores 50940-50949
   ===================================================================== */
SET NOCOUNT ON;
SET XACT_ABORT ON;
DECLARE @confirmar BIT = 0;          -- 0 = vista previa; 1 = borrar

DECLARE @cliente VARCHAR(10) = '486', @s NVARCHAR(1000), @n INT = 0, @i INT = 1, @total INT;
DECLARE @obj TABLE (ORDEN INT IDENTITY(1,1), TIPO NVARCHAR(20), OBJETO NVARCHAR(300), SENTENCIA NVARCHAR(1000));

IF EXISTS (SELECT 1 FROM ops.CORRIDA WHERE CLIENTE = @cliente AND ESTATUS = 'EN_PROCESO')
    THROW 50940, 'Hay una corrida en proceso; espera a que termine.', 1;
IF NOT EXISTS (SELECT 1 FROM dat.DAT_486 WHERE CLIENTE = @cliente)
    THROW 50941, 'El DAT está vacío: la migración no se ha hecho. No se borró nada.', 1;
IF NOT EXISTS (SELECT 1 FROM cfg.PARAMETRO WHERE CLIENTE = @cliente AND CLAVE = 'LLAVE_RIESGO_MIGRADA')
   AND EXISTS (SELECT 1 FROM dat.DAT_486 WHERE CLIENTE = @cliente AND SEGMENTO2 = 'TDC' AND CTA_BANCO IS NULL)
    THROW 50942, 'Hay TDC sin CTA_BANCO y no se ha corrido el cambio de llave por riesgo: primero EXEC ops.sp_llave_riesgo_migrar @confirmar = 1;', 1;

/* Vistas primero, luego stores, funciones y tablas */
INSERT INTO @obj (TIPO, OBJETO, SENTENCIA)
SELECT CASE o.type WHEN 'V' THEN N'Vista' WHEN 'P' THEN N'Store' WHEN 'U' THEN N'Tabla' ELSE N'Función' END,
       s.name + N'.' + o.name,
       CASE o.type WHEN 'V' THEN N'DROP VIEW ' WHEN 'P' THEN N'DROP PROCEDURE ' WHEN 'U' THEN N'DROP TABLE ' ELSE N'DROP FUNCTION ' END
       + QUOTENAME(s.name) + N'.' + QUOTENAME(o.name) + N';'
FROM sys.objects o
JOIN sys.schemas s ON s.schema_id = o.schema_id
WHERE (s.name = N'ops' AND o.name IN (N'sp_migrar_486', N'sp_llave_riesgo_migrar', N'fn_mig_faltan'))
   OR (s.name = N'stg' AND o.type IN ('U', 'V') AND (o.name LIKE N'MIG[_]%' OR o.name LIKE N'vMIG[_]%'))
ORDER BY CASE o.type WHEN 'V' THEN 1 WHEN 'P' THEN 2 WHEN 'FN' THEN 3 WHEN 'IF' THEN 3 WHEN 'TF' THEN 3 ELSE 4 END, o.name;
SET @total = @@ROWCOUNT;

SELECT TIPO, OBJETO, CASE WHEN @confirmar = 1 THEN N'se borra' ELSE N'se borraría' END AS ACCION FROM @obj ORDER BY ORDEN;

IF @confirmar = 0
BEGIN
    SELECT N'VISTA PREVIA' AS RESULTADO, @total AS OBJETOS,
           N'Cambia @confirmar a 1 y vuelve a correr el script.' AS NOTA;
    RETURN;
END;

BEGIN TRANSACTION;
WHILE @i <= @total
BEGIN
    SELECT @s = SENTENCIA FROM @obj WHERE ORDEN = @i;
    EXEC sp_executesql @s;
    SET @n += 1;
    SET @i += 1;
END;
IF EXISTS (SELECT 1 FROM cfg.PARAMETRO WHERE CLIENTE = @cliente AND CLAVE = 'MIGRACION_LIMPIA')
    UPDATE cfg.PARAMETRO SET VALOR = N'1' WHERE CLIENTE = @cliente AND CLAVE = 'MIGRACION_LIMPIA';
ELSE
    INSERT INTO cfg.PARAMETRO (CLIENTE, CLAVE, VALOR, DESCRIPCION)
    VALUES (@cliente, 'MIGRACION_LIMPIA', N'1', N'1 = ya se borró lo de la migración (sql/instalacion/05_limpiar_migracion.sql): sql/80_sp_migracion.sql no vuelve a crear nada');
COMMIT TRANSACTION;

SELECT N'MIGRACION LIMPIA' AS RESULTADO, @n AS OBJETOS_BORRADOS,
       N'Borra también la carpeta de los CSV de la migración (C:\MIGRA486\): traen datos de clientes.' AS NOTA;
