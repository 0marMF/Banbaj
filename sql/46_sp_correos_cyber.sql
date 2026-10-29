/* =====================================================================
   Banbaj · 46 Correos para CYBER (email.PRG + act_mail.prg)
   ---------------------------------------------------------------------
   ops.sp_correos arma, en la asignación, los correos del DAT (CORREO1 y
   CORREO2) para la remesa de CYBER: sub_mail.TXT (CUENTA2|CORREO), que se
   carga en RCVRY.JSP_TAB_MAIL_REMESA_486; luego RCVRY.JSP_CORREOS_486 purga
   y agrega (caja negra, como los teléfonos).

   Reglas de email.PRG:
   - se quitan espacios y se pasa a minúsculas
   - debe tener '@'
   - se descartan los "no tiene" (parámetro CORREOS_INVALIDOS)
   - un correo por cuenta
   - se quitan los de EMAILMALO (CORREOS_EXCLUIR_MALOS = 1; antes solo se
     quitaban de los INSERT directos)

   En CYBER, como hoy:
   1. Los correos nuevos se insertan directo en RCVRY.ADDRESS (email.sql):
      tools/bajar_cyber.py correos baja lo que ya tiene CYBER a stg.CYBER_CORREO
      y ops.sp_correos_nuevos arma los INSERT (MAIL_INSERTA_NUEVOS).
   2. Depuración (act_mail.prg): bandera de CYBER encendida, se vacía la
      remesa, se carga sub_mail.TXT, RCVRY.JSP_CORREOS_486 purga lo que ya no
      llega y se apaga la bandera (MAIL_ACTIVA_BANDERA … MAIL_INACTIVA_BANDERA).
   ===================================================================== */
SET NOCOUNT ON;
GO

