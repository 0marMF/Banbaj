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
   Hoy sub_mail.TXT sale antes de quitar EMAILMALO (la exclusión solo se
   aplicaba a los INSERT directos en RCVRY.ADDRESS). El parámetro
   CORREOS_EXCLUIR_MALOS = 1 la aplica también a la remesa (por definir; 0 = como hoy).
   ===================================================================== */
SET NOCOUNT ON;
GO

CREATE OR ALTER PROCEDURE ops.sp_correos
    @id_corrida INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @cliente VARCHAR(10) = (SELECT CLIENTE FROM ops.CORRIDA WHERE ID_CORRIDA = @id_corrida);
    DECLARE @malos BIT = CASE WHEN cfg.fn_param(@cliente, 'CORREOS_EXCLUIR_MALOS') = '1' THEN 1 ELSE 0 END;
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
    DELETE FROM ops.CYBER_SCRIPT WHERE ID_CORRIDA = @id_corrida AND SCRIPT IN ('MAIL_BORRA', 'MAIL_ACTUALIZA');
    INSERT INTO ops.CYBER_SCRIPT (ID_CORRIDA, SCRIPT, NUM, SENTENCIA)
    VALUES (@id_corrida, 'MAIL_BORRA', 1, N'TRUNCATE TABLE RCVRY.JSP_TAB_MAIL_REMESA_486;'),
           (@id_corrida, 'MAIL_BORRA', 2, N'COMMIT;'),
           (@id_corrida, 'MAIL_BORRA', 3, N'EXIT;'),
           (@id_corrida, 'MAIL_ACTUALIZA', 1, CONCAT(N'EXECUTE ', ISNULL(cfg.fn_param(@cliente, 'CYBER_PROC_CORREOS'), N'RCVRY.JSP_CORREOS_486'), N';')),
           (@id_corrida, 'MAIL_ACTUALIZA', 2, N'COMMIT;'),
           (@id_corrida, 'MAIL_ACTUALIZA', 3, N'exit;');
END;
GO
