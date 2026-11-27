USE [BNABAJ_486];   -- base del 486 (si la instalas con otro nombre, cámbialo aquí)
GO
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
     CUENTA         -> cuenta del banco (DAT.CTA_BANCO, la que va en DMSSNUM; en TDC la armada)
     FOLIO_O_CUENTA -> el valor se busca primero como folio del DAT y, si no, como
                       riesgo o cuenta del banco; se guarda como CUENTA2. Lo que no está
                       en el DAT se descarta.

   Etiqueta '-' = vacía a propósito: se guarda '' y en la salida deja el campo en blanco.
   (eti486 / moraeti.prg ya no se usan: la mora es la ETIQUETA1 que llega en la base.)
   ===================================================================== */
SET NOCOUNT ON;
GO

CREATE OR ALTER FUNCTION cfg.fn_llave_etiqueta (@cliente VARCHAR(10), @valor NVARCHAR(100), @tipo_llave VARCHAR(20))
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
                            WHERE d.CLIENTE = @cliente
                              AND TRY_CONVERT(DECIMAL(38,0), LTRIM(RTRIM(e.LLAVE_ORIGEN))) IN (TRY_CONVERT(DECIMAL(38,0), d.CUENTA), TRY_CONVERT(DECIMAL(38,0), d.CTA_BANCO))))
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
                         OR (@tipo_llave = 'CUENTA' AND ISNULL(d.CTA_BANCO, d.CUENTA) = e.LLAVE));

    SELECT @tipo AS TIPO, @modo AS MODO, @leidos AS LEIDOS, @cargados AS CARGADOS,
           @invalidos AS SIN_FOLIO_O_ETIQUETA, @repetidos AS REPETIDOS, @fuera_dat AS NO_ESTAN_EN_DAT;
END;
GO

CREATE OR ALTER PROCEDURE cfg.sp_etiqueta_alta
    @cliente    VARCHAR(10),
    @tipo       VARCHAR(20),
    @llave      NVARCHAR(100),
    @valor      NVARCHAR(100),
    @tipo_llave VARCHAR(20) = 'FOLIO'
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
    @tipo_llave VARCHAR(20) = 'FOLIO'
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @k VARCHAR(30) = cfg.fn_llave_etiqueta(@cliente, @llave, @tipo_llave);
    UPDATE cfg.ETIQUETA SET ACTIVO = 0, FE_ACT = SYSDATETIME()
    WHERE CLIENTE = @cliente AND TIPO = @tipo AND LLAVE = @k;
    IF @@ROWCOUNT = 0 THROW 50402, 'No existe esa etiqueta.', 1;
END;
GO

/* =====================================================================
   Blanqueo de ETIQUETA6 (REE) · correo "RE: Etiquetado REE" (23/11)
   ---------------------------------------------------------------------
   El etiquetado sale de la base maestra (catálogos ETIQUETA6_TDC y
   ETIQUETA6_CONSUMO). El REE se quita en dos casos:

   1. BASE   la cuenta llega en la base maestra sin la leyenda de REE y ya
             estaba etiquetada (TDC sin ENFOQUE_PLAN DE PAGOS, Consumo sin
             ENFOQUE_REESTRUCTURA). Lo hace ops.sp_asig_existentes, que deja
             aquí el registro.
   2. TRAMO  el tramo con que la manda el banco en el archivo de saldos (SEG
             del DAT; en el DAT de Operación es ETIQUETA3) ya no es elegible:
             TDC solo VEN2 y VEN3 (VEN4 y CCAS pierden el REE); Consumo de
             1-29 a 90+ (CASTIGADA lo pierde). Catálogos ETIQUETA6_SEG_TDC y
             ETIQUETA6_SEG_CONSUMO: 'SI' conserva, 'NO' blanquea. Un tramo que
             no está en el catálogo también blanquea (solo son elegibles los
             que se listan) y queda un AVISO en la bitácora para que lo
             revisen. Sin tramo (cuenta nueva sin saldos todavía) no se toca.
             Un segmento sin catálogo (Hipotecario) no se revisa.

   ops.sp_etiqueta6_blanqueo corre en la actualización (después de subir el
   SEG) y en la asignación (después de las altas). En la actualización el
   blanqueo sube a CYBER en el script ACT_PVS_REE (u1ext2 = ''); en la
   asignación va en el SCBSDOS (U1EXT2).
   Parámetro ETIQUETA6_BLANQUEO: 1 = activo (default), 0 = apagado.

   Lo blanqueado:  SELECT * FROM ops.ETIQUETA6_BLANQUEO WHERE ID_CORRIDA = <corrida>;
   ===================================================================== */