CREATE OR ALTER PROCEDURE ops.sp_correos
    @id_corrida INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @cliente VARCHAR(10) = (SELECT CLIENTE FROM ops.CORRIDA WHERE ID_CORRIDA = @id_corrida);
    DECLARE @malos BIT = CASE WHEN ISNULL(cfg.fn_param(@cliente, 'CORREOS_EXCLUIR_MALOS'), '1') = '1' THEN 1 ELSE 0 END;
    DECLARE @bandera VARCHAR(10) = ISNULL(cfg.fn_param(@cliente, 'CYBER_BANDERA_CORREOS'), '416');
    DECLARE @inval TABLE (CORREO VARCHAR(100) PRIMARY KEY);
    INSERT INTO @inval
    SELECT DISTINCT LOWER(LTRIM(RTRIM(value))) FROM STRING_SPLIT(ISNULL(cfg.fn_param(@cliente, 'CORREOS_INVALIDOS'), ''), ',')
    WHERE LTRIM(RTRIM(value)) <> '';
    DECLARE @leidos INT, @sin_arroba INT, @no_tiene INT, @excluidos INT = 0, @repetidos INT, @n INT, @msg NVARCHAR(400);

    SELECT d.CUENTA, d.CUENTA2, v.N, LOWER(REPLACE(LTRIM(RTRIM(v.C)), ' ', '')) AS CORREO
    INTO #c
    FROM dat.DAT_486 d
    CROSS APPLY (VALUES (1, d.CORREO1), (2, d.CORREO2)) v(N, C)
    WHERE d.CLIENTE = @cliente AND d.CUENTA2 IS NOT NULL AND NULLIF(LTRIM(RTRIM(v.C)), '') IS NOT NULL;
    SET @leidos = @@ROWCOUNT;

    DELETE FROM #c WHERE CORREO NOT LIKE '%@%';
    SET @sin_arroba = @@ROWCOUNT;
    DELETE c FROM #c c WHERE EXISTS (SELECT 1 FROM @inval i WHERE i.CORREO = c.CORREO);
    SET @no_tiene = @@ROWCOUNT;
    IF @malos = 1
    BEGIN
        DELETE c FROM #c c
        WHERE EXISTS (SELECT 1 FROM cfg.EXCLUSION e WHERE e.CLIENTE = @cliente AND e.TIPO = 'CORREO' AND e.ACTIVO = 1
                        AND LOWER(e.VALOR) = c.CORREO AND (e.VALOR2 IS NULL OR e.VALOR2 IN (c.CUENTA, c.CUENTA2)));
        SET @excluidos = @@ROWCOUNT;
    END;
    ;WITH r AS (SELECT ROW_NUMBER() OVER (PARTITION BY CUENTA2, CORREO ORDER BY N) AS RN FROM #c)
    DELETE FROM r WHERE RN > 1;
    SET @repetidos = @@ROWCOUNT;

    DELETE FROM ops.CORREO WHERE ID_CORRIDA = @id_corrida;
    INSERT INTO ops.CORREO (ID_CORRIDA, CUENTA2, CORREO, CAMPO_DAT)
    SELECT @id_corrida, CUENTA2, LEFT(CORREO, 100), CONCAT('CORREO', N) FROM #c;
    SET @n = @@ROWCOUNT;

    SET @msg = CONCAT(N'Capturados: ', @leidos, N' · sin @: ', @sin_arroba, N' · "no tiene": ', @no_tiene,
                      N' · EMAILMALO: ', CASE WHEN @malos = 1 THEN CAST(@excluidos AS NVARCHAR(10)) ELSE N'no se aplica' END,
                      N' · repetidos: ', @repetidos, N' · a CYBER: ', @n);
    EXEC ops.sp_log @id_corrida, 'CORREOS', 'OK', @n, @msg;

    /* Scripts para CYBER (act_mail.prg): vaciar la remesa, cargar sub_mail.TXT con sqlldr y ejecutar el procedimiento */
    DELETE FROM ops.CYBER_SCRIPT WHERE ID_CORRIDA = @id_corrida AND SCRIPT IN ('MAIL_ACTIVA_BANDERA', 'MAIL_BORRA', 'MAIL_ACTUALIZA', 'MAIL_INACTIVA_BANDERA');
    /* Banderas de CYBER (ACTIVA_BANDERA.SQL / INACTIVA_BANDERA.SQL): se conservan */
    INSERT INTO ops.CYBER_SCRIPT (ID_CORRIDA, SCRIPT, NUM, SENTENCIA)
    VALUES (@id_corrida, 'MAIL_ACTIVA_BANDERA', 1, CONCAT(N'UPDATE RCVRY.RPT_LOG_CYBER_REG SET STATUS=1, ETAPA=''INICIA ACTUALIZACION ADDRESS 486'', ACTIVADO=SYSDATE  where id_proc=', @bandera, N';')),
           (@id_corrida, 'MAIL_ACTIVA_BANDERA', 2, CONCAT(N'INSERT INTO RCVRY.rpt_log_cyber VALUES(', @bandera, N',1,SYSDATE,''PRODUCCION'',''ACTUALIZANDO ADDRESS G1 486'');')),
           (@id_corrida, 'MAIL_ACTIVA_BANDERA', 3, N'COMMIT;'),
           (@id_corrida, 'MAIL_ACTIVA_BANDERA', 4, N'EXIT'),
           (@id_corrida, 'MAIL_INACTIVA_BANDERA', 1, CONCAT(N'INSERT INTO RCVRY.rpt_log_cyber VALUES(', @bandera, N',2,SYSDATE,''PRODUCCION'',''FINALIZA PROCESO ACTUALIZACION ADDRESS G1 486'');')),
           (@id_corrida, 'MAIL_INACTIVA_BANDERA', 2, CONCAT(N'UPDATE RCVRY.RPT_LOG_CYBER_REG SET STATUS=0, ETAPA=''FINALIZA ACTUALIZACION ADDRESS G1 486'' where id_proc=', @bandera, N';')),
           (@id_corrida, 'MAIL_INACTIVA_BANDERA', 3, N'COMMIT;'),
           (@id_corrida, 'MAIL_INACTIVA_BANDERA', 4, N'EXIT');
    INSERT INTO ops.CYBER_SCRIPT (ID_CORRIDA, SCRIPT, NUM, SENTENCIA)
    VALUES (@id_corrida, 'MAIL_BORRA', 1, N'TRUNCATE TABLE RCVRY.JSP_TAB_MAIL_REMESA_486;'),
           (@id_corrida, 'MAIL_BORRA', 2, N'COMMIT;'),
           (@id_corrida, 'MAIL_BORRA', 3, N'EXIT;'),
           (@id_corrida, 'MAIL_ACTUALIZA', 1, CONCAT(N'EXECUTE ', ISNULL(cfg.fn_param(@cliente, 'CYBER_PROC_CORREOS'), N'RCVRY.JSP_CORREOS_486'), N';')),
           (@id_corrida, 'MAIL_ACTUALIZA', 2, N'COMMIT;'),
           (@id_corrida, 'MAIL_ACTUALIZA', 3, N'exit;');
END;
GO

/* ---------------------------------------------------------------------
   Correos nuevos (email.PRG -> email.sql): los que no tiene CYBER se
   insertan directo en RCVRY.ADDRESS. Después de la asignación:
   1. python tools/bajar_cyber.py correos --corrida <asignación> … (correos tipo 3 del 486
      a stg.CYBER_CORREO y ejecuta este procedimiento; sin archivos en la máquina).
   2. Correr cyber/MAIL_INSERTA_NUEVOS.sql y luego la depuración (banderas y remesa).
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE ops.sp_correos_nuevos
    @id_corrida      INT,
    @cyber_sin_datos BIT = 0      -- 1 = la consulta a CYBER sí corrió y no trajo correos (todos son nuevos)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @cliente VARCHAR(10), @proceso VARCHAR(10), @fecha DATE;
    SELECT @cliente = CLIENTE, @proceso = PROCESO, @fecha = FECHA_PROCESO FROM ops.CORRIDA WHERE ID_CORRIDA = @id_corrida;
    IF @proceso IS NULL OR @proceso <> 'ASIG' THROW 50640, 'Indica una corrida de asignación.', 1;
    IF NOT EXISTS (SELECT 1 FROM ops.CORREO WHERE ID_CORRIDA = @id_corrida) THROW 50641, 'Esa corrida no tiene correos (ops.sp_correos).', 1;

    /* Si la tabla de paso viene vacía y no se confirmó, se detiene: insertaría correos que CYBER ya tiene */
    IF NOT EXISTS (SELECT 1 FROM stg.CYBER_CORREO) AND @cyber_sin_datos = 0
        THROW 50642, 'stg.CYBER_CORREO está vacía: baja primero los correos de CYBER (tools/bajar_cyber.py correos).', 1;

    DELETE FROM ops.CORREO_CYBER WHERE ID_CORRIDA = @id_corrida;
    INSERT INTO ops.CORREO_CYBER (ID_CORRIDA, CUENTA2, CORREO)
    SELECT DISTINCT @id_corrida, LEFT(LTRIM(RTRIM(CUENTA)), 28), LEFT(LOWER(LTRIM(RTRIM(REPLACE(CORREO, NCHAR(13), N'')))), 100)
    FROM stg.CYBER_CORREO WHERE NULLIF(LTRIM(RTRIM(CUENTA)), N'') IS NOT NULL AND NULLIF(LTRIM(RTRIM(REPLACE(CORREO, NCHAR(13), N''))), N'') IS NOT NULL;
    TRUNCATE TABLE stg.CYBER_CORREO;

    DECLARE @momento NVARCHAR(20) = CONCAT(CONVERT(CHAR(8), @fecha, 3), N' ', CONVERT(CHAR(8), SYSDATETIME(), 108));   -- DD/MM/YY HH24:MI:SS
    /* Mismo formato que email.PRG (email.sql) */
    DECLARE @plantilla NVARCHAR(1000) = N'INSERT INTO RCVRY.ADDRESS VALUES(''{SSNUM}'',''3'','''',''{CORREO}'','''','''','''','''','''',''A'','''',''1'',''{CUENTA2}'',TO_DATE(''{M}'',''DD/MM/YY HH24:MI:SS''),''zzasg'',''zzasg'',TO_DATE(''{M}'',''DD/MM/YY HH24:MI:SS''),'''');';
    DECLARE @n INT;
    DELETE FROM ops.CYBER_SCRIPT WHERE ID_CORRIDA = @id_corrida AND SCRIPT = 'MAIL_INSERTA_NUEVOS';
    INSERT INTO ops.CYBER_SCRIPT (ID_CORRIDA, SCRIPT, NUM, SENTENCIA)
    SELECT @id_corrida, 'MAIL_INSERTA_NUEVOS', ROW_NUMBER() OVER (ORDER BY c.CUENTA2, c.CORREO),
           REPLACE(REPLACE(REPLACE(REPLACE(@plantilla, N'{SSNUM}', REPLACE(d.CUENTA, '''', '''''')),
                   N'{CORREO}', REPLACE(c.CORREO, '''', '''''')), N'{CUENTA2}', c.CUENTA2), N'{M}', @momento)
    FROM ops.CORREO c
    JOIN dat.DAT_486 d ON d.CUENTA2 = c.CUENTA2 AND d.CLIENTE = @cliente
    WHERE c.ID_CORRIDA = @id_corrida
      AND NOT EXISTS (SELECT 1 FROM ops.CORREO_CYBER x WHERE x.ID_CORRIDA = @id_corrida AND x.CUENTA2 = c.CUENTA2 AND x.CORREO = c.CORREO);
    SET @n = @@ROWCOUNT;
    INSERT INTO ops.CYBER_SCRIPT (ID_CORRIDA, SCRIPT, NUM, SENTENCIA)
    VALUES (@id_corrida, 'MAIL_INSERTA_NUEVOS', @n + 1, N'commit;'), (@id_corrida, 'MAIL_INSERTA_NUEVOS', @n + 2, N'exit');

    DECLARE @msg NVARCHAR(400) = CONCAT(N'Correos que ya tiene CYBER: ', (SELECT COUNT(*) FROM ops.CORREO_CYBER WHERE ID_CORRIDA = @id_corrida),
                                        N' · nuevos a insertar: ', @n);
    EXEC ops.sp_log @id_corrida, 'CORREOS NUEVOS', 'OK', @n, @msg;
    SELECT @n AS NUEVOS, (SELECT COUNT(*) FROM ops.CORREO WHERE ID_CORRIDA = @id_corrida) - @n AS YA_EN_CYBER;
END;
GO
