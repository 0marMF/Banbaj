USE [BNABAJ_486];
GO
/* =====================================================================
   Banbaj · 47 Ladas válidas (19/11)
   ---------------------------------------------------------------------
   cfg.PHNVAL es la copia estática, en SQL Server, de la tabla PHNVAL de
   CYBER: las ladas (VTARECOD) y la longitud del número (VTLENGTH) que admite
   el cargador al subir los teléfonos. ops.sp_telefonos deja fuera del SCBTEL
   y de la remesa los teléfonos cuya AREA + longitud no está ahí
   (parámetro TEL_VALIDAR_LADA).

   ops.sp_phnval_actualizar la vuelve a copiar de CYBER. La corre el job
   "Banbaj 486 ladas" el día 1 de cada mes (sql/instalacion/02); también se
   puede correr a mano. Si CYBER falla o la tabla llega con menos de
   LADAS_MIN_FILAS renglones, cfg.PHNVAL no se toca, queda ERROR en
   cfg.PHNVAL_CARGA, llega HALLAZGO_486 y el paso del job falla.

   Errores 50470-50479
   ===================================================================== */
SET NOCOUNT ON;
GO

CREATE OR ALTER PROCEDURE ops.sp_phnval_actualizar
    @cliente     VARCHAR(10) = '486',
    @sin_bajar   BIT = 0,          -- 1 = toma lo que ya esté en stg.CYBER_PHNVAL (pruebas)
    @solo_prueba BIT = 0           -- hallazgo sin enviar (pruebas)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @srv SYSNAME = ISNULL(cfg.fn_param(@cliente, 'CYBER_LINKED_SERVER'), 'CYBER'),
            @tabla NVARCHAR(200) = ISNULL(NULLIF(cfg.fn_param(@cliente, 'CYBER_TABLA_LADAS'), N''), N'RCVRY.PHNVAL'),
            @min INT = ISNULL(TRY_CONVERT(INT, cfg.fn_param(@cliente, 'LADAS_MIN_FILAS')), 100),
            @id INT, @filas INT, @validas INT, @altas INT = 0, @bajas INT = 0, @sql NVARCHAR(MAX), @msg NVARCHAR(4000), @json NVARCHAR(MAX);

    INSERT INTO cfg.PHNVAL_CARGA (ESTATUS) VALUES ('EN_PROCESO');
    SET @id = SCOPE_IDENTITY();
    BEGIN TRY
        IF @tabla LIKE N'%[^A-Za-z0-9_.]%'
            THROW 50470, 'CYBER_TABLA_LADAS solo puede tener letras, números, punto y _.', 1;
        IF @sin_bajar = 0
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM sys.servers WHERE name = @srv)
            BEGIN
                SET @msg = CONCAT(N'No existe el servidor vinculado ', @srv, N'.');
                THROW 50471, @msg, 1;
            END;
            TRUNCATE TABLE stg.CYBER_PHNVAL;
            SET @sql = N'INSERT INTO stg.CYBER_PHNVAL (VTCOMUNA, VTARECOD, VTLENGTH) EXEC (N''select VTCOMUNA, VTARECOD, VTLENGTH from '
                     + @tabla + N''') AT ' + QUOTENAME(@srv) + N';';
            EXEC (@sql);
        END;

        /* Lo que se puede usar: lada de dígitos y longitud numérica, sin repetidos */
        SELECT DISTINCT CAST(LTRIM(RTRIM(VTARECOD)) AS VARCHAR(10)) AS VTARECOD, TRY_CONVERT(INT, LTRIM(RTRIM(VTLENGTH))) AS VTLENGTH,
               MAX(LTRIM(RTRIM(VTCOMUNA))) OVER (PARTITION BY LTRIM(RTRIM(VTARECOD)), TRY_CONVERT(INT, LTRIM(RTRIM(VTLENGTH)))) AS VTCOMUNA
        INTO #n
        FROM stg.CYBER_PHNVAL
        WHERE NULLIF(LTRIM(RTRIM(VTARECOD)), N'') IS NOT NULL AND LTRIM(RTRIM(VTARECOD)) NOT LIKE N'%[^0-9]%' AND LEN(LTRIM(RTRIM(VTARECOD))) <= 10
          AND TRY_CONVERT(INT, LTRIM(RTRIM(VTLENGTH))) BETWEEN 1 AND 15;
        SELECT @filas = (SELECT COUNT(*) FROM stg.CYBER_PHNVAL), @validas = (SELECT COUNT(*) FROM #n);
        IF @validas < @min
        BEGIN
            SET @msg = CONCAT(@tabla, N' llegó con ', @validas, N' ladas válidas (de ', @filas, N' renglones); el mínimo es ', @min,
                              N' (LADAS_MIN_FILAS). cfg.PHNVAL se queda como estaba.');
            THROW 50472, @msg, 1;
        END;

        BEGIN TRANSACTION;
            DELETE p FROM cfg.PHNVAL p WHERE NOT EXISTS (SELECT 1 FROM #n n WHERE n.VTARECOD = p.VTARECOD AND n.VTLENGTH = p.VTLENGTH);
            SET @bajas = @@ROWCOUNT;
            UPDATE p SET VTCOMUNA = n.VTCOMUNA, FE_CARGA = SYSDATETIME()
            FROM cfg.PHNVAL p JOIN #n n ON n.VTARECOD = p.VTARECOD AND n.VTLENGTH = p.VTLENGTH;
            INSERT INTO cfg.PHNVAL (VTARECOD, VTLENGTH, VTCOMUNA)
            SELECT n.VTARECOD, n.VTLENGTH, n.VTCOMUNA FROM #n n
            WHERE NOT EXISTS (SELECT 1 FROM cfg.PHNVAL p WHERE p.VTARECOD = n.VTARECOD AND p.VTLENGTH = n.VTLENGTH);
            SET @altas = @@ROWCOUNT;
        COMMIT TRANSACTION;

        SET @msg = CONCAT(N'Ladas copiadas de ', @tabla, N': ', @validas, N' (altas ', @altas, N', bajas ', @bajas, N')',
                          CASE WHEN @filas > @validas THEN CONCAT(N' · ', @filas - @validas, N' renglones repetidos o sin lada/longitud válida') ELSE N'' END);
        UPDATE cfg.PHNVAL_CARGA SET FE_FIN = SYSDATETIME(), ESTATUS = 'OK', FILAS = @filas, ALTAS = @altas, BAJAS = @bajas, MENSAJE = @msg WHERE ID = @id;
        SELECT 'OK' AS ESTATUS, @validas AS LADAS, @altas AS ALTAS, @bajas AS BAJAS, @msg AS MENSAJE;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SET @msg = ERROR_MESSAGE();
        UPDATE cfg.PHNVAL_CARGA SET FE_FIN = SYSDATETIME(), ESTATUS = 'ERROR', FILAS = @filas, MENSAJE = @msg WHERE ID = @id;
        /* Aviso al equipo (sin corrida: es un proceso mensual aparte) */
        SET @json = (SELECT N'Ladas válidas (PHNVAL) sin actualizar' AS TIPO, @msg AS DETALLE,
                            N'Los teléfonos se siguen validando con la copia anterior. Revisar el error y correr EXEC ops.sp_phnval_actualizar; (historial: SELECT * FROM cfg.PHNVAL_CARGA ORDER BY ID DESC;)' AS ACCION,
                            N'LADAS' AS PROCESO, N'' AS HTML_TABLA
                     FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        BEGIN TRY
            EXEC mail.sp_enviar @plantilla = 'HALLAZGO_486', @id_corrida = NULL, @valores = @json, @solo_prueba = @solo_prueba;
        END TRY
        BEGIN CATCH
        END CATCH;
        THROW;
    END CATCH;
END;
GO