IF OBJECT_ID('ops.ETIQUETA6_BLANQUEO') IS NULL
CREATE TABLE ops.ETIQUETA6_BLANQUEO (
    ID            INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_ETIQUETA6_BLANQUEO PRIMARY KEY,
    ID_CORRIDA    INT           NOT NULL,
    TIPO          VARCHAR(10)   NOT NULL,           -- BASE | TRAMO
    CUENTA        VARCHAR(20)   NOT NULL,
    CUENTA2       VARCHAR(28)   NULL,
    SEGMENTO2     VARCHAR(20)   NULL,
    ETIQUETA_ANT  VARCHAR(15)   NULL,
    SEG           VARCHAR(15)   NULL,
    FECHA         DATETIME2(0)  NOT NULL CONSTRAINT DF_ETIQUETA6_BLANQUEO_FE DEFAULT SYSDATETIME(),
    CONSTRAINT CK_ETIQUETA6_BLANQUEO_TIPO CHECK (TIPO IN ('BASE', 'TRAMO'))
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_ETIQUETA6_BLANQUEO_CORRIDA' AND object_id = OBJECT_ID('ops.ETIQUETA6_BLANQUEO'))
    CREATE INDEX IX_ETIQUETA6_BLANQUEO_CORRIDA ON ops.ETIQUETA6_BLANQUEO (ID_CORRIDA, TIPO);
GO

CREATE OR ALTER PROCEDURE ops.sp_etiqueta6_blanqueo
    @id_corrida INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @cliente VARCHAR(10) = (SELECT CLIENTE FROM ops.CORRIDA WHERE ID_CORRIDA = @id_corrida),
            @n INT, @msg NVARCHAR(4000), @nuevos NVARCHAR(2000);
    IF ISNULL(cfg.fn_param(@cliente, 'ETIQUETA6_BLANQUEO'), '1') <> '1'
    BEGIN
        EXEC ops.sp_log @id_corrida, 'ETIQUETA6 BLANQUEO', 'AVISO', 0, N'Blanqueo de ETIQUETA6 apagado (parámetro ETIQUETA6_BLANQUEO = 0).';
        RETURN;
    END;

    DELETE FROM ops.ETIQUETA6_BLANQUEO WHERE ID_CORRIDA = @id_corrida AND TIPO = 'TRAMO';

    /* Cuentas etiquetadas con tramo, en un segmento que tiene catálogo de tramos elegibles */
    SELECT d.CUENTA, d.CUENTA2, d.SEGMENTO2, d.ETIQUETA6, t.SEG,
           cfg.fn_catalogo(@cliente, LEFT('ETIQUETA6_SEG_' + d.SEGMENTO2, 40), t.SEG) AS ELEGIBLE
    INTO #rev
    FROM dat.DAT_486 d
    CROSS APPLY (SELECT NULLIF(LTRIM(RTRIM(d.SEG)), '') AS SEG) t
    WHERE d.CLIENTE = @cliente
      AND NULLIF(LTRIM(RTRIM(d.ETIQUETA6)), '') IS NOT NULL
      AND t.SEG IS NOT NULL
      AND EXISTS (SELECT 1 FROM cfg.CATALOGO k WHERE k.CLIENTE = @cliente AND k.ACTIVO = 1 AND k.CATALOGO = LEFT('ETIQUETA6_SEG_' + d.SEGMENTO2, 40));

    BEGIN TRANSACTION;
    INSERT INTO ops.ETIQUETA6_BLANQUEO (ID_CORRIDA, TIPO, CUENTA, CUENTA2, SEGMENTO2, ETIQUETA_ANT, SEG)
    SELECT @id_corrida, 'TRAMO', CUENTA, CUENTA2, SEGMENTO2, ETIQUETA6, SEG
    FROM #rev WHERE ISNULL(ELEGIBLE, N'') <> N'SI';
    SET @n = @@ROWCOUNT;

    UPDATE d SET d.ETIQUETA6 = '', d.ID_CORRIDA_ULT = @id_corrida, d.FE_ULT_ACT = SYSDATETIME()
    FROM dat.DAT_486 d
    JOIN ops.ETIQUETA6_BLANQUEO b ON b.CUENTA = d.CUENTA AND b.ID_CORRIDA = @id_corrida AND b.TIPO = 'TRAMO';
    COMMIT TRANSACTION;

    /* Resumen por segmento y tramo (solo conteos) */
    SET @msg = (SELECT STRING_AGG(CAST(CONCAT(SEGMENTO2, N' ', SEG, N': ', N) AS NVARCHAR(MAX)), N', ') WITHIN GROUP (ORDER BY SEGMENTO2, SEG)
                FROM (SELECT SEGMENTO2, SEG, COUNT(*) AS N FROM ops.ETIQUETA6_BLANQUEO
                      WHERE ID_CORRIDA = @id_corrida AND TIPO = 'TRAMO' GROUP BY SEGMENTO2, SEG) x);
    SET @msg = CONCAT(@n, N' cuentas pierden el REE por tramo no elegible', CASE WHEN @msg IS NOT NULL THEN N' (' + @msg + N')' END,
                      N'. Revisadas: ', (SELECT COUNT(*) FROM #rev), N' etiquetadas con tramo.');
    EXEC ops.sp_log @id_corrida, 'ETIQUETA6 BLANQUEO', 'OK', @n, @msg;

    /* Tramos que no están en el catálogo: se blanquearon, pero puede ser un valor nuevo del banco */
    SET @nuevos = (SELECT STRING_AGG(CAST(CONCAT(SEGMENTO2, N' ', SEG, N' (', N, N')') AS NVARCHAR(MAX)), N', ')
                   FROM (SELECT SEGMENTO2, SEG, COUNT(*) AS N FROM #rev WHERE ELEGIBLE IS NULL GROUP BY SEGMENTO2, SEG) x);
    IF @nuevos IS NOT NULL
    BEGIN
        SET @msg = CONCAT(N'Tramos que no están en los catálogos ETIQUETA6_SEG_*: ', @nuevos,
                          N'. Se blanquearon; si alguno es elegible, agrégalo con cfg.sp_catalogo_alta (destino SI) y vuelve a etiquetar.');
        EXEC ops.sp_log @id_corrida, 'ETIQUETA6 BLANQUEO', 'AVISO', NULL, @msg;
    END;
END;
GO
