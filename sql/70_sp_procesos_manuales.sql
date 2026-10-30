/* =====================================================================
   Banbaj · 70 Procesos manuales del 486
   ---------------------------------------------------------------------
   ops.sp_etiquetar_campo    etiquetado de un campo del DAT con un CSV
                             FOLIO,ETIQUETA que manda Operación (sustituye a
                             eti486.prg) y genera SCBSDOS_ETI
   ops.sp_regenerar_scbsdos  SCBSDOS fuera de proceso (después de cargar
                             etiquetas de mora o TOP: moraeti.prg corría asi486)
   ops.sp_blanqueo_status    status.prg: blanqueo de status en CYBER del día 1
                             al 10, a partir de lo que baja STATUS.SQL
   cfg.sp_exclusion_cargar   blacklist_486.prg: alta masiva de exclusiones con
   cfg.sp_exclusion_alta/baja requerimiento y quién lo solicita
   ops.sp_gescar_sin_telefono ges486.prg: gescar de nuevas sin teléfono en CYBER
   ops.sp_avisar             correos de confirmación a Operación, después de
                             arribar a CYBER (MAIL, correo_486, correo, correo_486noti)
   ===================================================================== */
SET NOCOUNT ON;
GO

CREATE OR ALTER PROCEDURE ops.sp_regenerar_scbsdos
    @cliente    VARCHAR(10)   = '486',
    @motivo     NVARCHAR(400) = N'SCBSDOS fuera de proceso',
    @id_corrida INT           = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    EXEC ops.sp_corrida_iniciar @cliente, 'ETI', NULL, NULL, @id_corrida OUTPUT;
    BEGIN TRY
        EXEC ops.sp_respaldo @id_corrida;          -- para que el retroceso de corridas anteriores no se bloquee
        EXEC ops.sp_generar_salidas @id_corrida, 'ETI';
        EXEC ops.sp_corrida_finalizar @id_corrida, 'OK', @motivo;
    END TRY
    BEGIN CATCH
        DECLARE @msg NVARCHAR(4000) = ERROR_MESSAGE();
        EXEC ops.sp_corrida_finalizar @id_corrida, 'ERROR', @msg;
        THROW;
    END CATCH;
END;
GO
/* ---------------------------------------------------------------------
   Etiquetado de un campo del DAT (sustituye a eti486.prg).
   Operación manda, de vez en cuando, un CSV con encabezado y dos columnas:
       FOLIO,ETIQUETA
   @campo dice qué columna del DAT se actualiza. Acepta el nombre del DAT
   (SALDO1, TRAMO, ETIQUETA1…) o el nombre del DAT de Operación
   (ETIQUETAS486.xlsx: SEG_CICLO, MORA, LEYENDA…) según ETIQUETADO_ALIAS.
   Solo se permiten las columnas de ETIQUETADO_CAMPOS.
     FOLIO     '102', '0102' o '486-102'   (@tipo_llave = 'FOLIO', por omisión)
     CUENTA    crédito del banco            (@tipo_llave = 'CUENTA')
     ETIQUETA  '-' = dejar el campo en blanco; vacío = se rechaza
   @confirmar = 0: vista previa (no cambia nada). Con 1: respaldo, actualiza
   el DAT, rechazos a ops.RECHAZO y SCBSDOS_ETI para arribar.
   ETIQUETA6 / TOP no es columna del DAT: va con cfg.sp_etiqueta_cargar 'TOP'.
   --------------------------------------------------------------------- */
DROP PROCEDURE IF EXISTS ops.sp_etiquetado_dat;
GO

