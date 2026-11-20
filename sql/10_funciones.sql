USE [BNABAJ_486];   -- base del 486 (si la instalas con otro nombre, cámbialo aquí)
GO
/* =====================================================================
   Banbaj · 10 Funciones de apoyo (esquema cfg)
   Se usan en cfg.ARCHIVO_COLUMNA.TRANSFORMACION y cfg.SALIDA.EXPRESION.
   ===================================================================== */
SET NOCOUNT ON;
GO

/* Las funciones con SCHEMABINDING que usan a otras (fn_fecha usa fn_texto, fn_entero usa fn_importe)
   impiden el ALTER de esas otras en una base existente (Msg 3729). Se borran aquí y se vuelven a crear abajo. */
IF OBJECT_ID('cfg.fn_fecha', 'FN') IS NOT NULL DROP FUNCTION cfg.fn_fecha;
IF OBJECT_ID('cfg.fn_entero', 'FN') IS NOT NULL DROP FUNCTION cfg.fn_entero;
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

/* Día hábil anterior (lunes a viernes): el lunes regresa el viernes. No considera días festivos.
   Sin depender de SET DATEFIRST: el 01/01/1900 fue lunes. */
CREATE OR ALTER FUNCTION cfg.fn_dia_habil_anterior (@fecha DATE)
RETURNS DATE
AS
BEGIN
    RETURN DATEADD(DAY, CASE DATEDIFF(DAY, '19000101', @fecha) % 7 WHEN 0 THEN -3 WHEN 6 THEN -2 ELSE -1 END, @fecha);
END;
GO
/* 1 si la fecha es sábado o domingo */
CREATE OR ALTER FUNCTION cfg.fn_es_fin_de_semana (@fecha DATE)
RETURNS BIT
AS
BEGIN
    RETURN CASE WHEN DATEDIFF(DAY, '19000101', @fecha) % 7 IN (5, 6) THEN 1 ELSE 0 END;
END;
GO

/* ---------------------------------------------------------------------
   Catálogos estáticos (cfg.CATALOGO, decisión 17/11)
   Etiqueta del catálogo para un valor del banco; NULL si no está.
   Compara sin acentos ni mayúsculas; el valor exacto gana sobre los patrones
   (VALOR_ORIGEN con % o [0-9]) y entre patrones gana el ORDEN menor.
   --------------------------------------------------------------------- */
CREATE OR ALTER FUNCTION cfg.fn_catalogo (@cliente VARCHAR(10), @catalogo VARCHAR(40), @valor NVARCHAR(4000))
RETURNS NVARCHAR(200)
AS
BEGIN
    DECLARE @v NVARCHAR(4000) = cfg.fn_texto(@valor);
    IF @v IS NULL RETURN NULL;
    RETURN (SELECT TOP (1) VALOR_DESTINO
            FROM cfg.CATALOGO
            WHERE CLIENTE = @cliente AND CATALOGO = @catalogo AND ACTIVO = 1
              AND (@v = VALOR_ORIGEN COLLATE Latin1_General_CI_AI OR @v LIKE VALOR_ORIGEN COLLATE Latin1_General_CI_AI)
            ORDER BY CASE WHEN @v = VALOR_ORIGEN COLLATE Latin1_General_CI_AI THEN 0 ELSE 1 END, ORDEN, ID);
END;
GO

/* Valor enmascarado para correos y bitácora: letras -> x, dígitos -> 9 (el resto se queda).
   Sirve para ver la forma de un dato ("xxxx@xxx" o "99-xxxx") sin exponerlo. */
CREATE OR ALTER FUNCTION cfg.fn_enmascarar (@t NVARCHAR(4000))
RETURNS NVARCHAR(60)
AS
BEGIN
    IF @t IS NULL RETURN NULL;
    DECLARE @r NVARCHAR(60) = N'', @i INT = 1, @c NCHAR(1), @n INT = LEN(@t);
    IF @n > 40 SET @n = 40;
    WHILE @i <= @n
    BEGIN
        SET @c = SUBSTRING(@t, @i, 1);
        SET @r += CASE WHEN @c LIKE N'[0-9]' THEN N'9'
                       WHEN UPPER(@c) COLLATE Latin1_General_CI_AI LIKE N'[A-Z]' OR @c LIKE N'[ñÑ]' THEN N'x'
                       ELSE @c END;
        SET @i += 1;
    END;
    RETURN @r + CASE WHEN LEN(@t) > 40 THEN N'…' ELSE N'' END;
END;
GO

