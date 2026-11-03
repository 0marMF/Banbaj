/* =====================================================================
   Banbaj · 76 Arribo automático a CYBER de teléfonos y correos (decisión 02/11)
   ---------------------------------------------------------------------
   El operador solo sube los archivos de ancho fijo con el cargador de CYBER
   (SCBSDOS, SCBTEL, gescar). Lo demás lo hace SQL Server por el servidor
   vinculado [CYBER], sin sqlldr ni scripts a mano:

   Correos (en cuanto el SCBSDOS ya subió: las altas del día están activas en DELQMST)
     1. Baja los correos que tiene CYBER e inserta los nuevos en ADDRESS.
     2. Bandera 416 encendida, vacía la remesa, la carga y ejecuta JSP_CORREOS_486.
     3. Apaga la bandera.
   Teléfonos (en cuanto el SCBTEL ya subió: los teléfonos de las altas están en PHONE_G1)
     1. Vacía la remesa (y crea el renglón del validador), la carga y ejecuta
        JSP_TELEFONOS_REMESA_486.
     2. Baja los teléfonos activos y genera el gescar de cuentas sin teléfono
        (SCBACTH_SINTEL.TXT), que se escribe en la carpeta de la corrida.

   ops.sp_arribo_automatico lo llama el job (ops.sp_diario_486) cada 30 minutos
   cuando la asignación del día ya terminó. Cada proceso corre una sola vez por
   corrida; si falla, queda ERROR en la bitácora y no se reintenta solo:
   se corrige y se corre a mano con EXEC ops.sp_arribar_cyber <corrida>, '<CORREOS|TELEFONOS>';
   ===================================================================== */
SET NOCOUNT ON;
GO

/* Ejecuta en CYBER un script de ops.CYBER_SCRIPT, en bloques PL/SQL.
   EXIT se omite; TRUNCATE va con EXECUTE IMMEDIATE; EXECUTE x se vuelve llamada. */
