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
    CONSTRAINT UX_ARCHIVO_CODIGO UNIQUE (CLIENTE, CODIGO),
    CONSTRAINT CK_ARCHIVO_PROCESO CHECK (PROCESO IN ('ASIG','ACT'))
);
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

/* Campos de los archivos de salida de ancho fijo (SCBSDOS, SCBTEL…).
   EXPRESION es SQL sobre el DAT con alias d.
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

/* Etiquetas externas por cuenta (hoy DBF sueltas: eti486, eti, dm1, top, STATUS, covid, garantizada) */
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
