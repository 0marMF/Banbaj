USE [BNABAJ_486];
GO
/* =====================================================================
   Vistas de usuarios (18/11)
   ---------------------------------------------------------------------
   Usuarios externos (AEM, MIS…) con login de SQL Server que solo ven su
   esquema: <esquema>.DAT_486 con las columnas que el equipo de
   asignaciones configura en cfg.VISTA_COLUMNA y, si aplica,
   <esquema>.RETIROS_HOY (cuentas retiradas hoy en la actualización y en
   la asignación; antes el archivo MX_G1MCT_DVBJIG_* para \\.1\Cyber_00).

   Origen de cada columna (cfg.VISTA_COLUMNA.ORIGEN):
     DAT        columna de dat.DAT_486
     CYBER      columna de RCVRY.RPT_DAT_486_1, después de correr RCVRY.PROC_DAT_486
     MAESTRA    encabezado de la base maestra (último renglón de la cuenta, dat.BASE_MAESTRA_CUENTA)
     CONSTANTE  valor fijo
   Los textos van recortados (decisión 18/11).

   ops.sp_vistas_usuario_refrescar  lo llaman la actualización y la asignación al
                                    terminar OK, y el arribo cuando suben los saldos:
     1. ops.sp_dat_cyber_bajar     ejecuta RCVRY.PROC_DAT_486 y baja las columnas de CYBER
     2. ops.sp_vistas_usuario_armar arma la tabla de cada usuario (se rearma aparte y se
                                    cambia de golpe: nunca la ven vacía ni a medias)
   cfg.sp_vista_columna_alta        agrega o cambia una columna (revisa que el campo exista)
   cfg.sp_vista_usuario_login       crea el login con su contraseña (no se guarda) y le da su rol

   Diagrama: docs/flujo/10_vistas_usuario.md · Errores 50830-50839
   ===================================================================== */
SET NOCOUNT ON;
GO

/* Ejecuta RCVRY.PROC_DAT_486 en CYBER y baja de RPT_DAT_486_1 solo las columnas que pide alguna vista activa.
   @sin_ejecutar = 1 no corre el store; @sin_bajar = 1 toma lo que ya esté en stg.CYBER_DAT_486 (pruebas). */
