USE [BNABAJ_486];   -- base del 486 (si la instalas con otro nombre, cámbialo aquí)
GO
/* =====================================================================
   Banbaj · 76 Arribo automático a CYBER de teléfonos y correos (decisión 02/11)
   ---------------------------------------------------------------------
   El operador solo sube los archivos de ancho fijo con el cargador de CYBER
   (SCBSDOS, SCBTEL, gescar). Lo demás lo hace SQL Server por el servidor
   vinculado [CYBER], sin sqlldr ni scripts a mano:

   Orden (decisión 17/11):
     1. Asignaciones sube el SCBSDOS. Saldos arriba (DMHOSTUP del día = cuentas del SCBSDOS) -> paso ARRIBO SALDOS:
        se escriben y avisan los gescar de nuevas y reasignadas.
     2. Depuración de teléfonos: vacía la remesa (y crea el renglón del validador) y la carga; si
        RCVRY.JSP_TAB_TEL_REMESA_486 tiene los mismos renglones que nuestro archivo de teléfonos
        (ops.sp_tel_remesa_validar), ejecuta JSP_TELEFONOS_REMESA_486, que inactiva lo que no está
        en la remesa. Entonces se escribe el SCBTEL y se avisa a asignaciones que ya lo puede subir.
     3. Depuración de correos (con la de teléfonos OK): correos nuevos en ADDRESS, bandera 416,
        remesa y JSP_CORREOS_486, bandera apagada.
     4. Asignaciones sube el SCBTEL (los teléfonos que le faltaban a PHONE_G1 ya llegaron) ->
        gescar de cuentas sin teléfono (SCBACTH_SINTEL.TXT, ops.sp_arribo_gescar_sintel).
     5. Blanqueo de status y confirmación de la asignación (ops.sp_arribo_posterior).

   ops.sp_arribo_automatico lo llama el job (ops.sp_diario_486) cada 30 minutos
   cuando la asignación del día ya terminó. Cada proceso corre una sola vez por
   corrida; si falla, queda ERROR en la bitácora y no se reintenta solo:
   se avisa al equipo de asignaciones (HALLAZGO_486), se corrige y se corre a mano con
   EXEC ops.sp_arribar_cyber <corrida>, '<CORREOS|TELEFONOS>';  o  EXEC ops.sp_arribo_gescar_sintel <corrida>;
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

/* La remesa de teléfonos que quedó en CYBER (RCVRY.JSP_TAB_TEL_REMESA_486) tiene que tener los mismos renglones que
   nuestro archivo de teléfonos (ops.TELEFONO, lo que va en sub_mst.TXT). Si no, JSP_TELEFONOS_REMESA_486 inactivaría
   teléfonos buenos: no se ejecuta y se avisa. @conteo_cyber sirve para probar sin servidor vinculado. */
