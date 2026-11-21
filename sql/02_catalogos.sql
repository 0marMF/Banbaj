USE [BNABAJ_486];   -- base del 486 (si la instalas con otro nombre, cámbialo aquí)
GO
/* =====================================================================
   Banbaj · 02 Catálogos (esquema cfg)
   ---------------------------------------------------------------------
   Todo lo que hoy está escrito en los .prg vive aquí como filas.
   Las columnas CONDICION, VALOR, EXPRESION y TRANSFORMACION contienen
   SQL que los stored procedures ejecutan de forma dinámica: solo el
   equipo que administra los procesos debe tener permiso de escritura
   sobre el esquema cfg.
   ===================================================================== */
SET NOCOUNT ON;
GO

/* Parámetros sueltos por cliente (topes, prefijos, modos) */
IF OBJECT_ID('cfg.PARAMETRO') IS NULL
CREATE TABLE cfg.PARAMETRO (
    CLIENTE      VARCHAR(10)    NOT NULL,
    CLAVE        VARCHAR(50)    NOT NULL,
    VALOR        NVARCHAR(4000) NOT NULL,
    DESCRIPCION  NVARCHAR(400)  NULL,
    CONSTRAINT PK_PARAMETRO PRIMARY KEY (CLIENTE, CLAVE)
);
GO

/* Un archivo de entrada (base maestra, saldos, pagos…) */
IF OBJECT_ID('cfg.ARCHIVO') IS NULL
CREATE TABLE cfg.ARCHIVO (
    ID_ARCHIVO        INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_ARCHIVO PRIMARY KEY,
    CLIENTE           VARCHAR(10)    NOT NULL,
    PROCESO           VARCHAR(10)    NOT NULL,          -- ASIG / ACT
    CODIGO            VARCHAR(50)    NOT NULL,          -- MAESTRA_TDC, SALDOS_CONS, PAGOS…
    SEGMENTO2         VARCHAR(20)    NULL,              -- TDC / CONSUMO / HIPOTECARIO (NULL = no aplica)
    RUTA              NVARCHAR(400)  NOT NULL,          -- carpeta, termina en '\'
    PATRON_NOMBRE     NVARCHAR(200)  NOT NULL,          -- LIKE sobre el nombre; admite {AAAAMMDD} {DD-MM-AAAA} {AAAA-MM-DD}
    SEPARADOR         VARCHAR(5)     NOT NULL CONSTRAINT DF_ARCHIVO_SEP DEFAULT ',',
    CON_COMILLAS      BIT            NOT NULL CONSTRAINT DF_ARCHIVO_COM DEFAULT 1,   -- campos entre comillas (FORMAT='CSV')
    CODEPAGE          VARCHAR(10)    NOT NULL CONSTRAINT DF_ARCHIVO_CP  DEFAULT 'ACP',
    FIN_DE_LINEA      VARCHAR(10)    NOT NULL CONSTRAINT DF_ARCHIVO_FDL DEFAULT '0x0a',
    FILA_ENCABEZADO   INT            NOT NULL CONSTRAINT DF_ARCHIVO_ENC DEFAULT 1,
    NUM_COLUMNAS      INT            NOT NULL,          -- columnas esperadas en el archivo
    TABLA_DESTINO     SYSNAME        NOT NULL,          -- ej. stg.ENT_MAESTRA_TDC
    LLAVE_DAT         SYSNAME        NULL,              -- columna con la que el archivo cruza contra el DAT (DES_PROD, RIESGO…)
    OBLIGATORIO       BIT            NOT NULL CONSTRAINT DF_ARCHIVO_OBL DEFAULT 0,
    ORDEN             INT            NOT NULL CONSTRAINT DF_ARCHIVO_ORD DEFAULT 0,
    ACTIVO            BIT            NOT NULL CONSTRAINT DF_ARCHIVO_ACT DEFAULT 1,
    COMENTARIO        NVARCHAR(400)  NULL,
    GUARDAR_COMPLETO  BIT            NOT NULL CONSTRAINT DF_ARCHIVO_GC DEFAULT 0,    -- 1 = se guarda el archivo completo en dat.BASE_RECIBIDA
    CONSTRAINT UX_ARCHIVO_CODIGO UNIQUE (CLIENTE, CODIGO),
    CONSTRAINT CK_ARCHIVO_PROCESO CHECK (PROCESO IN ('ASIG','ACT'))
);
GO
IF COL_LENGTH('cfg.ARCHIVO', 'GUARDAR_COMPLETO') IS NULL
    ALTER TABLE cfg.ARCHIVO ADD GUARDAR_COMPLETO BIT NOT NULL CONSTRAINT DF_ARCHIVO_GC DEFAULT 0;
GO

/* Columnas de cada archivo y cómo se convierten al campo destino.
   - PATRON_ENCABEZADO: LIKE sobre el encabezado (sin acentos ni mayúsculas).
     Los encabezados del banco traen fechas ("ADEUDO TOTAL AL 29/06/2026"),
     por eso se busca por patrón y no por posición.
   - POSICION: opcional, se usa solo si no hay patrón.
   - Sin patrón y sin posición = columna DERIVADA: se crea vacía y la llena
     la homologación (ej. ESTATUS2, SEGMENTO2, SALDO3).
   - TRANSFORMACION: expresión SQL; {v} es el texto limpio de la columna. */
