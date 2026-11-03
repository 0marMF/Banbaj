/* =====================================================================
   Banbaj · 76 Arribo automático a CYBER de teléfonos y correos (decisión 02/11)
   ---------------------------------------------------------------------
   El operador solo sube los archivos de ancho fijo con el cargador de CYBER
   (SCBSDOS, SCBTEL, gescar). Lo demás lo hace SQL Server por el servidor
   vinculado [CYBER], sin sqlldr ni scripts a mano:

   Correos (en cuanto el SCBSDOS ya subió: lo que le faltaba a DELQMST al terminar la asignación ya llegó)
     1. Baja los correos que tiene CYBER e inserta los nuevos en ADDRESS.
     2. Bandera 416 encendida, vacía la remesa, la carga y ejecuta JSP_CORREOS_486.
     3. Apaga la bandera.
   Teléfonos (en cuanto el SCBTEL ya subió: los teléfonos que le faltaban a PHONE_G1 ya llegaron)
     1. Vacía la remesa (y crea el renglón del validador), la carga y ejecuta
        JSP_TELEFONOS_REMESA_486.
     2. Baja los teléfonos activos y genera el gescar de cuentas sin teléfono
        (SCBACTH_SINTEL.TXT), que se escribe en la carpeta de la corrida.

   ops.sp_arribo_automatico lo llama el job (ops.sp_diario_486) cada 30 minutos
   cuando la asignación del día ya terminó. Cada proceso corre una sola vez por
   corrida; si falla, queda ERROR en la bitácora y no se reintenta solo:
   se avisa al equipo de asignaciones (HALLAZGO_486), se corrige y se corre a mano con
   EXEC ops.sp_arribar_cyber <corrida>, '<CORREOS|TELEFONOS>';
   La detección compara contra lo pendiente (ops.sp_arribo_base), así funciona aunque no haya cuentas nuevas.
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
    IF @@TRANCOUNT > 0 AND @solo_mostrar = 0 THROW 50765, 'El arribo a CYBER no puede correr dentro de una transacción.', 1;

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

/* Baja de CYBER lo necesario para detectar el arribo: cuentas activas del 486 con su domicilio
   (DELQMST) y teléfonos que dejó el arribo del SCBTEL (PHONE_G1). Va directo a tablas de paso. */
CREATE OR ALTER PROCEDURE ops.sp_arribo_bajar
    @cliente   VARCHAR(10) = '486',
    @telefonos BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @srv SYSNAME = ISNULL(cfg.fn_param(@cliente, 'CYBER_LINKED_SERVER'), 'CYBER'),
            @dom NVARCHAR(128) = NULLIF(LTRIM(RTRIM(cfg.fn_param(@cliente, 'CYBER_COLUMNA_DOMICILIO'))), N''),
            @q NVARCHAR(MAX), @sql NVARCHAR(MAX), @msg NVARCHAR(400);
    IF NOT EXISTS (SELECT 1 FROM sys.servers WHERE name = @srv)
    BEGIN
        SET @msg = CONCAT(N'No existe el servidor vinculado ', @srv, N'. Captura la credencial CYBER_ORACLE y corre EXEC cfg.sp_cyber_conectar;');
        THROW 50823, @msg, 1;
    END;
    IF @dom LIKE N'%[^A-Za-z0-9_]%' THROW 50768, 'CYBER_COLUMNA_DOMICILIO inválida (solo el nombre de la columna de DELQMST).', 1;

    TRUNCATE TABLE stg.CYBER_DELQMST_ACT;
    SET @q = N'select DMACCT, ' + ISNULL(@dom, N'cast(null as varchar2(80))') + N' from RCVRY.delqmst where DMACCTG = ''1'' and DMCOMPANY = '''
           + @cliente + N''' and DMSTATUS is null';
    SET @sql = N'INSERT INTO stg.CYBER_DELQMST_ACT (CUENTA, DOMICILIO) EXEC (N''' + REPLACE(@q, N'''', N'''''') + N''') AT ' + QUOTENAME(@srv) + N';';
    EXEC (@sql);
    IF @telefonos = 1
    BEGIN
        TRUNCATE TABLE stg.CYBER_PHONE_G1;
        SET @q = N'select PHACCT, PHAREACODE, PHPHONE from RCVRY.phone_g1 where PHACCTG = ''1'' and PHACCT like ''' + @cliente + N'-%''';
        SET @sql = N'INSERT INTO stg.CYBER_PHONE_G1 (CUENTA, AREA, TELEFONO) EXEC (N''' + REPLACE(@q, N'''', N'''''') + N''') AT ' + QUOTENAME(@srv) + N';';
        EXEC (@sql);
    END;