CREATE OR ALTER PROCEDURE ops.sp_dat_cyber_bajar
    @id_corrida   INT,
    @sin_ejecutar BIT = 0,
    @sin_bajar    BIT = 0,
    @solo_mostrar BIT = 0,
    @filas        INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @cliente VARCHAR(10) = (SELECT CLIENTE FROM ops.CORRIDA WHERE ID_CORRIDA = @id_corrida);
    DECLARE @srv SYSNAME = ISNULL(cfg.fn_param(@cliente, 'CYBER_LINKED_SERVER'), 'CYBER'),
            @store NVARCHAR(200) = ISNULL(NULLIF(cfg.fn_param(@cliente, 'DAT_CYBER_STORE'), N''), N'RCVRY.PROC_DAT_486'),
            @tabla NVARCHAR(200) = ISNULL(NULLIF(cfg.fn_param(@cliente, 'DAT_CYBER_TABLA'), N''), N'RCVRY.RPT_DAT_486_1'),
            @llave SYSNAME       = ISNULL(NULLIF(cfg.fn_param(@cliente, 'DAT_CYBER_LLAVE'), N''), N'CUENTA'),
            @cols NVARCHAR(MAX), @def NVARCHAR(MAX), @json NVARCHAR(MAX), @sql NVARCHAR(MAX), @q NVARCHAR(MAX), @msg NVARCHAR(4000);
    IF @cliente IS NULL THROW 50830, 'La corrida no existe.', 1;

    SELECT DISTINCT UPPER(LTRIM(RTRIM(c.CAMPO))) AS CAMPO
    INTO #c
    FROM cfg.VISTA_COLUMNA c JOIN cfg.VISTA_USUARIO u ON u.CLIENTE = c.CLIENTE AND u.VISTA = c.VISTA
    WHERE c.CLIENTE = @cliente AND c.ORIGEN = 'CYBER' AND c.ACTIVO = 1 AND u.ACTIVO = 1;
    IF NOT EXISTS (SELECT 1 FROM #c)
    BEGIN
        EXEC ops.sp_log @id_corrida, 'DAT CYBER', 'OK', 0, N'Ninguna vista pide columnas de CYBER';
        SET @filas = 0;
        RETURN;
    END;
    IF EXISTS (SELECT 1 FROM #c WHERE CAMPO LIKE N'%[^A-Z0-9_]%' OR CAMPO = UPPER(@llave))
       OR @store LIKE N'%[^A-Za-z0-9_.]%' OR @tabla LIKE N'%[^A-Za-z0-9_.]%' OR @llave LIKE N'%[^A-Za-z0-9_]%'
        THROW 50831, 'Columna, tabla o store de CYBER con caracteres inválidos (solo letras, números y _).', 1;

    SELECT @cols = STRING_AGG(CAST(CAMPO AS NVARCHAR(MAX)), N', ') WITHIN GROUP (ORDER BY CAMPO),
           @def  = STRING_AGG(CAST(QUOTENAME(CAMPO) + N' NVARCHAR(400) NULL' AS NVARCHAR(MAX)), N', ') WITHIN GROUP (ORDER BY CAMPO),
           @json = STRING_AGG(CAST(N's.' + QUOTENAME(CAMPO) AS NVARCHAR(MAX)), N', ') WITHIN GROUP (ORDER BY CAMPO)
    FROM #c;

    /* 1. El store llena RPT_DAT_486_1 con los datos del momento (única forma de tenerlos actualizados) */
    IF @sin_ejecutar = 0
    BEGIN
        DELETE FROM ops.CYBER_SCRIPT WHERE ID_CORRIDA = @id_corrida AND SCRIPT = 'DAT_CYBER';
        INSERT INTO ops.CYBER_SCRIPT (ID_CORRIDA, SCRIPT, NUM, SENTENCIA)
        VALUES (@id_corrida, 'DAT_CYBER', 1, CONCAT(N'EXECUTE ', @store, N';')), (@id_corrida, 'DAT_CYBER', 2, N'COMMIT;');
        EXEC ops.sp_cyber_ejecutar @id_corrida, 'DAT_CYBER', @solo_mostrar;
        IF @solo_mostrar = 0
        BEGIN
            SET @msg = CONCAT(@store, N' ejecutado en CYBER');
            EXEC ops.sp_log @id_corrida, 'DAT CYBER STORE', 'OK', NULL, @msg;
        END;
    END;

    /* 2. Se bajan la llave y las columnas pedidas */
    IF @sin_bajar = 0
    BEGIN
        SET @q = N'select ' + @llave + N', ' + @cols + N' from ' + @tabla + N' where ' + @llave + N' is not null';
        IF @solo_mostrar = 1
        BEGIN
            SELECT 'DAT_CYBER' AS SCRIPT, @q AS CONSULTA;
            RETURN;
        END;
        IF NOT EXISTS (SELECT 1 FROM sys.servers WHERE name = @srv)
        BEGIN
            SET @msg = CONCAT(N'No existe el servidor vinculado ', @srv, N'.');
            THROW 50832, @msg, 1;
        END;
        SET @sql = N'DROP TABLE IF EXISTS stg.CYBER_DAT_486; CREATE TABLE stg.CYBER_DAT_486 (CUENTA NVARCHAR(60) NULL, ' + @def + N');';
        EXEC (@sql);
        SET @sql = N'INSERT INTO stg.CYBER_DAT_486 (CUENTA, ' + @cols + N') EXEC (N''' + REPLACE(@q, N'''', N'''''') + N''') AT ' + QUOTENAME(@srv) + N';';
        EXEC (@sql);
    END
    ELSE IF @solo_mostrar = 1
        RETURN;
    IF OBJECT_ID('stg.CYBER_DAT_486') IS NULL
        THROW 50833, 'No hay datos de CYBER en stg.CYBER_DAT_486.', 1;
    /* Columnas pedidas que no llegaron (solo con @sin_bajar) se agregan vacías */
    SET @sql = (SELECT STRING_AGG(CAST(N'ALTER TABLE stg.CYBER_DAT_486 ADD ' + QUOTENAME(c.CAMPO) + N' NVARCHAR(400) NULL;' AS NVARCHAR(MAX)), N' ')
                FROM #c c WHERE COL_LENGTH('stg.CYBER_DAT_486', c.CAMPO) IS NULL);
    IF @sql IS NOT NULL EXEC (@sql);

    /* 3. Si no llegó nada no se toca lo que ya había (las vistas siguen con lo anterior) */
    SET @sql = N'SELECT @n = COUNT(*) FROM stg.CYBER_DAT_486 WHERE NULLIF(LTRIM(RTRIM(CUENTA)), N'''') IS NOT NULL;';
    EXEC sp_executesql @sql, N'@n INT OUTPUT', @n = @filas OUTPUT;
    IF @filas = 0
    BEGIN
        SET @msg = CONCAT(@tabla, N' llegó vacía: las vistas se quedan con lo que bajó la última vez.');
        THROW 50834, @msg, 1;
    END;
    BEGIN TRANSACTION;
        DELETE FROM dat.CYBER_DAT WHERE CLIENTE = @cliente;
        SET @sql = N'INSERT INTO dat.CYBER_DAT (CLIENTE, CUENTA, DATOS, ID_CORRIDA)
                     SELECT @cliente, x.CUENTA, (SELECT ' + @json + N' FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES), @id_corrida
                     FROM (SELECT *, LTRIM(RTRIM(CUENTA)) AS CUENTA_L, ROW_NUMBER() OVER (PARTITION BY LTRIM(RTRIM(CUENTA)) ORDER BY (SELECT NULL)) AS RN
                           FROM stg.CYBER_DAT_486 WHERE NULLIF(LTRIM(RTRIM(CUENTA)), N'''') IS NOT NULL) s
                     CROSS APPLY (SELECT CAST(s.CUENTA_L AS VARCHAR(28)) AS CUENTA) x
                     WHERE s.RN = 1;';
        EXEC sp_executesql @sql, N'@cliente VARCHAR(10), @id_corrida INT', @cliente = @cliente, @id_corrida = @id_corrida;
        SET @filas = @@ROWCOUNT;
    COMMIT TRANSACTION;
    DROP TABLE IF EXISTS stg.CYBER_DAT_486;
    SET @msg = CONCAT(N'Bajadas de ', @tabla, N': ', @filas, N' cuentas · columnas ', @cols);
    EXEC ops.sp_log @id_corrida, 'DAT CYBER', 'OK', @filas, @msg;
END;
GO

/* Arma la tabla <esquema>.DAT_486 de cada usuario activo con sus columnas, y su vista RETIROS_HOY.
   Un campo que no existe no detiene: se arma sin él (o vacío) y queda en @avisos. @id_corrida puede ir vacío
   (a mano, después de cambiar cfg.VISTA_COLUMNA): entonces no se escribe en la bitácora. */
CREATE OR ALTER PROCEDURE ops.sp_vistas_usuario_armar
    @id_corrida INT           = NULL,
    @cliente    VARCHAR(10)   = '486',
    @vista      VARCHAR(30)   = NULL,          -- NULL = todas
    @avisos     NVARCHAR(MAX) = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    IF @id_corrida IS NOT NULL SET @cliente = (SELECT CLIENTE FROM ops.CORRIDA WHERE ID_CORRIDA = @id_corrida);
    DECLARE @v VARCHAR(30), @esq SYSNAME, @rol SYSNAME, @activo BIT, @ret BIT, @sql NVARCHAR(MAX), @sel NVARCHAR(MAX),
            @join_m NVARCHAR(MAX) = N'', @aviso NVARCHAR(MAX), @n INT, @msg NVARCHAR(4000), @mc NVARCHAR(MAX), @ml NVARCHAR(MAX), @ddl NVARCHAR(MAX);
    SET @avisos = NULL;

    /* Columnas del DAT y llaves que existen en CYBER y en las bases maestras */
    SELECT c.name AS CAMPO, t.name AS TIPO INTO #dat
    FROM sys.columns c JOIN sys.types t ON t.user_type_id = c.user_type_id WHERE c.object_id = OBJECT_ID('dat.DAT_486');
    SELECT DISTINCT j.[key] AS CAMPO INTO #cyber
    FROM (SELECT TOP (50) DATOS FROM dat.CYBER_DAT WHERE CLIENTE = @cliente) x CROSS APPLY OPENJSON(x.DATOS) j;
    SELECT DISTINCT j.[key] AS CAMPO INTO #maestra
    FROM (SELECT CODIGO, MAX(LLAVE) AS LLAVE FROM dat.BASE_MAESTRA_CUENTA WHERE CLIENTE = @cliente GROUP BY CODIGO) k
    JOIN dat.BASE_MAESTRA_CUENTA m ON m.CLIENTE = @cliente AND m.CODIGO = k.CODIGO AND m.LLAVE = k.LLAVE
    CROSS APPLY OPENJSON(m.DATOS) j;

    /* Qué base maestra y qué llave corresponden a cada cuenta del DAT, según su segmento */
    SELECT @mc = STRING_AGG(CAST(N'WHEN ''' + REPLACE(SEGMENTO2, '''', '''''') + N''' THEN ''' + CODIGO + N'''' AS NVARCHAR(MAX)), N' '),
           @ml = STRING_AGG(CAST(N'WHEN ''' + REPLACE(SEGMENTO2, '''', '''''') + N''' THEN CAST(LTRIM(RTRIM(d.' + QUOTENAME(LLAVE_DAT) + N')) AS NVARCHAR(60))' AS NVARCHAR(MAX)), N' ')
    FROM cfg.ARCHIVO
    WHERE CLIENTE = @cliente AND PROCESO = 'ASIG' AND GUARDAR_COMPLETO = 1 AND ACTIVO = 1 AND SEGMENTO2 IS NOT NULL
      AND LLAVE_DAT IN (SELECT CAMPO FROM #dat);
    IF @mc IS NOT NULL
        SET @join_m = N' CROSS APPLY (SELECT CASE d.SEGMENTO2 ' + @mc + N' END AS CODIGO, CASE d.SEGMENTO2 ' + @ml + N' END AS LLAVE) k'
                    + N' LEFT JOIN dat.BASE_MAESTRA_CUENTA m ON m.CLIENTE = @cliente AND m.CODIGO = k.CODIGO AND m.LLAVE = k.LLAVE';

    DECLARE cv CURSOR LOCAL FAST_FORWARD FOR
        SELECT VISTA, LOWER(VISTA), ACTIVO, VER_RETIROS FROM cfg.VISTA_USUARIO
        WHERE CLIENTE = @cliente AND (@vista IS NULL OR VISTA = @vista) ORDER BY VISTA;
    OPEN cv; FETCH NEXT FROM cv INTO @v, @esq, @activo, @ret;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @rol = N'rol_' + @esq;
        SET @aviso = NULL;
        /* Esquema y rol del usuario: solo SELECT sobre su esquema */
        IF SCHEMA_ID(@esq) IS NULL BEGIN SET @ddl = N'CREATE SCHEMA ' + QUOTENAME(@esq) + N' AUTHORIZATION dbo;'; EXEC (@ddl); END;
        IF DATABASE_PRINCIPAL_ID(@rol) IS NULL BEGIN SET @ddl = N'CREATE ROLE ' + QUOTENAME(@rol) + N' AUTHORIZATION dbo;'; EXEC (@ddl); END;
        BEGIN SET @ddl = N'GRANT SELECT ON SCHEMA::' + QUOTENAME(@esq) + N' TO ' + QUOTENAME(@rol) + N';'; EXEC (@ddl); END;

        IF @activo = 0
        BEGIN
            /* Usuario dado de baja: deja de ver datos */
            BEGIN SET @ddl = N'DROP VIEW IF EXISTS ' + QUOTENAME(@esq) + N'.RETIROS_HOY; DROP TABLE IF EXISTS ' + QUOTENAME(@esq) + N'.DAT_486;'; EXEC (@ddl); END;
            IF @id_corrida IS NOT NULL
            BEGIN
                SET @msg = CONCAT(@v, N' inactivo: sin datos');
                EXEC ops.sp_log @id_corrida, 'VISTA USUARIO', 'OK', 0, @msg;
            END;
            FETCH NEXT FROM cv INTO @v, @esq, @activo, @ret;
            CONTINUE;
        END;

        /* Columnas: las que no existen se reportan; DAT inexistente se omite, CYBER y MAESTRA quedan vacías */
        SELECT c.ORDEN, c.ID, c.ENCABEZADO, c.ORIGEN, LTRIM(RTRIM(c.CAMPO)) AS CAMPO, d.TIPO,
               CASE WHEN c.ORIGEN = 'DAT' AND d.CAMPO IS NULL THEN N'el DAT no tiene la columna ' + c.CAMPO
                    WHEN c.ORIGEN = 'CYBER' AND y.CAMPO IS NULL THEN N'no bajó de CYBER la columna ' + c.CAMPO
                    WHEN c.ORIGEN = 'MAESTRA' AND @mc IS NULL THEN N'no hay bases maestras guardadas'
                    WHEN c.ORIGEN = 'MAESTRA' AND m.CAMPO IS NULL THEN N'la base maestra no trae el encabezado ' + c.CAMPO
               END AS PROBLEMA
        INTO #col
        FROM cfg.VISTA_COLUMNA c
        LEFT JOIN #dat d ON c.ORIGEN = 'DAT' AND d.CAMPO = LTRIM(RTRIM(c.CAMPO))
        LEFT JOIN #cyber y ON c.ORIGEN = 'CYBER' AND UPPER(y.CAMPO) = UPPER(LTRIM(RTRIM(c.CAMPO)))
        LEFT JOIN #maestra m ON c.ORIGEN = 'MAESTRA' AND m.CAMPO = LTRIM(RTRIM(c.CAMPO))
        WHERE c.CLIENTE = @cliente AND c.VISTA = @v AND c.ACTIVO = 1;

        SET @aviso = (SELECT STRING_AGG(CAST(ENCABEZADO + N': ' + PROBLEMA AS NVARCHAR(MAX)), N'; ') WITHIN GROUP (ORDER BY ORDEN, ID)
                      FROM #col WHERE PROBLEMA IS NOT NULL);
        SET @sel = (SELECT STRING_AGG(CAST(
                        CASE ORIGEN
                            WHEN 'DAT' THEN CASE WHEN TIPO IN ('varchar','nvarchar','char','nchar') THEN N'LTRIM(RTRIM(d.' + QUOTENAME(CAMPO) + N'))'
                                                 ELSE N'd.' + QUOTENAME(CAMPO) END
                            WHEN 'CYBER' THEN N'LTRIM(RTRIM(JSON_VALUE(c.DATOS, N''$."' + REPLACE(REPLACE(UPPER(CAMPO), N'\', N'\\'), N'''', N'''''') + N'"'')))'
                            WHEN 'MAESTRA' THEN CASE WHEN @mc IS NULL THEN N'CAST(NULL AS NVARCHAR(400))'
                                                ELSE N'LTRIM(RTRIM(JSON_VALUE(m.DATOS, N''$."' + REPLACE(REPLACE(REPLACE(CAMPO, N'\', N'\\'), N'"', N'\"'), N'''', N'''''') + N'"'')))' END
                            ELSE CASE WHEN CAMPO NOT LIKE N'%[^0-9]%' AND LEN(CAMPO) BETWEEN 1 AND 9 THEN CAMPO
                                      ELSE N'N''' + REPLACE(CAMPO, N'''', N'''''') + N'''' END
                        END + N' AS ' + QUOTENAME(ENCABEZADO) AS NVARCHAR(MAX)), N', ') WITHIN GROUP (ORDER BY ORDEN, ID)
                    FROM #col WHERE NOT (ORIGEN = 'DAT' AND PROBLEMA IS NOT NULL));
        DROP TABLE #col;

        IF @sel IS NULL
            SET @aviso = CONCAT(@aviso, CASE WHEN @aviso IS NOT NULL THEN N'; ' END, N'sin columnas activas: no se armó la tabla');
        ELSE
        BEGIN
            /* Se arma aparte y se cambia de golpe */
            SET @sql = N'DROP TABLE IF EXISTS ' + QUOTENAME(@esq) + N'.DAT_486_NUEVA; SELECT ' + @sel
                     + N' INTO ' + QUOTENAME(@esq) + N'.DAT_486_NUEVA FROM dat.DAT_486 d'
                     + N' LEFT JOIN dat.CYBER_DAT c ON c.CLIENTE = @cliente AND c.CUENTA = d.CUENTA2' + @join_m
                     + N' WHERE d.CLIENTE = @cliente OR d.CLIENTE IS NULL; SET @n = @@ROWCOUNT;';
            EXEC sp_executesql @sql, N'@cliente VARCHAR(10), @n INT OUTPUT', @cliente = @cliente, @n = @n OUTPUT;
            BEGIN TRANSACTION;
                BEGIN SET @ddl = N'DROP TABLE IF EXISTS ' + QUOTENAME(@esq) + N'.DAT_486;'; EXEC (@ddl); END;
                SET @sql = QUOTENAME(@esq) + N'.DAT_486_NUEVA';
                EXEC sp_rename @sql, N'DAT_486';
            COMMIT TRANSACTION;
        END;

        /* Retiros del día (actualización y asignación; un cierre por reasignación no es retiro) */
        IF @ret = 1
            BEGIN SET @ddl = N'CREATE OR ALTER VIEW ' + QUOTENAME(@esq) + N'.RETIROS_HOY
AS
SELECT DISTINCT h.CUENTA2 AS CUENTA
FROM dat.HISTORIA_FOLIO h
JOIN ops.CORRIDA c ON c.ID_CORRIDA = h.ID_CORRIDA_BAJA
WHERE h.CLIENTE = ''' + @cliente + N''' AND h.ESTATUS = ''B'' AND c.PROCESO IN (''ACT'', ''ASIG'')
  AND c.FECHA_PROCESO = CAST(SYSDATETIME() AS DATE)
  AND ISNULL(h.MOTIVO_BAJA, '''') <> ''CIERRE POR REASIGNACION'';'; EXEC (@ddl); END
        ELSE
            BEGIN SET @ddl = N'DROP VIEW IF EXISTS ' + QUOTENAME(@esq) + N'.RETIROS_HOY;'; EXEC (@ddl); END;

        SET @msg = LEFT(CONCAT(@v, N': ', ISNULL(@n, 0), N' cuentas', CASE WHEN @aviso IS NOT NULL THEN N' · ' + @aviso END), 4000);
        IF @id_corrida IS NOT NULL
        BEGIN
            SET @ddl = CASE WHEN @aviso IS NULL THEN N'OK' ELSE N'AVISO' END;
            EXEC ops.sp_log @id_corrida, 'VISTA USUARIO', @ddl, @n, @msg;
        END
        ELSE
            PRINT @msg;
        IF @aviso IS NOT NULL
            SET @avisos = CONCAT(@avisos, CASE WHEN @avisos IS NOT NULL THEN N' | ' END, @v, N': ', @aviso);
        SET @n = NULL;
        FETCH NEXT FROM cv INTO @v, @esq, @activo, @ret;
    END;
    CLOSE cv; DEALLOCATE cv;
END;
GO

/* Paso completo (actualización, asignación y saldos arriba): store y bajada de CYBER, luego las tablas.
   Si CYBER falla, las tablas se arman igual con lo último que bajó y se avisa. Idempotente por @paso. */
CREATE OR ALTER PROCEDURE ops.sp_vistas_usuario_refrescar
    @id_corrida   INT,
    @paso         VARCHAR(40) = 'VISTAS USUARIO',
    @sin_ejecutar BIT = 0,
    @sin_bajar    BIT = 0,
    @forzar       BIT = 0,          -- 1 = aunque el paso ya esté OK (a mano)
    @solo_prueba  BIT = 0           -- hallazgo sin enviar (pruebas)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @cliente VARCHAR(10) = (SELECT CLIENTE FROM ops.CORRIDA WHERE ID_CORRIDA = @id_corrida);
    DECLARE @err NVARCHAR(4000), @avisos NVARCHAR(MAX), @msg NVARCHAR(4000), @acc NVARCHAR(4000);
    IF ISNULL(cfg.fn_param(@cliente, 'VISTAS_USUARIO'), '0') <> '1' AND @forzar = 0 RETURN;
    IF @forzar = 0 AND EXISTS (SELECT 1 FROM ops.BITACORA WHERE ID_CORRIDA = @id_corrida AND PASO = @paso AND ESTATUS IN ('OK', 'AVISO')) RETURN;

    BEGIN TRY
        EXEC ops.sp_dat_cyber_bajar @id_corrida, @sin_ejecutar = @sin_ejecutar, @sin_bajar = @sin_bajar;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SET @err = ERROR_MESSAGE();
        EXEC ops.sp_log @id_corrida, 'DAT CYBER', 'ERROR', NULL, @err;
    END CATCH;

    BEGIN TRY
        EXEC ops.sp_vistas_usuario_armar @id_corrida, @avisos = @avisos OUTPUT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SET @msg = ERROR_MESSAGE();
        EXEC ops.sp_log @id_corrida, @paso, 'ERROR', NULL, @msg;
        SET @acc = CONCAT(N'Revisar el error y volver a correr EXEC ops.sp_vistas_usuario_refrescar ', @id_corrida, N', @forzar = 1;');
        EXEC mail.sp_hallazgo @id_corrida, N'Vistas de usuarios sin actualizar', @msg, @acc, NULL, @solo_prueba;
        RETURN;
    END CATCH;

    SET @msg = LEFT(CONCAT(CASE WHEN @err IS NULL THEN N'Vistas de usuarios actualizadas'
                                ELSE N'Vistas actualizadas con los datos de CYBER de la vez anterior (' + @err + N')' END,
                           CASE WHEN @avisos IS NOT NULL THEN N' · ' + @avisos END), 4000);
    SET @acc = CASE WHEN @err IS NULL AND @avisos IS NULL THEN N'OK' ELSE N'AVISO' END;
    EXEC ops.sp_log @id_corrida, @paso, @acc, NULL, @msg;
    IF @err IS NOT NULL OR @avisos IS NOT NULL
    BEGIN
        SET @acc = CASE WHEN @err IS NOT NULL
                        THEN CONCAT(N'Revisar el error de CYBER (permisos de EXECUTE en RCVRY.PROC_DAT_486 y SELECT en RCVRY.RPT_DAT_486_1) y volver a correr EXEC ops.sp_vistas_usuario_refrescar ', @id_corrida, N', @forzar = 1;')
                        ELSE N'El equipo de asignaciones revisa cfg.VISTA_COLUMNA (el campo debe existir en su origen) y corre EXEC ops.sp_vistas_usuario_armar;' END;
        EXEC mail.sp_hallazgo @id_corrida, N'Vistas de usuarios con avisos', @msg, @acc, NULL, @solo_prueba;
    END;
END;
GO

/* Agrega o cambia una columna de la vista de un usuario. Revisa que el campo exista en su origen. */
CREATE OR ALTER PROCEDURE cfg.sp_vista_columna_alta
    @vista      VARCHAR(30),
    @encabezado NVARCHAR(128),
    @origen     VARCHAR(10),
    @campo      NVARCHAR(200),
    @orden      INT         = NULL,      -- NULL = al final (o el que ya tenía)
    @activo     BIT         = 1,
    @cliente    VARCHAR(10) = '486'
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @msg NVARCHAR(4000), @existe BIT = 1;
    SET @origen = UPPER(LTRIM(RTRIM(@origen)));
    SET @campo = LTRIM(RTRIM(@campo));
    IF NOT EXISTS (SELECT 1 FROM cfg.VISTA_USUARIO WHERE CLIENTE = @cliente AND VISTA = @vista)
    BEGIN
        SET @msg = CONCAT(N'No existe la vista ', @vista, N' en cfg.VISTA_USUARIO.');
        THROW 50835, @msg, 1;
    END;
    IF @origen NOT IN ('DAT', 'CYBER', 'MAESTRA', 'CONSTANTE')
        THROW 50836, 'El origen debe ser DAT, CYBER, MAESTRA o CONSTANTE.', 1;
    IF @origen = 'DAT' AND COL_LENGTH('dat.DAT_486', @campo) IS NULL
    BEGIN
        SET @msg = CONCAT(N'El DAT no tiene la columna ', @campo, N'.');
        THROW 50837, @msg, 1;
    END;
    IF @origen = 'CYBER' AND @campo LIKE N'%[^A-Za-z0-9_]%'
        THROW 50838, 'La columna de CYBER solo puede tener letras, números y _.', 1;
    IF @origen = 'MAESTRA' AND NOT EXISTS (SELECT 1 FROM dat.BASE_MAESTRA_CUENTA m CROSS APPLY OPENJSON(m.DATOS) j
                                           WHERE m.CLIENTE = @cliente AND j.[key] = @campo
                                             AND m.LLAVE = (SELECT MAX(x.LLAVE) FROM dat.BASE_MAESTRA_CUENTA x WHERE x.CLIENTE = @cliente AND x.CODIGO = m.CODIGO))
        SET @existe = 0;

    IF EXISTS (SELECT 1 FROM cfg.VISTA_COLUMNA WHERE CLIENTE = @cliente AND VISTA = @vista AND ENCABEZADO = @encabezado)
        UPDATE cfg.VISTA_COLUMNA SET ORIGEN = @origen, CAMPO = @campo, ORDEN = ISNULL(@orden, ORDEN), ACTIVO = @activo
        WHERE CLIENTE = @cliente AND VISTA = @vista AND ENCABEZADO = @encabezado;
    ELSE
        INSERT INTO cfg.VISTA_COLUMNA (CLIENTE, VISTA, ORDEN, ENCABEZADO, ORIGEN, CAMPO, ACTIVO)
        VALUES (@cliente, @vista, ISNULL(@orden, (SELECT ISNULL(MAX(ORDEN), 0) + 10 FROM cfg.VISTA_COLUMNA WHERE CLIENTE = @cliente AND VISTA = @vista)),
                @encabezado, @origen, @campo, @activo);
    SET @msg = CONCAT(@vista, N'.', @encabezado, N' = ', @origen, N' ', @campo,
                      CASE WHEN @existe = 0 THEN N' · AVISO: la última base maestra guardada no trae ese encabezado; quedará vacío hasta que llegue' ELSE N'' END,
                      N'. Se aplica en la siguiente actualización o con EXEC ops.sp_vistas_usuario_armar;');
    PRINT @msg;
END;
GO

/* Crea (o cambia la contraseña de) el login de SQL Server de un usuario y le da su rol. La contraseña no se guarda.
   Requiere permisos para crear logins (securityadmin). */
CREATE OR ALTER PROCEDURE cfg.sp_vista_usuario_login
    @vista    VARCHAR(30),
    @login    SYSNAME,
    @password NVARCHAR(128),
    @cliente  VARCHAR(10) = '486'
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @esq SYSNAME = LOWER(@vista), @rol SYSNAME, @sql NVARCHAR(MAX), @msg NVARCHAR(4000), @ddl NVARCHAR(MAX);
    SET @rol = N'rol_' + @esq;
    IF NOT EXISTS (SELECT 1 FROM cfg.VISTA_USUARIO WHERE CLIENTE = @cliente AND VISTA = @vista)
    BEGIN
        SET @msg = CONCAT(N'No existe la vista ', @vista, N' en cfg.VISTA_USUARIO.');
        THROW 50835, @msg, 1;
    END;
    IF @login LIKE N'%[^A-Za-z0-9_.-]%' OR LEN(@login) < 3
        THROW 50839, 'El login solo puede tener letras, números, punto, guion y guion bajo.', 1;
    IF SCHEMA_ID(@esq) IS NULL OR DATABASE_PRINCIPAL_ID(@rol) IS NULL
        EXEC ops.sp_vistas_usuario_armar @cliente = @cliente, @vista = @vista;

    IF SUSER_ID(@login) IS NULL
        SET @sql = N'CREATE LOGIN ' + QUOTENAME(@login) + N' WITH PASSWORD = @p, DEFAULT_DATABASE = ' + QUOTENAME(DB_NAME())
                 + N', CHECK_POLICY = ON, CHECK_EXPIRATION = OFF;';
    ELSE
        SET @sql = N'ALTER LOGIN ' + QUOTENAME(@login) + N' WITH PASSWORD = @p;';
    /* CREATE/ALTER LOGIN no acepta variables: la contraseña se escapa y va en el texto (no se guarda en ningún lado) */
    SET @sql = REPLACE(@sql, N'@p', N'N''' + REPLACE(@password, N'''', N'''''') + N'''');
    EXEC (@sql);
    IF DATABASE_PRINCIPAL_ID(@login) IS NULL
        BEGIN SET @ddl = N'CREATE USER ' + QUOTENAME(@login) + N' FOR LOGIN ' + QUOTENAME(@login) + N' WITH DEFAULT_SCHEMA = ' + QUOTENAME(@esq) + N';'; EXEC (@ddl); END;
    IF IS_ROLEMEMBER(@rol, @login) = 0 OR IS_ROLEMEMBER(@rol, @login) IS NULL
        BEGIN SET @ddl = N'ALTER ROLE ' + QUOTENAME(@rol) + N' ADD MEMBER ' + QUOTENAME(@login) + N';'; EXEC (@ddl); END;
    UPDATE cfg.VISTA_USUARIO SET LOGIN = @login WHERE CLIENTE = @cliente AND VISTA = @vista;
    SET @msg = CONCAT(N'Login ', @login, N' listo: solo ve el esquema ', @esq, N' (', @esq, N'.DAT_486',
                      CASE WHEN EXISTS (SELECT 1 FROM cfg.VISTA_USUARIO WHERE CLIENTE = @cliente AND VISTA = @vista AND VER_RETIROS = 1) THEN N' y ' + @esq + N'.RETIROS_HOY' ELSE N'' END, N').');
    PRINT @msg;
END;
GO
