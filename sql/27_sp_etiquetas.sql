/* =====================================================================
   Banbaj · 27 Etiquetas externas (cfg.ETIQUETA)
   ---------------------------------------------------------------------
   TOP: base que alimenta Asignaciones con lo que comparte Operación
        (folio + etiqueta). La salida la busca por CUENTA2 = '486-' + folio
        (antes: top.dbf, asi486.prg -> U1EXT2, REQ 2020-123954).

   cfg.sp_etiqueta_cargar  carga un CSV FOLIO,ETIQUETA (reemplaza o agrega)
   cfg.sp_etiqueta_alta    alta o cambio de una etiqueta suelta
   cfg.sp_etiqueta_baja    baja de una etiqueta suelta

   @tipo_llave:
     FOLIO          -> el archivo trae el folio (con o sin '486-'); se guarda como CUENTA2
     CUENTA2        -> el archivo ya trae '486-folio'
     CUENTA         -> crédito del banco (DAT.CUENTA), para tipos que cruzan por DMSSNUM
     FOLIO_O_CUENTA -> moraeti.prg: el valor se busca primero como folio del DAT y,
                       si no, como crédito (DAT.CUENTA); se guarda como CUENTA2.
                       Lo que no está en el DAT se descarta (como hoy).

   Etiqueta '-' = vacía a propósito (moraeti.prg): se guarda '' y en la salida
   deja el campo en blanco aunque el banco traiga valor.

   Mora (eti486): EXEC cfg.sp_etiqueta_cargar '486', 'ETI486', N'…\mora.csv', 'AGREGAR', 'FOLIO_O_CUENTA';
                  EXEC ops.sp_regenerar_scbsdos @motivo = N'Actualización de mora';
   ===================================================================== */
SET NOCOUNT ON;
GO

CREATE OR ALTER FUNCTION cfg.fn_llave_etiqueta (@cliente VARCHAR(10), @valor NVARCHAR(100), @tipo_llave VARCHAR(10))
RETURNS VARCHAR(30)
AS
BEGIN
    DECLARE @v NVARCHAR(100) = cfg.fn_texto(@valor);
    DECLARE @prefijo VARCHAR(10) = ISNULL(cfg.fn_param(@cliente, 'PREFIJO_CUENTA2'), @cliente + '-');
    IF @v IS NULL RETURN NULL;
    IF @tipo_llave = 'FOLIO'
    BEGIN
        IF @v LIKE @prefijo + '%' SET @v = SUBSTRING(@v, LEN(@prefijo) + 1, 100);
        SET @v = TRY_CONVERT(VARCHAR(20), TRY_CONVERT(BIGINT, @v));     -- quita ceros y espacios
        RETURN CASE WHEN @v IS NULL THEN NULL ELSE @prefijo + @v END;
    END;
    RETURN LEFT(@v, 30);
END;
GO