END;
GO

/* Foto de lo que le falta a CYBER al terminar la asignación, antes de que existan los archivos
   (los TXT solo se escriben con ops.sp_exportar_salidas, así que el operador no pudo haber subido nada):
     CUENTA     cuentas del SCBSDOS que no están activas en DELQMST (nuevas y reasignadas)
     DOMICILIO  cuentas activas cuyo domicilio en CYBER es distinto al que manda el SCBSDOS (CYBER_COLUMNA_DOMICILIO)
     TELEFONO   teléfonos del SCBTEL (de todas las cuentas) que no están en PHONE_G1
   ops.sp_arribo_automatico da por subido cada archivo cuando ya llegó lo pendiente. */
CREATE OR ALTER PROCEDURE ops.sp_arribo_base
    @id_corrida INT,
    @sin_bajar  BIT = 0              -- 1 = usa lo que ya está en las tablas de paso
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @cliente VARCHAR(10), @proceso VARCHAR(10), @o_cta INT, @w_cta INT, @o_dom INT, @w_dom INT,
            @usa_dom BIT, @c INT, @d INT, @t INT, @msg NVARCHAR(400);
    SELECT @cliente = CLIENTE, @proceso = PROCESO FROM ops.CORRIDA WHERE ID_CORRIDA = @id_corrida;
    IF @proceso IS NULL OR @proceso <> 'ASIG' THROW 50763, 'Indica una corrida de asignación.', 1;
    IF @sin_bajar = 0 EXEC ops.sp_arribo_bajar @cliente, 1;
    SET @usa_dom = CASE WHEN NULLIF(LTRIM(RTRIM(cfg.fn_param(@cliente, 'CYBER_COLUMNA_DOMICILIO'))), N'') IS NULL THEN 0 ELSE 1 END;

    /* Posición de CUENTA y DMADDR1 en el SCBSDOS: se compara exactamente lo que se manda */
    SELECT @o_cta = (SELECT ISNULL(SUM(x.ANCHO), 0) FROM cfg.SALIDA x WHERE x.CLIENTE = @cliente AND x.ARCHIVO = 'SCBSDOS' AND x.ACTIVO = 1 AND x.ORDEN < s.ORDEN),
           @w_cta = s.ANCHO
    FROM cfg.SALIDA s WHERE s.CLIENTE = @cliente AND s.ARCHIVO = 'SCBSDOS' AND s.ACTIVO = 1 AND s.CAMPO = 'CUENTA';
    SELECT @o_dom = (SELECT ISNULL(SUM(x.ANCHO), 0) FROM cfg.SALIDA x WHERE x.CLIENTE = @cliente AND x.ARCHIVO = 'SCBSDOS' AND x.ACTIVO = 1 AND x.ORDEN < s.ORDEN),
           @w_dom = s.ANCHO
    FROM cfg.SALIDA s WHERE s.CLIENTE = @cliente AND s.ARCHIVO = 'SCBSDOS' AND s.ACTIVO = 1 AND s.CAMPO = 'DMADDR1';
    IF @w_cta IS NULL THROW 50769, 'El SCBSDOS no tiene el campo CUENTA en cfg.SALIDA.', 1;
    IF @w_dom IS NULL SET @usa_dom = 0;

    SELECT CUENTA, MAX(DOM) AS DOM INTO #l
    FROM (SELECT LTRIM(RTRIM(SUBSTRING(LINEA, @o_cta + 1, @w_cta))) AS CUENTA,
                 CASE WHEN @usa_dom = 1 THEN UPPER(LTRIM(RTRIM(SUBSTRING(LINEA, @o_dom + 1, @w_dom)))) END AS DOM
          FROM ops.SALIDA_LINEA WHERE ID_CORRIDA = @id_corrida AND ARCHIVO = 'SCBSDOS') z
    WHERE CUENTA <> N'' GROUP BY CUENTA;
    SELECT LTRIM(RTRIM(CUENTA)) AS CUENTA, MAX(UPPER(LTRIM(RTRIM(ISNULL(DOMICILIO, N''))))) AS DOM INTO #d
    FROM stg.CYBER_DELQMST_ACT WHERE CUENTA IS NOT NULL GROUP BY LTRIM(RTRIM(CUENTA));
    CREATE UNIQUE CLUSTERED INDEX IX ON #d (CUENTA);
    SELECT DISTINCT LTRIM(RTRIM(CUENTA)) AS CUENTA, LTRIM(RTRIM(AREA)) AS AREA, LTRIM(RTRIM(TELEFONO)) AS TELEFONO INTO #g
    FROM stg.CYBER_PHONE_G1 WHERE CUENTA IS NOT NULL;
    CREATE CLUSTERED INDEX IX ON #g (CUENTA, AREA, TELEFONO);

    DELETE FROM ops.ARRIBO_PENDIENTE WHERE ID_CORRIDA = @id_corrida;
    INSERT INTO ops.ARRIBO_PENDIENTE (ID_CORRIDA, TIPO, CUENTA, VALOR)
    SELECT @id_corrida, CASE WHEN d.CUENTA IS NULL THEN 'CUENTA' ELSE 'DOMICILIO' END, l.CUENTA, l.DOM
    FROM #l l LEFT JOIN #d d ON d.CUENTA = l.CUENTA
    WHERE d.CUENTA IS NULL OR (@usa_dom = 1 AND ISNULL(l.DOM, N'') <> d.DOM);
    INSERT INTO ops.ARRIBO_PENDIENTE (ID_CORRIDA, TIPO, CUENTA, AREA, TELEFONO)
    SELECT DISTINCT @id_corrida, 'TELEFONO', t.CUENTA2, t.AREA, t.TELEFONO
    FROM ops.TELEFONO t
    WHERE t.ID_CORRIDA = @id_corrida
      AND NOT EXISTS (SELECT 1 FROM #g g WHERE g.CUENTA = t.CUENTA2 AND g.AREA = t.AREA AND g.TELEFONO = t.TELEFONO);

    SELECT @c = SUM(CASE WHEN TIPO = 'CUENTA' THEN 1 ELSE 0 END), @d = SUM(CASE WHEN TIPO = 'DOMICILIO' THEN 1 ELSE 0 END),
           @t = SUM(CASE WHEN TIPO = 'TELEFONO' THEN 1 ELSE 0 END)
    FROM ops.ARRIBO_PENDIENTE WHERE ID_CORRIDA = @id_corrida;
    SET @msg = CONCAT(N'Pendiente en CYBER: ', ISNULL(@c, 0), N' cuentas, ', ISNULL(@d, 0), N' domicilios, ', ISNULL(@t, 0), N' teléfonos');
    EXEC ops.sp_log @id_corrida, 'ARRIBO BASE', 'OK', NULL, @msg;
END;
GO

/* Detecta si el operador ya subió el SCBSDOS y el SCBTEL de la asignación del día y arriba lo que falte.
   Se compara contra lo que estaba pendiente (ops.ARRIBO_PENDIENTE, foto de ops.sp_arribo_base), no contra
   las altas, para que funcione aunque no haya cuentas nuevas:
     SCBSDOS subido = al menos ARRIBO_MIN_PCT % de las cuentas y domicilios pendientes ya están en DELQMST.
     SCBTEL subido  = al menos ARRIBO_MIN_PCT % de los teléfonos pendientes ya están en PHONE_G1, y las cuentas
                      pendientes ya están activas (JSP_TELEFONOS_REMESA_486 solo trabaja cuentas activas).
     Sin pendientes = CYBER ya tiene todo lo que necesita el procedimiento: se arriba en la siguiente vuelta.
   EXEC ops.sp_marcar_arribo <corrida>, 'FIN' da todo por subido. */
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
            @p_c INT, @r_c INT, @p_d INT, @r_d INT, @p_t INT, @r_t INT, @ok_c BIT, @ok_d BIT, @ok_t BIT,
            @hecho_c BIT, @hecho_t BIT, @fin BIT, @listo_c BIT = 0, @listo_t BIT = 0, @res NVARCHAR(400) = N'',
            @err NVARCHAR(4000), @acc NVARCHAR(4000);

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
        EXEC ops.sp_arribo_bajar @cliente, 1;
    END;

    /* Sin foto (la asignación se corrió antes de esta versión o no alcanzó CYBER al terminar): se toma ahora
       y se compara en la siguiente vuelta */
    IF NOT EXISTS (SELECT 1 FROM ops.BITACORA WHERE ID_CORRIDA = @id AND PASO = 'ARRIBO BASE' AND ESTATUS = 'OK')
        EXEC ops.sp_arribo_base @id, @sin_bajar = 1;

    SELECT LTRIM(RTRIM(CUENTA)) AS CUENTA, MAX(UPPER(LTRIM(RTRIM(ISNULL(DOMICILIO, N''))))) AS DOM INTO #d
    FROM stg.CYBER_DELQMST_ACT WHERE CUENTA IS NOT NULL GROUP BY LTRIM(RTRIM(CUENTA));
    CREATE UNIQUE CLUSTERED INDEX IX ON #d (CUENTA);
    SELECT DISTINCT LTRIM(RTRIM(CUENTA)) AS CUENTA, LTRIM(RTRIM(AREA)) AS AREA, LTRIM(RTRIM(TELEFONO)) AS TELEFONO INTO #g
    FROM stg.CYBER_PHONE_G1 WHERE CUENTA IS NOT NULL;
    CREATE CLUSTERED INDEX IX ON #g (CUENTA, AREA, TELEFONO);

    SELECT @p_c = SUM(CASE WHEN p.TIPO = 'CUENTA' THEN 1 ELSE 0 END),
           @r_c = SUM(CASE WHEN p.TIPO = 'CUENTA' AND d.CUENTA IS NOT NULL THEN 1 ELSE 0 END),
           @p_d = SUM(CASE WHEN p.TIPO = 'DOMICILIO' THEN 1 ELSE 0 END),
           @r_d = SUM(CASE WHEN p.TIPO = 'DOMICILIO' AND d.DOM = ISNULL(p.VALOR, N'') THEN 1 ELSE 0 END),
           @p_t = SUM(CASE WHEN p.TIPO = 'TELEFONO' THEN 1 ELSE 0 END),
           @r_t = SUM(CASE WHEN p.TIPO = 'TELEFONO' AND g.CUENTA IS NOT NULL THEN 1 ELSE 0 END)
    FROM ops.ARRIBO_PENDIENTE p
    LEFT JOIN #d d ON d.CUENTA = p.CUENTA
    LEFT JOIN #g g ON p.TIPO = 'TELEFONO' AND g.CUENTA = p.CUENTA AND g.AREA = p.AREA AND g.TELEFONO = p.TELEFONO
    WHERE p.ID_CORRIDA = @id;
    SELECT @p_c = ISNULL(@p_c, 0), @r_c = ISNULL(@r_c, 0), @p_d = ISNULL(@p_d, 0), @r_d = ISNULL(@r_d, 0), @p_t = ISNULL(@p_t, 0), @r_t = ISNULL(@r_t, 0);
    SET @fin = CASE WHEN EXISTS (SELECT 1 FROM ops.BITACORA WHERE ID_CORRIDA = @id AND PASO = 'ARRIBO FIN') THEN 1 ELSE 0 END;

    SET @ok_c = CASE WHEN @p_c = 0 OR 100.0 * @r_c / @p_c >= @min THEN 1 ELSE 0 END;
    SET @ok_d = CASE WHEN @p_d = 0 OR 100.0 * @r_d / @p_d >= @min THEN 1 ELSE 0 END;
    SET @ok_t = CASE WHEN @p_t = 0 OR 100.0 * @r_t / @p_t >= @min THEN 1 ELSE 0 END;
    SET @listo_c = CASE WHEN @fin = 1 OR (@ok_c = 1 AND @ok_d = 1) THEN 1 ELSE 0 END;
    SET @listo_t = CASE WHEN @fin = 1 OR (@ok_t = 1 AND @ok_c = 1) THEN 1 ELSE 0 END;

    IF @listo_c = 1 AND @hecho_c = 0
    BEGIN
        BEGIN TRY
            EXEC ops.sp_arribar_cyber @id, 'CORREOS';
            SET @res += N'CORREOS OK · ';
        END TRY
        BEGIN CATCH
            SET @res += N'CORREOS ERROR · ';
            SET @err = ERROR_MESSAGE();
            SET @acc = CONCAT(N'Corregir la causa y correr EXEC ops.sp_arribar_cyber ', @id, N', ''CORREOS''; (con @solo_mostrar = 1 se ven los bloques sin ejecutar). El job no lo reintenta solo.');
            EXEC mail.sp_hallazgo @id, N'Arribo de correos a CYBER con error', @err, @acc;
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
            SET @err = ERROR_MESSAGE();
            SET @acc = CONCAT(N'Corregir la causa y correr EXEC ops.sp_arribar_cyber ', @id, N', ''TELEFONOS''; (con @solo_mostrar = 1 se ven los bloques sin ejecutar). El job no lo reintenta solo.');
            EXEC mail.sp_hallazgo @id, N'Arribo de teléfonos a CYBER con error', @err, @acc;
        END CATCH;
    END;

    SET @resultado = CASE WHEN @res = N'' THEN N'ESPERANDO ARRIBO' ELSE RTRIM(LEFT(@res, LEN(@res) - 1)) END;
    SELECT @resultado AS ARRIBO, @id AS CORRIDA,
           CONCAT(@r_c, N' de ', @p_c) AS CUENTAS_PENDIENTES_EN_CYBER, CONCAT(@r_d, N' de ', @p_d) AS DOMICILIOS_PENDIENTES_EN_CYBER,
           CONCAT(@r_t, N' de ', @p_t) AS TELEFONOS_PENDIENTES_EN_PHONE_G1;
END;
GO