/* Patrón LIKE a partir de un encabezado tal como viene en el archivo (lo mismo que patron() de
   tools/generar_sql_486.py): escapa [ % _, cambia las fechas DD/MM/AAAA por % y "01 ENE…" por
   "[0-9][0-9] %", para que el patrón siga sirviendo cuando cambie la fecha del encabezado. */
CREATE OR ALTER FUNCTION cfg.fn_patron_encabezado (@encabezado NVARCHAR(200))
RETURNS NVARCHAR(200)
AS
BEGIN
    DECLARE @p NVARCHAR(400) = cfg.fn_texto(@encabezado), @i INT, @j INT;
    IF @p IS NULL RETURN NULL;
    SET @p = REPLACE(REPLACE(REPLACE(@p, N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]');
    SET @i = PATINDEX(N'%[0-9][0-9]/[0-9][0-9]/[0-9][0-9][0-9][0-9]%', @p);
    WHILE @i > 0
    BEGIN
        SET @p = STUFF(@p, @i, 10, N'%');
        SET @i = PATINDEX(N'%[0-9][0-9]/[0-9][0-9]/[0-9][0-9][0-9][0-9]%', @p);
    END;
    SET @i = PATINDEX(N'%[0-9][0-9] [A-Za-z][A-Za-z][A-Za-z]%', @p);
    IF @i > 0 AND UPPER(SUBSTRING(@p, @i + 3, 3)) IN (N'ENE', N'FEB', N'MAR', N'ABR', N'MAY', N'JUN', N'JUL', N'AGO', N'SEP', N'OCT', N'NOV', N'DIC')
    BEGIN
        SET @j = @i + 6;                                         -- fin de la palabra del mes
        WHILE @j <= LEN(@p) AND SUBSTRING(@p, @j, 1) LIKE N'[A-Za-z0-9]' SET @j += 1;
        SET @p = STUFF(@p, @i, @j - @i, N'[0-9][0-9] %');
    END;
    RETURN LEFT(@p, 200);
END;
GO

/* ---------------------------------------------------------------------
   Orden del arribo de la asignación (decisión 17/11): archivos que todavía no se escriben
   ni se avisan porque esperan su paso. Con ARRIBO_AUTOMATICO = 1:
     ARCHIVOS_DESPUES_SALDOS        (GESCAR_NVA, GESCAR_REA, GESCAR_SINTEL) hasta que suben los saldos (paso ARRIBO SALDOS)
     ARCHIVOS_DESPUES_DEPURACION_TEL (SCBTEL) hasta que la depuración de teléfonos queda OK: el SCBTEL
                                     lleva los teléfonos nuevos y solo se sube con lo demás ya depurado.
   Devuelve la lista separada por comas (NULL = nada pendiente). Lo usan ops.sp_exportar_auto y ops.sp_retiro_cerrar.
   --------------------------------------------------------------------- */
CREATE OR ALTER FUNCTION ops.fn_archivos_diferidos (@id_corrida INT)
RETURNS NVARCHAR(400)
AS
BEGIN
    DECLARE @cliente VARCHAR(10), @proceso VARCHAR(10), @r NVARCHAR(400) = N'';
    SELECT @cliente = CLIENTE, @proceso = PROCESO FROM ops.CORRIDA WHERE ID_CORRIDA = @id_corrida;
    IF @proceso IS NULL OR @proceso <> 'ASIG' OR ISNULL(cfg.fn_param(@cliente, 'ARRIBO_AUTOMATICO'), '0') <> '1' RETURN NULL;
    IF NOT EXISTS (SELECT 1 FROM ops.BITACORA WHERE ID_CORRIDA = @id_corrida AND PASO = 'ARRIBO SALDOS' AND ESTATUS = 'OK')
    BEGIN
        SET @r += N',' + ISNULL(cfg.fn_param(@cliente, 'ARCHIVOS_DESPUES_SALDOS'), N'GESCAR_NVA,GESCAR_REA,GESCAR_SINTEL');
        /* 19/11: el gescar sin teléfono siempre espera a los saldos, aunque el parámetro del servidor sea anterior */
        IF NOT EXISTS (SELECT 1 FROM STRING_SPLIT(@r, N',') WHERE UPPER(LTRIM(RTRIM(value))) = N'GESCAR_SINTEL')
            SET @r += N',GESCAR_SINTEL';
    END;
    IF NOT EXISTS (SELECT 1 FROM ops.BITACORA WHERE ID_CORRIDA = @id_corrida AND PASO = 'ARRIBO TELEFONOS' AND ESTATUS = 'OK')
        SET @r += N',' + ISNULL(cfg.fn_param(@cliente, 'ARCHIVOS_DESPUES_DEPURACION_TEL'), N'SCBTEL');
    RETURN NULLIF(STUFF(@r, 1, 1, N''), N'');
END;
GO
