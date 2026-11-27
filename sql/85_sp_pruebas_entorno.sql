USE [BNABAJ_486];   -- base del 486 (si la instalas con otro nombre, cámbialo aquí)
GO
/* =====================================================================
   Banbaj · 85 Pruebas de entorno (20/11)
   ---------------------------------------------------------------------
   Para probar en el servidor, antes de producción, que todo lo de afuera
   responde: CYBER, correo, carpetas del banco, lectura de archivos y una
   asignación completa que después se revierte. Los scripts de la carpeta
   pruebas_entorno/ los llaman en orden (ver pruebas_entorno/LEEME.md).

   ops.sp_prueba_modo        enciende / apaga el modo de prueba: correos solo a
                             una dirección, nada se escribe en CYBER, archivos a
                             una carpeta de prueba y job apagado. Guarda y repone
                             los valores de antes.
   ops.sp_prueba_cyber       consultas de solo lectura a CYBER (solo conteos)
   ops.sp_prueba_correo      perfil de Database Mail, plantillas y un correo real
   ops.sp_prueba_archivos    qué archivos del banco encuentra en la carpeta del día
   ops.sp_prueba_lectura     lee y valida cada archivo sin tocar el DAT
   ops.sp_prueba_asignacion  actualización y asignación del día en modo prueba
   ops.sp_prueba_resumen     qué hizo una corrida (solo conteos)
   ops.sp_prueba_revertir    revierte lo que corrió la prueba

   Nada de esto imprime cuentas, nombres, teléfonos ni correos de clientes:
   solo conteos, nombres de archivo y mensajes de la bitácora (que ya vienen
   enmascarados).

   Ya en producción: sql/instalacion/06_limpiar_pruebas.sql borra todo lo de aquí.

   Errores 50850-50869
   ===================================================================== */
SET NOCOUNT ON;
GO
/* Si las pruebas de entorno ya se limpiaron (sql/instalacion/06_limpiar_pruebas.sql deja PRUEBAS_LIMPIAS = 1),
   este script no vuelve a crear nada: se puede seguir corriendo todos los scripts de sql/ al actualizar el servidor. */
IF EXISTS (SELECT 1 FROM cfg.PARAMETRO WHERE CLIENTE = '486' AND CLAVE = 'PRUEBAS_LIMPIAS' AND VALOR = '1')
BEGIN
    PRINT '85_sp_pruebas_entorno: las pruebas ya se limpiaron (PRUEBAS_LIMPIAS = 1); no se crea nada.';
    SET NOEXEC ON;
END;
GO

IF OBJECT_ID('ops.PRUEBA_PARAM') IS NULL
CREATE TABLE ops.PRUEBA_PARAM (
    CLIENTE  VARCHAR(10)    NOT NULL,
    CLAVE    VARCHAR(60)    NOT NULL,
    VALOR    NVARCHAR(4000) NULL,          -- valor de antes de la prueba (NULL = no existía)
    FECHA    DATETIME2(0)   NOT NULL CONSTRAINT DF_PRUEBA_PARAM_FE DEFAULT SYSDATETIME(),
    CONSTRAINT PK_PRUEBA_PARAM PRIMARY KEY (CLIENTE, CLAVE)
);
GO
IF OBJECT_ID('ops.PRUEBA_CORRIDA') IS NULL
CREATE TABLE ops.PRUEBA_CORRIDA (
    ID_CORRIDA INT          NOT NULL CONSTRAINT PK_PRUEBA_CORRIDA PRIMARY KEY,
    PROCESO    VARCHAR(10)  NOT NULL,
    FECHA      DATETIME2(0) NOT NULL CONSTRAINT DF_PRUEBA_CORRIDA_FE DEFAULT SYSDATETIME()
);
GO

