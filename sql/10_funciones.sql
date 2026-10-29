/* =====================================================================
   Banbaj · 10 Funciones de apoyo (esquema cfg)
   Se usan en cfg.ARCHIVO_COLUMNA.TRANSFORMACION y cfg.SALIDA.EXPRESION.
   ===================================================================== */
SET NOCOUNT ON;
GO

/* Texto limpio: quita espacios de no separación, tabuladores, CR/LF y
   espacios a los lados. Vacío o valores de Excel sin dato -> NULL. */
CREATE OR ALTER FUNCTION cfg.fn_texto (@t NVARCHAR(4000))
RETURNS NVARCHAR(4000)
WITH SCHEMABINDING
AS
BEGIN
    DECLARE @s NVARCHAR(4000) =
        LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(REPLACE(@t, NCHAR(160), N' '), NCHAR(9), N' '), NCHAR(13), N''), NCHAR(10), N'')));
    IF @s IN (N'', N'#N/D', N'#N/A', N'NULL') RETURN NULL;
    RETURN @s;
END;
GO

/* Importe desde texto del banco: "$1,234.50", " 99,999.99 ", "(12.00)", " - " (cero contable de Excel).
   Devuelve NULL si no es convertible (la carga lo manda a rechazos). */
CREATE OR ALTER FUNCTION cfg.fn_importe (@t NVARCHAR(4000))
RETURNS DECIMAL(18,2)
WITH SCHEMABINDING
AS
BEGIN
    DECLARE @s NVARCHAR(4000) = REPLACE(REPLACE(REPLACE(REPLACE(@t, N'$', N''), N',', N''), N' ', N''), NCHAR(160), N'');
    SET @s = REPLACE(REPLACE(@s, NCHAR(13), N''), NCHAR(10), N'');
    IF @s IS NULL OR @s = N'' RETURN NULL;
    IF @s = N'-' RETURN 0;
    IF LEFT(@s, 1) = N'(' AND RIGHT(@s, 1) = N')' SET @s = N'-' + SUBSTRING(@s, 2, LEN(@s) - 2);
    RETURN TRY_CONVERT(DECIMAL(18,2), @s);
END;
GO

/* Entero desde texto ("762", "96.0", "#N/D" -> NULL) */
CREATE OR ALTER FUNCTION cfg.fn_entero (@t NVARCHAR(4000))
RETURNS INT
WITH SCHEMABINDING
AS
BEGIN
    DECLARE @d DECIMAL(18,2) = cfg.fn_importe(@t);
    RETURN TRY_CONVERT(INT, ROUND(@d, 0));
END;
GO

/* Fecha según formato del archivo.
   AAAAMMDD | AAAA-MM-DD (admite hora después) | DD/MM/AAAA | MM/DD/AAAA */
CREATE OR ALTER FUNCTION cfg.fn_fecha (@t NVARCHAR(4000), @formato VARCHAR(20))
RETURNS DATE
WITH SCHEMABINDING
AS
BEGIN
    DECLARE @s NVARCHAR(4000) = cfg.fn_texto(@t);
    IF @s IS NULL OR @s = N'-' RETURN NULL;
    RETURN CASE @formato
        WHEN 'AAAAMMDD'   THEN TRY_CONVERT(DATE, LEFT(@s, 8), 112)
        WHEN 'AAAA-MM-DD' THEN TRY_CONVERT(DATE, LEFT(@s, 10), 23)
        WHEN 'DD/MM/AAAA' THEN TRY_CONVERT(DATE, LEFT(@s, 10), 103)
        WHEN 'MM/DD/AAAA' THEN TRY_CONVERT(DATE, LEFT(@s, 10), 101)
    END;
END;
GO

/* Solo dígitos (ej. CP con letras -> '06600') */
CREATE OR ALTER FUNCTION cfg.fn_solo_digitos (@t NVARCHAR(4000))
RETURNS VARCHAR(4000)
WITH SCHEMABINDING
AS
BEGIN
    IF @t IS NULL RETURN NULL;
    DECLARE @r VARCHAR(4000) = '', @i INT = 1, @c NCHAR(1);
    WHILE @i <= LEN(@t)
    BEGIN
        SET @c = SUBSTRING(@t, @i, 1);
        IF @c LIKE N'[0-9]' SET @r += CAST(@c AS VARCHAR(1));
        SET @i += 1;
    END;
    RETURN NULLIF(@r, '');
END;
GO