CREATE OR ALTER PROCEDURE ops.sp_tel_remesa_validar
    @id_corrida   INT,
    @conteo_cyber INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @cliente VARCHAR(10) = (SELECT CLIENTE FROM ops.CORRIDA WHERE ID_CORRIDA = @id_corrida);
    DECLARE @srv SYSNAME = ISNULL(cfg.fn_param(@cliente, 'CYBER_LINKED_SERVER'), 'CYBER'), @nuestro INT, @archivo INT, @msg NVARCHAR(4000), @sql NVARCHAR(MAX);
    SET @nuestro = (SELECT COUNT(*) FROM ops.TELEFONO WHERE ID_CORRIDA = @id_corrida);
    SET @archivo = (SELECT COUNT(*) FROM ops.SALIDA_LINEA WHERE ID_CORRIDA = @id_corrida AND ARCHIVO = 'TEL_SUBMST');
    IF @conteo_cyber IS NULL
    BEGIN
        DECLARE @t TABLE (N INT);
        SET @sql = N'INSERT INTO @x (N) EXEC (N''select count(*) from RCVRY.JSP_TAB_TEL_REMESA_486'') AT ' + QUOTENAME(@srv) + N';';
        SET @sql = REPLACE(@sql, N'@x', N'#remesa');
        CREATE TABLE #remesa (N INT);
        EXEC (@sql);
        SET @conteo_cyber = (SELECT TOP (1) N FROM #remesa);
    END;
    SET @msg = CONCAT(N'RCVRY.JSP_TAB_TEL_REMESA_486: ', @conteo_cyber, N' · nuestro archivo de teléfonos: ', @nuestro,
                      CASE WHEN @archivo > 0 AND @archivo <> @nuestro THEN CONCAT(N' (sub_mst.TXT: ', @archivo, N')') ELSE N'' END);
    IF ISNULL(@conteo_cyber, -1) <> @nuestro
    BEGIN
        SET @msg = N'La remesa de teléfonos en CYBER no cuadra con nuestro archivo; no se ejecuta JSP_TELEFONOS_REMESA_486 (inactivaría teléfonos buenos). ' + @msg;
        EXEC ops.sp_log @id_corrida, 'TEL REMESA VALIDADA', 'ERROR', @conteo_cyber, @msg;
        THROW 50776, @msg, 1;
    END;
    EXEC ops.sp_log @id_corrida, 'TEL REMESA VALIDADA', 'OK', @conteo_cyber, @msg;
END;
GO

/* Gescar de cuentas nuevas y reasignadas sin teléfono activo en CYBER (ges486.prg), cuando asignaciones ya subió
   el SCBTEL: baja los teléfonos, arma SCBACTH_SINTEL.TXT, lo escribe y avisa. Paso GESCAR SIN TELEFONO, una vez. */
CREATE OR ALTER PROCEDURE ops.sp_arribo_gescar_sintel
    @id_corrida INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @msg NVARCHAR(4000), @n INT;
    BEGIN TRY
        EXEC ops.sp_bajar_cyber 'TELEFONOS', @id_corrida = @id_corrida;
        SET @n = (SELECT COUNT(*) FROM ops.SALIDA_LINEA WHERE ID_CORRIDA = @id_corrida AND ARCHIVO = 'GESCAR_SINTEL');
        SET @msg = CONCAT(N'Cuentas nuevas o reasignadas sin teléfono activo en CYBER: ', @n);
        BEGIN TRY
            IF @n > 0
            BEGIN
                EXEC ops.sp_exportar_salidas @id_corrida, @solo = 'GESCAR_SINTEL';
                SET @msg += N' · SCBACTH_SINTEL.TXT escrito en la carpeta de la corrida';
                EXEC ops.sp_aviso_archivos @id_corrida, @solo = 'GESCAR_SINTEL';
            END;
        END TRY
        BEGIN CATCH
            SET @msg += CONCAT(N' · no se pudo escribir SCBACTH_SINTEL.TXT: ', ERROR_MESSAGE());
        END CATCH;
        EXEC ops.sp_log @id_corrida, 'GESCAR SIN TELEFONO', 'OK', @n, @msg;
    END TRY
    BEGIN CATCH
        SET @msg = ERROR_MESSAGE();
        EXEC ops.sp_log @id_corrida, 'GESCAR SIN TELEFONO', 'ERROR', NULL, @msg;
        THROW;
    END CATCH;
END;
GO

/* Depuración con TEL_DEPURACION = NUEVOS (18/11): después de JSP_TELEFONOS_DEPURA_486 se bajan de la remesa los
   teléfonos que no existían en PHONE (NUEVO = 1). Se marcan en ops.TELEFONO, el SCBTEL se vuelve a generar solo con
   ellos y son lo que el arribo espera ver en PHONE_G1 para dar por subido el SCBTEL.
   @sin_bajar = 1 toma lo que ya esté en stg.CYBER_TEL_NUEVOS (pruebas). */
CREATE OR ALTER PROCEDURE ops.sp_tel_nuevos
    @id_corrida INT,
    @sin_bajar  BIT = 0,
    @nuevos     INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @cliente VARCHAR(10) = (SELECT CLIENTE FROM ops.CORRIDA WHERE ID_CORRIDA = @id_corrida);
    DECLARE @srv SYSNAME = ISNULL(cfg.fn_param(@cliente, 'CYBER_LINKED_SERVER'), 'CYBER'), @sql NVARCHAR(MAX), @msg NVARCHAR(4000), @sin INT;
    IF @sin_bajar = 0
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM sys.servers WHERE name = @srv)
        BEGIN
            SET @msg = CONCAT(N'No existe el servidor vinculado ', @srv, N'.');
            THROW 50777, @msg, 1;
        END;
        TRUNCATE TABLE stg.CYBER_TEL_NUEVOS;
        SET @sql = N'INSERT INTO stg.CYBER_TEL_NUEVOS (CUENTA, AREA, TELEFONO) EXEC (N''select CUENTA, AREA, TELEFONO from RCVRY.JSP_TAB_TEL_REMESA_486 where NUEVO = 1'') AT ' + QUOTENAME(@srv) + N';';
        EXEC (@sql);
    END;

    UPDATE t SET NUEVO = CASE WHEN EXISTS (SELECT 1 FROM stg.CYBER_TEL_NUEVOS n
                                           WHERE LTRIM(RTRIM(n.CUENTA)) = t.CUENTA2 AND LTRIM(RTRIM(n.AREA)) = t.AREA AND LTRIM(RTRIM(n.TELEFONO)) = t.TELEFONO)
                              THEN 1 ELSE 0 END
    FROM ops.TELEFONO t WHERE t.ID_CORRIDA = @id_corrida;
    SET @nuevos = (SELECT COUNT(*) FROM ops.TELEFONO WHERE ID_CORRIDA = @id_corrida AND NUEVO = 1);
    /* Nuevos en CYBER que no están en nuestro archivo: no debería pasar (la remesa salió de él) */
    SET @sin = (SELECT COUNT(*) FROM stg.CYBER_TEL_NUEVOS n
                WHERE NOT EXISTS (SELECT 1 FROM ops.TELEFONO t WHERE t.ID_CORRIDA = @id_corrida AND t.CUENTA2 = LTRIM(RTRIM(n.CUENTA))
                                    AND t.AREA = LTRIM(RTRIM(n.AREA)) AND t.TELEFONO = LTRIM(RTRIM(n.TELEFONO))));

    /* Lo que el arribo espera ver en PHONE_G1 cuando suban el SCBTEL: solo los nuevos */
    DELETE FROM ops.ARRIBO_PENDIENTE WHERE ID_CORRIDA = @id_corrida AND TIPO = 'TELEFONO';
    INSERT INTO ops.ARRIBO_PENDIENTE (ID_CORRIDA, TIPO, CUENTA, AREA, TELEFONO)
    SELECT @id_corrida, 'TELEFONO', CUENTA2, AREA, TELEFONO FROM ops.TELEFONO WHERE ID_CORRIDA = @id_corrida AND NUEVO = 1;

    /* El SCBTEL se vuelve a generar: su ORIGEN toma solo NUEVO = 1 una vez marcados */
    EXEC ops.sp_generar_salida @id_corrida, 'SCBTEL';
    SET @msg = CONCAT(N'Teléfonos nuevos (no existían en PHONE): ', @nuevos, N' de ', (SELECT COUNT(*) FROM ops.TELEFONO WHERE ID_CORRIDA = @id_corrida),
                      N' · el SCBTEL lleva solo esos', CASE WHEN @nuevos = 0 THEN N' (no hay SCBTEL que subir)' ELSE N'' END,
                      CASE WHEN @sin > 0 THEN CONCAT(N' · ', @sin, N' nuevos de CYBER que no están en nuestro archivo') ELSE N'' END);
    DECLARE @est VARCHAR(10) = CASE WHEN @sin > 0 THEN 'AVISO' ELSE 'OK' END;
    EXEC ops.sp_log @id_corrida, 'TEL NUEVOS', @est, @nuevos, @msg;
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
    DECLARE @cli VARCHAR(10), @modo NVARCHAR(20) = N'ACTUAL', @nuevos INT;
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
            /* El store depende del modo (TEL_DEPURACION): ACTUAL = el de hoy; NUEVOS = JSP_TELEFONOS_DEPURA_486 */
            SET @cli = (SELECT CLIENTE FROM ops.CORRIDA WHERE ID_CORRIDA = @id_corrida);
            SET @modo = UPPER(ISNULL(NULLIF(cfg.fn_param(@cli, 'TEL_DEPURACION'), N''), N'ACTUAL'));
            UPDATE ops.CYBER_SCRIPT
            SET SENTENCIA = CONCAT(N'EXECUTE ', CASE WHEN @modo = N'NUEVOS' THEN ISNULL(NULLIF(cfg.fn_param(@cli, 'CYBER_PROC_TEL_DEPURA'), N''), N'RCVRY.JSP_TELEFONOS_DEPURA_486')
                                                      ELSE ISNULL(NULLIF(cfg.fn_param(@cli, 'CYBER_PROC_TELEFONOS'), N''), N'RCVRY.JSP_TELEFONOS_REMESA_486') END, N';')
            WHERE ID_CORRIDA = @id_corrida AND SCRIPT = 'TEL_ACTUALIZA' AND NUM = 1;
            EXEC ops.sp_cyber_remesa @id_corrida, 'TEL', @n OUTPUT;
            EXEC ops.sp_cyber_ejecutar @id_corrida, 'TEL_BORRA', @solo_mostrar;
            EXEC ops.sp_cyber_ejecutar @id_corrida, 'TEL_REMESA', @solo_mostrar;
            /* La remesa en CYBER debe cuadrar con nuestro archivo antes de que el store inactive lo que no está en ella */
            IF @solo_mostrar = 0 EXEC ops.sp_tel_remesa_validar @id_corrida;
            EXEC ops.sp_cyber_ejecutar @id_corrida, 'TEL_ACTUALIZA', @solo_mostrar;
            /* NUEVOS: se bajan los teléfonos que no existían en PHONE y el SCBTEL queda solo con ellos */
            IF @modo = N'NUEVOS' AND @solo_mostrar = 0
                EXEC ops.sp_tel_nuevos @id_corrida, @nuevos = @nuevos OUTPUT;
            SET @msg = CONCAT(N'Depuración de teléfonos en CYBER: remesa de ', @n, N' (cuadra con RCVRY.JSP_TAB_TEL_REMESA_486)',
                              CASE WHEN @modo = N'NUEVOS' THEN CONCAT(N' · nuevos para el SCBTEL: ', ISNULL(@nuevos, 0)) ELSE N'' END);
        END;
        IF @solo_mostrar = 0 EXEC ops.sp_log @id_corrida, @paso, 'OK', @n, @msg;
        /* Con la depuración de teléfonos OK, asignaciones ya puede subir el SCBTEL: se escribe y se avisa */
        IF @que = 'TELEFONOS' AND @solo_mostrar = 0
        BEGIN
            DECLARE @tel NVARCHAR(400) = ISNULL(cfg.fn_param((SELECT CLIENTE FROM ops.CORRIDA WHERE ID_CORRIDA = @id_corrida), 'ARCHIVOS_DESPUES_DEPURACION_TEL'), N'SCBTEL');
            /* Sin teléfonos nuevos no hay SCBTEL que escribir ni que subir */
            IF @modo = N'NUEVOS' AND ISNULL(@nuevos, 0) = 0
                SET @tel = NULLIF((SELECT STRING_AGG(LTRIM(RTRIM(value)), N',') FROM STRING_SPLIT(@tel, N',') WHERE UPPER(LTRIM(RTRIM(value))) <> N'SCBTEL'), N'');
            IF @tel IS NOT NULL
                EXEC ops.sp_exportar_auto @id_corrida, @solo = @tel;
        END;
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
            @hostup NVARCHAR(200) = NULLIF(LTRIM(RTRIM(cfg.fn_param(@cliente, 'CYBER_HOSTUP_EXPR'))), N''),
            @q NVARCHAR(MAX), @sql NVARCHAR(MAX), @msg NVARCHAR(400);
    IF NOT EXISTS (SELECT 1 FROM sys.servers WHERE name = @srv)
    BEGIN
        SET @msg = CONCAT(N'No existe el servidor vinculado ', @srv, N'. Captura la credencial CYBER_ORACLE y corre EXEC cfg.sp_cyber_conectar;');
        THROW 50823, @msg, 1;
    END;
    IF @dom LIKE N'%[^A-Za-z0-9_]%' THROW 50768, 'CYBER_COLUMNA_DOMICILIO inválida (solo el nombre de la columna de DELQMST).', 1;
    IF @hostup LIKE N'%;%' OR @hostup LIKE N'%--%' OR @hostup LIKE N'%/*%'
        THROW 50775, 'CYBER_HOSTUP_EXPR inválida: solo una expresión sobre DMHOSTUP, sin ; ni comentarios.', 1;

    /* Validación de saldos del equipo (val.txt, 15/11): cuentas activas del 486 por fecha de DMHOSTUP */
    TRUNCATE TABLE stg.CYBER_HOSTUP;
    IF @hostup IS NOT NULL
    BEGIN
        SET @q = N'select ' + @hostup + N', count(*) from RCVRY.delqmst where DMACCTG = ''1'' and DMCOMPANY = ''' + @cliente
               + N''' and DMSTATUS is null group by ' + @hostup;
        SET @sql = N'INSERT INTO stg.CYBER_HOSTUP (FECHA, CUENTAS) EXEC (N''' + REPLACE(@q, N'''', N'''''') + N''') AT ' + QUOTENAME(@srv) + N';';
        EXEC (@sql);
    END;

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
     SCBSDOS subido = validación de saldos del equipo (15/11): las cuentas activas del 486 con DMHOSTUP del día
                      (CYBER_HOSTUP_EXPR) son al menos ARRIBO_SDOS_MIN_PCT % (100 = coinciden) de las cuentas del
                      SCBSDOS. Con CYBER_HOSTUP_EXPR vacío: al menos ARRIBO_MIN_PCT % de las cuentas y domicilios
                      pendientes ya están en DELQMST.
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
            @hecho_s BIT, @hecho_c BIT, @hecho_t BIT, @hecho_g BIT, @fin BIT, @listo_s BIT = 0, @listo_g BIT = 0, @res NVARCHAR(400) = N'',
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
    /* Pasos ya intentados (OK o ERROR: no se reintentan solos) */
    SET @hecho_s = CASE WHEN EXISTS (SELECT 1 FROM ops.BITACORA WHERE ID_CORRIDA = @id AND PASO = 'ARRIBO SALDOS' AND ESTATUS = 'OK') THEN 1 ELSE 0 END;
    SET @hecho_c = CASE WHEN EXISTS (SELECT 1 FROM ops.BITACORA WHERE ID_CORRIDA = @id AND PASO = 'ARRIBO CORREOS' AND ESTATUS IN ('OK', 'ERROR')) THEN 1 ELSE 0 END;
    SET @hecho_t = CASE WHEN EXISTS (SELECT 1 FROM ops.BITACORA WHERE ID_CORRIDA = @id AND PASO = 'ARRIBO TELEFONOS' AND ESTATUS IN ('OK', 'ERROR')) THEN 1 ELSE 0 END;
    SET @hecho_g = CASE WHEN EXISTS (SELECT 1 FROM ops.BITACORA WHERE ID_CORRIDA = @id AND PASO = 'GESCAR SIN TELEFONO' AND ESTATUS IN ('OK', 'ERROR')) THEN 1 ELSE 0 END;
    IF @hecho_s = 1 AND @hecho_c = 1 AND @hecho_t = 1 AND @hecho_g = 1
    BEGIN
        EXEC ops.sp_arribo_posterior @id;          -- blanqueo y confirmación, si quedaron pendientes (p. ej. tras un arribo a mano)
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

    /* Saldos del día: DMHOSTUP con la fecha del día en tantas cuentas como manda el SCBSDOS */
    DECLARE @usa_hostup BIT = CASE WHEN NULLIF(LTRIM(RTRIM(cfg.fn_param(@cliente, 'CYBER_HOSTUP_EXPR'))), N'') IS NULL THEN 0 ELSE 1 END,
            @pct_sdos DECIMAL(5,2) = ISNULL(TRY_CONVERT(DECIMAL(5,2), cfg.fn_param(@cliente, 'ARRIBO_SDOS_MIN_PCT')), 100),
            @n_sdos INT, @n_hoy INT, @ok_sdos BIT;
    SET @n_sdos = (SELECT COUNT(*) FROM ops.SALIDA_LINEA WHERE ID_CORRIDA = @id AND ARCHIVO = 'SCBSDOS');
    SET @n_hoy = ISNULL((SELECT SUM(CUENTAS) FROM stg.CYBER_HOSTUP
                         WHERE TRY_CONVERT(DATE, LEFT(LTRIM(FECHA), 8), 112) >= @fecha      -- AAAAMMDD (to_char de fábrica)
                            OR TRY_CONVERT(DATE, LEFT(LTRIM(FECHA), 10), 23) >= @fecha     -- AAAA-MM-DD
                            OR TRY_CONVERT(DATE, LEFT(LTRIM(FECHA), 10), 103) >= @fecha    -- DD/MM/AAAA
                            OR TRY_CONVERT(DATE, LEFT(LTRIM(FECHA), 8), 3) >= @fecha), 0); -- DD/MM/AA, como lo muestra val.txt
    SET @ok_sdos = CASE WHEN @n_sdos > 0 AND 100.0 * @n_hoy >= @pct_sdos * @n_sdos THEN 1 ELSE 0 END;

    SET @ok_c = CASE WHEN @p_c = 0 OR 100.0 * @r_c / @p_c >= @min THEN 1 ELSE 0 END;
    SET @ok_d = CASE WHEN @p_d = 0 OR 100.0 * @r_d / @p_d >= @min THEN 1 ELSE 0 END;
    SET @ok_t = CASE WHEN @p_t = 0 OR 100.0 * @r_t / @p_t >= @min THEN 1 ELSE 0 END;
    /* Saldos arriba: validación del equipo por DMHOSTUP; sin ella, por cuentas y domicilios pendientes */
    SET @listo_s = CASE WHEN @fin = 1 OR (@usa_hostup = 1 AND @ok_sdos = 1) OR (@usa_hostup = 0 AND @ok_c = 1 AND @ok_d = 1) THEN 1 ELSE 0 END;
    /* SCBTEL arriba: los teléfonos que le faltaban a PHONE_G1 ya llegaron (solo cuenta después de la depuración de teléfonos) */
    SET @listo_g = CASE WHEN @fin = 1 OR @ok_t = 1 THEN 1 ELSE 0 END;

    /* 1. Saldos arriba: se marca el paso y salen los gescar de nuevas y reasignadas */
    IF @listo_s = 1 AND @hecho_s = 0
    BEGIN
        SET @acc = CONCAT(N'Saldos del día en CYBER', CASE WHEN @usa_hostup = 1 THEN CONCAT(N': ', @n_hoy, N' de ', @n_sdos, N' cuentas con DMHOSTUP del día') ELSE N' (por cuentas y domicilios pendientes)' END);
        EXEC ops.sp_log @id, 'ARRIBO SALDOS', 'OK', @n_hoy, @acc;
        SET @hecho_s = 1;
        SET @acc = ISNULL(cfg.fn_param(@cliente, 'ARCHIVOS_DESPUES_SALDOS'), N'GESCAR_NVA,GESCAR_REA');
        EXEC ops.sp_exportar_auto @id, @solo = @acc;
        SET @res += N'SALDOS OK · ';
        /* Con los saldos arriba las cuentas nuevas ya existen en CYBER: se vuelven a bajar ESTATUS, ABAN_SR… para las vistas de usuarios */
        BEGIN TRY
            EXEC ops.sp_vistas_usuario_refrescar @id, 'VISTAS USUARIO SALDOS';
        END TRY
        BEGIN CATCH
            SET @err = ERROR_MESSAGE();
            EXEC ops.sp_log @id, 'VISTAS USUARIO SALDOS', 'ERROR', NULL, @err;
        END CATCH;
    END;
    /* 2. Depuración de teléfonos (con los saldos arriba; si la remesa cuadra, sale el aviso para subir el SCBTEL) */
    IF @hecho_s = 1 AND @hecho_t = 0
    BEGIN
        BEGIN TRY
            EXEC ops.sp_arribar_cyber @id, 'TELEFONOS';
            SET @res += N'TELEFONOS OK · ';
        END TRY
        BEGIN CATCH
            SET @res += N'TELEFONOS ERROR · ';
            SET @err = ERROR_MESSAGE();
            SET @acc = CONCAT(N'No subir el SCBTEL todavía. Corregir la causa (si la remesa no cuadró, revisar RCVRY.JSP_TAB_TEL_REMESA_486 contra sub_mst.TXT) y correr EXEC ops.sp_arribar_cyber ', @id,
                              N', ''TELEFONOS''; (con @solo_mostrar = 1 se ven los bloques sin ejecutar). Los correos esperan a que esta depuración quede bien. El job no lo reintenta solo.');
            EXEC mail.sp_hallazgo @id, N'Depuración de teléfonos en CYBER con error', @err, @acc;
        END CATCH;
    END;
    DECLARE @tel_ok BIT = CASE WHEN EXISTS (SELECT 1 FROM ops.BITACORA WHERE ID_CORRIDA = @id AND PASO = 'ARRIBO TELEFONOS' AND ESTATUS = 'OK') THEN 1 ELSE 0 END;
    /* 3. Depuración de correos, después de la de teléfonos */
    IF @tel_ok = 1 AND @hecho_c = 0
    BEGIN
        BEGIN TRY
            EXEC ops.sp_arribar_cyber @id, 'CORREOS';
            SET @res += N'CORREOS OK · ';
        END TRY
        BEGIN CATCH
            SET @res += N'CORREOS ERROR · ';
            SET @err = ERROR_MESSAGE();
            SET @acc = CONCAT(N'Corregir la causa y correr EXEC ops.sp_arribar_cyber ', @id, N', ''CORREOS''; (con @solo_mostrar = 1 se ven los bloques sin ejecutar). El job no lo reintenta solo.');
            EXEC mail.sp_hallazgo @id, N'Depuración de correos en CYBER con error', @err, @acc;
        END CATCH;
    END;
    /* 4. SCBTEL arriba: gescar de cuentas sin teléfono */
    IF @tel_ok = 1 AND @listo_g = 1 AND @hecho_g = 0
    BEGIN
        BEGIN TRY
            EXEC ops.sp_arribo_gescar_sintel @id;
            SET @res += N'GESCAR SIN TELEFONO OK · ';
        END TRY
        BEGIN CATCH
            SET @res += N'GESCAR SIN TELEFONO ERROR · ';
            SET @err = ERROR_MESSAGE();
            SET @acc = CONCAT(N'Corregir la causa y correr EXEC ops.sp_arribo_gescar_sintel ', @id, N';');
            EXEC mail.sp_hallazgo @id, N'Gescar de cuentas sin teléfono con error', @err, @acc;
        END CATCH;
    END;

    EXEC ops.sp_arribo_posterior @id;              -- blanqueo de status y confirmación de la asignación
    SET @resultado = CASE WHEN @res <> N'' THEN RTRIM(LEFT(@res, LEN(@res) - 1))
                          WHEN @hecho_s = 0 THEN N'ESPERANDO SALDOS'
                          WHEN @tel_ok = 0 THEN N'DEPURACION DE TELEFONOS CON ERROR'
                          WHEN @hecho_g = 0 THEN N'ESPERANDO SCBTEL'
                          ELSE N'ESPERANDO ARRIBO' END;
    SELECT @resultado AS ARRIBO, @id AS CORRIDA,
           CASE WHEN @usa_hostup = 1 THEN CONCAT(@n_hoy, N' de ', @n_sdos) END AS SALDOS_DEL_DIA_EN_CYBER,
           CONCAT(@r_c, N' de ', @p_c) AS CUENTAS_PENDIENTES_EN_CYBER, CONCAT(@r_d, N' de ', @p_d) AS DOMICILIOS_PENDIENTES_EN_CYBER,
           CONCAT(@r_t, N' de ', @p_t) AS TELEFONOS_PENDIENTES_EN_PHONE_G1;
END;
GO