IF OBJECT_ID('cfg.ARCHIVO_COLUMNA') IS NULL
CREATE TABLE cfg.ARCHIVO_COLUMNA (
    ID                 INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_ARCHIVO_COLUMNA PRIMARY KEY,
    ID_ARCHIVO         INT            NOT NULL CONSTRAINT FK_ARCHIVO_COLUMNA_ARCHIVO REFERENCES cfg.ARCHIVO (ID_ARCHIVO),
    CAMPO_DESTINO      SYSNAME        NOT NULL,
    PATRON_ENCABEZADO  NVARCHAR(200)  NULL,
    POSICION           INT            NULL,
    TIPO_SQL           VARCHAR(50)    NOT NULL,          -- VARCHAR(50), DECIMAL(18,2), DATE…
    TRANSFORMACION     NVARCHAR(1000) NOT NULL CONSTRAINT DF_ARCHIVO_COLUMNA_TRF DEFAULT N'{v}',
    OBLIGATORIO        BIT            NOT NULL CONSTRAINT DF_ARCHIVO_COLUMNA_OBL DEFAULT 0,
    ACTIVO             BIT            NOT NULL CONSTRAINT DF_ARCHIVO_COLUMNA_ACT DEFAULT 1,
    COMENTARIO         NVARCHAR(400)  NULL,
    CONSTRAINT UX_ARCHIVO_COLUMNA UNIQUE (ID_ARCHIVO, CAMPO_DESTINO)
);
GO
/* PERMITE_VACIO: con OBLIGATORIO = 1, un valor vacío no rechaza el renglón (solo uno que no convierte).
   Ej. el saldo actualizado de TDC viene vacío en VEN2 y VEN3 y la homologación toma el saldo PRIME. */
IF COL_LENGTH('cfg.ARCHIVO_COLUMNA', 'PERMITE_VACIO') IS NULL
    ALTER TABLE cfg.ARCHIVO_COLUMNA ADD PERMITE_VACIO BIT NOT NULL CONSTRAINT DF_ARCHIVO_COLUMNA_PV DEFAULT 0;
GO

/* ---------------------------------------------------------------------
   Layout editable por el equipo de asignaciones (decisión 17/11)
   ---------------------------------------------------------------------
   El layout de cada archivo vive en cfg.ARCHIVO (nombre y carpeta) y en
   cfg.ARCHIVO_COLUMNA (encabezado de cada campo). El equipo lo cambia con un
   UPDATE o con cfg.sp_layout_cambiar. Cada cambio queda en cfg.LAYOUT_HISTORIAL
   y marca el renglón (EDITADO_POR, FE_EDICION): la semilla (90_semilla_486.sql)
   conserva lo que el equipo cambió en vez de regresarlo al valor de fábrica.
   Para volver al valor de fábrica: EDITADO_POR = NULL y correr la semilla.
   --------------------------------------------------------------------- */
IF COL_LENGTH('cfg.ARCHIVO_COLUMNA', 'EDITADO_POR') IS NULL
    ALTER TABLE cfg.ARCHIVO_COLUMNA ADD EDITADO_POR SYSNAME NULL, FE_EDICION DATETIME2(0) NULL;
GO
IF COL_LENGTH('cfg.ARCHIVO', 'EDITADO_POR') IS NULL
    ALTER TABLE cfg.ARCHIVO ADD EDITADO_POR SYSNAME NULL, FE_EDICION DATETIME2(0) NULL;
GO
IF OBJECT_ID('cfg.LAYOUT_HISTORIAL') IS NULL
CREATE TABLE cfg.LAYOUT_HISTORIAL (
    ID           INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_LAYOUT_HISTORIAL PRIMARY KEY,
    CLIENTE      VARCHAR(10)    NOT NULL,
    CODIGO       VARCHAR(50)    NOT NULL,           -- archivo (cfg.ARCHIVO.CODIGO)
    CAMPO        SYSNAME        NULL,               -- NULL = cambio del archivo (nombre, carpeta, activo)
    DATO         VARCHAR(30)    NOT NULL,           -- PATRON_ENCABEZADO, ACTIVO, RUTA, PATRON_NOMBRE…
    ANTES        NVARCHAR(400)  NULL,
    DESPUES      NVARCHAR(400)  NULL,
    USUARIO      SYSNAME        NOT NULL CONSTRAINT DF_LAYOUT_HISTORIAL_USR DEFAULT SUSER_SNAME(),
    FECHA        DATETIME2(0)   NOT NULL CONSTRAINT DF_LAYOUT_HISTORIAL_FE DEFAULT SYSDATETIME()
);
GO
/* La semilla corre con SESSION_CONTEXT('SEMILLA') = 1: sus cambios no cuentan como del equipo */
CREATE OR ALTER TRIGGER cfg.tr_ARCHIVO_COLUMNA_EDICION ON cfg.ARCHIVO_COLUMNA AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF TRY_CONVERT(INT, SESSION_CONTEXT(N'SEMILLA')) = 1 RETURN;
    IF NOT (UPDATE(PATRON_ENCABEZADO) OR UPDATE(POSICION) OR UPDATE(ACTIVO) OR UPDATE(OBLIGATORIO) OR UPDATE(PERMITE_VACIO)) RETURN;
    INSERT INTO cfg.LAYOUT_HISTORIAL (CLIENTE, CODIGO, CAMPO, DATO, ANTES, DESPUES)
    SELECT a.CLIENTE, a.CODIGO, i.CAMPO_DESTINO, v.DATO, v.ANTES, v.DESPUES
    FROM inserted i
    JOIN deleted d ON d.ID = i.ID
    JOIN cfg.ARCHIVO a ON a.ID_ARCHIVO = i.ID_ARCHIVO
    CROSS APPLY (VALUES ('PATRON_ENCABEZADO', d.PATRON_ENCABEZADO, i.PATRON_ENCABEZADO),
                        ('POSICION', CAST(d.POSICION AS NVARCHAR(400)), CAST(i.POSICION AS NVARCHAR(400))),
                        ('ACTIVO', CAST(d.ACTIVO AS NVARCHAR(400)), CAST(i.ACTIVO AS NVARCHAR(400))),
                        ('OBLIGATORIO', CAST(d.OBLIGATORIO AS NVARCHAR(400)), CAST(i.OBLIGATORIO AS NVARCHAR(400))),
                        ('PERMITE_VACIO', CAST(d.PERMITE_VACIO AS NVARCHAR(400)), CAST(i.PERMITE_VACIO AS NVARCHAR(400)))) v(DATO, ANTES, DESPUES)
    WHERE ISNULL(v.ANTES, N'<<NULL>>') <> ISNULL(v.DESPUES, N'<<NULL>>');
    UPDATE c SET EDITADO_POR = SUSER_SNAME(), FE_EDICION = SYSDATETIME()
    FROM cfg.ARCHIVO_COLUMNA c
    JOIN inserted i ON i.ID = c.ID
    JOIN deleted d ON d.ID = i.ID
    WHERE ISNULL(i.PATRON_ENCABEZADO, N'<<NULL>>') <> ISNULL(d.PATRON_ENCABEZADO, N'<<NULL>>') OR ISNULL(i.POSICION, -1) <> ISNULL(d.POSICION, -1)
       OR i.ACTIVO <> d.ACTIVO OR i.OBLIGATORIO <> d.OBLIGATORIO OR i.PERMITE_VACIO <> d.PERMITE_VACIO;