/* ---------------------------------------------------------------------
   Modo de prueba. @activar = 1 guarda los valores de ahora y pone:
     CORREO_PRUEBA_PARA  = @correo  (todos los correos solo a esa dirección)
     CYBER_SOLO_LECTURA  = 1        (ningún script se ejecuta en CYBER)
     RUTA_SALIDA, RUTA_MIS, CARPETA_ZIP = @carpeta (los archivos no van a las carpetas reales)
   y apaga los jobs "Banbaj 486 diario" y "Banbaj 486 ladas".
   @activar = 0 repone todo como estaba (y vuelve a prender los jobs que estaban prendidos).
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE ops.sp_prueba_modo
    @activar BIT,
    @correo  NVARCHAR(400) = NULL,
    @carpeta NVARCHAR(400) = N'C:\BANBAJ\486\PRUEBA\',
    @cliente VARCHAR(10)   = '486'
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @claves TABLE (CLAVE VARCHAR(60) PRIMARY KEY, NUEVO NVARCHAR(4000));
    DECLARE @job SYSNAME, @hab TINYINT;
    IF @activar = 1
    BEGIN
        IF NULLIF(LTRIM(RTRIM(@correo)), N'') IS NULL OR @correo NOT LIKE N'%_@_%._%'
            THROW 50850, 'Indica @correo: la dirección que va a recibir todos los correos de la prueba.', 1;
        IF RIGHT(@carpeta, 1) NOT IN (N'\', N'/') SET @carpeta += N'\';
        INSERT INTO @claves VALUES ('CORREO_PRUEBA_PARA', @correo), ('CYBER_SOLO_LECTURA', N'1'),
                                   ('RUTA_SALIDA', @carpeta), ('RUTA_MIS', @carpeta), ('CARPETA_ZIP', @carpeta);
        /* Valores de antes (solo la primera vez: si ya estaba en modo prueba no se pisan) */
        INSERT INTO ops.PRUEBA_PARAM (CLIENTE, CLAVE, VALOR)
        SELECT @cliente, k.CLAVE, p.VALOR FROM @claves k
        LEFT JOIN cfg.PARAMETRO p ON p.CLIENTE = @cliente AND p.CLAVE = k.CLAVE
        WHERE NOT EXISTS (SELECT 1 FROM ops.PRUEBA_PARAM x WHERE x.CLIENTE = @cliente AND x.CLAVE = k.CLAVE);
        UPDATE p SET VALOR = k.NUEVO FROM cfg.PARAMETRO p JOIN @claves k ON k.CLAVE = p.CLAVE WHERE p.CLIENTE = @cliente;
        INSERT INTO cfg.PARAMETRO (CLIENTE, CLAVE, VALOR, DESCRIPCION)
        SELECT @cliente, k.CLAVE, k.NUEVO, N'Modo de prueba (ops.sp_prueba_modo)' FROM @claves k
        WHERE NOT EXISTS (SELECT 1 FROM cfg.PARAMETRO p WHERE p.CLIENTE = @cliente AND p.CLAVE = k.CLAVE);
        /* Jobs: se apagan y se recuerda si estaban prendidos */
        DECLARE cj CURSOR LOCAL FAST_FORWARD FOR SELECT name, enabled FROM msdb.dbo.sysjobs WHERE name IN (N'Banbaj 486 diario', N'Banbaj 486 ladas');
        OPEN cj; FETCH NEXT FROM cj INTO @job, @hab;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM ops.PRUEBA_PARAM WHERE CLIENTE = @cliente AND CLAVE = LEFT('JOB:' + @job, 60))
                INSERT INTO ops.PRUEBA_PARAM (CLIENTE, CLAVE, VALOR) VALUES (@cliente, LEFT('JOB:' + @job, 60), CAST(@hab AS NVARCHAR(5)));
            BEGIN TRY EXEC msdb.dbo.sp_update_job @job_name = @job, @enabled = 0; END TRY BEGIN CATCH END CATCH;
            FETCH NEXT FROM cj INTO @job, @hab;
        END;
        CLOSE cj; DEALLOCATE cj;
        SELECT N'MODO PRUEBA ENCENDIDO' AS RESULTADO, @correo AS CORREOS_A, @carpeta AS ARCHIVOS_EN,
               N'CYBER solo lectura; jobs apagados. Al terminar: EXEC ops.sp_prueba_modo @activar = 0;' AS NOTA;
        RETURN;
    END;

    /* Apagar: repone los parámetros y los jobs */
    IF NOT EXISTS (SELECT 1 FROM ops.PRUEBA_PARAM WHERE CLIENTE = @cliente)
    BEGIN
        SELECT N'NO ESTABA EN MODO PRUEBA' AS RESULTADO;
        RETURN;
    END;
    UPDATE p SET VALOR = x.VALOR
    FROM cfg.PARAMETRO p JOIN ops.PRUEBA_PARAM x ON x.CLIENTE = p.CLIENTE AND x.CLAVE = p.CLAVE
    WHERE p.CLIENTE = @cliente AND x.VALOR IS NOT NULL AND x.CLAVE NOT LIKE 'JOB:%';
    /* Lo que no existía antes queda en su valor de producción */
    UPDATE p SET VALOR = CASE p.CLAVE WHEN 'CYBER_SOLO_LECTURA' THEN N'0' ELSE N'' END
    FROM cfg.PARAMETRO p JOIN ops.PRUEBA_PARAM x ON x.CLIENTE = p.CLIENTE AND x.CLAVE = p.CLAVE
    WHERE p.CLIENTE = @cliente AND x.VALOR IS NULL AND p.CLAVE IN ('CORREO_PRUEBA_PARA', 'CYBER_SOLO_LECTURA');
    DECLARE cj2 CURSOR LOCAL FAST_FORWARD FOR
        SELECT SUBSTRING(CLAVE, 5, 60), TRY_CONVERT(TINYINT, VALOR) FROM ops.PRUEBA_PARAM WHERE CLIENTE = @cliente AND CLAVE LIKE 'JOB:%';
    OPEN cj2; FETCH NEXT FROM cj2 INTO @job, @hab;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        IF @hab = 1 BEGIN TRY EXEC msdb.dbo.sp_update_job @job_name = @job, @enabled = 1; END TRY BEGIN CATCH END CATCH;
        FETCH NEXT FROM cj2 INTO @job, @hab;
    END;
    CLOSE cj2; DEALLOCATE cj2;
    DELETE FROM ops.PRUEBA_PARAM WHERE CLIENTE = @cliente;
    SELECT CLAVE, VALOR FROM cfg.PARAMETRO
    WHERE CLIENTE = @cliente AND CLAVE IN ('CORREO_PRUEBA_PARA', 'CYBER_SOLO_LECTURA', 'RUTA_SALIDA', 'RUTA_MIS', 'CARPETA_ZIP')
    ORDER BY CLAVE;
    SELECT N'MODO PRUEBA APAGADO' AS RESULTADO, N'Parámetros y jobs como estaban. Borra la carpeta de prueba: trae datos de clientes.' AS NOTA;
END;
GO

