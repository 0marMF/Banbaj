USE [BNABAJ_486];   -- base del 486 (si la instalas con otro nombre, cámbialo aquí)
GO
/* =====================================================================
   Banbaj · 76 Arribo automático a CYBER de teléfonos y correos (decisión 02/11)
   ---------------------------------------------------------------------
   El operador solo sube los archivos de ancho fijo con el cargador de CYBER
   (SCBSDOS, SCBTEL, gescar). Lo demás lo hace SQL Server por el servidor
   vinculado [CYBER], sin sqlldr ni scripts a mano:

   Orden (decisiones 17/11 y 19/11):
     1. Asignaciones sube el SCBSDOS. Saldos arriba (DMHOSTUP del día = cuentas del SCBSDOS) -> paso ARRIBO SALDOS:
        se escriben y avisan los gescar de nuevas, reasignadas y sin teléfono (este último sale de nuestros teléfonos:
        después de la depuración lo activo en CYBER es lo de ops.TELEFONO).
     2. Depuración de teléfonos, con la bandera de CYBER encendida (CYBER_BANDERA_TELEFONOS, 416). TEL_DEPURACION:
          DIFERENCIA (19/11) = baja la foto de PHONE de las cuentas activas, la compara aquí con nuestros teléfonos y a
                       CYBER solo sube lo que cambia (RCVRY.JSP_TAB_TEL_DEPURA_486: I inactivar, A activar, N nuevo);
                       si cuadra, ejecuta JSP_TELEFONOS_DEPURA_486. El SCBTEL lleva solo los nuevos.
          ACTUAL     = remesa completa (RCVRY.JSP_TAB_TEL_REMESA_486) y JSP_TELEFONOS_REMESA_486.
        Se apaga la bandera, se escribe el SCBTEL (si hay nuevos) y se avisa a asignaciones que ya lo puede subir.
     3. Depuración de correos (con la de teléfonos OK): correos nuevos en ADDRESS, bandera 416,
        remesa y JSP_CORREOS_486, bandera apagada.
     4. Asignaciones sube el SCBTEL: los nuevos llegan a PHONE_G1.
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
    /* Pruebas de entorno (20/11): con CYBER_SOLO_LECTURA = 1 no se escribe nada en CYBER; solo queda en la bitácora */
    IF ISNULL(cfg.fn_param(@cliente, 'CYBER_SOLO_LECTURA'), '0') = '1'
    BEGIN
        SET @msg = CONCAT(@script, N': ', @sentencias, N' sentencias NO ejecutadas en CYBER (CYBER_SOLO_LECTURA = 1, modo de prueba)');
        EXEC ops.sp_log @id_corrida, 'CYBER EJECUTA', 'AVISO', @sentencias, @msg;
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

/* La depuración del 18/11 bajaba los nuevos de la remesa; la del 19/11 los calcula aquí (ops.sp_tel_depura_calcular) */
DROP PROCEDURE IF EXISTS ops.sp_tel_nuevos;
GO

/* Depuración de teléfonos por diferencia (TEL_DEPURACION = DIFERENCIA, 19/11). Corre con la bandera ya encendida:
   1. Baja de CYBER la foto de PHONE de las cuentas activas del 486 (activos e inactivos) a stg.CYBER_PHONE_FOTO.
   2. La compara con nuestros teléfonos (ops.TELEFONO) y deja en ops.TEL_DEPURA solo lo que cambia:
        I = activo en CYBER y no está en nuestro archivo · A = inactivo en CYBER y sí está · N = no existe en PHONE.
      Lo de gestores de queja (TEL_GESTORES_QUEJA) no se toca.
   3. Marca NUEVO en ops.TELEFONO, vuelve a generar el SCBTEL solo con los nuevos y deja en ops.ARRIBO_PENDIENTE los
      teléfonos que el arribo espera ver en PHONE_G1.
   4. Arma los scripts: TEL_BORRA vacía RCVRY.JSP_TAB_TEL_DEPURA_486, TEL_DEPURA la llena y TEL_ACTUALIZA llama al store
      con la bandera, los renglones esperados y los teléfonos de queja (para el validador).
   Si se inactivaría más de TEL_DEPURA_MAX_INACTIVAR_PCT % de los activos de la foto, se detiene sin tocar CYBER.
   Lo que un gestor agregue entre la foto y el store se queda activo hasta la siguiente asignación.
   @sin_bajar = 1 usa lo que ya esté en stg.CYBER_PHONE_FOTO (pruebas). */