END;
GO
CREATE OR ALTER TRIGGER cfg.tr_ARCHIVO_EDICION ON cfg.ARCHIVO AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF TRY_CONVERT(INT, SESSION_CONTEXT(N'SEMILLA')) = 1 RETURN;
    IF NOT (UPDATE(RUTA) OR UPDATE(PATRON_NOMBRE) OR UPDATE(ACTIVO) OR UPDATE(OBLIGATORIO)) RETURN;
    INSERT INTO cfg.LAYOUT_HISTORIAL (CLIENTE, CODIGO, CAMPO, DATO, ANTES, DESPUES)
    SELECT i.CLIENTE, i.CODIGO, NULL, v.DATO, v.ANTES, v.DESPUES
    FROM inserted i
    JOIN deleted d ON d.ID_ARCHIVO = i.ID_ARCHIVO
    CROSS APPLY (VALUES ('RUTA', d.RUTA, i.RUTA),
                        ('PATRON_NOMBRE', d.PATRON_NOMBRE, i.PATRON_NOMBRE),
                        ('ACTIVO', CAST(d.ACTIVO AS NVARCHAR(400)), CAST(i.ACTIVO AS NVARCHAR(400))),
                        ('OBLIGATORIO', CAST(d.OBLIGATORIO AS NVARCHAR(400)), CAST(i.OBLIGATORIO AS NVARCHAR(400)))) v(DATO, ANTES, DESPUES)
    WHERE ISNULL(v.ANTES, N'<<NULL>>') <> ISNULL(v.DESPUES, N'<<NULL>>');
    UPDATE a SET EDITADO_POR = SUSER_SNAME(), FE_EDICION = SYSDATETIME()
    FROM cfg.ARCHIVO a
    JOIN inserted i ON i.ID_ARCHIVO = a.ID_ARCHIVO
    JOIN deleted d ON d.ID_ARCHIVO = i.ID_ARCHIVO
    WHERE i.RUTA <> d.RUTA OR i.PATRON_NOMBRE <> d.PATRON_NOMBRE OR i.ACTIVO <> d.ACTIVO OR i.OBLIGATORIO <> d.OBLIGATORIO;
END;
GO

/* Homologación: UPDATE t SET CAMPO_DESTINO = VALOR WHERE CONDICION, en ORDEN.
   VALOR es una expresión SQL (un literal va entre comillas: 'VIG').
   CONDICION NULL = todos los registros. Alias de la tabla: t.
   Admite {FECHA} (fecha de proceso) y {CLIENTE}. */