CREATE OR ALTER PROCEDURE ops.sp_etiquetar_campo
    @campo      SYSNAME,
    @archivo    NVARCHAR(500),
    @cliente    VARCHAR(10)   = '486',
    @tipo_llave VARCHAR(10)   = 'FOLIO',
    @confirmar  BIT           = 0,
    @codepage   VARCHAR(10)   = 'ACP',      -- '' en SQL Server Linux
    @id_corrida INT           = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @sql NVARCHAR(MAX), @msg NVARCHAR(4000), @n INT, @tipo SYSNAME, @largo INT;
    DECLARE @prefijo VARCHAR(10) = ISNULL(cfg.fn_param(@cliente, 'PREFIJO_CUENTA2'), @cliente + '-');
    DECLARE @pedido SYSNAME = UPPER(LTRIM(RTRIM(@campo)));

    IF @tipo_llave NOT IN ('FOLIO', 'CUENTA') THROW 50604, '@tipo_llave debe ser FOLIO o CUENTA.', 1;

    /* Nombre de Operación -> columna del DAT */
    SELECT @campo = UPPER(LTRIM(RTRIM(SUBSTRING(value, CHARINDEX('=', value) + 1, 200))))
    FROM STRING_SPLIT(ISNULL(cfg.fn_param(@cliente, 'ETIQUETADO_ALIAS'), ''), ',')
    WHERE CHARINDEX('=', value) > 0 AND UPPER(LTRIM(RTRIM(LEFT(value, CHARINDEX('=', value) - 1)))) = @pedido;
    IF @@ROWCOUNT = 0 SET @campo = @pedido;

    IF @campo IN ('TOP', 'ETIQUETA6')
        THROW 50605, 'TOP (ETIQUETA6) no es columna del DAT: cárgalo con cfg.sp_etiqueta_cargar @tipo = ''TOP''.', 1;
    IF COL_LENGTH('dat.DAT_486', @campo) IS NULL
       OR @campo NOT IN (SELECT UPPER(LTRIM(RTRIM(value))) FROM STRING_SPLIT(ISNULL(cfg.fn_param(@cliente, 'ETIQUETADO_CAMPOS'), ''), ','))
    BEGIN
        SET @msg = CONCAT(N'El campo ', @pedido, N' no se puede etiquetar. Permitidos: ', cfg.fn_param(@cliente, 'ETIQUETADO_CAMPOS'),
                          N' (o sus nombres de Operación en ETIQUETADO_ALIAS).');
        THROW 50602, @msg, 1;
    END;
    SELECT @tipo = TYPE_NAME(c.system_type_id), @largo = CASE WHEN TYPE_NAME(c.system_type_id) LIKE 'n%char' THEN c.max_length / 2 ELSE c.max_length END
    FROM sys.columns c WHERE c.object_id = OBJECT_ID('dat.DAT_486') AND c.name = @campo;

    /* Archivo FOLIO,ETIQUETA */
    CREATE TABLE #e (LLAVE NVARCHAR(100), ETIQUETA NVARCHAR(400));
    SET @sql = N'BULK INSERT #e FROM ' + QUOTENAME(@archivo, '''')
             + N' WITH (FORMAT = ''CSV'', FIELDQUOTE = ''"'', FIRSTROW = 2, FIELDTERMINATOR = '','', ROWTERMINATOR = ''0x0a'''
             + CASE WHEN NULLIF(@codepage, '') IS NOT NULL THEN N', CODEPAGE = ' + QUOTENAME(@codepage, '''') ELSE N'' END + N');';
    EXEC (@sql);
    IF NOT EXISTS (SELECT 1 FROM #e) THROW 50600, 'El archivo está vacío.', 1;

    CREATE TABLE #v (LLAVE NVARCHAR(100), CUENTA VARCHAR(20) NULL, VALOR NVARCHAR(400) NULL, RESULTADO VARCHAR(30) NULL);
    INSERT INTO #v (LLAVE, VALOR)
    SELECT NULLIF(LTRIM(RTRIM(REPLACE(REPLACE(LLAVE, NCHAR(13), N''), NCHAR(65279), N''))), N''),
           NULLIF(LTRIM(RTRIM(REPLACE(ETIQUETA, NCHAR(13), N''))), N'')
    FROM #e;

    IF @tipo_llave = 'FOLIO'
        UPDATE v SET CUENTA = d.CUENTA
        FROM #v v JOIN dat.DAT_486 d ON d.CLIENTE = @cliente AND d.CUENTA2 = cfg.fn_llave_etiqueta(@cliente, v.LLAVE, 'FOLIO');
    ELSE
        UPDATE v SET CUENTA = d.CUENTA
        FROM #v v JOIN dat.DAT_486 d ON d.CLIENTE = @cliente AND d.CUENTA = LEFT(v.LLAVE, 20);

    UPDATE #v SET RESULTADO = 'SIN FOLIO' WHERE LLAVE IS NULL;
    UPDATE #v SET RESULTADO = 'SIN ETIQUETA' WHERE RESULTADO IS NULL AND VALOR IS NULL;
    UPDATE #v SET RESULTADO = 'NO ESTA EN EL DAT' WHERE RESULTADO IS NULL AND CUENTA IS NULL;
    ;WITH r AS (SELECT RESULTADO, COUNT(*) OVER (PARTITION BY CUENTA) AS N FROM #v WHERE RESULTADO IS NULL)
    UPDATE r SET RESULTADO = 'FOLIO REPETIDO' WHERE N > 1;
    UPDATE #v SET VALOR = N'' WHERE RESULTADO IS NULL AND VALOR = N'-';
    IF @tipo IN ('decimal', 'numeric', 'int', 'money')
        UPDATE #v SET RESULTADO = 'IMPORTE INVALIDO' WHERE RESULTADO IS NULL AND cfg.fn_importe(VALOR) IS NULL;
    ELSE IF @tipo = 'date'
        UPDATE #v SET RESULTADO = 'FECHA INVALIDA' WHERE RESULTADO IS NULL AND COALESCE(TRY_CONVERT(DATE, VALOR, 103), TRY_CONVERT(DATE, VALOR, 23)) IS NULL;
    UPDATE #v SET RESULTADO = 'A ACTUALIZAR' WHERE RESULTADO IS NULL;

    IF @confirmar = 0
    BEGIN
        SELECT @campo AS CAMPO, RESULTADO, COUNT(*) AS REGISTROS FROM #v GROUP BY RESULTADO ORDER BY RESULTADO;
        PRINT 'Vista previa: no se cambió nada. Ejecuta con @confirmar = 1 para actualizar el DAT y generar SCBSDOS.';
        RETURN;
    END;
    IF NOT EXISTS (SELECT 1 FROM #v WHERE RESULTADO = 'A ACTUALIZAR')
        THROW 50603, 'No hay nada que actualizar.', 1;

    EXEC ops.sp_corrida_iniciar @cliente, 'ETI', NULL, NULL, @id_corrida OUTPUT;
    BEGIN TRY
        EXEC ops.sp_respaldo @id_corrida;
        BEGIN TRANSACTION;
        SET @sql = N'UPDATE d SET ' + QUOTENAME(@campo) + N' = '
                 + CASE WHEN @tipo IN ('decimal', 'numeric', 'int', 'money') THEN N'cfg.fn_importe(v.VALOR)'
                        WHEN @tipo = 'date' THEN N'COALESCE(TRY_CONVERT(DATE, v.VALOR, 103), TRY_CONVERT(DATE, v.VALOR, 23))'
                        ELSE N'LEFT(v.VALOR, ' + CAST(@largo AS NVARCHAR(10)) + N')' END
                 + N', ID_CORRIDA_ULT = @id_corrida, FE_ULT_ACT = SYSDATETIME() '
                 + N'FROM dat.DAT_486 d JOIN #v v ON v.CUENTA = d.CUENTA AND v.RESULTADO = ''A ACTUALIZAR'' WHERE d.CLIENTE = @cliente;';
        EXEC sp_executesql @sql, N'@id_corrida INT, @cliente VARCHAR(10)', @id_corrida = @id_corrida, @cliente = @cliente;
        SET @n = @@ROWCOUNT;

        INSERT INTO ops.RECHAZO (ID_CORRIDA, ORIGEN, MOTIVO, DATOS)
        SELECT @id_corrida, 'ETIQUETADO_DAT', CONCAT(N'Etiquetado ', @campo, N': ', RESULTADO),
               (SELECT v.LLAVE AS FOLIO, v.VALOR AS ETIQUETA FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
        FROM #v v WHERE RESULTADO <> 'A ACTUALIZAR';
        COMMIT TRANSACTION;

        SET @msg = CONCAT(@campo, N' (', @pedido, N'): ', @n, N' cuentas · archivo: ', @archivo);
        EXEC ops.sp_log @id_corrida, 'ETIQUETADO DAT', 'OK', @n, @msg;
        EXEC ops.sp_generar_salidas @id_corrida, 'ETI';
        SET @msg = CONCAT(N'Etiquetado de ', @campo, N': ', @n, N' cuentas · rechazados: ', (SELECT COUNT(*) FROM #v WHERE RESULTADO <> 'A ACTUALIZAR'));
        EXEC ops.sp_corrida_finalizar @id_corrida, 'OK', @msg;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SET @msg = ERROR_MESSAGE();
        EXEC ops.sp_corrida_finalizar @id_corrida, 'ERROR', @msg;
        THROW;
    END CATCH;

    SELECT @campo AS CAMPO, RESULTADO, COUNT(*) AS REGISTROS FROM #v GROUP BY RESULTADO ORDER BY RESULTADO;
END;
GO

/* ---------------------------------------------------------------------
   Blanqueo de status (status.prg, REQ 2020-029307). Del día 1 al 10
   (DIAS_BLANQUEO_STATUS), después de arribar la asignación:
   1. EXEC ops.sp_bajar_cyber 'status', @id_corrida = <asignación> (consulta de STATUS.SQL
      a stg.CYBER_STATUS y ejecuta este procedimiento; sin archivos en la máquina).
   2. Revisar BLANQUEO_LISTA y correr cyber/BLANQUEO_STATUS.sql.
   Se blanquean las cuentas nuevas y reasignadas de esa asignación, salvo
   los status de STATUS_NO_BLANQUEAR y las que no tienen status ni acción.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE ops.sp_blanqueo_status
    @id_corrida INT,
    @forzar     BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @cliente VARCHAR(10), @proceso VARCHAR(10), @fecha DATE;
    SELECT @cliente = CLIENTE, @proceso = PROCESO, @fecha = FECHA_PROCESO FROM ops.CORRIDA WHERE ID_CORRIDA = @id_corrida;
    IF @proceso IS NULL OR @proceso <> 'ASIG' THROW 50610, 'Indica una corrida de asignación.', 1;

    DECLARE @dias VARCHAR(20) = ISNULL(cfg.fn_param(@cliente, 'DIAS_BLANQUEO_STATUS'), '1-10');
    DECLARE @d1 INT = TRY_CONVERT(INT, LEFT(@dias, CHARINDEX('-', @dias + '-') - 1)),
            @d2 INT = TRY_CONVERT(INT, SUBSTRING(@dias, CHARINDEX('-', @dias + '-') + 1, 10));
    IF DAY(@fecha) NOT BETWEEN ISNULL(@d1, 1) AND ISNULL(@d2, 31) AND @forzar = 0
    BEGIN
        EXEC ops.sp_log @id_corrida, 'BLANQUEO STATUS', 'AVISO', 0, N'Hoy no se debe blanquear status (DIAS_BLANQUEO_STATUS). Usa @forzar = 1 si es necesario.';
        PRINT 'Hoy no se debe blanquear status del 486.';
        RETURN;
    END;

    IF NOT EXISTS (SELECT 1 FROM stg.CYBER_STATUS) THROW 50611, 'stg.CYBER_STATUS está vacía: baja primero los status de CYBER (ops.sp_bajar_cyber ''STATUS'').', 1;

    DECLARE @no TABLE (STATUS VARCHAR(10) PRIMARY KEY);
    INSERT INTO @no SELECT DISTINCT UPPER(LTRIM(RTRIM(value))) FROM STRING_SPLIT(ISNULL(cfg.fn_param(@cliente, 'STATUS_NO_BLANQUEAR'), ''), ',') WHERE LTRIM(RTRIM(value)) <> '';

    DELETE FROM ops.STATUS_CYBER WHERE ID_CORRIDA = @id_corrida;
    INSERT INTO ops.STATUS_CYBER (ID_CORRIDA, NUM, CLIENTE, FOLIO, CUENTA, STATUS, ACCION, FECHA, PESO, DMSSNUM)
    SELECT @id_corrida, ROW_NUMBER() OVER (ORDER BY (SELECT NULL)),
           LEFT(NULLIF(LTRIM(RTRIM(CLIENTE)), ''), 10), LEFT(NULLIF(LTRIM(RTRIM(FOLIO)), ''), 20), LEFT(NULLIF(LTRIM(RTRIM(CUENTA)), ''), 28),
           LEFT(NULLIF(LTRIM(RTRIM(STATUS)), ''), 10), LEFT(NULLIF(LTRIM(RTRIM(ACCION)), ''), 10), LEFT(NULLIF(LTRIM(RTRIM(FECHA)), ''), 30),
           LEFT(NULLIF(LTRIM(RTRIM(PESO)), ''), 10), LEFT(NULLIF(LTRIM(RTRIM(REPLACE(DMSSNUM, NCHAR(13), N''))), ''), 28)
    FROM stg.CYBER_STATUS;
    TRUNCATE TABLE stg.CYBER_STATUS;

    UPDATE s SET MOTIVO = CASE
            WHEN ISNULL(s.CLIENTE, '') <> @cliente THEN 'OTRO CLIENTE'
            WHEN NOT EXISTS (SELECT 1 FROM dat.HISTORIA_FOLIO h WHERE h.CLIENTE = @cliente AND h.ID_CORRIDA_ALTA = @id_corrida AND h.CUENTA = s.DMSSNUM)
                 THEN 'NO ES NUEVA NI REASIGNADA EN LA CORRIDA'
            WHEN UPPER(s.STATUS) IN (SELECT STATUS FROM @no) THEN 'STATUS QUE NO SE BLANQUEA'
            WHEN s.STATUS IS NULL AND s.ACCION IS NULL THEN 'SIN STATUS NI ACCION'
         END
    FROM ops.STATUS_CYBER s WHERE s.ID_CORRIDA = @id_corrida;
    UPDATE ops.STATUS_CYBER SET BLANQUEA = 1 WHERE ID_CORRIDA = @id_corrida AND MOTIVO IS NULL AND CUENTA IS NOT NULL;

    DECLARE @n INT = (SELECT COUNT(*) FROM ops.STATUS_CYBER WHERE ID_CORRIDA = @id_corrida AND BLANQUEA = 1);
    DELETE FROM ops.CYBER_SCRIPT WHERE ID_CORRIDA = @id_corrida AND SCRIPT = 'BLANQUEO_STATUS';
    INSERT INTO ops.CYBER_SCRIPT (ID_CORRIDA, SCRIPT, NUM, SENTENCIA)
    SELECT @id_corrida, 'BLANQUEO_STATUS', ROW_NUMBER() OVER (ORDER BY CUENTA),
           CONCAT(N'update RCVRY.delqmst set DMACAC2=NULL, DMACRC2=NULL, DMACDT2=NULL, DMACSC2=NULL WHERE DMACCTG=''1'' AND DMACCT=''',
                  REPLACE(CUENTA, '''', ''''''), N''';')
    FROM ops.STATUS_CYBER WHERE ID_CORRIDA = @id_corrida AND BLANQUEA = 1;
    INSERT INTO ops.CYBER_SCRIPT (ID_CORRIDA, SCRIPT, NUM, SENTENCIA)
    VALUES (@id_corrida, 'BLANQUEO_STATUS', @n + 1, N'commit;'), (@id_corrida, 'BLANQUEO_STATUS', @n + 2, N'exit');

    EXEC ops.sp_generar_salidas @id_corrida, 'BLANQUEO';

    DECLARE @msg NVARCHAR(4000) = (SELECT CONCAT(N'Bajados de CYBER: ', COUNT(*), N' · a blanquear: ', SUM(CAST(BLANQUEA AS INT)),
                                                 N' · status que no se blanquean: ', SUM(CASE WHEN MOTIVO = 'STATUS QUE NO SE BLANQUEA' THEN 1 ELSE 0 END))
                                   FROM ops.STATUS_CYBER WHERE ID_CORRIDA = @id_corrida);
    EXEC ops.sp_log @id_corrida, 'BLANQUEO STATUS', 'OK', @n, @msg;
    SELECT MOTIVO = ISNULL(MOTIVO, 'SE BLANQUEA'), REGISTROS = COUNT(*) FROM ops.STATUS_CYBER WHERE ID_CORRIDA = @id_corrida GROUP BY MOTIVO;
END;
GO

/* ---------------------------------------------------------------------
   Exclusiones (blacklist_486.prg y las demás listas): archivo CSV con
   encabezado y el valor en la primera columna (para TELEFONO, el teléfono).
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE cfg.sp_exclusion_cargar
    @cliente   VARCHAR(10)   = '486',
    @tipo      VARCHAR(20)   = 'TELEFONO',
    @archivo   NVARCHAR(500),
    @req       VARCHAR(40),
    @solicita  NVARCHAR(100),
    @codepage  VARCHAR(10)   = 'ACP'
AS
BEGIN
    SET NOCOUNT ON;
    IF @tipo NOT IN ('CUENTA', 'TELEFONO', 'DIRECCION', 'CORREO') THROW 50620, '@tipo debe ser CUENTA, TELEFONO, DIRECCION o CORREO.', 1;
    IF NULLIF(LTRIM(@req), '') IS NULL OR NULLIF(LTRIM(@solicita), '') IS NULL THROW 50621, 'Indica el requerimiento y quién lo solicita.', 1;
    CREATE TABLE #e (L NVARCHAR(1000));
    DECLARE @sql NVARCHAR(MAX) = N'BULK INSERT #e FROM ' + QUOTENAME(@archivo, '''')
        + N' WITH (FIRSTROW = 2, ROWTERMINATOR = ''0x0a'', FIELDTERMINATOR = ''\t\t\t'''
        + CASE WHEN NULLIF(@codepage, '') IS NOT NULL THEN N', CODEPAGE = ' + QUOTENAME(@codepage, '''') ELSE N'' END + N');';
    EXEC (@sql);

    /* Teléfonos (lista negra): solo 10 dígitos exactos; espacios y guiones se quitan, lo demás se rechaza */
    SELECT v.VALOR, CASE WHEN @tipo = 'TELEFONO' AND LEN(v.VALOR) <> 10 THEN 0 ELSE 1 END AS VALIDO
    INTO #c
    FROM #e
    CROSS APPLY (SELECT LTRIM(RTRIM(REPLACE(REPLACE(LEFT(L, CHARINDEX(N',', L + N',') - 1), NCHAR(13), N''), N'"', N''))) AS V0) a
    CROSS APPLY (SELECT CASE WHEN @tipo = 'TELEFONO' THEN cfg.fn_solo_digitos(a.V0)
                             WHEN @tipo = 'CORREO' THEN LOWER(a.V0) ELSE a.V0 END AS VALOR) v
    WHERE NULLIF(v.VALOR, N'') IS NOT NULL;
    SELECT DISTINCT VALOR INTO #x FROM #c WHERE VALIDO = 1;

    DECLARE @leidos INT = (SELECT COUNT(*) FROM #e), @nuevos INT;
    INSERT INTO cfg.EXCLUSION (CLIENTE, TIPO, VALOR, MOTIVO, REQ)
    SELECT @cliente, @tipo, x.VALOR, CONCAT(N'Solicita: ', @solicita), @req
    FROM #x x
    WHERE NOT EXISTS (SELECT 1 FROM cfg.EXCLUSION e WHERE e.CLIENTE = @cliente AND e.TIPO = @tipo AND e.VALOR = x.VALOR AND e.VALOR2 IS NULL AND e.ACTIVO = 1);
    SET @nuevos = @@ROWCOUNT;
    SELECT @tipo AS TIPO, @leidos AS LEIDOS, (SELECT COUNT(*) FROM #x) AS VALIDOS, @nuevos AS NUEVOS, (SELECT COUNT(*) FROM #x) - @nuevos AS YA_EXISTIAN,
           (SELECT COUNT(*) FROM #c WHERE VALIDO = 0) AS NO_SON_10_DIGITOS;
END;
GO

CREATE OR ALTER PROCEDURE cfg.sp_exclusion_alta
    @cliente VARCHAR(10) = '486', @tipo VARCHAR(20), @valor NVARCHAR(200), @valor2 NVARCHAR(200) = NULL,
    @req VARCHAR(40), @solicita NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM cfg.EXCLUSION WHERE CLIENTE = @cliente AND TIPO = @tipo AND VALOR = @valor AND ISNULL(VALOR2, N'') = ISNULL(@valor2, N'') AND ACTIVO = 1)
        RETURN;
    INSERT INTO cfg.EXCLUSION (CLIENTE, TIPO, VALOR, VALOR2, MOTIVO, REQ)
    VALUES (@cliente, @tipo, @valor, @valor2, CONCAT(N'Solicita: ', @solicita), @req);
END;
GO

CREATE OR ALTER PROCEDURE cfg.sp_exclusion_baja
    @cliente VARCHAR(10) = '486', @tipo VARCHAR(20), @valor NVARCHAR(200), @valor2 NVARCHAR(200) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE cfg.EXCLUSION SET ACTIVO = 0
    WHERE CLIENTE = @cliente AND TIPO = @tipo AND VALOR = @valor AND ISNULL(VALOR2, N'') = ISNULL(@valor2, N'') AND ACTIVO = 1;
    IF @@ROWCOUNT = 0 THROW 50622, 'No existe esa exclusión activa.', 1;
END;
GO

/* ---------------------------------------------------------------------
   Avisos a Operación después de arribar a CYBER (hoy se mandan a mano al final):
     CONFIRMACION_ASIG_486    MAIL.prg
     ASIG_EXPRESS_486         correo_486.prg
     CONFIRMACION_ACT_486     correo.prg
     NOTIFICACION_RETIRO_486  correo_486noti.prg
     AVISO_DEVOLUCION_486     devfianey.prg (archivo de devolución actualizado, a AEM)
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE ops.sp_avisar
    @id_corrida INT,
    @plantilla  VARCHAR(60),
    @solo_prueba BIT = 0,
    @adjuntos   NVARCHAR(MAX) = NULL    -- rutas visibles para el servicio de SQL Server, separadas por ';' (ej. el ZIP de retiros)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @json NVARCHAR(MAX) = (SELECT ID_CORRIDA AS CORRIDA, PROCESO, ISNULL(MENSAJE, N'') AS RESUMEN
                                   FROM ops.CORRIDA WHERE ID_CORRIDA = @id_corrida FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
    IF @json IS NULL THROW 50630, 'La corrida no existe.', 1;
    EXEC mail.sp_enviar @plantilla = @plantilla, @id_corrida = @id_corrida, @valores = @json, @adjuntos = @adjuntos, @solo_prueba = @solo_prueba;
END;
GO

/* ---------------------------------------------------------------------
   Gescar de cuentas sin teléfono (ges486.prg, REQ 2021-051126). Después de
   arribar los teléfonos de la asignación:
   1. EXEC ops.sp_bajar_cyber 'telefonos', @id_corrida = <asignación> (teléfonos activos del 486
      a stg.CYBER_TELEFONO y ejecuta este procedimiento).
   2. Arribar SCBACTH_SINTEL.TXT ("CUENTA SIN NUMERO TELEFONICO", origen zzasg).
   Aplica a las cuentas nuevas y reasignadas de esa asignación que no tienen
   ningún teléfono activo en CYBER.
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE ops.sp_gescar_sin_telefono
    @id_corrida INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @cliente VARCHAR(10), @proceso VARCHAR(10);
    SELECT @cliente = CLIENTE, @proceso = PROCESO FROM ops.CORRIDA WHERE ID_CORRIDA = @id_corrida;
    IF @proceso IS NULL OR @proceso <> 'ASIG' THROW 50650, 'Indica una corrida de asignación.', 1;

    IF NOT EXISTS (SELECT 1 FROM stg.CYBER_TELEFONO) THROW 50651, 'stg.CYBER_TELEFONO está vacía: baja primero los teléfonos de CYBER (ops.sp_bajar_cyber ''TELEFONOS'').', 1;

    DELETE FROM ops.TELEFONO_CYBER WHERE ID_CORRIDA = @id_corrida;
    INSERT INTO ops.TELEFONO_CYBER (ID_CORRIDA, CUENTA2, TELEFONOS)
    SELECT @id_corrida, LEFT(LTRIM(RTRIM(CUENTA)), 28), COUNT(*)
    FROM stg.CYBER_TELEFONO WHERE NULLIF(LTRIM(RTRIM(CUENTA)), N'') IS NOT NULL
    GROUP BY LEFT(LTRIM(RTRIM(CUENTA)), 28);
    TRUNCATE TABLE stg.CYBER_TELEFONO;

    EXEC ops.sp_generar_salidas @id_corrida, 'SINTEL';

    DECLARE @n INT = (SELECT COUNT(*) FROM ops.SALIDA_LINEA WHERE ID_CORRIDA = @id_corrida AND ARCHIVO = 'GESCAR_SINTEL');
    DECLARE @msg NVARCHAR(400) = CONCAT(N'Cuentas con teléfono en CYBER: ', (SELECT COUNT(*) FROM ops.TELEFONO_CYBER WHERE ID_CORRIDA = @id_corrida),
                                        N' · nuevas/reasignadas sin teléfono: ', @n);
    EXEC ops.sp_log @id_corrida, 'GESCAR SIN TELEFONO', 'OK', @n, @msg;
    SELECT @n AS SIN_TELEFONO;
END;
GO