CREATE OR ALTER PROCEDURE ops.sp_tel_depura_calcular
    @id_corrida INT,
    @sin_bajar  BIT = 0,
    @cambios    INT = NULL OUTPUT,
    @nuevos     INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @cliente VARCHAR(10) = (SELECT CLIENTE FROM ops.CORRIDA WHERE ID_CORRIDA = @id_corrida);
    DECLARE @srv SYSNAME = ISNULL(cfg.fn_param(@cliente, 'CYBER_LINKED_SERVER'), 'CYBER'),
            @queja NVARCHAR(400) = ISNULL(NULLIF(cfg.fn_param(@cliente, 'TEL_GESTORES_QUEJA'), N''), N'HOMS,HPHPI,BLACK,ZZZTE'),
            @max DECIMAL(5,2) = ISNULL(TRY_CONVERT(DECIMAL(5,2), cfg.fn_param(@cliente, 'TEL_DEPURA_MAX_INACTIVAR_PCT')), 30),
            @proc NVARCHAR(200) = ISNULL(NULLIF(cfg.fn_param(@cliente, 'CYBER_PROC_TEL_DEPURA'), N''), N'RCVRY.JSP_TELEFONOS_DEPURA_486'),
            @bandera VARCHAR(10) = ISNULL(NULLIF(LTRIM(RTRIM(cfg.fn_param(@cliente, 'CYBER_BANDERA_TELEFONOS'))), N''), '416'),
            @q NVARCHAR(MAX), @sql NVARCHAR(MAX), @msg NVARCHAR(4000),
            @foto INT, @activos INT, @i INT, @a INT, @quejas INT, @total INT;
    IF @cliente IS NULL OR @cliente LIKE '%[^0-9]%' THROW 50778, 'Indica una corrida válida.', 1;
    IF @proc LIKE N'%[^A-Za-z0-9_.]%' OR @bandera LIKE '%[^0-9]%'
        THROW 50778, 'CYBER_PROC_TEL_DEPURA (solo letras, números, punto y _) o CYBER_BANDERA_TELEFONOS (numérico) inválidos.', 1;

    /* 1. Foto de PHONE */
    IF @sin_bajar = 0
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM sys.servers WHERE name = @srv)
        BEGIN
            SET @msg = CONCAT(N'No existe el servidor vinculado ', @srv, N'.');
            THROW 50777, @msg, 1;
        END;
        TRUNCATE TABLE stg.CYBER_PHONE_FOTO;
        SET @q = N'select p.PHACCT, p.PHAREACODE, p.PHPHONE, p.PHSTATUS, p.PHSTCOLLID from RCVRY.phone p '
               + N'join RCVRY.delqmst d on d.DMACCTG = p.PHACCTG and d.DMACCT = p.PHACCT '
               + N'where d.DMACCTG = ''1'' and d.DMCOMPANY = ''' + @cliente + N''' and d.DMSTATUS is null';
        SET @sql = N'INSERT INTO stg.CYBER_PHONE_FOTO (CUENTA, AREA, TELEFONO, ESTATUS, GESTOR) EXEC (N''' + REPLACE(@q, N'''', N'''''') + N''') AT ' + QUOTENAME(@srv) + N';';
        EXEC (@sql);
    END;

    /* 2. Un renglón por teléfono de la foto con lo que hay de él en CYBER */
    SELECT k.CUENTA, k.AREA, k.TELEFONO,
           MAX(CASE WHEN q.G IS NULL AND k.ESTATUS = N'A' THEN 1 ELSE 0 END) AS ACT_LIBRE,
           MAX(CASE WHEN q.G IS NULL AND k.ESTATUS = N'I' THEN 1 ELSE 0 END) AS INA_LIBRE,
           MAX(CASE WHEN k.ESTATUS = N'A' THEN 1 ELSE 0 END) AS ACTIVO,
           MAX(CASE WHEN q.G IS NOT NULL THEN 1 ELSE 0 END) AS QUEJA
    INTO #f
    FROM stg.CYBER_PHONE_FOTO f
    CROSS APPLY (SELECT LEFT(LTRIM(RTRIM(f.CUENTA)), 28) AS CUENTA, LEFT(ISNULL(LTRIM(RTRIM(f.AREA)), N''), 10) AS AREA,
                        LEFT(ISNULL(LTRIM(RTRIM(f.TELEFONO)), N''), 20) AS TELEFONO, UPPER(LTRIM(RTRIM(f.ESTATUS))) AS ESTATUS) k
    OUTER APPLY (SELECT TOP (1) 1 AS G FROM STRING_SPLIT(@queja, N',') s
                 WHERE UPPER(LTRIM(RTRIM(s.value))) = UPPER(LTRIM(RTRIM(f.GESTOR))) AND LTRIM(RTRIM(s.value)) <> N'') q
    WHERE NULLIF(k.CUENTA, N'') IS NOT NULL AND k.TELEFONO <> N''
    GROUP BY k.CUENTA, k.AREA, k.TELEFONO;
    CREATE UNIQUE CLUSTERED INDEX IX ON #f (CUENTA, AREA, TELEFONO);

    DELETE FROM ops.TEL_DEPURA WHERE ID_CORRIDA = @id_corrida;
    INSERT INTO ops.TEL_DEPURA (ID_CORRIDA, CUENTA2, AREA, TELEFONO, ACCION)
    SELECT @id_corrida, f.CUENTA, f.AREA, f.TELEFONO, 'I'
    FROM #f f
    WHERE f.ACT_LIBRE = 1
      AND NOT EXISTS (SELECT 1 FROM ops.TELEFONO t WHERE t.ID_CORRIDA = @id_corrida AND t.CUENTA2 = f.CUENTA AND t.AREA = f.AREA AND t.TELEFONO = f.TELEFONO);
    INSERT INTO ops.TEL_DEPURA (ID_CORRIDA, CUENTA2, AREA, TELEFONO, ACCION)
    SELECT @id_corrida, t.CUENTA2, t.AREA, t.TELEFONO, CASE WHEN f.CUENTA IS NULL THEN 'N' ELSE 'A' END
    FROM ops.TELEFONO t
    LEFT JOIN #f f ON f.CUENTA = t.CUENTA2 AND f.AREA = t.AREA AND f.TELEFONO = t.TELEFONO
    WHERE t.ID_CORRIDA = @id_corrida AND (f.CUENTA IS NULL OR (f.INA_LIBRE = 1 AND f.ACTIVO = 0));

    SELECT @i = ISNULL(SUM(CASE WHEN ACCION = 'I' THEN 1 ELSE 0 END), 0), @a = ISNULL(SUM(CASE WHEN ACCION = 'A' THEN 1 ELSE 0 END), 0),
           @nuevos = ISNULL(SUM(CASE WHEN ACCION = 'N' THEN 1 ELSE 0 END), 0), @cambios = COUNT(*)
    FROM ops.TEL_DEPURA WHERE ID_CORRIDA = @id_corrida;
    SELECT @foto = COUNT(*), @activos = ISNULL(SUM(ACT_LIBRE), 0) FROM #f;
    SET @total = (SELECT COUNT(*) FROM ops.TELEFONO WHERE ID_CORRIDA = @id_corrida);
    SET @quejas = (SELECT COUNT(*) FROM ops.TELEFONO t JOIN #f f ON f.CUENTA = t.CUENTA2 AND f.AREA = t.AREA AND f.TELEFONO = t.TELEFONO
                   WHERE t.ID_CORRIDA = @id_corrida AND f.QUEJA = 1);
    SET @msg = CONCAT(N'Foto de PHONE en CYBER: ', @foto, N' teléfonos (', @activos, N' activos sin queja) · nuestro archivo: ', @total,
                      N' · a inactivar: ', @i, N' · a activar: ', @a, N' · nuevos (van en el SCBTEL): ', @nuevos,
                      N' · de queja sin tocar: ', @quejas, N' · renglones a CYBER: ', @cambios);

    /* Freno: una foto o un archivo incompletos inactivarían teléfonos buenos */
    IF @activos > 0 AND 100.0 * @i > @max * @activos
    BEGIN
        SET @msg = CONCAT(N'Se inactivarían ', @i, N' de ', @activos, N' teléfonos activos (más del ', @max,
                          N' % de TEL_DEPURA_MAX_INACTIVAR_PCT); no se toca CYBER. Revisar nuestro archivo de teléfonos y la foto. ', @msg);
        EXEC ops.sp_log @id_corrida, 'TEL DIFERENCIA', 'ERROR', @i, @msg;
        THROW 50779, @msg, 1;
    END;

    /* 3. Nuevos: SCBTEL solo con ellos y lo que el arribo espera ver en PHONE_G1 */
    UPDATE t SET NUEVO = CASE WHEN EXISTS (SELECT 1 FROM ops.TEL_DEPURA d WHERE d.ID_CORRIDA = t.ID_CORRIDA AND d.CUENTA2 = t.CUENTA2
                                                AND d.AREA = t.AREA AND d.TELEFONO = t.TELEFONO AND d.ACCION = 'N') THEN 1 ELSE 0 END
    FROM ops.TELEFONO t WHERE t.ID_CORRIDA = @id_corrida;
    DELETE FROM ops.ARRIBO_PENDIENTE WHERE ID_CORRIDA = @id_corrida AND TIPO = 'TELEFONO';
    INSERT INTO ops.ARRIBO_PENDIENTE (ID_CORRIDA, TIPO, CUENTA, AREA, TELEFONO)
    SELECT @id_corrida, 'TELEFONO', CUENTA2, AREA, TELEFONO FROM ops.TELEFONO WHERE ID_CORRIDA = @id_corrida AND NUEVO = 1;
    EXEC ops.sp_generar_salida @id_corrida, 'SCBTEL';

    /* 4. Scripts para CYBER */
    DELETE FROM ops.CYBER_SCRIPT WHERE ID_CORRIDA = @id_corrida AND SCRIPT = 'TEL_DEPURA';
    INSERT INTO ops.CYBER_SCRIPT (ID_CORRIDA, SCRIPT, NUM, SENTENCIA)
    SELECT @id_corrida, 'TEL_DEPURA', ROW_NUMBER() OVER (ORDER BY ACCION, CUENTA2, AREA, TELEFONO),
           CONCAT(N'INSERT INTO RCVRY.JSP_TAB_TEL_DEPURA_486 (CUENTA, AREA, TELEFONO, ACCION) VALUES (''', REPLACE(CUENTA2, '''', ''''''), N''', ''',
                  REPLACE(AREA, '''', ''''''), N''', ''', REPLACE(TELEFONO, '''', ''''''), N''', ''', ACCION, N''');')
    FROM ops.TEL_DEPURA WHERE ID_CORRIDA = @id_corrida;
    UPDATE ops.CYBER_SCRIPT SET SENTENCIA = N'TRUNCATE TABLE RCVRY.JSP_TAB_TEL_DEPURA_486;'
    WHERE ID_CORRIDA = @id_corrida AND SCRIPT = 'TEL_BORRA' AND NUM = 1;
    UPDATE ops.CYBER_SCRIPT SET SENTENCIA = CONCAT(N'EXECUTE ', @proc, N'(', @bandera, N', ', @cambios, N', ', @quejas, N');')
    WHERE ID_CORRIDA = @id_corrida AND SCRIPT = 'TEL_ACTUALIZA' AND NUM = 1;

    EXEC ops.sp_log @id_corrida, 'TEL DIFERENCIA', 'OK', @cambios, @msg;
END;
GO

/* Lo que quedó en CYBER tiene que tener los mismos renglones que lo que mandamos antes de ejecutar el store:
   con ACTUAL, RCVRY.JSP_TAB_TEL_REMESA_486 contra ops.TELEFONO (si no, JSP_TELEFONOS_REMESA_486 inactivaría teléfonos
   buenos); con DIFERENCIA (@depura = 1), RCVRY.JSP_TAB_TEL_DEPURA_486 contra ops.TEL_DEPURA.
   @conteo_cyber sirve para probar sin servidor vinculado. */
CREATE OR ALTER PROCEDURE ops.sp_tel_remesa_validar
    @id_corrida   INT,
    @conteo_cyber INT = NULL,
    @depura       BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @cliente VARCHAR(10) = (SELECT CLIENTE FROM ops.CORRIDA WHERE ID_CORRIDA = @id_corrida);
    DECLARE @srv SYSNAME = ISNULL(cfg.fn_param(@cliente, 'CYBER_LINKED_SERVER'), 'CYBER'), @nuestro INT, @archivo INT, @msg NVARCHAR(4000), @sql NVARCHAR(MAX),
            @tabla NVARCHAR(100) = CASE WHEN @depura = 1 THEN N'RCVRY.JSP_TAB_TEL_DEPURA_486' ELSE N'RCVRY.JSP_TAB_TEL_REMESA_486' END;
    SET @nuestro = CASE WHEN @depura = 1 THEN (SELECT COUNT(*) FROM ops.TEL_DEPURA WHERE ID_CORRIDA = @id_corrida)
                        ELSE (SELECT COUNT(*) FROM ops.TELEFONO WHERE ID_CORRIDA = @id_corrida) END;
    SET @archivo = CASE WHEN @depura = 1 THEN 0 ELSE (SELECT COUNT(*) FROM ops.SALIDA_LINEA WHERE ID_CORRIDA = @id_corrida AND ARCHIVO = 'TEL_SUBMST') END;
    IF @conteo_cyber IS NULL
    BEGIN
        CREATE TABLE #remesa (N INT);
        SET @sql = N'INSERT INTO #remesa (N) EXEC (N''select count(*) from ' + @tabla + N''') AT ' + QUOTENAME(@srv) + N';';
        EXEC (@sql);
        SET @conteo_cyber = (SELECT TOP (1) N FROM #remesa);
    END;
    SET @msg = CONCAT(@tabla, N': ', @conteo_cyber, CASE WHEN @depura = 1 THEN N' · cambios que mandamos: ' ELSE N' · nuestro archivo de teléfonos: ' END, @nuestro,
                      CASE WHEN @archivo > 0 AND @archivo <> @nuestro THEN CONCAT(N' (sub_mst.TXT: ', @archivo, N')') ELSE N'' END);
    IF ISNULL(@conteo_cyber, -1) <> @nuestro
    BEGIN
        SET @msg = CONCAT(N'Lo que quedó en CYBER no cuadra con lo que mandamos; no se ejecuta el store de teléfonos', 
                          CASE WHEN @depura = 1 THEN N'. ' ELSE N' (inactivaría teléfonos buenos). ' END, @msg);
        EXEC ops.sp_log @id_corrida, 'TEL REMESA VALIDADA', 'ERROR', @conteo_cyber, @msg;
        THROW 50776, @msg, 1;
    END;
    EXEC ops.sp_log @id_corrida, 'TEL REMESA VALIDADA', 'OK', @conteo_cyber, @msg;
END;
GO

/* Gescar de cuentas nuevas y reasignadas sin teléfono (ges486.prg). Desde el 19/11 sale de nuestros teléfonos: después de la
   depuración, lo activo en CYBER es lo de ops.TELEFONO (lo de gestores de queja no cuenta), así que no hay que esperar al
   SCBTEL. Se genera con la asignación y el job lo escribe junto con los gescar de nuevas y reasignadas al subir los saldos.
   A mano (vuelve a generar, escribe y avisa): EXEC ops.sp_arribo_gescar_sintel <corrida>; */
CREATE OR ALTER PROCEDURE ops.sp_arribo_gescar_sintel
    @id_corrida INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @msg NVARCHAR(4000), @n INT;
    BEGIN TRY
        EXEC ops.sp_generar_salida @id_corrida, 'GESCAR_SINTEL';
        SET @n = (SELECT COUNT(*) FROM ops.SALIDA_LINEA WHERE ID_CORRIDA = @id_corrida AND ARCHIVO = 'GESCAR_SINTEL');
        SET @msg = CONCAT(N'Cuentas nuevas o reasignadas sin teléfono en nuestro archivo: ', @n);
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
            /* Sin teléfonos nuestros, cualquiera de los dos stores inactivaría todos los teléfonos del 486 */
            IF NOT EXISTS (SELECT 1 FROM ops.TELEFONO WHERE ID_CORRIDA = @id_corrida)
                THROW 50767, 'La corrida no tiene teléfonos; no se ejecuta la depuración de teléfonos en CYBER.', 1;
            /* Modo (TEL_DEPURACION): ACTUAL = remesa completa y JSP_TELEFONOS_REMESA_486; DIFERENCIA (19/11) = foto de PHONE,
               comparación aquí y a CYBER solo lo que cambia (JSP_TELEFONOS_DEPURA_486). NUEVOS (18/11) se toma como DIFERENCIA. */
            SET @cli = (SELECT CLIENTE FROM ops.CORRIDA WHERE ID_CORRIDA = @id_corrida);
            SET @modo = UPPER(ISNULL(NULLIF(LTRIM(RTRIM(cfg.fn_param(@cli, 'TEL_DEPURACION'))), N''), N'ACTUAL'));
            IF @modo = N'NUEVOS' SET @modo = N'DIFERENCIA';
            IF @modo NOT IN (N'ACTUAL', N'DIFERENCIA') THROW 50758, 'TEL_DEPURACION debe ser ACTUAL o DIFERENCIA.', 1;
            /* Bandera de CYBER encendida durante toda la depuración (corridas anteriores al 19/11: se arma aquí) */
            IF NOT EXISTS (SELECT 1 FROM ops.CYBER_SCRIPT WHERE ID_CORRIDA = @id_corrida AND SCRIPT = 'TEL_ACTIVA_BANDERA')
                EXEC ops.sp_tel_bandera_script @id_corrida;
            EXEC ops.sp_cyber_ejecutar @id_corrida, 'TEL_ACTIVA_BANDERA', @solo_mostrar;
            SET @bandera = 1;
            IF @modo = N'ACTUAL'
            BEGIN
                UPDATE ops.CYBER_SCRIPT SET SENTENCIA = N'TRUNCATE TABLE RCVRY.JSP_TAB_TEL_REMESA_486;'
                WHERE ID_CORRIDA = @id_corrida AND SCRIPT = 'TEL_BORRA' AND NUM = 1;
                UPDATE ops.CYBER_SCRIPT SET SENTENCIA = CONCAT(N'EXECUTE ', ISNULL(NULLIF(cfg.fn_param(@cli, 'CYBER_PROC_TELEFONOS'), N''), N'RCVRY.JSP_TELEFONOS_REMESA_486'), N';')
                WHERE ID_CORRIDA = @id_corrida AND SCRIPT = 'TEL_ACTUALIZA' AND NUM = 1;
                EXEC ops.sp_cyber_remesa @id_corrida, 'TEL', @n OUTPUT;
                EXEC ops.sp_cyber_ejecutar @id_corrida, 'TEL_BORRA', @solo_mostrar;
                EXEC ops.sp_cyber_ejecutar @id_corrida, 'TEL_REMESA', @solo_mostrar;
                /* La remesa en CYBER debe cuadrar con nuestro archivo antes de que el store inactive lo que no está en ella */
                IF @solo_mostrar = 0 EXEC ops.sp_tel_remesa_validar @id_corrida;
                EXEC ops.sp_cyber_ejecutar @id_corrida, 'TEL_ACTUALIZA', @solo_mostrar;
                SET @msg = CONCAT(N'Depuración de teléfonos en CYBER (ACTUAL): remesa de ', @n, N' (cuadra con RCVRY.JSP_TAB_TEL_REMESA_486)');
            END
            ELSE
            BEGIN
                /* Foto de PHONE y diferencia (con @solo_mostrar se muestra lo último que se calculó) */
                IF @solo_mostrar = 0
                    EXEC ops.sp_tel_depura_calcular @id_corrida, @cambios = @n OUTPUT, @nuevos = @nuevos OUTPUT;
                ELSE
                BEGIN
                    SELECT @n = COUNT(*), @nuevos = ISNULL(SUM(CASE WHEN ACCION = 'N' THEN 1 ELSE 0 END), 0) FROM ops.TEL_DEPURA WHERE ID_CORRIDA = @id_corrida;
                    IF NOT EXISTS (SELECT 1 FROM ops.CYBER_SCRIPT WHERE ID_CORRIDA = @id_corrida AND SCRIPT = 'TEL_DEPURA')
                        UPDATE ops.CYBER_SCRIPT
                        SET SENTENCIA = CASE SCRIPT WHEN 'TEL_BORRA' THEN N'TRUNCATE TABLE RCVRY.JSP_TAB_TEL_DEPURA_486;'
                                        ELSE CONCAT(N'EXECUTE ', ISNULL(NULLIF(cfg.fn_param(@cli, 'CYBER_PROC_TEL_DEPURA'), N''), N'RCVRY.JSP_TELEFONOS_DEPURA_486'),
                                                    N'(', ISNULL(NULLIF(cfg.fn_param(@cli, 'CYBER_BANDERA_TELEFONOS'), N''), N'416'), N', 0, 0);') END
                        WHERE ID_CORRIDA = @id_corrida AND SCRIPT IN ('TEL_BORRA', 'TEL_ACTUALIZA') AND NUM = 1;
                END;
                /* Sin cambios no hay nada que subir ni que ejecutar */
                IF @n > 0 OR @solo_mostrar = 1
                BEGIN
                    EXEC ops.sp_cyber_ejecutar @id_corrida, 'TEL_BORRA', @solo_mostrar;
                    EXEC ops.sp_cyber_ejecutar @id_corrida, 'TEL_DEPURA', @solo_mostrar;
                    IF @solo_mostrar = 0 EXEC ops.sp_tel_remesa_validar @id_corrida, @depura = 1;
                    EXEC ops.sp_cyber_ejecutar @id_corrida, 'TEL_ACTUALIZA', @solo_mostrar;
                END;
                SET @msg = CONCAT(N'Depuración de teléfonos en CYBER (DIFERENCIA): ', @n, N' cambios',
                                  CASE WHEN @n > 0 THEN N' (cuadran con RCVRY.JSP_TAB_TEL_DEPURA_486)' ELSE N', no se ejecutó el store' END,
                                  N' · nuevos para el SCBTEL: ', ISNULL(@nuevos, 0));
            END;
            EXEC ops.sp_cyber_ejecutar @id_corrida, 'TEL_INACTIVA_BANDERA', @solo_mostrar;
            SET @bandera = 0;
        END;
        IF @solo_mostrar = 0 EXEC ops.sp_log @id_corrida, @paso, 'OK', @n, @msg;
        /* Con la depuración de teléfonos OK, asignaciones ya puede subir el SCBTEL: se escribe y se avisa */
        IF @que = 'TELEFONOS' AND @solo_mostrar = 0
        BEGIN
            DECLARE @tel NVARCHAR(400) = ISNULL(cfg.fn_param((SELECT CLIENTE FROM ops.CORRIDA WHERE ID_CORRIDA = @id_corrida), 'ARCHIVOS_DESPUES_DEPURACION_TEL'), N'SCBTEL');
            /* Sin teléfonos nuevos no hay SCBTEL que escribir ni que subir */
            IF @modo = N'DIFERENCIA' AND ISNULL(@nuevos, 0) = 0
                SET @tel = NULLIF((SELECT STRING_AGG(LTRIM(RTRIM(value)), N',') FROM STRING_SPLIT(@tel, N',') WHERE UPPER(LTRIM(RTRIM(value))) <> N'SCBTEL'), N'');
            IF @tel IS NOT NULL
                EXEC ops.sp_exportar_auto @id_corrida, @solo = @tel;
        END;
    END TRY
    BEGIN CATCH
        SET @msg = ERROR_MESSAGE();
        /* La bandera no se queda encendida si algo falla */
        IF @bandera = 1 AND @solo_mostrar = 0
        BEGIN
            DECLARE @apaga VARCHAR(40) = CASE WHEN @que = 'CORREOS' THEN 'MAIL_INACTIVA_BANDERA' ELSE 'TEL_INACTIVA_BANDERA' END;
            BEGIN TRY EXEC ops.sp_cyber_ejecutar @id_corrida, @apaga; END TRY BEGIN CATCH END CATCH;
        END;
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
    @fecha      DATE = NULL,
    @cliente    VARCHAR(10) = '486',
    @sin_bajar  BIT = 0,                 -- 1 = usa lo que ya está en stg.CYBER_DELQMST_ACT y stg.CYBER_PHONE_G1 (pruebas)
    @resultado  NVARCHAR(400) = NULL OUTPUT,
    @id_corrida INT = NULL               -- NULL = cada asignación OK del día, de la más antigua a la más reciente (20/11)
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
    /* Una asignación por segmento (20/11): el arribo de cada una sigue su propio camino. Se revisan todas las del día;
       si solo hay una, el resultado es el de siempre. */
    IF @id_corrida IS NULL
    BEGIN
        DECLARE @c INT, @r1 NVARCHAR(400), @todas NVARCHAR(4000) = N'', @k INT = 0;
        DECLARE ca CURSOR LOCAL FAST_FORWARD FOR
            SELECT ID_CORRIDA FROM ops.CORRIDA
            WHERE CLIENTE = @cliente AND PROCESO = 'ASIG' AND FECHA_PROCESO = @fecha AND ESTATUS = 'OK'
            ORDER BY ID_CORRIDA;
        OPEN ca; FETCH NEXT FROM ca INTO @c;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @r1 = NULL;
            EXEC ops.sp_arribo_automatico @fecha = @fecha, @cliente = @cliente, @sin_bajar = @sin_bajar, @resultado = @r1 OUTPUT, @id_corrida = @c;
            SET @k += 1;
            SET @todas = CONCAT(@todas, CASE WHEN @k > 1 THEN N' | ' ELSE N'' END, N'corrida ', @c, N': ', @r1);
            SET @resultado = @r1;
            FETCH NEXT FROM ca INTO @c;
        END;
        CLOSE ca; DEALLOCATE ca;
        IF @k = 0
        BEGIN
            SET @resultado = N'SIN ASIGNACION OK DEL DIA';
            SELECT @resultado AS ARRIBO;
        END
        ELSE IF @k > 1
            SET @resultado = LEFT(@todas, 400);
        RETURN;
    END;
    DECLARE @id INT, @srv SYSNAME = ISNULL(cfg.fn_param(@cliente, 'CYBER_LINKED_SERVER'), 'CYBER'),
            @min DECIMAL(5,2) = ISNULL(TRY_CONVERT(DECIMAL(5,2), cfg.fn_param(@cliente, 'ARRIBO_MIN_PCT')), 95),
            @p_c INT, @r_c INT, @p_d INT, @r_d INT, @p_t INT, @r_t INT, @ok_c BIT, @ok_d BIT, @ok_t BIT,
            @hecho_s BIT, @hecho_c BIT, @hecho_t BIT, @hecho_g BIT, @hecho_b BIT, @fin BIT, @listo_s BIT = 0, @res NVARCHAR(400) = N'',
            @err NVARCHAR(4000), @acc NVARCHAR(4000);

    SELECT @id = ID_CORRIDA FROM ops.CORRIDA
    WHERE ID_CORRIDA = @id_corrida AND CLIENTE = @cliente AND PROCESO = 'ASIG' AND ESTATUS = 'OK';
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
    SET @hecho_b = CASE WHEN EXISTS (SELECT 1 FROM ops.BITACORA WHERE ID_CORRIDA = @id AND PASO = 'ARRIBO SCBTEL' AND ESTATUS = 'OK') THEN 1 ELSE 0 END;
    IF @hecho_s = 1 AND @hecho_c = 1 AND @hecho_t = 1 AND @hecho_g = 1 AND @hecho_b = 1
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

    /* 1. Saldos arriba: se marca el paso y salen los gescar de nuevas y reasignadas */
    IF @listo_s = 1 AND @hecho_s = 0
    BEGIN
        SET @acc = CONCAT(N'Saldos del día en CYBER', CASE WHEN @usa_hostup = 1 THEN CONCAT(N': ', @n_hoy, N' de ', @n_sdos, N' cuentas con DMHOSTUP del día') ELSE N' (por cuentas y domicilios pendientes)' END);
        EXEC ops.sp_log @id, 'ARRIBO SALDOS', 'OK', @n_hoy, @acc;
        SET @hecho_s = 1;
        /* Gescar sin teléfono (19/11): sale de nuestros teléfonos y va junto con los de nuevas y reasignadas */
        SET @acc = ISNULL(cfg.fn_param(@cliente, 'ARCHIVOS_DESPUES_SALDOS'), N'GESCAR_NVA,GESCAR_REA,GESCAR_SINTEL');
        IF NOT EXISTS (SELECT 1 FROM STRING_SPLIT(@acc, N',') WHERE UPPER(LTRIM(RTRIM(value))) = N'GESCAR_SINTEL')
            SET @acc += N',GESCAR_SINTEL';
        IF @hecho_g = 0
        BEGIN
            BEGIN TRY
                EXEC ops.sp_generar_salida @id, 'GESCAR_SINTEL';
            END TRY
            BEGIN CATCH
                SET @err = ERROR_MESSAGE();
                EXEC ops.sp_log @id, 'GESCAR SIN TELEFONO', 'ERROR', NULL, @err;
                SET @hecho_g = 1;
            END CATCH;
        END;
        EXEC ops.sp_exportar_auto @id, @solo = @acc;
        IF @hecho_g = 0
        BEGIN
            DECLARE @sintel INT = (SELECT COUNT(*) FROM ops.SALIDA_LINEA WHERE ID_CORRIDA = @id AND ARCHIVO = 'GESCAR_SINTEL');
            SET @err = CONCAT(N'Cuentas nuevas o reasignadas sin teléfono en nuestro archivo: ', @sintel,
                              CASE WHEN @sintel > 0 THEN N' · SCBACTH_SINTEL.TXT va con los gescar de nuevas y reasignadas' ELSE N'' END);
            EXEC ops.sp_log @id, 'GESCAR SIN TELEFONO', 'OK', @sintel, @err;
            SET @hecho_g = 1;
        END;
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
    /* 4. SCBTEL arriba: los teléfonos nuevos ya están en PHONE_G1 (sin nuevos no hay nada que esperar). Solo cuenta si la
          depuración de teléfonos quedó OK en una vuelta anterior, cuando lo pendiente ya son los nuevos. */
    IF @hecho_t = 1 AND @tel_ok = 1 AND @hecho_b = 0 AND (@fin = 1 OR @ok_t = 1)
    BEGIN
        SET @acc = CONCAT(N'SCBTEL arriba: ', @r_t, N' de ', @p_t, N' teléfonos nuevos en PHONE_G1');
        EXEC ops.sp_log @id, 'ARRIBO SCBTEL', 'OK', @r_t, @acc;
        SET @hecho_b = 1;
        SET @res += N'SCBTEL OK · ';
    END;

    EXEC ops.sp_arribo_posterior @id;              -- blanqueo de status y confirmación de la asignación
    SET @resultado = CASE WHEN @res <> N'' THEN RTRIM(LEFT(@res, LEN(@res) - 1))
                          WHEN @hecho_s = 0 THEN N'ESPERANDO SALDOS'
                          WHEN @tel_ok = 0 THEN N'DEPURACION DE TELEFONOS CON ERROR'
                          WHEN @hecho_b = 0 THEN N'ESPERANDO SCBTEL'
                          ELSE N'ESPERANDO ARRIBO' END;
    SELECT @resultado AS ARRIBO, @id AS CORRIDA,
           CASE WHEN @usa_hostup = 1 THEN CONCAT(@n_hoy, N' de ', @n_sdos) END AS SALDOS_DEL_DIA_EN_CYBER,
           CONCAT(@r_c, N' de ', @p_c) AS CUENTAS_PENDIENTES_EN_CYBER, CONCAT(@r_d, N' de ', @p_d) AS DOMICILIOS_PENDIENTES_EN_CYBER,
           CONCAT(@r_t, N' de ', @p_t) AS TELEFONOS_PENDIENTES_EN_PHONE_G1;
END;
GO