/* ---------------------------------------------------------------------
   CYBER, solo lectura: el servidor vinculado responde y cada tabla que usa
   Banbaj se puede consultar. Regresa conteos, nunca datos de clientes.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE ops.sp_prueba_cyber
    @cliente VARCHAR(10) = '486'
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @srv SYSNAME = ISNULL(cfg.fn_param(@cliente, 'CYBER_LINKED_SERVER'), 'CYBER'), @q NVARCHAR(2000), @p NVARCHAR(200),
            @sql NVARCHAR(MAX), @n BIGINT;
    CREATE TABLE #r (ORDEN INT IDENTITY(1,1), PRUEBA NVARCHAR(200), RESULTADO VARCHAR(10), VALOR BIGINT NULL, DETALLE NVARCHAR(1000) NULL);
    CREATE TABLE #n (N BIGINT);
    IF NOT EXISTS (SELECT 1 FROM sys.servers WHERE name = @srv)
    BEGIN
        INSERT INTO #r (PRUEBA, RESULTADO, DETALLE) VALUES (CONCAT(N'Servidor vinculado ', @srv), 'FALLA', N'No existe: corre cfg.sp_cyber_conectar (paso 4 del manual).');
        SELECT PRUEBA, RESULTADO, VALOR, DETALLE FROM #r ORDER BY ORDEN;
        RETURN;
    END;
    DECLARE @c TABLE (ORDEN INT IDENTITY(1,1), PRUEBA NVARCHAR(200), Q NVARCHAR(2000));
    INSERT INTO @c (PRUEBA, Q) VALUES
        (N'Conexión (select from dual)', N'select 1 from dual'),
        (N'DELQMST: cuentas activas del cliente', CONCAT(N'select count(*) from RCVRY.delqmst where dmacctg = ''1'' and dmcompany = ''', @cliente, N''' and dmstatus is null')),
        (N'DELQMST: consulta de saldos del día (val.txt), fechas distintas', CONCAT(N'select count(distinct dmhostup) from RCVRY.delqmst where dmacctg = ''1'' and dmcompany = ''', @cliente, N''' and dmstatus is null')),
        (N'PHONE: teléfonos de las cuentas activas (foto de la depuración)', CONCAT(N'select count(*) from RCVRY.phone p join RCVRY.delqmst d on d.dmacctg = p.phacctg and d.dmacct = p.phacct where d.dmacctg = ''1'' and d.dmcompany = ''', @cliente, N''' and d.dmstatus is null')),
        (N'PHONE_G1 (arribo del SCBTEL)', CONCAT(N'select count(*) from RCVRY.phone_g1 where phacctg = ''1'' and phacct like ''', @cliente, N'-%''')),
        (N'ADDRESS (correos)', CONCAT(N'select count(*) from RCVRY.address a join RCVRY.delqmst d on d.dmacctg = a.adacctg and d.dmacct = a.adacct where d.dmacctg = ''1'' and d.dmcompany = ''', @cliente, N''' and d.dmstatus is null')),
        (N'UDA1 (vistas, pago mínimo)', N'select count(*) from RCVRY.uda1 where rownum <= 1'),
        (N'Tabla de abandono (ABAN_SR de las vistas, CYBER_TABLA_ABANDONO)', CONCAT(N'select count(*) from ', ISNULL(NULLIF(cfg.fn_param(@cliente, 'CYBER_TABLA_ABANDONO'), N''), N'RCVRY.RPT_DAT_486_1'))),
        (N'PHNVAL (ladas válidas)', CONCAT(N'select count(*) from ', ISNULL(NULLIF(cfg.fn_param(@cliente, 'CYBER_TABLA_LADAS'), N''), N'RCVRY.PHNVAL'))),
        (N'RPT_LOG_CYBER_REG: bandera de correos y teléfonos (1 = encendida)', CONCAT(N'select nvl(max(status), -1) from RCVRY.rpt_log_cyber_reg where id_proc = ', ISNULL(NULLIF(cfg.fn_param(@cliente, 'CYBER_BANDERA_TELEFONOS'), N''), N'416'))),
        (N'JSP_TAB_TEL_REMESA_486 (remesa de teléfonos)', N'select count(*) from RCVRY.jsp_tab_tel_remesa_486'),
        (N'JSP_TAB_TEL_DEPURA_486 (depuración por diferencia; falla si el DBA no la ha creado)', N'select count(*) from RCVRY.jsp_tab_tel_depura_486'),
        (N'JSP_TAB_MAIL_REMESA_486 (remesa de correos)', N'select count(*) from RCVRY.jsp_tab_mail_remesa_486'),
        (N'JSP_VALIDADOR_TELEFONOS', N'select count(*) from RCVRY.jsp_validador_telefonos'),
        (N'Stores instalados y válidos (de 3: JSP_TELEFONOS_REMESA_486, JSP_TELEFONOS_DEPURA_486, JSP_CORREOS_486)',
         N'select count(*) from all_objects where owner = ''RCVRY'' and object_type = ''PROCEDURE'' and status = ''VALID'' and object_name in (''JSP_TELEFONOS_REMESA_486'', ''JSP_TELEFONOS_DEPURA_486'', ''JSP_CORREOS_486'')');
    DECLARE cc CURSOR LOCAL FAST_FORWARD FOR SELECT PRUEBA, Q FROM @c ORDER BY ORDEN;
    OPEN cc; FETCH NEXT FROM cc INTO @p, @q;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        BEGIN TRY
            DELETE FROM #n;
            SET @sql = N'INSERT INTO #n (N) EXEC (N''' + REPLACE(@q, N'''', N'''''') + N''') AT ' + QUOTENAME(@srv) + N';';
            EXEC (@sql);
            SET @n = (SELECT TOP (1) N FROM #n);
            INSERT INTO #r (PRUEBA, RESULTADO, VALOR) VALUES (@p, 'OK', @n);
        END TRY
        BEGIN CATCH
            INSERT INTO #r (PRUEBA, RESULTADO, DETALLE) VALUES (@p, 'FALLA', LEFT(ERROR_MESSAGE(), 1000));
        END CATCH;
        FETCH NEXT FROM cc INTO @p, @q;
    END;
    CLOSE cc; DEALLOCATE cc;
    /* Las bajadas reales de Banbaj (escriben solo en tablas de paso de SQL Server) */
    BEGIN TRY
        EXEC ops.sp_arribo_bajar @cliente, 1;
        INSERT INTO #r (PRUEBA, RESULTADO, VALOR, DETALLE)
        SELECT N'ops.sp_arribo_bajar (lo que usa el arribo automático)', 'OK', (SELECT COUNT(*) FROM stg.CYBER_DELQMST_ACT), N'Cuentas bajadas de DELQMST';
    END TRY
    BEGIN CATCH
        INSERT INTO #r (PRUEBA, RESULTADO, DETALLE) VALUES (N'ops.sp_arribo_bajar (lo que usa el arribo automático)', 'FALLA', LEFT(ERROR_MESSAGE(), 1000));
    END CATCH;
    BEGIN TRY
        DECLARE @fx DATE = CAST(GETDATE() AS DATE), @id_x INT = (SELECT MAX(ID_CORRIDA) FROM ops.CORRIDA WHERE CLIENTE = @cliente AND ESTATUS = 'OK' AND PROCESO IN ('ASIG', 'ACT'));
        IF @id_x IS NOT NULL
        BEGIN
            EXEC ops.sp_dat_cyber_bajar @id_corrida = @id_x;
            INSERT INTO #r (PRUEBA, RESULTADO, VALOR, DETALLE)
            SELECT N'ops.sp_dat_cyber_bajar (vistas AEM / MIS)', 'OK', (SELECT COUNT(*) FROM dat.CYBER_DAT WHERE CLIENTE = @cliente), N'Cuentas con datos de CYBER';
        END;
    END TRY
    BEGIN CATCH
        INSERT INTO #r (PRUEBA, RESULTADO, DETALLE) VALUES (N'ops.sp_dat_cyber_bajar (vistas AEM / MIS)', 'FALLA', LEFT(ERROR_MESSAGE(), 1000));
    END CATCH;
    SELECT PRUEBA, RESULTADO, VALOR, DETALLE FROM #r ORDER BY ORDEN;
    SELECT CONCAT((SELECT COUNT(*) FROM #r WHERE RESULTADO = 'OK'), N' de ', (SELECT COUNT(*) FROM #r), N' pruebas de CYBER OK') AS RESUMEN;
END;
GO

/* ---------------------------------------------------------------------
   Correo: perfil de Database Mail, que todas las plantillas se armen y un
   correo real a la dirección de prueba (con el modo de prueba encendido).
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE ops.sp_prueba_correo
    @cliente VARCHAR(10) = '486'
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @para NVARCHAR(400) = NULLIF(cfg.fn_param(@cliente, 'CORREO_PRUEBA_PARA'), N''), @pl VARCHAR(60), @rc INT, @ok INT = 0, @mal INT = 0,
            @json NVARCHAR(MAX), @antes INT, @mid INT, @est NVARCHAR(30);
    IF @para IS NULL THROW 50851, 'Primero enciende el modo de prueba: EXEC ops.sp_prueba_modo @activar = 1, @correo = N''tu@correo'';', 1;
    CREATE TABLE #r (ORDEN INT IDENTITY(1,1), PRUEBA NVARCHAR(200), RESULTADO VARCHAR(10), DETALLE NVARCHAR(1000) NULL);

    /* Perfiles de las plantillas */
    INSERT INTO #r (PRUEBA, RESULTADO, DETALLE)
    SELECT CONCAT(N'Perfil de Database Mail ', p.PERFIL_DBMAIL),
           CASE WHEN EXISTS (SELECT 1 FROM msdb.dbo.sysmail_profile s WHERE s.name = p.PERFIL_DBMAIL) THEN 'OK' ELSE 'FALLA' END,
           CONCAT(COUNT(*), N' plantillas lo usan')
    FROM mail.PLANTILLA p WHERE p.ACTIVO = 1 GROUP BY p.PERFIL_DBMAIL;

    /* Cada plantilla se arma (sin enviar) */
    CREATE TABLE #armado (PARA NVARCHAR(MAX), CC NVARCHAR(MAX), CCO NVARCHAR(MAX), ASUNTO NVARCHAR(255), CUERPO_HTML NVARCHAR(MAX), ADJUNTOS NVARCHAR(MAX));
    DECLARE cp CURSOR LOCAL FAST_FORWARD FOR SELECT CODIGO FROM mail.PLANTILLA WHERE ACTIVO = 1 ORDER BY CODIGO;
    OPEN cp; FETCH NEXT FROM cp INTO @pl;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        BEGIN TRY
            DELETE FROM #armado;
            INSERT INTO #armado EXEC @rc = mail.sp_enviar @plantilla = @pl, @solo_prueba = 1;
            IF @rc = 0 SET @ok += 1; ELSE BEGIN SET @mal += 1; INSERT INTO #r (PRUEBA, RESULTADO, DETALLE) VALUES (CONCAT(N'Plantilla ', @pl), 'FALLA', N'No se pudo armar: revisa mail.ENVIO (lista sin destinatarios o plantilla inactiva)'); END;
        END TRY
        BEGIN CATCH
            SET @mal += 1;
            INSERT INTO #r (PRUEBA, RESULTADO, DETALLE) VALUES (CONCAT(N'Plantilla ', @pl), 'FALLA', LEFT(ERROR_MESSAGE(), 1000));
        END CATCH;
        FETCH NEXT FROM cp INTO @pl;
    END;
    CLOSE cp; DEALLOCATE cp;
    INSERT INTO #r (PRUEBA, RESULTADO, DETALLE) VALUES (N'Plantillas que se arman', CASE WHEN @mal = 0 THEN 'OK' ELSE 'FALLA' END, CONCAT(@ok, N' bien, ', @mal, N' con problema'));

    /* Un correo real (va solo a la dirección de prueba) */
    SET @antes = ISNULL((SELECT MAX(ID) FROM mail.ENVIO), 0);
    SET @json = (SELECT N'Prueba de entorno' AS TIPO, N'Si te llegó este correo, Database Mail funciona desde Banbaj.' AS DETALLE,
                        N'Nada: es una prueba (ops.sp_prueba_correo).' AS ACCION, N'PRUEBA' AS PROCESO, N'' AS HTML_TABLA FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    EXEC mail.sp_enviar @plantilla = 'HALLAZGO_486', @valores = @json;
    SELECT TOP (1) @est = ESTATUS, @mid = MAILITEM_ID FROM mail.ENVIO WHERE ID > @antes ORDER BY ID DESC;
    IF @mid IS NOT NULL
    BEGIN
        WAITFOR DELAY '00:00:10';
        SELECT @est = CONCAT(@est, N' · Database Mail: ', sent_status) FROM msdb.dbo.sysmail_allitems WHERE mailitem_id = @mid;
    END;
    INSERT INTO #r (PRUEBA, RESULTADO, DETALLE)
    VALUES (CONCAT(N'Correo real a ', @para), CASE WHEN @est LIKE N'ENVIADO%' AND @est NOT LIKE N'%failed%' THEN 'OK' ELSE 'FALLA' END,
            CONCAT(ISNULL(@est, N'sin registro'), N'. Revisa tu bandeja; si dice unsent espera un minuto y consulta msdb.dbo.sysmail_allitems.'));
    SELECT PRUEBA, RESULTADO, DETALLE FROM #r ORDER BY ORDEN;
END;
GO

/* ---------------------------------------------------------------------
   Detección de archivos: para cada archivo activo, la carpeta del día, si
   se puede leer y qué archivo encuentra con su patrón. Solo nombres.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE ops.sp_prueba_archivos
    @fecha   DATE        = NULL,
    @cliente VARCHAR(10) = '486'
AS
BEGIN
    SET NOCOUNT ON;
    SET @fecha = ISNULL(@fecha, CAST(GETDATE() AS DATE));
    DECLARE @id INT, @proc VARCHAR(10), @cod VARCHAR(50), @seg VARCHAR(20), @ruta NVARCHAR(400), @patron NVARCHAR(200), @n INT, @nact INT, @nasig INT, @npend INT;
    DECLARE @dir TABLE (subdirectory NVARCHAR(512), depth INT, [file] INT);
    CREATE TABLE #r (PROCESO VARCHAR(10), CODIGO VARCHAR(50), SEGMENTO VARCHAR(20), CARPETA NVARCHAR(400), PATRON NVARCHAR(200),
                     CARPETA_OK VARCHAR(5), ARCHIVOS_EN_CARPETA INT, ENCONTRADO NVARCHAR(512), COINCIDEN INT);
    DECLARE ca CURSOR LOCAL FAST_FORWARD FOR
        SELECT ID_ARCHIVO, PROCESO, CODIGO, SEGMENTO2, cfg.fn_ruta(RUTA, @fecha),
               REPLACE(REPLACE(REPLACE(PATRON_NOMBRE, N'{AAAAMMDD}', CONVERT(CHAR(8), @fecha, 112)),
                       N'{DD-MM-AAAA}', REPLACE(CONVERT(CHAR(10), @fecha, 105), '.', '-')), N'{AAAA-MM-DD}', CONVERT(CHAR(10), @fecha, 23))
        FROM cfg.ARCHIVO WHERE CLIENTE = @cliente AND ACTIVO = 1 ORDER BY PROCESO, ORDEN;
    OPEN ca; FETCH NEXT FROM ca INTO @id, @proc, @cod, @seg, @ruta, @patron;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        DELETE FROM @dir;
        BEGIN TRY INSERT INTO @dir EXEC master.sys.xp_dirtree @ruta, 1, 1; END TRY BEGIN CATCH END CATCH;
        INSERT INTO #r
        SELECT @proc, @cod, @seg, @ruta, @patron,
               CASE WHEN EXISTS (SELECT 1 FROM @dir) THEN 'SI' ELSE 'NO' END,
               (SELECT COUNT(*) FROM @dir WHERE [file] = 1),
               (SELECT TOP (1) subdirectory FROM @dir WHERE [file] = 1 AND subdirectory LIKE @patron COLLATE Latin1_General_CI_AI ORDER BY subdirectory DESC),
               (SELECT COUNT(*) FROM @dir WHERE [file] = 1 AND subdirectory LIKE @patron COLLATE Latin1_General_CI_AI);
        FETCH NEXT FROM ca INTO @id, @proc, @cod, @seg, @ruta, @patron;
    END;
    CLOSE ca; DEALLOCATE ca;
    SELECT PROCESO, CODIGO, SEGMENTO, CARPETA, PATRON, CARPETA_OK, ARCHIVOS_EN_CARPETA, ENCONTRADO,
           CASE WHEN COINCIDEN > 1 THEN CONCAT(N'Hay ', COINCIDEN, N' con el patrón: se toma el último por nombre') END AS NOTA
    FROM #r ORDER BY PROCESO DESC, CODIGO;
    EXEC ops.sp_archivos_presentes @cliente, 'ACT', @fecha, @nact OUTPUT;
    EXEC ops.sp_archivos_presentes @cliente, 'ASIG', @fecha, @nasig OUTPUT;
    EXEC ops.sp_archivos_presentes @cliente, 'ASIG', @fecha, @npend OUTPUT, @solo_pendientes = 1;
    SELECT @fecha AS FECHA, @nact AS ARCHIVOS_ACT, @nasig AS BASES_ASIG, @npend AS BASES_SIN_ASIGNAR_HOY,
           CASE WHEN @nact = 0 THEN N'El job diría ESPERANDO ACTUALIZACION'
                WHEN @nasig = 0 THEN N'El job correría la actualización y diría SIN ASIGNACION (POR AHORA)'
                ELSE N'El job correría la actualización y la asignación' END AS QUE_HARIA_EL_JOB;
    /* Carpetas donde Banbaj escribe */
    DELETE FROM @dir;
    DECLARE @sal NVARCHAR(400) = cfg.fn_param(@cliente, 'RUTA_SALIDA');
    BEGIN TRY INSERT INTO @dir EXEC master.sys.xp_dirtree @sal, 1, 0; END TRY BEGIN CATCH END CATCH;
    DECLARE @existe TABLE (ARCHIVO_EXISTE INT, ES_CARPETA INT, CARPETA_PADRE INT);
    BEGIN TRY INSERT INTO @existe EXEC master.dbo.xp_fileexist @sal; END TRY BEGIN CATCH END CATCH;
    SELECT N'RUTA_SALIDA' AS PARAMETRO, @sal AS CARPETA,
           CASE WHEN EXISTS (SELECT 1 FROM @existe WHERE ES_CARPETA = 1) THEN N'existe' ELSE N'NO existe o el servicio de SQL Server no la ve' END AS ESTADO;
END;
GO

/* ---------------------------------------------------------------------
   Lectura de archivos sin tocar el DAT: abre una corrida PRUEBA, lee y
   valida cada archivo del proceso (layout y reglas de datos) y la cierra.
   No guarda la base completa ni el último renglón por cuenta; las tablas de
   paso (stg) sí se llenan, como en cualquier carga.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE ops.sp_prueba_lectura
    @proceso VARCHAR(10),            -- ACT | ASIG
    @fecha   DATE        = NULL,
    @cliente VARCHAR(10) = '486'
AS
BEGIN
    SET NOCOUNT ON;
    SET @fecha = ISNULL(@fecha, CAST(GETDATE() AS DATE));
    IF @proceso NOT IN ('ACT', 'ASIG') THROW 50852, '@proceso debe ser ACT o ASIG.', 1;
    IF EXISTS (SELECT 1 FROM ops.CORRIDA WHERE CLIENTE = @cliente AND ESTATUS = 'EN_PROCESO')
        THROW 50853, 'Hay una corrida en proceso; espera a que termine.', 1;
    DECLARE @id INT, @a INT, @ok BIT, @err NVARCHAR(4000);
    INSERT INTO ops.CORRIDA (CLIENTE, PROCESO, FECHA_PROCESO) VALUES (@cliente, 'PRUEBA', @fecha);
    SET @id = SCOPE_IDENTITY();
    EXEC ops.sp_log @id, 'CORRIDA', 'INICIO', NULL, N'Prueba de lectura (no toca el DAT)';
    CREATE TABLE #err (CODIGO VARCHAR(50), ERROR NVARCHAR(4000));
    DECLARE ca CURSOR LOCAL FAST_FORWARD FOR SELECT ID_ARCHIVO FROM cfg.ARCHIVO WHERE CLIENTE = @cliente AND PROCESO = @proceso AND ACTIVO = 1 ORDER BY ORDEN;
    OPEN ca; FETCH NEXT FROM ca INTO @a;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        BEGIN TRY
            EXEC ops.sp_cargar_archivo @id, @a, @ok OUTPUT;
        END TRY
        BEGIN CATCH
            INSERT INTO #err VALUES ((SELECT CODIGO FROM cfg.ARCHIVO WHERE ID_ARCHIVO = @a), ERROR_MESSAGE());
        END CATCH;
        FETCH NEXT FROM ca INTO @a;
    END;
    CLOSE ca; DEALLOCATE ca;
    UPDATE ops.CORRIDA SET ESTATUS = 'CANCELADA', FIN = SYSDATETIME(), MENSAJE = N'Prueba de lectura: no tocó el DAT' WHERE ID_CORRIDA = @id;
    EXEC ops.sp_log @id, 'CORRIDA', 'CANCELADA', NULL, N'Prueba de lectura terminada';

    SELECT a.CODIGO, ISNULL(c.ESTATUS, 'SIN REGISTRO') AS ESTATUS, c.RUTA AS ARCHIVO, c.COLUMNAS, c.LEIDOS, c.INSERTADOS, c.RECHAZADOS,
           (SELECT COUNT(*) FROM ops.VALIDACION_ENTRADA v WHERE v.ID_CORRIDA = @id AND v.CODIGO = a.CODIGO AND v.DETIENE = 1) AS REGLAS_QUE_DETIENEN,
           (SELECT COUNT(*) FROM ops.VALIDACION_ENTRADA v WHERE v.ID_CORRIDA = @id AND v.CODIGO = a.CODIGO AND v.DETIENE = 0) AS AVISOS,
           (SELECT TOP (1) ERROR FROM #err e WHERE e.CODIGO = a.CODIGO) AS ERROR
    FROM cfg.ARCHIVO a
    LEFT JOIN ops.ARCHIVO_CARGADO c ON c.ID_CORRIDA = @id AND c.ID_ARCHIVO = a.ID_ARCHIVO
    WHERE a.CLIENTE = @cliente AND a.PROCESO = @proceso AND a.ACTIVO = 1
    ORDER BY a.ORDEN;
    SELECT CODIGO, TIPO, CAMPO, ESPERADO, REVISADOS, ANOMALOS, PCT, PCT_MAX, EJEMPLOS,
           CASE WHEN DETIENE = 1 THEN N'DETENDRÍA LA CORRIDA' ELSE N'aviso' END AS EFECTO
    FROM ops.VALIDACION_ENTRADA WHERE ID_CORRIDA = @id ORDER BY DETIENE DESC, CODIGO, TIPO;
    SELECT @id AS CORRIDA_DE_PRUEBA,
           CASE WHEN EXISTS (SELECT 1 FROM ops.VALIDACION_ENTRADA WHERE ID_CORRIDA = @id AND DETIENE = 1) OR EXISTS (SELECT 1 FROM #err)
                THEN N'Con estos archivos el proceso se DETENDRÍA: revisa lo de arriba'
                ELSE N'Los archivos se leen y pasan la validación' END AS RESULTADO;
END;
GO

/* ---------------------------------------------------------------------
   Qué hizo una corrida, en conteos (para revisar la asignación de prueba).
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE ops.sp_prueba_resumen
    @id_corrida INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT ID_CORRIDA, PROCESO, FECHA_PROCESO, ESTATUS, INICIO, FIN, DATEDIFF(SECOND, INICIO, FIN) AS SEGUNDOS, MENSAJE
    FROM ops.CORRIDA WHERE ID_CORRIDA = @id_corrida;
    SELECT PASO, ESTATUS, REGISTROS, MENSAJE FROM ops.BITACORA
    WHERE ID_CORRIDA = @id_corrida AND ESTATUS IN ('ERROR', 'AVISO') ORDER BY ID;
    SELECT N'Altas NVA' AS CONCEPTO, COUNT(*) AS CANTIDAD FROM dat.HISTORIA_FOLIO WHERE ID_CORRIDA_ALTA = @id_corrida AND SUB_CTE = 'NVA'
    UNION ALL SELECT N'Altas REA (reasignadas)', COUNT(*) FROM dat.HISTORIA_FOLIO WHERE ID_CORRIDA_ALTA = @id_corrida AND SUB_CTE = 'REA'
    UNION ALL SELECT N'Retiros (devolución)', COUNT(*) FROM ops.DEVOLUCION WHERE ID_CORRIDA = @id_corrida
    UNION ALL SELECT N'Retiros aplicados (bajas en el histórico)', COUNT(*) FROM dat.HISTORIA_FOLIO WHERE ID_CORRIDA_BAJA = @id_corrida
    UNION ALL SELECT N'Rechazos', COUNT(*) FROM ops.RECHAZO WHERE ID_CORRIDA = @id_corrida
    UNION ALL SELECT N'Teléfonos', COUNT(*) FROM ops.TELEFONO WHERE ID_CORRIDA = @id_corrida
    UNION ALL SELECT N'Pagos a arribar', COUNT(*) FROM dat.PAGO_ARRIBADO WHERE ID_CORRIDA = @id_corrida AND ORIGEN = 'CORRIDA'
    UNION ALL SELECT N'DAT (cuentas activas ahora)', COUNT(*) FROM dat.DAT_486;
    SELECT ARCHIVO, COUNT(*) AS LINEAS FROM ops.SALIDA_LINEA WHERE ID_CORRIDA = @id_corrida GROUP BY ARCHIVO ORDER BY ARCHIVO;
    SELECT SCRIPT, COUNT(*) AS SENTENCIAS FROM ops.CYBER_SCRIPT WHERE ID_CORRIDA = @id_corrida GROUP BY SCRIPT ORDER BY SCRIPT;
    SELECT PLANTILLA, ESTATUS, COUNT(*) AS CORREOS, MAX(PARA) AS PARA FROM mail.ENVIO WHERE ID_CORRIDA = @id_corrida GROUP BY PLANTILLA, ESTATUS ORDER BY PLANTILLA;
END;
GO

/* ---------------------------------------------------------------------
   Asignación de prueba: con el modo de prueba encendido corre la
   actualización (si ese día no hay una OK) y la asignación de @fecha con
   los archivos reales de esa carpeta. Al terminar muestra el resumen.
   Después: revisar y EXEC ops.sp_prueba_revertir;
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE ops.sp_prueba_asignacion
    @fecha   DATE        = NULL,
    @cliente VARCHAR(10) = '486'
AS
BEGIN
    SET NOCOUNT ON;
    SET @fecha = ISNULL(@fecha, CAST(GETDATE() AS DATE));
    IF ISNULL(cfg.fn_param(@cliente, 'CYBER_SOLO_LECTURA'), '0') <> '1' OR NULLIF(cfg.fn_param(@cliente, 'CORREO_PRUEBA_PARA'), N'') IS NULL
        THROW 50854, 'Primero enciende el modo de prueba: EXEC ops.sp_prueba_modo @activar = 1, @correo = N''tu@correo'';', 1;
    DECLARE @act INT, @asig INT, @err NVARCHAR(4000);
    IF NOT EXISTS (SELECT 1 FROM ops.CORRIDA WHERE CLIENTE = @cliente AND PROCESO = 'ACT' AND FECHA_PROCESO = @fecha AND ESTATUS = 'OK')
    BEGIN
        BEGIN TRY
            EXEC ops.sp_actualizacion_486 @fecha = @fecha, @id_corrida = @act OUTPUT;
        END TRY
        BEGIN CATCH
            SET @err = ERROR_MESSAGE();
        END CATCH;
        IF @act IS NULL SET @act = (SELECT MAX(ID_CORRIDA) FROM ops.CORRIDA WHERE CLIENTE = @cliente AND PROCESO = 'ACT' AND FECHA_PROCESO = @fecha);
        IF @act IS NOT NULL AND NOT EXISTS (SELECT 1 FROM ops.PRUEBA_CORRIDA WHERE ID_CORRIDA = @act)
            INSERT INTO ops.PRUEBA_CORRIDA (ID_CORRIDA, PROCESO) VALUES (@act, 'ACT');
        IF @err IS NOT NULL
        BEGIN
            SELECT N'LA ACTUALIZACION DE PRUEBA FALLÓ' AS RESULTADO, @err AS DETALLE;
            IF @act IS NOT NULL EXEC ops.sp_prueba_resumen @act;
            RETURN;
        END;
        EXEC ops.sp_prueba_resumen @act;
    END;
    BEGIN TRY
        EXEC ops.sp_asignacion_486 @fecha = @fecha, @id_corrida = @asig OUTPUT;
    END TRY
    BEGIN CATCH
        SET @err = ERROR_MESSAGE();
    END CATCH;
    IF @asig IS NULL SET @asig = (SELECT MAX(ID_CORRIDA) FROM ops.CORRIDA WHERE CLIENTE = @cliente AND PROCESO = 'ASIG' AND FECHA_PROCESO = @fecha);
    IF @asig IS NOT NULL AND NOT EXISTS (SELECT 1 FROM ops.PRUEBA_CORRIDA WHERE ID_CORRIDA = @asig)
        INSERT INTO ops.PRUEBA_CORRIDA (ID_CORRIDA, PROCESO) VALUES (@asig, 'ASIG');
    SELECT CASE WHEN @err IS NULL THEN N'ASIGNACION DE PRUEBA OK' ELSE N'LA ASIGNACION DE PRUEBA FALLÓ (el DAT ya regresó solo)' END AS RESULTADO, @err AS DETALLE;
    IF @asig IS NOT NULL EXEC ops.sp_prueba_resumen @asig;
END;
GO

/* ---------------------------------------------------------------------
   Revierte lo que corrió la prueba (de la más reciente a la más antigua).
   @confirmar = 0 solo muestra qué revertiría.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE ops.sp_prueba_revertir
    @confirmar BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @id INT, @est VARCHAR(15), @auto BIT;
    SELECT p.ID_CORRIDA, p.PROCESO, c.FECHA_PROCESO, c.ESTATUS, c.REVERTIDA_AUTO
    FROM ops.PRUEBA_CORRIDA p JOIN ops.CORRIDA c ON c.ID_CORRIDA = p.ID_CORRIDA ORDER BY p.ID_CORRIDA DESC;
    IF @confirmar = 0
    BEGIN
        PRINT 'Vista previa: ejecuta con @confirmar = 1 para revertir estas corridas.';
        RETURN;
    END;
    DECLARE cr CURSOR LOCAL FAST_FORWARD FOR
        SELECT p.ID_CORRIDA, c.ESTATUS, c.REVERTIDA_AUTO FROM ops.PRUEBA_CORRIDA p JOIN ops.CORRIDA c ON c.ID_CORRIDA = p.ID_CORRIDA ORDER BY p.ID_CORRIDA DESC;
    OPEN cr; FETCH NEXT FROM cr INTO @id, @est, @auto;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        IF @est <> 'REVERTIDA' AND @auto = 0
            EXEC ops.sp_revertir_corrida @id, @confirmar = 1;
        FETCH NEXT FROM cr INTO @id, @est, @auto;
    END;
    CLOSE cr; DEALLOCATE cr;
    SELECT p.ID_CORRIDA, p.PROCESO, c.ESTATUS, c.REVERTIDA_AUTO FROM ops.PRUEBA_CORRIDA p JOIN ops.CORRIDA c ON c.ID_CORRIDA = p.ID_CORRIDA ORDER BY p.ID_CORRIDA DESC;
    DELETE FROM ops.PRUEBA_CORRIDA;
    SELECT N'PRUEBA REVERTIDA' AS RESULTADO, N'Lo que se escribió en la carpeta de prueba no se borra solo: bórralo (trae datos de clientes).' AS NOTA;
END;
GO

SET NOEXEC OFF;
GO
