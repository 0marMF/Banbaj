/* =====================================================================
   Banbaj · 74 Consultas a CYBER (Oracle) desde SQL Server
   ---------------------------------------------------------------------
   Sustituye a tools/bajar_cyber.py (Python): todo corre en el servidor.

   1. Una vez (y cada vez que cambie la contraseña):
        INSERT INTO cfg.CAPTURA_CREDENCIAL (SISTEMA, USUARIO, CLAVE) VALUES ('CYBER_ORACLE', '…', '…');
        EXEC cfg.sp_cyber_conectar;          -- crea o actualiza el servidor vinculado CYBER
   2. Cuando toque:
        EXEC ops.sp_bajar_cyber 'STATUS',    @id_corrida = 125;   -- STATUS.SQL  -> blanqueo de status
        EXEC ops.sp_bajar_cyber 'CORREOS',   @id_corrida = 125;   -- cyadd.sql   -> INSERT de correos nuevos
        EXEC ops.sp_bajar_cyber 'TELEFONOS', @id_corrida = 125;   -- TELs_486    -> gescar sin teléfono
        EXEC ops.sp_bajar_cyber 'PAGOS',     @id_corrida = 130;   -- BAJ.sql     -> cuadre de pagos
      @solo_bajar = 1 solo llena la tabla de paso; @solo_mostrar = 1 enseña la consulta sin ejecutarla.

   Requisitos en el servidor de SQL Server (una vez, lo hace un administrador):
     - Cliente de Oracle de 64 bits con el proveedor OLE DB (OraOLEDB.Oracle) y la
       opción "Allow inprocess" activada para ese proveedor.
     - Parámetros CYBER_ORACLE_ORIGEN (host:puerto/servicio) y CYBER_LINKED_SERVER.
   ===================================================================== */
SET NOCOUNT ON;
GO

CREATE OR ALTER PROCEDURE cfg.sp_cyber_conectar
    @cliente VARCHAR(10) = '486'
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @srv SYSNAME = ISNULL(cfg.fn_param(@cliente, 'CYBER_LINKED_SERVER'), 'CYBER'),
            @origen NVARCHAR(400) = cfg.fn_param(@cliente, 'CYBER_ORACLE_ORIGEN'),
            @proveedor NVARCHAR(100) = ISNULL(cfg.fn_param(@cliente, 'CYBER_ORACLE_PROVEEDOR'), 'OraOLEDB.Oracle'),
            @usuario NVARCHAR(128), @clave NVARCHAR(256);
    IF NULLIF(@origen, N'') IS NULL THROW 50810, 'Falta el parámetro CYBER_ORACLE_ORIGEN (host:puerto/servicio de Oracle).', 1;
    EXEC cfg.sp_credencial_leer 'CYBER_ORACLE', @usuario OUTPUT, @clave OUTPUT;

    IF NOT EXISTS (SELECT 1 FROM sys.servers WHERE name = @srv)
        EXEC master.dbo.sp_addlinkedserver @server = @srv, @srvproduct = N'Oracle', @provider = @proveedor, @datasrc = @origen;
    ELSE
        EXEC master.dbo.sp_setnetname @server = @srv, @netname = @origen;
    EXEC master.dbo.sp_serveroption @server = @srv, @optname = 'rpc out', @optvalue = 'true';
    EXEC master.dbo.sp_serveroption @server = @srv, @optname = 'remote proc transaction promotion', @optvalue = 'false';
    EXEC master.dbo.sp_addlinkedsrvlogin @rmtsrvname = @srv, @useself = 'FALSE', @locallogin = NULL, @rmtuser = @usuario, @rmtpassword = @clave;
    PRINT CONCAT('Servidor vinculado ', @srv, ' listo con el usuario ', @usuario, '.');
END;
GO

