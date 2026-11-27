USE [BNABAJ_486];
/* =====================================================================
   Limpieza de las pruebas de entorno (cuando ya se está en producción)
   ---------------------------------------------------------------------
   Borra lo que se instaló para las pruebas de pruebas_entorno/
   (sql/85_sp_pruebas_entorno.sql):

     Stores:  ops.sp_prueba_modo, sp_prueba_cyber, sp_prueba_correo,
              sp_prueba_archivos, sp_prueba_lectura, sp_prueba_resumen,
              sp_prueba_asignacion, sp_prueba_revertir (todos los ops.sp_prueba_*)
     Tablas:  ops.PRUEBA_PARAM, ops.PRUEBA_CORRIDA
     Datos:   las corridas de lectura de prueba (PROCESO = 'PRUEBA', las del
              paso 5) con su bitácora, archivos cargados, validaciones,
              rechazos y correos (@borrar_corridas_prueba = 1)

   Las corridas ACT y ASIG del paso 6 son corridas normales: el paso 7 ya las
   revirtió y quedan en la bitácora como REVERTIDA. No se borran.
   Los parámetros CORREO_PRUEBA_PARA y CYBER_SOLO_LECTURA se quedan (vacío y 0):
   el envío de correos y CYBER los leen.

   Deja PRUEBAS_LIMPIAS = 1: sql/85_sp_pruebas_entorno.sql ya no vuelve a crear
   nada, así que se puede seguir corriendo sql/*.sql completo al actualizar.
   Para volver a probar: borra ese parámetro y corre sql/85_sp_pruebas_entorno.sql.

   Cómo se corre:
     1. Con @confirmar = 0 (como viene): solo muestra lo que borraría.
     2. Cambia @confirmar a 1 y vuelve a correrlo.
     3. Borra la carpeta de prueba (C:\BANBAJ\486\PRUEBA\): trae datos de clientes.

   Se detiene sin borrar nada si:
     - hay una corrida en proceso;
     - el modo de prueba sigue encendido (corre pruebas_entorno/08_modo_prueba_apagar.sql);
     - CORREO_PRUEBA_PARA tiene una dirección o CYBER_SOLO_LECTURA está en 1;
     - hay corridas de la asignación de prueba sin revertir (corre
       pruebas_entorno/07_revertir_prueba.sql; si esas corridas se quedan a
       propósito, vacía ops.PRUEBA_CORRIDA antes).
   Errores 50950-50959
   ===================================================================== */
SET NOCOUNT ON;
SET XACT_ABORT ON;
DECLARE @confirmar              BIT = 0;   -- 0 = vista previa; 1 = borrar
DECLARE @borrar_corridas_prueba BIT = 1;   -- 1 = también las corridas PROCESO = 'PRUEBA' y lo que dejaron

DECLARE @cliente VARCHAR(10) = '486', @s NVARCHAR(2000), @i INT = 1, @total INT, @n INT = 0, @filas INT = 0, @f INT;
DECLARE @obj TABLE (ORDEN INT IDENTITY(1,1), TIPO NVARCHAR(20), OBJETO NVARCHAR(300), SENTENCIA NVARCHAR(1000));
DECLARE @datos TABLE (ORDEN INT IDENTITY(1,1), TABLA NVARCHAR(300), SENTENCIA NVARCHAR(2000), FILAS INT NULL);
DECLARE @corridas TABLE (ID_CORRIDA INT PRIMARY KEY);

IF EXISTS (SELECT 1 FROM ops.CORRIDA WHERE CLIENTE = @cliente AND ESTATUS = 'EN_PROCESO')
    THROW 50950, 'Hay una corrida en proceso; espera a que termine.', 1;
IF OBJECT_ID('ops.PRUEBA_PARAM') IS NOT NULL
   AND EXISTS (SELECT 1 FROM ops.PRUEBA_PARAM)
    THROW 50951, 'El modo de prueba sigue encendido: corre pruebas_entorno/08_modo_prueba_apagar.sql. No se borró nada.', 1;
IF EXISTS (SELECT 1 FROM cfg.PARAMETRO WHERE CLIENTE = @cliente
           AND ((CLAVE = 'CORREO_PRUEBA_PARA' AND NULLIF(LTRIM(RTRIM(VALOR)), N'') IS NOT NULL)
             OR (CLAVE = 'CYBER_SOLO_LECTURA' AND VALOR = N'1')))
    THROW 50952, 'CORREO_PRUEBA_PARA tiene una dirección o CYBER_SOLO_LECTURA está en 1: déjalos vacío y 0 (producción) antes de limpiar.', 1;
IF OBJECT_ID('ops.PRUEBA_CORRIDA') IS NOT NULL
   AND EXISTS (SELECT 1 FROM ops.PRUEBA_CORRIDA)
    THROW 50953, 'Hay corridas de la asignación de prueba sin revertir (ops.PRUEBA_CORRIDA): corre pruebas_entorno/07_revertir_prueba.sql o vacía la tabla si se quedan. No se borró nada.', 1;