/* Importe a ancho fijo con ceros a la izquierda (formato CYBER).
   @modo:
     ABS_LEGADO -> como el .prg actual: el '-' se cambia por '0', el negativo sale positivo (H-01)
     CERO       -> un negativo se envía como cero
     SIGNO      -> '-' + (ancho-1) dígitos, como U1ACTASIG/U1VDOASIG/U1MINASIG */
CREATE OR ALTER FUNCTION cfg.fn_pad_importe (@v DECIMAL(18,2), @ancho INT, @modo VARCHAR(12))
RETURNS VARCHAR(30)
WITH SCHEMABINDING
AS
BEGIN
    DECLARE @x DECIMAL(18,2) = ISNULL(@v, 0);
    DECLARE @abs VARCHAR(30) = CONVERT(VARCHAR(30), ABS(@x));
    IF @modo = 'SIGNO' AND @x < 0
        RETURN '-' + RIGHT(REPLICATE('0', 30) + @abs, @ancho - 1);
    IF @modo = 'CERO' AND @x < 0
        RETURN RIGHT(REPLICATE('0', 30) + '0.00', @ancho);
    RETURN RIGHT(REPLICATE('0', 30) + @abs, @ancho);
END;
GO

/* Fecha a texto MMDDAAAA (formato CYBER); NULL -> '' */
CREATE OR ALTER FUNCTION cfg.fn_fecha_mmddaaaa (@d DATE)
RETURNS VARCHAR(8)
WITH SCHEMABINDING
AS
BEGIN
    RETURN ISNULL(REPLACE(CONVERT(VARCHAR(10), @d, 101), '/', ''), '');
END;
GO

/* Estado por rango de CP (antes DO CASE en asi486.prg) */
CREATE OR ALTER FUNCTION cfg.fn_cp_estado (@cp VARCHAR(10))
RETURNS VARCHAR(5)
AS
BEGIN
    DECLARE @e VARCHAR(5);
    IF LEN(@cp) = 5
        SELECT @e = ESTADO FROM cfg.CP_ESTADO WHERE @cp BETWEEN CP_INI AND CP_FIN;
    RETURN @e;
END;
GO

/* Etiqueta externa vigente por cuenta */
CREATE OR ALTER FUNCTION cfg.fn_etiqueta (@cliente VARCHAR(10), @tipo VARCHAR(20), @llave VARCHAR(30))
RETURNS NVARCHAR(100)
AS
BEGIN
    DECLARE @v NVARCHAR(100);
    SELECT @v = VALOR FROM cfg.ETIQUETA
    WHERE CLIENTE = @cliente AND TIPO = @tipo AND LLAVE = @llave AND ACTIVO = 1;
    RETURN @v;
END;
GO

/* Parámetro del cliente */
CREATE OR ALTER FUNCTION cfg.fn_param (@cliente VARCHAR(10), @clave VARCHAR(50))
RETURNS NVARCHAR(4000)
AS
BEGIN
    DECLARE @v NVARCHAR(4000);
    SELECT @v = VALOR FROM cfg.PARAMETRO WHERE CLIENTE = @cliente AND CLAVE = @clave;
    RETURN @v;
END;
GO

/* Ruta de entrada por fecha: Q:\CYBER\C_486\{AAAA}\{MES}\{DD}\ -> Q:\CYBER\C_486\2026\octubre\28\
   Tokens: {AAAA} año, {MM} mes a 2 dígitos, {MES} mes en español en minúsculas, {DD} día a 2 dígitos.
   El nombre del mes no depende del idioma del servidor. */
CREATE OR ALTER FUNCTION cfg.fn_ruta (@ruta NVARCHAR(400), @fecha DATE)
RETURNS NVARCHAR(400)
AS
BEGIN
    RETURN REPLACE(REPLACE(REPLACE(REPLACE(@ruta,
           N'{AAAA}', CAST(YEAR(@fecha) AS NCHAR(4))),
           N'{MM}',   RIGHT(N'0' + CAST(MONTH(@fecha) AS NVARCHAR(2)), 2)),
           N'{MES}',  CHOOSE(MONTH(@fecha), N'enero', N'febrero', N'marzo', N'abril', N'mayo', N'junio', N'julio',
                             N'agosto', N'septiembre', N'octubre', N'noviembre', N'diciembre')),
           N'{DD}',   RIGHT(N'0' + CAST(DAY(@fecha) AS NVARCHAR(2)), 2));
END;
GO