CREATE OR ALTER PROCEDURE ops.sp_bajar_cyber
    @que          VARCHAR(20),               -- STATUS / CORREOS / TELEFONOS / PAGOS
    @id_corrida   INT  = NULL,
    @fecha        DATE = NULL,               -- solo PAGOS: día a cuadrar (por omisión hoy, como BAJ.sql)
    @forzar       BIT  = 0,                  -- solo STATUS: blanquea aunque no sea día 1 a 10
    @solo_bajar   BIT  = 0,
    @solo_mostrar BIT  = 0
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @cliente VARCHAR(10), @srv SYSNAME, @q NVARCHAR(MAX), @tabla SYSNAME, @cols NVARCHAR(400), @sql NVARCHAR(MAX), @n INT, @msg NVARCHAR(4000);
    SET @que = UPPER(LTRIM(RTRIM(@que)));
    IF @que NOT IN ('STATUS', 'CORREOS', 'TELEFONOS', 'PAGOS') THROW 50820, '@que debe ser STATUS, CORREOS, TELEFONOS o PAGOS.', 1;
    IF @solo_bajar = 0 AND @solo_mostrar = 0 AND @id_corrida IS NULL THROW 50821, 'Indica @id_corrida (o usa @solo_bajar = 1).', 1;

    SELECT @cliente = CLIENTE FROM ops.CORRIDA WHERE ID_CORRIDA = @id_corrida;
    SET @cliente = ISNULL(@cliente, '486');
    IF @cliente LIKE '%[^0-9]%' THROW 50822, 'Cliente inválido.', 1;
    SET @srv = ISNULL(cfg.fn_param(@cliente, 'CYBER_LINKED_SERVER'), 'CYBER');
    SET @fecha = ISNULL(@fecha, CAST(GETDATE() AS DATE));

    /* Mismas consultas que STATUS.SQL, cyadd.sql, TELs_486.sql y BAJ.sql */
    IF @que = 'STATUS'
        SELECT @tabla = 'stg.CYBER_STATUS', @cols = N'CLIENTE, FOLIO, CUENTA, STATUS, ACCION, FECHA, PESO, DMSSNUM',
               @q = N'select DMCOMPANY, DMADL1, DMACCT, DMACRC2, DMACAC2, TO_CHAR(DMACDT2, ''DD/MM/YYYY HH24:MI:SS''), DMACSC2, DMSSNUM '
                  + N'from RCVRY.delqmst where DMACCTG = ''1'' and DMCOMPANY = ''' + @cliente + N''' and DMSTATUS is null';
    ELSE IF @que = 'CORREOS'
        SELECT @tabla = 'stg.CYBER_CORREO', @cols = N'CUENTA, CORREO',
               @q = N'select a.ADACCT, a.ADADDR1 from RCVRY.Address a join RCVRY.delqmst d on d.DMACCTG = a.ADACCTG and d.DMACCT = a.ADACCT '
                  + N'where d.DMACCTG = ''1'' and d.DMCOMPANY = ''' + @cliente + N''' and d.DMSTATUS is null and a.ADTYPE = ''3''';
    ELSE IF @que = 'TELEFONOS'
        SELECT @tabla = 'stg.CYBER_TELEFONO', @cols = N'CUENTA, LADA, TEL',
               @q = N'select p.PHACCT, p.PHAREACODE, p.PHPHONE from RCVRY.delqmst d join RCVRY.phone p on p.PHACCTG = d.DMACCTG and p.PHACCT = d.DMACCT '
                  + N'where d.DMACCTG = ''1'' and d.DMCOMPANY = ''' + @cliente + N''' and p.PHSTATUS = ''A''';
    ELSE
        SELECT @tabla = 'stg.CYBER_PAGO', @cols = N'CUENTA, MONTO, FECHA',
               @q = N'select PMACCT, TO_CHAR(PMAMOUNT, ''FM999999999990.00''), TO_CHAR(PMEDATE, ''DD/MM/YYYY'') from RCVRY.pmtfil '
                  + N'where PMACCTG = ''1'' and PMACCT in (select DMACCT from RCVRY.delqmst where DMCOMPANY = ''' + @cliente + N''') '
                  + N'and TRUNC(PMEDATE) = TO_DATE(''' + CONVERT(CHAR(10), @fecha, 23) + N''', ''YYYY-MM-DD'')';

    SET @sql = N'INSERT INTO ' + @tabla + N' (' + @cols + N') EXEC (N''' + REPLACE(@q, N'''', N'''''') + N''') AT ' + QUOTENAME(@srv) + N';';   -- QUOTENAME corta a 128 caracteres
    IF @solo_mostrar = 1
    BEGIN
        SELECT @que AS CONSULTA, @srv AS SERVIDOR, @q AS ORACLE, @sql AS SQL_SERVER;
        RETURN;
    END;
    IF NOT EXISTS (SELECT 1 FROM sys.servers WHERE name = @srv)
    BEGIN
        SET @msg = CONCAT(N'No existe el servidor vinculado ', @srv, N'. Captura la credencial CYBER_ORACLE y ejecuta EXEC cfg.sp_cyber_conectar.');
        THROW 50823, @msg, 1;
    END;

    EXEC (N'TRUNCATE TABLE ' + @tabla + N';');
    EXEC (@sql);
    SET @n = @@ROWCOUNT;
    IF @id_corrida IS NOT NULL
    BEGIN
        SET @msg = CONCAT(@que, N': ', @n, N' registros de CYBER');
        EXEC ops.sp_log @id_corrida, 'CYBER BAJADA', 'OK', @n, @msg;
    END;
    PRINT CONCAT(@que, ': ', @n, ' registros bajados a ', @tabla);
    IF @solo_bajar = 1 RETURN;

    IF @que = 'STATUS'         EXEC ops.sp_blanqueo_status @id_corrida = @id_corrida, @forzar = @forzar;
    ELSE IF @que = 'CORREOS'
    BEGIN
        DECLARE @sin_datos BIT = CASE WHEN @n = 0 THEN 1 ELSE 0 END;   -- la consulta corrió y no trajo correos: todos son nuevos
        EXEC ops.sp_correos_nuevos @id_corrida = @id_corrida, @cyber_sin_datos = @sin_datos;
    END
    ELSE IF @que = 'TELEFONOS' EXEC ops.sp_gescar_sin_telefono @id_corrida = @id_corrida;
    ELSE                       EXEC ops.sp_cuadrar_pagos @id_corrida = @id_corrida;
END;
GO
