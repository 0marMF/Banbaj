/* =====================================================================
   Banbaj · Instalación 4 · Accesos desde otras computadoras
   ---------------------------------------------------------------------
   Antes, en el servidor (fuera de SQL, ver el manual):
     1. SQL Server Configuration Manager: activar TCP/IP, puerto fijo 1433, reiniciar el servicio.
     2. Firewall de Windows: abrir TCP 1433 (y UDP 1434 si es instancia con nombre).
   Este script crea los inicios de sesión y les da permisos. Córrelo como sysadmin.

   Niveles:
     CONSULTA  · solo lee DAT, histórico, corridas y bitácora. No ve credenciales.
     OPERADOR  · corre los procesos (db_owner de la base). Los procedimientos usan SQL
                 dinámico, BULK INSERT y tablas de paso, por eso necesita permisos amplios
                 en la base. Se le niega leer las credenciales.
     ADMIN     · sysadmin. Solo para quien escribe los archivos y arma el ZIP a mano
                 (ops.sp_exportar_salidas): Automatización OLE y xp_cmdshell exigen sysadmin.
                 El job diario corre como el Agente y no necesita esto. Bajar de CYBER
                 (sp_bajar_cyber) sí lo puede hacer un OPERADOR.

   Usuarios de Windows del dominio: 'DOMINIO\usuario' (recomendado, sin contraseña en SQL).
   No pongas aquí a sa ni a quien corre el script: ya tienen acceso total y se omiten.
   Cambia @base si la base no se llama Banbaj.
   Usuarios de SQL: requiere modo mixto; se crean con contraseña y CHECK_POLICY.
   ===================================================================== */
SET NOCOUNT ON;
USE master;

DECLARE @base SYSNAME = N'Banbaj';
DECLARE @accesos TABLE (LOGIN SYSNAME, NIVEL VARCHAR(10), CLAVE NVARCHAR(128) NULL);
INSERT INTO @accesos (LOGIN, NIVEL, CLAVE) VALUES
    (N'<<DOMINIO\usuario1>>', 'OPERADOR', NULL),        -- Windows: CLAVE en NULL
    (N'<<DOMINIO\usuario2>>', 'CONSULTA', NULL);
--  (N'banbaj_consulta',     'CONSULTA', N'<<contraseña>>');   -- usuario SQL (modo mixto)

IF EXISTS (SELECT 1 FROM @accesos WHERE LOGIN LIKE N'%<<%' OR CLAVE LIKE N'%<<%')
    THROW 50999, 'Faltan valores <<…>> por reemplazar en este script.', 1;
IF EXISTS (SELECT 1 FROM @accesos WHERE NIVEL NOT IN ('CONSULTA', 'OPERADOR', 'ADMIN'))
    THROW 50998, 'NIVEL debe ser CONSULTA, OPERADOR o ADMIN.', 1;

DECLARE @login SYSNAME, @nivel VARCHAR(10), @clave NVARCHAR(128), @sql NVARCHAR(MAX);
DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT LOGIN, NIVEL, CLAVE FROM @accesos;
OPEN c; FETCH NEXT FROM c INTO @login, @nivel, @clave;
WHILE @@FETCH_STATUS = 0
BEGIN
    /* sa, los sysadmin, el dueño de la base y quien corre el script ya tienen acceso total:
       no se les puede dar ni negar permisos (errores 15405 y "Cannot grant… to yourself"). Se omiten. */
    IF @login = N'sa' OR @login = SUSER_SNAME()
       OR IS_SRVROLEMEMBER('sysadmin', @login) = 1
       OR @login = (SELECT SUSER_SNAME(owner_sid) FROM sys.databases WHERE name = @base)
    BEGIN
        PRINT CONCAT(@login, N': ya tiene acceso total (sa, sysadmin, dueño de la base o quien corre el script); se omite');
        FETCH NEXT FROM c INTO @login, @nivel, @clave;
        CONTINUE;
    END;

    /* Inicio de sesión en el servidor */
    IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = @login)
    BEGIN
        IF @clave IS NULL
            SET @sql = N'CREATE LOGIN ' + QUOTENAME(@login) + N' FROM WINDOWS WITH DEFAULT_DATABASE = ' + QUOTENAME(@base) + N';';
        ELSE
            SET @sql = N'CREATE LOGIN ' + QUOTENAME(@login) + N' WITH PASSWORD = ' + QUOTENAME(@clave, '''')
                     + N', CHECK_POLICY = ON, DEFAULT_DATABASE = ' + QUOTENAME(@base) + N';';
        EXEC (@sql);
    END;

    IF @nivel = 'ADMIN'
        EXEC sp_addsrvrolemember @loginame = @login, @rolename = 'sysadmin';
    IF @nivel = 'OPERADOR'
    BEGIN
        SET @sql = N'GRANT ADMINISTER BULK OPERATIONS TO ' + QUOTENAME(@login) + N';';      -- lectura de CSV
        EXEC (@sql);
    END;

    /* Usuario en la base y rol */
    IF @nivel <> 'ADMIN'
    BEGIN
        SET @sql = N'USE ' + QUOTENAME(@base) + N';
            IF DATABASE_PRINCIPAL_ID(@login) IS NULL
                EXEC (N''CREATE USER '' + @q + N'' FOR LOGIN '' + @q + N'';'');
            IF @nivel = ''CONSULTA''
            BEGIN
                ALTER ROLE db_datareader ADD MEMBER ' + QUOTENAME(@login) + N';
                GRANT VIEW DEFINITION TO ' + QUOTENAME(@login) + N';
            END
            ELSE
                ALTER ROLE db_owner ADD MEMBER ' + QUOTENAME(@login) + N';
            DENY SELECT ON cfg.CREDENCIAL TO ' + QUOTENAME(@login) + N';
            DENY EXECUTE ON cfg.sp_credencial_leer TO ' + QUOTENAME(@login) + N';';
        DECLARE @q NVARCHAR(300) = QUOTENAME(@login);
        EXEC sp_executesql @sql, N'@login SYSNAME, @nivel VARCHAR(10), @q NVARCHAR(300)', @login = @login, @nivel = @nivel, @q = @q;

        /* Correos manuales (sp_avisar, sp_aviso_devolucion) */
        IF @nivel = 'OPERADOR'
        BEGIN
            SET @sql = N'USE msdb;
                IF DATABASE_PRINCIPAL_ID(@login) IS NULL
                    EXEC (N''CREATE USER '' + @q + N'' FOR LOGIN '' + @q + N'';'');
                ALTER ROLE DatabaseMailUserRole ADD MEMBER ' + QUOTENAME(@login) + N';';
            EXEC sp_executesql @sql, N'@login SYSNAME, @q NVARCHAR(300)', @login = @login, @q = @q;
        END;
    END;

    PRINT CONCAT(@login, ': ', @nivel);
    FETCH NEXT FROM c INTO @login, @nivel, @clave;
END;
CLOSE c; DEALLOCATE c;

/* Revisar */
SELECT p.name AS LOGIN, p.type_desc AS TIPO, IS_SRVROLEMEMBER('sysadmin', p.name) AS SYSADMIN
FROM sys.server_principals p
WHERE p.name IN (SELECT LOGIN FROM @accesos);