CREATE OR ALTER PROCEDURE cfg.sp_etiqueta_cargar
    @cliente    VARCHAR(10),
    @tipo       VARCHAR(20),
    @archivo    NVARCHAR(500),              -- CSV con encabezado: FOLIO,ETIQUETA
    @modo       VARCHAR(10) = 'REEMPLAZAR', -- REEMPLAZAR: la lista nueva sustituye a la anterior | AGREGAR
    @tipo_llave VARCHAR(20) = 'FOLIO',
    @codepage   VARCHAR(10) = 'ACP'         -- '' en SQL Server Linux
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @modo NOT IN ('REEMPLAZAR', 'AGREGAR') THROW 50400, '@modo debe ser REEMPLAZAR o AGREGAR.', 1;
    IF @tipo_llave NOT IN ('FOLIO', 'CUENTA2', 'CUENTA', 'FOLIO_O_CUENTA') THROW 50403, '@tipo_llave debe ser FOLIO, CUENTA2, CUENTA o FOLIO_O_CUENTA.', 1;
    DECLARE @prefijo VARCHAR(10) = ISNULL(cfg.fn_param(@cliente, 'PREFIJO_CUENTA2'), @cliente + '-');

    CREATE TABLE #e (LLAVE_ORIGEN NVARCHAR(100), ETIQUETA NVARCHAR(100));
    DECLARE @sql NVARCHAR(MAX) = N'BULK INSERT #e FROM ' + QUOTENAME(@archivo, '''')
        + N' WITH (FORMAT = ''CSV'', FIELDQUOTE = ''"'', FIRSTROW = 2, FIELDTERMINATOR = '','', ROWTERMINATOR = ''0x0a'''
        + CASE WHEN NULLIF(@codepage, '') IS NOT NULL THEN N', CODEPAGE = ' + QUOTENAME(@codepage, '''') ELSE N'' END + N');';
    EXEC (@sql);

    ;WITH x AS (
        SELECT CASE WHEN @tipo_llave = 'FOLIO_O_CUENTA'
                    THEN COALESCE(
                           (SELECT TOP (1) d.CUENTA2 FROM dat.DAT_486 d
                            WHERE d.CLIENTE = @cliente
                              AND TRY_CONVERT(BIGINT, LTRIM(d.FOLIO)) = TRY_CONVERT(BIGINT, CASE WHEN LTRIM(RTRIM(e.LLAVE_ORIGEN)) LIKE @prefijo + '%'
                                                                                              THEN SUBSTRING(LTRIM(RTRIM(e.LLAVE_ORIGEN)), LEN(@prefijo) + 1, 50)
                                                                                              ELSE LTRIM(RTRIM(e.LLAVE_ORIGEN)) END)),
                           (SELECT TOP (1) d.CUENTA2 FROM dat.DAT_486 d
                            WHERE d.CLIENTE = @cliente AND TRY_CONVERT(DECIMAL(38,0), d.CUENTA) = TRY_CONVERT(DECIMAL(38,0), LTRIM(RTRIM(e.LLAVE_ORIGEN)))))
                    ELSE cfg.fn_llave_etiqueta(@cliente, e.LLAVE_ORIGEN, @tipo_llave) END AS LLAVE,
               CASE WHEN LTRIM(RTRIM(REPLACE(e.ETIQUETA, CHAR(13), ''))) = N'-' THEN N'' ELSE cfg.fn_texto(e.ETIQUETA) END AS VALOR,
               e.LLAVE_ORIGEN
        FROM #e e
    )
    SELECT LLAVE, VALOR, LLAVE_ORIGEN,
           ROW_NUMBER() OVER (PARTITION BY LLAVE ORDER BY (SELECT NULL)) AS RN
    INTO #l
    FROM x;

    DECLARE @leidos INT = (SELECT COUNT(*) FROM #e),
            @invalidos INT = (SELECT COUNT(*) FROM #l WHERE LLAVE IS NULL OR VALOR IS NULL),
            @repetidos INT = (SELECT COUNT(*) FROM #l WHERE RN > 1 AND LLAVE IS NOT NULL),
            @cargados INT, @fuera_dat INT;

    BEGIN TRANSACTION;
    IF @modo = 'REEMPLAZAR'
        DELETE FROM cfg.ETIQUETA WHERE CLIENTE = @cliente AND TIPO = @tipo;

    MERGE cfg.ETIQUETA AS t
    USING (SELECT LLAVE, VALOR FROM #l WHERE RN = 1 AND LLAVE IS NOT NULL AND VALOR IS NOT NULL) AS s
       ON t.CLIENTE = @cliente AND t.TIPO = @tipo AND t.LLAVE = s.LLAVE
    WHEN MATCHED THEN UPDATE SET VALOR = s.VALOR, ACTIVO = 1, FE_ACT = SYSDATETIME()
    WHEN NOT MATCHED THEN INSERT (CLIENTE, TIPO, LLAVE, VALOR) VALUES (@cliente, @tipo, s.LLAVE, s.VALOR);
    SET @cargados = @@ROWCOUNT;
    COMMIT TRANSACTION;

    /* Aviso: etiquetas de cuentas que no están en el DAT (no se pierden: aplican si la cuenta regresa) */
    SELECT @fuera_dat = COUNT(*) FROM cfg.ETIQUETA e
    WHERE e.CLIENTE = @cliente AND e.TIPO = @tipo AND e.ACTIVO = 1
      AND NOT EXISTS (SELECT 1 FROM dat.DAT_486 d
                      WHERE (@tipo_llave IN ('FOLIO', 'CUENTA2', 'FOLIO_O_CUENTA') AND d.CUENTA2 = e.LLAVE)
                         OR (@tipo_llave = 'CUENTA' AND d.CUENTA = e.LLAVE));

    SELECT @tipo AS TIPO, @modo AS MODO, @leidos AS LEIDOS, @cargados AS CARGADOS,
           @invalidos AS SIN_FOLIO_O_ETIQUETA, @repetidos AS REPETIDOS, @fuera_dat AS NO_ESTAN_EN_DAT;
END;
GO

CREATE OR ALTER PROCEDURE cfg.sp_etiqueta_alta
    @cliente    VARCHAR(10),
    @tipo       VARCHAR(20),
    @llave      NVARCHAR(100),
    @valor      NVARCHAR(100),
    @tipo_llave VARCHAR(10) = 'FOLIO'
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @k VARCHAR(30) = cfg.fn_llave_etiqueta(@cliente, @llave, @tipo_llave);
    IF @k IS NULL OR cfg.fn_texto(@valor) IS NULL THROW 50401, 'Folio o etiqueta vacíos o inválidos.', 1;
    MERGE cfg.ETIQUETA AS t
    USING (SELECT @k AS LLAVE, cfg.fn_texto(@valor) AS VALOR) AS s
       ON t.CLIENTE = @cliente AND t.TIPO = @tipo AND t.LLAVE = s.LLAVE
    WHEN MATCHED THEN UPDATE SET VALOR = s.VALOR, ACTIVO = 1, FE_ACT = SYSDATETIME()
    WHEN NOT MATCHED THEN INSERT (CLIENTE, TIPO, LLAVE, VALOR) VALUES (@cliente, @tipo, s.LLAVE, s.VALOR);
END;
GO

CREATE OR ALTER PROCEDURE cfg.sp_etiqueta_baja
    @cliente    VARCHAR(10),
    @tipo       VARCHAR(20),
    @llave      NVARCHAR(100),
    @tipo_llave VARCHAR(10) = 'FOLIO'
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @k VARCHAR(30) = cfg.fn_llave_etiqueta(@cliente, @llave, @tipo_llave);
    UPDATE cfg.ETIQUETA SET ACTIVO = 0, FE_ACT = SYSDATETIME()
    WHERE CLIENTE = @cliente AND TIPO = @tipo AND LLAVE = @k;
    IF @@ROWCOUNT = 0 THROW 50402, 'No existe esa etiqueta.', 1;
END;
GO