/* Objetos */
INSERT INTO @obj (TIPO, OBJETO, SENTENCIA)
SELECT CASE o.type WHEN 'P' THEN N'Store' ELSE N'Tabla' END, s.name + N'.' + o.name,
       CASE o.type WHEN 'P' THEN N'DROP PROCEDURE ' ELSE N'DROP TABLE ' END + QUOTENAME(s.name) + N'.' + QUOTENAME(o.name) + N';'
FROM sys.objects o
JOIN sys.schemas s ON s.schema_id = o.schema_id
WHERE s.name = N'ops'
  AND ((o.type = 'P' AND o.name LIKE N'sp[_]prueba[_]%') OR (o.type = 'U' AND o.name IN (N'PRUEBA_PARAM', N'PRUEBA_CORRIDA')))
ORDER BY CASE o.type WHEN 'P' THEN 1 ELSE 2 END, o.name;
SET @total = @@ROWCOUNT;

/* Datos de las corridas de lectura de prueba: toda tabla de ops, stg o mail con columna ID_CORRIDA */
IF @borrar_corridas_prueba = 1
BEGIN
    INSERT INTO @corridas SELECT ID_CORRIDA FROM ops.CORRIDA WHERE CLIENTE = @cliente AND PROCESO = 'PRUEBA';
    IF EXISTS (SELECT 1 FROM @corridas)
    BEGIN
        INSERT INTO @datos (TABLA, SENTENCIA)
        SELECT s.name + N'.' + t.name,
               N'DELETE x FROM ' + QUOTENAME(s.name) + N'.' + QUOTENAME(t.name) + N' x WHERE x.ID_CORRIDA IN (SELECT ID_CORRIDA FROM ops.CORRIDA WHERE CLIENTE = ''486'' AND PROCESO = ''PRUEBA''); SET @f = @@ROWCOUNT;'
        FROM sys.tables t
        JOIN sys.schemas s ON s.schema_id = t.schema_id
        JOIN sys.columns c ON c.object_id = t.object_id AND c.name = N'ID_CORRIDA'
        WHERE s.name IN (N'ops', N'stg', N'mail')
          AND NOT (s.name = N'ops' AND t.name IN (N'CORRIDA', N'PRUEBA_PARAM', N'PRUEBA_CORRIDA'))
        ORDER BY s.name, t.name;
        /* La corrida al final */
        INSERT INTO @datos (TABLA, SENTENCIA)
        VALUES (N'ops.CORRIDA', N'DELETE FROM ops.CORRIDA WHERE CLIENTE = ''486'' AND PROCESO = ''PRUEBA''; SET @f = @@ROWCOUNT;');
    END;
END;

SELECT TIPO, OBJETO, CASE WHEN @confirmar = 1 THEN N'se borra' ELSE N'se borraría' END AS ACCION FROM @obj ORDER BY ORDEN;
SELECT (SELECT COUNT(*) FROM @corridas) AS CORRIDAS_PRUEBA_LECTURA, (SELECT COUNT(*) FROM @datos) AS TABLAS_CON_DATOS_A_REVISAR;

IF @confirmar = 0
BEGIN
    SELECT N'VISTA PREVIA' AS RESULTADO, @total AS OBJETOS,
           N'Cambia @confirmar a 1 y vuelve a correr el script.' AS NOTA;
    RETURN;
END;

BEGIN TRANSACTION;
/* Datos primero (las tablas de prueba se borran después) */
SET @i = 1;
WHILE @i <= (SELECT COUNT(*) FROM @datos)
BEGIN
    SELECT @s = SENTENCIA FROM @datos WHERE ORDEN = @i;
    SET @f = 0;
    EXEC sp_executesql @s, N'@f INT OUTPUT', @f = @f OUTPUT;
    UPDATE @datos SET FILAS = @f WHERE ORDEN = @i;
    SET @filas += @f;
    SET @i += 1;
END;
SET @i = 1;
WHILE @i <= @total
BEGIN
    SELECT @s = SENTENCIA FROM @obj WHERE ORDEN = @i;
    EXEC sp_executesql @s;
    SET @n += 1;
    SET @i += 1;
END;
IF EXISTS (SELECT 1 FROM cfg.PARAMETRO WHERE CLIENTE = @cliente AND CLAVE = 'PRUEBAS_LIMPIAS')
    UPDATE cfg.PARAMETRO SET VALOR = N'1' WHERE CLIENTE = @cliente AND CLAVE = 'PRUEBAS_LIMPIAS';
ELSE
    INSERT INTO cfg.PARAMETRO (CLIENTE, CLAVE, VALOR, DESCRIPCION)
    VALUES (@cliente, 'PRUEBAS_LIMPIAS', N'1', N'1 = ya se borró lo de las pruebas de entorno (sql/instalacion/06_limpiar_pruebas.sql): sql/85_sp_pruebas_entorno.sql no vuelve a crear nada');
COMMIT TRANSACTION;

SELECT TABLA, FILAS FROM @datos WHERE FILAS > 0 ORDER BY ORDEN;
SELECT N'PRUEBAS LIMPIAS' AS RESULTADO, @n AS OBJETOS_BORRADOS, @filas AS FILAS_BORRADAS,
       N'Borra también la carpeta de prueba (C:\BANBAJ\486\PRUEBA\): trae datos de clientes.' AS NOTA;