CREATE OR ALTER PROCEDURE ops.sp_cyber_ejecutar
    @id_corrida   INT,
    @script       VARCHAR(40),
    @solo_mostrar BIT = 0,
    @sentencias   INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @cliente VARCHAR(10) = (SELECT CLIENTE FROM ops.CORRIDA WHERE ID_CORRIDA = @id_corrida);
    DECLARE @srv SYSNAME = ISNULL(cfg.fn_param(@cliente, 'CYBER_LINKED_SERVER'), 'CYBER'),
            @tam INT = ISNULL(TRY_CONVERT(INT, cfg.fn_param(@cliente, 'CYBER_SENTENCIAS_POR_BLOQUE')), 200),
            @b NVARCHAR(MAX), @x NVARCHAR(400), @i INT, @msg NVARCHAR(4000);

    SELECT ROW_NUMBER() OVER (ORDER BY NUM) AS RN,
           CASE WHEN UPPER(t.S) LIKE N'TRUNCATE %' THEN N'EXECUTE IMMEDIATE ''' + REPLACE(t.S, N'''', N'''''') + N''''
                WHEN UPPER(t.S) LIKE N'EXECUTE %' THEN LTRIM(SUBSTRING(t.S, 9, 4000))
                WHEN UPPER(t.S) LIKE N'EXEC %' THEN LTRIM(SUBSTRING(t.S, 6, 4000))
                ELSE t.S END + N';' AS S
    INTO #s
    FROM ops.CYBER_SCRIPT c
    CROSS APPLY (SELECT LTRIM(RTRIM(REPLACE(REPLACE(c.SENTENCIA, NCHAR(13), N''), NCHAR(10), N' '))) AS S0) a
    CROSS APPLY (SELECT CASE WHEN RIGHT(a.S0, 1) = N';' THEN RTRIM(LEFT(a.S0, LEN(a.S0) - 1)) ELSE a.S0 END AS S) t
    WHERE c.ID_CORRIDA = @id_corrida AND c.SCRIPT = @script
      AND UPPER(t.S) NOT IN (N'EXIT', N'COMMIT', N'') ;
    SET @sentencias = @@ROWCOUNT;
    IF @sentencias = 0 RETURN;

    SELECT (RN - 1) / @tam AS BLOQUE,
           N'BEGIN ' + STRING_AGG(CAST(S AS NVARCHAR(MAX)), N' ') WITHIN GROUP (ORDER BY RN) + N' COMMIT; END;' AS PLSQL
    INTO #b FROM #s GROUP BY (RN - 1) / @tam;

    IF @solo_mostrar = 1
    BEGIN
        SELECT @script AS SCRIPT, BLOQUE, PLSQL FROM #b ORDER BY BLOQUE;
        RETURN;
    END;
    IF NOT EXISTS (SELECT 1 FROM sys.servers WHERE name = @srv)
    BEGIN
        SET @msg = CONCAT(N'No existe el servidor vinculado ', @srv, N'.');
        THROW 50823, @msg, 1;
    END;
    SET @x = N'EXEC (@b) AT ' + QUOTENAME(@srv) + N';';
    DECLARE cb CURSOR LOCAL FAST_FORWARD FOR SELECT PLSQL FROM #b ORDER BY BLOQUE;
    OPEN cb; FETCH NEXT FROM cb INTO @b;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        EXEC sp_executesql @x, N'@b NVARCHAR(MAX)', @b = @b;
        FETCH NEXT FROM cb INTO @b;
    END;
    CLOSE cb; DEALLOCATE cb;
    SET @msg = CONCAT(@script, N': ', @sentencias, N' sentencias en CYBER');
    EXEC ops.sp_log @id_corrida, 'CYBER EJECUTA', 'OK', @sentencias, @msg;
END;
GO

/* Arma como script los INSERT de la remesa (lo que hacía sqlldr con sub_mst.TXT o sub_mail.TXT).
   Las columnas de la tabla de CYBER van en CYBER_REMESA_TEL_COLUMNAS / CYBER_REMESA_MAIL_COLUMNAS,
   en el orden CUENTA, AREA, TELEFONO, TIPOTEL (teléfonos) o CUENTA, CORREO (correos). */
CREATE OR ALTER PROCEDURE ops.sp_cyber_remesa
    @id_corrida INT,
    @que        VARCHAR(10),          -- TEL / MAIL
    @filas      INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @cliente VARCHAR(10) = (SELECT CLIENTE FROM ops.CORRIDA WHERE ID_CORRIDA = @id_corrida);
    DECLARE @cols NVARCHAR(400), @n INT, @tabla NVARCHAR(200), @script VARCHAR(40);
    IF @que NOT IN ('TEL', 'MAIL') THROW 50760, '@que debe ser TEL o MAIL.', 1;

    IF @que = 'TEL'
        SELECT @tabla = N'RCVRY.JSP_TAB_TEL_REMESA_486', @script = 'TEL_REMESA',
               @cols = ISNULL(cfg.fn_param(@cliente, 'CYBER_REMESA_TEL_COLUMNAS'), N'CUENTA,AREA,TELEFONO,TIPOTEL');
    ELSE
        SELECT @tabla = N'RCVRY.JSP_TAB_MAIL_REMESA_486', @script = 'MAIL_REMESA',
               @cols = ISNULL(cfg.fn_param(@cliente, 'CYBER_REMESA_MAIL_COLUMNAS'), N'CUENTA,CORREO');
    IF @cols LIKE N'%[^A-Za-z0-9_, ]%' THROW 50761, 'Columnas de la remesa inválidas.', 1;
    SET @n = (SELECT COUNT(*) FROM STRING_SPLIT(@cols, N',') WHERE LTRIM(value) <> N'');
    IF @n NOT BETWEEN 2 AND CASE WHEN @que = 'TEL' THEN 4 ELSE 2 END THROW 50762, 'Número de columnas de la remesa inválido.', 1;
    SET @cols = REPLACE(@cols, N' ', N'');

    DELETE FROM ops.CYBER_SCRIPT WHERE ID_CORRIDA = @id_corrida AND SCRIPT = @script;
    IF @que = 'TEL'
        INSERT INTO ops.CYBER_SCRIPT (ID_CORRIDA, SCRIPT, NUM, SENTENCIA)
        SELECT @id_corrida, @script, ROW_NUMBER() OVER (ORDER BY CUENTA2, TIPOTEL, AREA, TELEFONO),
               CONCAT(N'INSERT INTO ', @tabla, N' (', @cols, N') VALUES (''', REPLACE(CUENTA2, '''', ''''''), N''', ''', AREA, N''', ''', TELEFONO, N''''
                      , CASE WHEN @n = 4 THEN CONCAT(N', ''', TIPOTEL, N'''') ELSE N'' END, N');')
        FROM ops.TELEFONO WHERE ID_CORRIDA = @id_corrida;
    ELSE
        INSERT INTO ops.CYBER_SCRIPT (ID_CORRIDA, SCRIPT, NUM, SENTENCIA)
        SELECT @id_corrida, @script, ROW_NUMBER() OVER (ORDER BY CUENTA2, CORREO),
               CONCAT(N'INSERT INTO ', @tabla, N' (', @cols, N') VALUES (''', REPLACE(CUENTA2, '''', ''''''), N''', ''', REPLACE(CORREO, '''', ''''''), N''');')
        FROM ops.CORREO WHERE ID_CORRIDA = @id_corrida;
    SET @filas = @@ROWCOUNT;
END;
GO

/* Arribo a CYBER de correos o teléfonos de una asignación (lo llama ops.sp_arribo_automatico o se corre a mano) */
CREATE OR ALTER PROCEDURE ops.sp_arribar_cyber
    @id_corrida   INT,
    @que          VARCHAR(10),            -- CORREOS / TELEFONOS
    @solo_mostrar BIT = 0                 -- 1 = regresa los bloques PL/SQL sin tocar CYBER
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @proceso VARCHAR(10), @n INT, @r INT, @msg NVARCHAR(4000), @paso VARCHAR(40) = 'ARRIBO ' + UPPER(@que), @bandera BIT = 0;
    SELECT @proceso = PROCESO FROM ops.CORRIDA WHERE ID_CORRIDA = @id_corrida;
    SET @que = UPPER(LTRIM(RTRIM(@que)));
    IF @proceso IS NULL OR @proceso <> 'ASIG' THROW 50763, 'Indica una corrida de asignación.', 1;
    IF @que NOT IN ('CORREOS', 'TELEFONOS') THROW 50764, '@que debe ser CORREOS o TELEFONOS.', 1;
    IF @@TRANCOUNT > 0 THROW 50765, 'El arribo a CYBER no puede correr dentro de una transacción.', 1;

    BEGIN TRY
        IF @que = 'CORREOS'
        BEGIN
            /* Sin remesa, JSP_CORREOS_486 inactivaría todos los correos del 486 */
            IF NOT EXISTS (SELECT 1 FROM ops.CORREO WHERE ID_CORRIDA = @id_corrida)
                THROW 50766, 'La corrida no tiene correos para la remesa; no se ejecuta JSP_CORREOS_486.', 1;
            IF @solo_mostrar = 0 EXEC ops.sp_bajar_cyber 'CORREOS', @id_corrida = @id_corrida;   -- arma MAIL_INSERTA_NUEVOS
            EXEC ops.sp_cyber_remesa @id_corrida, 'MAIL', @n OUTPUT;
            EXEC ops.sp_cyber_ejecutar @id_corrida, 'MAIL_INSERTA_NUEVOS', @solo_mostrar;
            EXEC ops.sp_cyber_ejecutar @id_corrida, 'MAIL_ACTIVA_BANDERA', @solo_mostrar;
            SET @bandera = 1;
            EXEC ops.sp_cyber_ejecutar @id_corrida, 'MAIL_BORRA', @solo_mostrar;
            EXEC ops.sp_cyber_ejecutar @id_corrida, 'MAIL_REMESA', @solo_mostrar;
            EXEC ops.sp_cyber_ejecutar @id_corrida, 'MAIL_ACTUALIZA', @solo_mostrar;
            EXEC ops.sp_cyber_ejecutar @id_corrida, 'MAIL_INACTIVA_BANDERA', @solo_mostrar;
            SET @bandera = 0;
            SET @msg = CONCAT(N'Correos arribados a CYBER: remesa de ', @n, N' · nuevos insertados: ',
                              (SELECT COUNT(*) FROM ops.CYBER_SCRIPT WHERE ID_CORRIDA = @id_corrida AND SCRIPT = 'MAIL_INSERTA_NUEVOS' AND SENTENCIA LIKE N'INSERT%'));
        END
        ELSE
        BEGIN
            /* Sin remesa, JSP_TELEFONOS_REMESA_486 inactivaría todos los teléfonos del 486 */
            IF NOT EXISTS (SELECT 1 FROM ops.TELEFONO WHERE ID_CORRIDA = @id_corrida)
                THROW 50767, 'La corrida no tiene teléfonos para la remesa; no se ejecuta JSP_TELEFONOS_REMESA_486.', 1;
            EXEC ops.sp_cyber_remesa @id_corrida, 'TEL', @n OUTPUT;
            EXEC ops.sp_cyber_ejecutar @id_corrida, 'TEL_BORRA', @solo_mostrar;
            EXEC ops.sp_cyber_ejecutar @id_corrida, 'TEL_REMESA', @solo_mostrar;
            EXEC ops.sp_cyber_ejecutar @id_corrida, 'TEL_ACTUALIZA', @solo_mostrar;
            SET @msg = CONCAT(N'Teléfonos arribados a CYBER: remesa de ', @n);
            IF @solo_mostrar = 0
            BEGIN
                /* Gescar de nuevas y reasignadas sin teléfono activo, ya con lo que quedó en PHONE */
                EXEC ops.sp_bajar_cyber 'TELEFONOS', @id_corrida = @id_corrida;
                BEGIN TRY
                    EXEC ops.sp_exportar_salidas @id_corrida, @solo = 'GESCAR_SINTEL';
                    SET @msg += N' · SCBACTH_SINTEL.TXT escrito en la carpeta de la corrida';
                END TRY
                BEGIN CATCH
                    SET @msg += CONCAT(N' · no se pudo escribir SCBACTH_SINTEL.TXT: ', ERROR_MESSAGE());
                END CATCH;
            END;
        END;
        IF @solo_mostrar = 0 EXEC ops.sp_log @id_corrida, @paso, 'OK', @n, @msg;
    END TRY
    BEGIN CATCH
        SET @msg = ERROR_MESSAGE();
        IF @bandera = 1 AND @solo_mostrar = 0
            BEGIN TRY EXEC ops.sp_cyber_ejecutar @id_corrida, 'MAIL_INACTIVA_BANDERA'; END TRY BEGIN CATCH END CATCH;
        IF @solo_mostrar = 0 EXEC ops.sp_log @id_corrida, @paso, 'ERROR', NULL, @msg;
        THROW;
    END CATCH;
END;
GO

/* Detecta si el operador ya subió el SCBSDOS y el SCBTEL de la asignación del día y arriba lo que falte.
   SCBSDOS subido = las altas (NVA y REA) de la corrida ya están activas en DELQMST.
   SCBTEL subido  = los teléfonos de esas altas ya están en PHONE_G1 (son nuevos del día, no pueden venir de un arribo anterior).
   Si la corrida no tuvo altas con teléfono, los teléfonos esperan a que se marque el fin del arribo
   (EXEC ops.sp_marcar_arribo <corrida>, 'FIN') o se corren a mano. */
CREATE OR ALTER PROCEDURE ops.sp_arribo_automatico
    @fecha     DATE = NULL,
    @cliente   VARCHAR(10) = '486',
    @sin_bajar BIT = 0,                  -- 1 = usa lo que ya está en stg.CYBER_DELQMST_ACT y stg.CYBER_PHONE_G1 (pruebas)
    @resultado NVARCHAR(400) = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @fecha = ISNULL(@fecha, CAST(GETDATE() AS DATE));
    IF ISNULL(cfg.fn_param(@cliente, 'ARRIBO_AUTOMATICO'), '0') <> '1'
    BEGIN
        SET @resultado = N'ARRIBO AUTOMATICO APAGADO';
        SELECT @resultado AS ARRIBO;
        RETURN;
    END;
    DECLARE @id INT, @srv SYSNAME = ISNULL(cfg.fn_param(@cliente, 'CYBER_LINKED_SERVER'), 'CYBER'),
            @min DECIMAL(5,2) = ISNULL(TRY_CONVERT(DECIMAL(5,2), cfg.fn_param(@cliente, 'ARRIBO_MIN_PCT')), 95),
            @altas INT, @altas_cyber INT, @tels INT, @tels_cyber INT, @hecho_c BIT, @hecho_t BIT, @fin BIT,
            @listo_c BIT = 0, @listo_t BIT = 0, @q NVARCHAR(MAX), @sql NVARCHAR(MAX), @res NVARCHAR(400) = N'';

    SELECT TOP (1) @id = ID_CORRIDA FROM ops.CORRIDA
    WHERE CLIENTE = @cliente AND PROCESO = 'ASIG' AND FECHA_PROCESO = @fecha AND ESTATUS = 'OK'
    ORDER BY ID_CORRIDA DESC;
    IF @id IS NULL
    BEGIN
        SET @resultado = N'SIN ASIGNACION OK DEL DIA';
        SELECT @resultado AS ARRIBO;
        RETURN;
    END;
    SET @hecho_c = CASE WHEN EXISTS (SELECT 1 FROM ops.BITACORA WHERE ID_CORRIDA = @id AND PASO = 'ARRIBO CORREOS' AND ESTATUS IN ('OK', 'ERROR')) THEN 1 ELSE 0 END;
    SET @hecho_t = CASE WHEN EXISTS (SELECT 1 FROM ops.BITACORA WHERE ID_CORRIDA = @id AND PASO = 'ARRIBO TELEFONOS' AND ESTATUS IN ('OK', 'ERROR')) THEN 1 ELSE 0 END;
    IF @hecho_c = 1 AND @hecho_t = 1
    BEGIN
        SET @resultado = N'ARRIBO AUTOMATICO TERMINADO';
        SELECT @resultado AS ARRIBO, @id AS CORRIDA;
        RETURN;
    END;

    /* Lo que hay en CYBER ahora */
    IF @sin_bajar = 0
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM sys.servers WHERE name = @srv)
        BEGIN
            SET @resultado = N'SIN SERVIDOR VINCULADO A CYBER';
            SELECT @resultado AS ARRIBO, @id AS CORRIDA;
            RETURN;
        END;
        TRUNCATE TABLE stg.CYBER_DELQMST_ACT;
        SET @q = N'select DMACCT from RCVRY.delqmst where DMACCTG = ''1'' and DMCOMPANY = ''' + @cliente + N''' and DMSTATUS is null';
        SET @sql = N'INSERT INTO stg.CYBER_DELQMST_ACT (CUENTA) EXEC (N''' + REPLACE(@q, N'''', N'''''') + N''') AT ' + QUOTENAME(@srv) + N';';
        EXEC (@sql);
        IF @hecho_t = 0
        BEGIN
            TRUNCATE TABLE stg.CYBER_PHONE_G1;
            SET @q = N'select PHACCT, PHAREACODE, PHPHONE from RCVRY.phone_g1 where PHACCTG = ''1'' and PHACCT like ''' + @cliente + N'-%''';
            SET @sql = N'INSERT INTO stg.CYBER_PHONE_G1 (CUENTA, AREA, TELEFONO) EXEC (N''' + REPLACE(@q, N'''', N'''''') + N''') AT ' + QUOTENAME(@srv) + N';';
            EXEC (@sql);
        END;
    END;

    SELECT @altas = COUNT(*),
           @altas_cyber = SUM(CASE WHEN EXISTS (SELECT 1 FROM stg.CYBER_DELQMST_ACT x WHERE LTRIM(RTRIM(x.CUENTA)) = h.CUENTA2) THEN 1 ELSE 0 END)
    FROM dat.HISTORIA_FOLIO h WHERE h.CLIENTE = @cliente AND h.ID_CORRIDA_ALTA = @id;
    SELECT @tels = COUNT(*),
           @tels_cyber = SUM(CASE WHEN EXISTS (SELECT 1 FROM stg.CYBER_PHONE_G1 p WHERE LTRIM(RTRIM(p.CUENTA)) = t.CUENTA2
                                                 AND LTRIM(RTRIM(p.AREA)) = t.AREA AND LTRIM(RTRIM(p.TELEFONO)) = t.TELEFONO) THEN 1 ELSE 0 END)
    FROM ops.TELEFONO t
    WHERE t.ID_CORRIDA = @id AND t.CUENTA2 IN (SELECT CUENTA2 FROM dat.HISTORIA_FOLIO WHERE CLIENTE = @cliente AND ID_CORRIDA_ALTA = @id);
    SET @fin = CASE WHEN EXISTS (SELECT 1 FROM ops.BITACORA WHERE ID_CORRIDA = @id AND PASO = 'ARRIBO FIN') THEN 1 ELSE 0 END;

    SET @listo_t = CASE WHEN @tels > 0 AND 100.0 * ISNULL(@tels_cyber, 0) / @tels >= @min THEN 1
                        WHEN @tels = 0 AND @fin = 1 THEN 1 ELSE 0 END;
    SET @listo_c = CASE WHEN @altas > 0 AND 100.0 * ISNULL(@altas_cyber, 0) / @altas >= @min THEN 1
                        WHEN @altas = 0 AND (@listo_t = 1 OR @fin = 1) THEN 1 ELSE 0 END;

    IF @listo_c = 1 AND @hecho_c = 0
    BEGIN
        BEGIN TRY
            EXEC ops.sp_arribar_cyber @id, 'CORREOS';
            SET @res += N'CORREOS OK · ';
        END TRY
        BEGIN CATCH
            SET @res += N'CORREOS ERROR · ';
        END CATCH;
    END;
    IF @listo_t = 1 AND @hecho_t = 0
    BEGIN
        BEGIN TRY
            EXEC ops.sp_arribar_cyber @id, 'TELEFONOS';
            SET @res += N'TELEFONOS OK · ';
        END TRY
        BEGIN CATCH
            SET @res += N'TELEFONOS ERROR · ';
        END CATCH;
    END;

    SET @resultado = CASE WHEN @res = N'' THEN N'ESPERANDO ARRIBO' ELSE LEFT(@res, LEN(@res) - 1) END;
    SELECT @resultado AS ARRIBO, @id AS CORRIDA,
           CONCAT(ISNULL(@altas_cyber, 0), N' de ', @altas) AS ALTAS_EN_CYBER, CONCAT(ISNULL(@tels_cyber, 0), N' de ', @tels) AS TELEFONOS_EN_PHONE_G1;
END;
GO