IF OBJECT_ID('cfg.HOMOLOGACION') IS NULL
CREATE TABLE cfg.HOMOLOGACION (
    ID             INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_HOMOLOGACION PRIMARY KEY,
    CLIENTE        VARCHAR(10)    NOT NULL,
    PROCESO        VARCHAR(10)    NOT NULL,
    TABLA          SYSNAME        NOT NULL,              -- stg.ENT_MAESTRA_TDC, stg.LAYOUT_486…
    ORDEN          INT            NOT NULL,
    CAMPO_DESTINO  SYSNAME        NOT NULL,
    VALOR          NVARCHAR(1000) NOT NULL,
    CONDICION      NVARCHAR(1000) NULL,
    DESCRIPCION    NVARCHAR(400)  NULL,
    REQ            VARCHAR(40)    NULL,                  -- requerimiento que la originó
    ACTIVO         BIT            NOT NULL CONSTRAINT DF_HOMOLOGACION_ACT DEFAULT 1
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_HOMOLOGACION_ORDEN')
    CREATE INDEX IX_HOMOLOGACION_ORDEN ON cfg.HOMOLOGACION (CLIENTE, PROCESO, TABLA, ORDEN);
GO

/* Reglas de validación / filtro.
   EVALUA = FILAS     -> se dispara si hay >= UMBRAL registros que cumplen CONDICION
   EVALUA = SIN_FILAS -> se dispara si NINGÚN registro cumple CONDICION (ej. no hay pagos a T-1)
   ACCION = ALERTAR   -> bitácora + correo, el proceso sigue
            EXCLUIR   -> los registros pasan a ops.RECHAZO y se borran de TABLA
            DEVOLVER  -> las cuentas (columna CUENTA) pasan a ops.DEVOLUCION
            CANCELAR  -> bitácora + correo y se detiene la corrida */
IF OBJECT_ID('cfg.REGLA') IS NULL
CREATE TABLE cfg.REGLA (
    ID             INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_REGLA PRIMARY KEY,
    CLIENTE        VARCHAR(10)    NOT NULL,
    PROCESO        VARCHAR(10)    NOT NULL,
    PASO           VARCHAR(30)    NOT NULL,              -- POST_CARGA, PRE_ALTA, RETIRO…
    CODIGO         VARCHAR(60)    NOT NULL,
    TABLA          SYSNAME        NOT NULL,
    CONDICION      NVARCHAR(2000) NOT NULL,
    EVALUA         VARCHAR(10)    NOT NULL CONSTRAINT DF_REGLA_EVALUA DEFAULT 'FILAS',
    UMBRAL         INT            NOT NULL CONSTRAINT DF_REGLA_UMBRAL DEFAULT 1,
    ACCION         VARCHAR(10)    NOT NULL,
    MENSAJE        NVARCHAR(400)  NOT NULL,
    PLANTILLA_CORREO VARCHAR(60)  NULL,                  -- mail.PLANTILLA a enviar cuando se dispara
    ORDEN          INT            NOT NULL CONSTRAINT DF_REGLA_ORDEN DEFAULT 0,
    REQ            VARCHAR(40)    NULL,
    ACTIVO         BIT            NOT NULL CONSTRAINT DF_REGLA_ACT DEFAULT 1,
    CONSTRAINT UX_REGLA_CODIGO UNIQUE (CLIENTE, CODIGO),
    CONSTRAINT CK_REGLA_EVALUA CHECK (EVALUA IN ('FILAS','SIN_FILAS')),
    CONSTRAINT CK_REGLA_ACCION CHECK (ACCION IN ('ALERTAR','EXCLUIR','DEVOLVER','CANCELAR'))
);
GO

/* Campos de los archivos de salida (SCBSDOS, SCBTEL, SCBPAG, SCBACTH…).
   EXPRESION es SQL sobre el ORIGEN de cfg.SALIDA_ARCHIVO con alias d
   (el DAT si no hay origen); puede usar @fecha (fecha de la corrida) y @hora (HH:MM:SS).
   En archivos delimitados ANCHO no se usa (0).
   FORMATO: TEXTO | IMPORTE | IMPORTE_SIGNO | FECHA_MMDDAAAA | CONSTANTE */
IF OBJECT_ID('cfg.SALIDA') IS NULL
CREATE TABLE cfg.SALIDA (
    ID           INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_SALIDA PRIMARY KEY,
    CLIENTE      VARCHAR(10)    NOT NULL,
    ARCHIVO      VARCHAR(50)    NOT NULL,
    ORDEN        INT            NOT NULL,
    CAMPO        VARCHAR(50)    NOT NULL,
    ANCHO        INT            NOT NULL,
    FORMATO      VARCHAR(20)    NOT NULL CONSTRAINT DF_SALIDA_FMT DEFAULT 'TEXTO',
    EXPRESION    NVARCHAR(1000) NOT NULL CONSTRAINT DF_SALIDA_EXP DEFAULT N'''''',
    ALINEACION   CHAR(1)        NOT NULL CONSTRAINT DF_SALIDA_ALI DEFAULT 'I',   -- I=izquierda, D=derecha
    COMENTARIO   NVARCHAR(400)  NULL,
    ACTIVO       BIT            NOT NULL CONSTRAINT DF_SALIDA_ACT DEFAULT 1,
    CONSTRAINT UX_SALIDA UNIQUE (CLIENTE, ARCHIVO, ORDEN),
    CONSTRAINT CK_SALIDA_FMT CHECK (FORMATO IN ('TEXTO','IMPORTE','IMPORTE_SIGNO','FECHA_MMDDAAAA','CONSTANTE'))
);
GO

/* Archivos planos de salida (para arribo manual a CYBER y para operación).
   ORIGEN: FROM de la consulta, con alias d; puede usar @id_corrida, @cliente, @fecha.
           NULL = el DAT del cliente.
   SEPARADOR: NULL = ancho fijo (se valida la suma de ANCHO); '|' o ',' = delimitado.
   NOMBRE: nombre del archivo al exportar; admite {AAAAMMDD}, {MMDDAAAA}, {HHMMSS}, {CORRIDA}.
   PROCESO: grupo en que se genera (ASIG, ACT, RETIRO) con ops.sp_generar_salidas. */
IF OBJECT_ID('cfg.SALIDA_ARCHIVO') IS NULL
CREATE TABLE cfg.SALIDA_ARCHIVO (
    CLIENTE       VARCHAR(10)    NOT NULL,
    ARCHIVO       VARCHAR(50)    NOT NULL,
    PROCESO       VARCHAR(10)    NOT NULL,
    ORDEN         INT            NOT NULL CONSTRAINT DF_SALIDA_ARCHIVO_ORDEN DEFAULT 10,
    ORIGEN        NVARCHAR(2000) NULL,
    ORDEN_LINEAS  NVARCHAR(400)  NOT NULL CONSTRAINT DF_SALIDA_ARCHIVO_OL DEFAULT N'd.CUENTA2',
    SEPARADOR     VARCHAR(5)     NULL,
    NOMBRE        NVARCHAR(200)  NOT NULL,
    FIN_DE_LINEA  VARCHAR(4)     NOT NULL CONSTRAINT DF_SALIDA_ARCHIVO_FIN DEFAULT 'CRLF',
    CODIFICACION  VARCHAR(20)    NOT NULL CONSTRAINT DF_SALIDA_ARCHIVO_COD DEFAULT 'cp1252',
    COMILLAS      BIT            NOT NULL CONSTRAINT DF_SALIDA_ARCHIVO_COM DEFAULT 0,   -- delimitado: cada campo entre comillas (CSV)
    ENCABEZADO    BIT            NOT NULL CONSTRAINT DF_SALIDA_ARCHIVO_ENC DEFAULT 0,   -- primera línea con los nombres de los campos
    DESCRIPCION   NVARCHAR(400)  NULL,
    ACTIVO        BIT            NOT NULL CONSTRAINT DF_SALIDA_ARCHIVO_ACT DEFAULT 1,
    CONSTRAINT PK_SALIDA_ARCHIVO PRIMARY KEY (CLIENTE, ARCHIVO),
    CONSTRAINT CK_SALIDA_ARCHIVO_FIN CHECK (FIN_DE_LINEA IN ('CRLF','LF'))
);
GO
IF COL_LENGTH('cfg.SALIDA_ARCHIVO', 'COMILLAS') IS NULL
    ALTER TABLE cfg.SALIDA_ARCHIVO ADD COMILLAS BIT NOT NULL CONSTRAINT DF_SALIDA_ARCHIVO_COM DEFAULT 0,
                                       ENCABEZADO BIT NOT NULL CONSTRAINT DF_SALIDA_ARCHIVO_ENC DEFAULT 0;
GO

/* Etiquetas externas por cuenta (antes DBF sueltas: eti, dm1, top, STATUS; eti486, covid y garantizada ya no se usan) */
IF OBJECT_ID('cfg.ETIQUETA') IS NULL
CREATE TABLE cfg.ETIQUETA (
    CLIENTE   VARCHAR(10)   NOT NULL,
    TIPO      VARCHAR(20)   NOT NULL,
    LLAVE     VARCHAR(30)   NOT NULL,            -- CUENTA o CUENTA2 según el tipo
    VALOR     NVARCHAR(100) NOT NULL,
    FE_ACT    DATETIME2(0)  NOT NULL CONSTRAINT DF_ETIQUETA_FE DEFAULT SYSDATETIME(),
    ACTIVO    BIT           NOT NULL CONSTRAINT DF_ETIQUETA_ACT DEFAULT 1,
    CONSTRAINT PK_ETIQUETA PRIMARY KEY (CLIENTE, TIPO, LLAVE)
);
GO

/* Exclusiones: cuentas (exc486), teléfonos (blacklist_486, teléfonos del banco),
   direcciones malas (dirmal), correos malos (EMAILMALO) */
IF OBJECT_ID('cfg.EXCLUSION') IS NULL
CREATE TABLE cfg.EXCLUSION (
    ID        INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_EXCLUSION PRIMARY KEY,
    CLIENTE   VARCHAR(10)   NOT NULL,
    TIPO      VARCHAR(20)   NOT NULL,            -- CUENTA / TELEFONO / DIRECCION / CORREO
    VALOR     NVARCHAR(200) NOT NULL,
    VALOR2    NVARCHAR(200) NULL,                -- ej. DIRECC1 para DIRECCION, CUENTA para CORREO
    MOTIVO    NVARCHAR(200) NULL,
    REQ       VARCHAR(40)   NULL,
    ACTIVO    BIT           NOT NULL CONSTRAINT DF_EXCLUSION_ACT DEFAULT 1,
    FE_ALTA   DATETIME2(0)  NOT NULL CONSTRAINT DF_EXCLUSION_FE DEFAULT SYSDATETIME()
);
GO
/* ORIGEN: de dónde salió el registro (MIGRACION DBF, CARGA, ALTA). REQ es el requerimiento u OS. */
IF COL_LENGTH('cfg.EXCLUSION', 'ORIGEN') IS NULL
    ALTER TABLE cfg.EXCLUSION ADD ORIGEN VARCHAR(40) NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_EXCLUSION_VALOR')
    CREATE INDEX IX_EXCLUSION_VALOR ON cfg.EXCLUSION (CLIENTE, TIPO, VALOR) WHERE ACTIVO = 1;
GO

/* Catálogos de apoyo */
IF OBJECT_ID('cfg.CP_ESTADO') IS NULL
CREATE TABLE cfg.CP_ESTADO (
    CP_INI  CHAR(5)    NOT NULL CONSTRAINT PK_CP_ESTADO PRIMARY KEY,
    CP_FIN  CHAR(5)    NOT NULL,
    ESTADO  VARCHAR(5) NOT NULL
);
GO
IF OBJECT_ID('cfg.LADA') IS NULL
CREATE TABLE cfg.LADA (
    CP    CHAR(5)    NOT NULL CONSTRAINT PK_LADA PRIMARY KEY,
    LADA  VARCHAR(5) NOT NULL
);
GO
/* Plan de numeración (hoy pnc.dbf): rangos para clasificar fijo / móvil */
IF OBJECT_ID('cfg.PLAN_NUMERACION') IS NULL
CREATE TABLE cfg.PLAN_NUMERACION (
    LADA     VARCHAR(3)  NOT NULL,
    SERIE    VARCHAR(4)  NOT NULL,
    N_INI    INT         NOT NULL,
    N_FIN    INT         NOT NULL,
    TIPORED  VARCHAR(10) NOT NULL,              -- FIJO / MOVIL
    CONSTRAINT PK_PLAN_NUMERACION PRIMARY KEY (LADA, SERIE, N_INI)
);
GO
/* Teléfonos dados de baja (quejas) leídos de CYBER en cada asignación (telbaj, telbaj1, TENOVA1 del grupo).
   Se reemplaza completa cada vez que la lectura sale bien; si falla se conserva la última. */
IF OBJECT_ID('cfg.TEL_QUEJA_CYBER') IS NULL
CREATE TABLE cfg.TEL_QUEJA_CYBER (
    CUENTA    VARCHAR(30) NOT NULL,
    TELEFONO  VARCHAR(10) NOT NULL,
    FE_CARGA  DATETIME2(0) NOT NULL CONSTRAINT DF_TEL_QUEJA_CYBER_FE DEFAULT SYSDATETIME(),
    CONSTRAINT PK_TEL_QUEJA_CYBER PRIMARY KEY (CUENTA, TELEFONO)
);
GO

/* ---------------------------------------------------------------------
   Catálogos estáticos de etiquetado (decisión 17/11)
   ---------------------------------------------------------------------
   Lo que antes estaba escrito en el código de la homologación (estatus,
   tipo de crédito, cartera, enfoque, tramo…) ahora es una tabla que el equipo
   de asignaciones edita: cambia o agrega un valor y la próxima corrida lo usa.
   - VALOR_ORIGEN: el texto como llega del banco. Sin acentos ni mayúsculas.
     Admite comodines de LIKE (% y [0-9]); el valor exacto gana sobre el patrón.
   - VALOR_DESTINO: la etiqueta que se guarda ('' = se deja vacío a propósito).
   - ORDEN: entre patrones que coinciden, gana el ORDEN menor.
   - Para quitar un valor: ACTIVO = 0 (si se borra, la semilla lo vuelve a poner).
   La semilla solo agrega los valores que faltan: nunca cambia ni borra lo del equipo.
   Si un catálogo tiene VALIDA = 1, un valor que no esté en él detiene el proceso
   (validación de datos de la entrada, cfg.VALIDACION_DATO tipo CATALOGO).
   --------------------------------------------------------------------- */
IF OBJECT_ID('cfg.CATALOGO_DEF') IS NULL
CREATE TABLE cfg.CATALOGO_DEF (
    CLIENTE      VARCHAR(10)    NOT NULL,
    CATALOGO     VARCHAR(40)    NOT NULL,
    DESCRIPCION  NVARCHAR(400)  NOT NULL,
    ORIGEN       NVARCHAR(200)  NULL,               -- archivo y columna de donde sale el valor
    DESTINO      NVARCHAR(200)  NULL,               -- campo que llena
    CONSTRAINT PK_CATALOGO_DEF PRIMARY KEY (CLIENTE, CATALOGO)
);
GO
IF OBJECT_ID('cfg.CATALOGO') IS NULL
CREATE TABLE cfg.CATALOGO (
    ID             INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_CATALOGO PRIMARY KEY,
    CLIENTE        VARCHAR(10)    NOT NULL,
    CATALOGO       VARCHAR(40)    NOT NULL,
    VALOR_ORIGEN   NVARCHAR(200)  NOT NULL,
    VALOR_DESTINO  NVARCHAR(200)  NOT NULL CONSTRAINT DF_CATALOGO_DESTINO DEFAULT N'',
    ORDEN          INT            NOT NULL CONSTRAINT DF_CATALOGO_ORDEN DEFAULT 100,
    ACTIVO         BIT            NOT NULL CONSTRAINT DF_CATALOGO_ACT DEFAULT 1,
    COMENTARIO     NVARCHAR(400)  NULL,
    ALTA_POR       VARCHAR(10)    NOT NULL CONSTRAINT DF_CATALOGO_ALTA DEFAULT 'EQUIPO',   -- SEMILLA / EQUIPO
    USUARIO        SYSNAME        NOT NULL CONSTRAINT DF_CATALOGO_USR DEFAULT SUSER_SNAME(),
    FE_MOD         DATETIME2(0)   NOT NULL CONSTRAINT DF_CATALOGO_FE DEFAULT SYSDATETIME(),
    CONSTRAINT UX_CATALOGO UNIQUE (CLIENTE, CATALOGO, VALOR_ORIGEN)
);
GO
CREATE OR ALTER TRIGGER cfg.tr_CATALOGO_EDICION ON cfg.CATALOGO AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF TRY_CONVERT(INT, SESSION_CONTEXT(N'SEMILLA')) = 1 RETURN;
    IF NOT (UPDATE(VALOR_ORIGEN) OR UPDATE(VALOR_DESTINO) OR UPDATE(ORDEN) OR UPDATE(ACTIVO)) RETURN;
    UPDATE c SET USUARIO = SUSER_SNAME(), FE_MOD = SYSDATETIME()
    FROM cfg.CATALOGO c JOIN inserted i ON i.ID = c.ID;
END;
GO

/* ---------------------------------------------------------------------
   Validación de datos de la entrada (decisión 17/11)
   ---------------------------------------------------------------------
   Antes de tocar el DAT, cada archivo se revisa columna por columna. Si una
   regla encuentra más anomalías que su tolerancia, el proceso se detiene,
   se avisa al equipo de asignaciones (VALIDACION_ENTRADA_486) y se corre de
   nuevo a mano cuando se corrige. TIPO:
     IMPORTE      el texto no es un importe ("abc", "N/A")
     NO_NEGATIVO  importe menor que cero
     MAXIMO       importe mayor que VALOR (ej. 10000000): suele ser una cuenta en la columna de saldo
     ENTERO       el texto no es un número entero (días de mora)
     TELEFONO     trae letras o no tiene entre VALOR dígitos ('10-12'); '0' y '-' cuentan como vacío
     CORREO       no tiene forma de correo (sin @, con espacios, sin dominio); '0' y '-' cuentan como vacío
     CATALOGO     el valor no está en el catálogo VALOR (cfg.CATALOGO): segmento o estatus nuevo
     LLAVE_UNICA  la cuenta viene repetida en el archivo
     NO_VACIO     la columna viene vacía (en un % mayor a la tolerancia, la columna se corrió o cambió)
     VOLUMEN      el archivo trae menos o más renglones que la última carga buena: VALOR = 'mínimo-máximo' en %
   PCT_MAX: % de anomalías tolerado sobre los valores revisados (0 = ninguna).
   La semilla solo agrega las reglas que faltan: el equipo ajusta VALOR, PCT_MAX y ACTIVO.
   --------------------------------------------------------------------- */
IF OBJECT_ID('cfg.VALIDACION_DATO') IS NULL
CREATE TABLE cfg.VALIDACION_DATO (
    ID           INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_VALIDACION_DATO PRIMARY KEY,
    CLIENTE      VARCHAR(10)    NOT NULL,
    CODIGO       VARCHAR(50)    NOT NULL,           -- archivo (cfg.ARCHIVO.CODIGO)
    CAMPO        SYSNAME        NOT NULL,           -- cfg.ARCHIVO_COLUMNA.CAMPO_DESTINO; '*' para VOLUMEN
    TIPO         VARCHAR(15)    NOT NULL,
    VALOR        NVARCHAR(100)  NULL,
    PCT_MAX      DECIMAL(5,2)   NOT NULL CONSTRAINT DF_VALIDACION_DATO_PCT DEFAULT 0,
    ACTIVO       BIT            NOT NULL CONSTRAINT DF_VALIDACION_DATO_ACT DEFAULT 1,
    DESCRIPCION  NVARCHAR(400)  NULL,
    USUARIO      SYSNAME        NOT NULL CONSTRAINT DF_VALIDACION_DATO_USR DEFAULT SUSER_SNAME(),
    FE_MOD       DATETIME2(0)   NOT NULL CONSTRAINT DF_VALIDACION_DATO_FE DEFAULT SYSDATETIME(),
    CONSTRAINT UX_VALIDACION_DATO UNIQUE (CLIENTE, CODIGO, CAMPO, TIPO),
    CONSTRAINT CK_VALIDACION_DATO_TIPO CHECK (TIPO IN ('IMPORTE','NO_NEGATIVO','MAXIMO','ENTERO','TELEFONO','CORREO',
                                                       'CATALOGO','LLAVE_UNICA','NO_VACIO','VOLUMEN','DIGITOS','ARCHIVO_IGUAL','CRUCE_DAT'))
);
GO
/* 20/11: DIGITOS (solo dígitos y largo), ARCHIVO_IGUAL (idéntico al último archivo bueno) y CRUCE_DAT (renglones cuya
   llave no está en el DAT) */
IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_VALIDACION_DATO_TIPO' AND definition NOT LIKE '%CRUCE_DAT%')
BEGIN
    ALTER TABLE cfg.VALIDACION_DATO DROP CONSTRAINT CK_VALIDACION_DATO_TIPO;
    ALTER TABLE cfg.VALIDACION_DATO ADD CONSTRAINT CK_VALIDACION_DATO_TIPO CHECK (TIPO IN ('IMPORTE','NO_NEGATIVO','MAXIMO','ENTERO','TELEFONO','CORREO',
                                                       'CATALOGO','LLAVE_UNICA','NO_VACIO','VOLUMEN','DIGITOS','ARCHIVO_IGUAL','CRUCE_DAT'));
END;
GO
CREATE OR ALTER TRIGGER cfg.tr_VALIDACION_DATO_EDICION ON cfg.VALIDACION_DATO AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF TRY_CONVERT(INT, SESSION_CONTEXT(N'SEMILLA')) = 1 RETURN;
    IF NOT (UPDATE(VALOR) OR UPDATE(PCT_MAX) OR UPDATE(ACTIVO)) RETURN;
    UPDATE v SET USUARIO = SUSER_SNAME(), FE_MOD = SYSDATETIME()
    FROM cfg.VALIDACION_DATO v JOIN inserted i ON i.ID = v.ID;
END;
GO

/* =====================================================================
   Vistas de usuarios (18/11): qué datos ve cada usuario externo (AEM, MIS…).
   Las edita el equipo de asignaciones; ops.sp_vistas_usuario_armar arma con
   ellas la tabla <ESQUEMA>.DAT_486 de cada usuario en la actualización y en
   la asignación. La semilla solo agrega lo que falta.
   ===================================================================== */
IF OBJECT_ID('cfg.VISTA_USUARIO') IS NULL
CREATE TABLE cfg.VISTA_USUARIO (
    CLIENTE      VARCHAR(10)    NOT NULL,
    VISTA        VARCHAR(30)    NOT NULL,           -- AEM, MIS…; también es el esquema (en minúsculas)
    LOGIN        SYSNAME        NULL,               -- login de SQL Server (cfg.sp_vista_usuario_login)
    VER_RETIROS  BIT            NOT NULL CONSTRAINT DF_VISTA_USUARIO_RET DEFAULT 0,   -- 1 = también ve <esquema>.RETIROS_HOY
    ACTIVO       BIT            NOT NULL CONSTRAINT DF_VISTA_USUARIO_ACT DEFAULT 1,   -- 0 = se borra su tabla y deja de ver datos
    DESCRIPCION  NVARCHAR(400)  NULL,
    USUARIO      SYSNAME        NOT NULL CONSTRAINT DF_VISTA_USUARIO_USR DEFAULT SUSER_SNAME(),
    FE_MOD       DATETIME2(0)   NOT NULL CONSTRAINT DF_VISTA_USUARIO_FE DEFAULT SYSDATETIME(),
    CONSTRAINT PK_VISTA_USUARIO PRIMARY KEY (CLIENTE, VISTA),
    CONSTRAINT CK_VISTA_USUARIO_NOMBRE CHECK (VISTA NOT LIKE '%[^A-Za-z0-9_]%' AND VISTA LIKE '[A-Za-z]%')
);
GO
IF OBJECT_ID('cfg.VISTA_COLUMNA') IS NULL
CREATE TABLE cfg.VISTA_COLUMNA (
    ID           INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_VISTA_COLUMNA PRIMARY KEY,
    CLIENTE      VARCHAR(10)    NOT NULL,
    VISTA        VARCHAR(30)    NOT NULL,
    ORDEN        INT            NOT NULL,
    ENCABEZADO   NVARCHAR(128)  NOT NULL,           -- nombre de la columna tal como lo debe ver el usuario
    ORIGEN       VARCHAR(10)    NOT NULL,           -- DAT | CYBER | MAESTRA | CONSTANTE
    CAMPO        NVARCHAR(200)  NOT NULL,           -- columna del DAT, campo de cfg.CYBER_CAMPO, encabezado de la base maestra o valor fijo
    ACTIVO       BIT            NOT NULL CONSTRAINT DF_VISTA_COLUMNA_ACT DEFAULT 1,
    DESCRIPCION  NVARCHAR(400)  NULL,
    USUARIO      SYSNAME        NOT NULL CONSTRAINT DF_VISTA_COLUMNA_USR DEFAULT SUSER_SNAME(),
    FE_MOD       DATETIME2(0)   NOT NULL CONSTRAINT DF_VISTA_COLUMNA_FE DEFAULT SYSDATETIME(),
    CONSTRAINT UX_VISTA_COLUMNA UNIQUE (CLIENTE, VISTA, ENCABEZADO),
    CONSTRAINT CK_VISTA_COLUMNA_ORIGEN CHECK (ORIGEN IN ('DAT','CYBER','MAESTRA','CONSTANTE'))
);
GO
CREATE OR ALTER TRIGGER cfg.tr_VISTA_USUARIO_EDICION ON cfg.VISTA_USUARIO AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF TRY_CONVERT(INT, SESSION_CONTEXT(N'SEMILLA')) = 1 RETURN;
    UPDATE v SET USUARIO = SUSER_SNAME(), FE_MOD = SYSDATETIME()
    FROM cfg.VISTA_USUARIO v JOIN inserted i ON i.CLIENTE = v.CLIENTE AND i.VISTA = v.VISTA;
END;
GO
CREATE OR ALTER TRIGGER cfg.tr_VISTA_COLUMNA_EDICION ON cfg.VISTA_COLUMNA AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF TRY_CONVERT(INT, SESSION_CONTEXT(N'SEMILLA')) = 1 RETURN;
    IF NOT (UPDATE(ORDEN) OR UPDATE(ENCABEZADO) OR UPDATE(ORIGEN) OR UPDATE(CAMPO) OR UPDATE(ACTIVO)) RETURN;
    UPDATE v SET USUARIO = SUSER_SNAME(), FE_MOD = SYSDATETIME()
    FROM cfg.VISTA_COLUMNA v JOIN inserted i ON i.ID = v.ID;
END;
GO

/* =====================================================================
   Ladas válidas (19/11): copia estática de la tabla PHNVAL de CYBER, las ladas
   y longitudes que admite el cargador al subir los teléfonos. Un teléfono cuya
   AREA + longitud no está aquí no va al SCBTEL ni a la remesa.
   La actualiza ops.sp_phnval_actualizar (job "Banbaj 486 ladas", día 1 de cada mes).
   ===================================================================== */
IF OBJECT_ID('cfg.PHNVAL') IS NULL
CREATE TABLE cfg.PHNVAL (
    VTARECOD  VARCHAR(10)    NOT NULL,           -- lada como la manda el SCBTEL (AREA): 0155, 01222, 044, 045…
    VTLENGTH  INT            NOT NULL,           -- dígitos que debe tener el TELEFONO con esa lada
    VTCOMUNA  NVARCHAR(60)   NULL,
    FE_CARGA  DATETIME2(0)   NOT NULL CONSTRAINT DF_PHNVAL_FE DEFAULT SYSDATETIME(),
    CONSTRAINT PK_PHNVAL PRIMARY KEY (VTARECOD, VTLENGTH)
);
GO
IF OBJECT_ID('cfg.PHNVAL_CARGA') IS NULL
CREATE TABLE cfg.PHNVAL_CARGA (
    ID         INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_PHNVAL_CARGA PRIMARY KEY,
    FE_INICIO  DATETIME2(0)   NOT NULL CONSTRAINT DF_PHNVAL_CARGA_FE DEFAULT SYSDATETIME(),
    FE_FIN     DATETIME2(0)   NULL,
    ESTATUS    VARCHAR(10)    NOT NULL,           -- OK | ERROR
    FILAS      INT            NULL,               -- renglones que llegaron de CYBER
    ALTAS      INT            NULL,
    BAJAS      INT            NULL,
    MENSAJE    NVARCHAR(4000) NULL,
    USUARIO    SYSNAME        NOT NULL CONSTRAINT DF_PHNVAL_CARGA_USR DEFAULT SUSER_SNAME()
);
GO
IF OBJECT_ID('stg.CYBER_PHNVAL') IS NULL
CREATE TABLE stg.CYBER_PHNVAL (VTCOMUNA NVARCHAR(60) NULL, VTARECOD NVARCHAR(20) NULL, VTLENGTH NVARCHAR(10) NULL);
GO

/* Campos de CYBER que pueden usar las vistas de usuarios (19/11): cada uno es una columna (o expresión de Oracle) de
   d = DELQMST (cuentas activas del cliente), u = UDA1 o r = RPT_DAT_486_1 tal como esté en CYBER. ops.sp_dat_cyber_bajar
   los baja directo de las tablas, sin ejecutar ningún store. Los mantiene sistemas; la semilla solo agrega lo que falta. */
IF OBJECT_ID('cfg.CYBER_CAMPO') IS NULL
CREATE TABLE cfg.CYBER_CAMPO (
    CAMPO        VARCHAR(30)    NOT NULL CONSTRAINT PK_CYBER_CAMPO PRIMARY KEY,
    EXPRESION    NVARCHAR(400)  NOT NULL,
    DESCRIPCION  NVARCHAR(400)  NULL,
    ACTIVO       BIT            NOT NULL CONSTRAINT DF_CYBER_CAMPO_ACT DEFAULT 1,
    CONSTRAINT CK_CYBER_CAMPO_NOMBRE CHECK (CAMPO NOT LIKE '%[^A-Z0-9_]%')
);
GO
