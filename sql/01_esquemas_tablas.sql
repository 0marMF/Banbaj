/* =====================================================================
   Banbaj · 01 Esquemas y tablas base
   ---------------------------------------------------------------------
   Esquemas:
     dat  -> tablas FIJAS del negocio (DAT por cliente e histórico de folios)
     cfg  -> catálogos editables (archivos, columnas, homologación, reglas,
             salidas, etiquetas, exclusiones, parámetros)
     stg  -> tablas de trabajo que se recrean en cada corrida
     ops  -> operación: corridas, bitácora, rechazos, devoluciones, salidas
     mail -> listas de distribución y plantillas de correo
   Requiere SQL Server 2017 o superior (STRING_AGG, BULK INSERT FORMAT='CSV').
   Ejecutar en la base de datos destino (ej. USE BD_EXT;).
   ===================================================================== */
SET NOCOUNT ON;
GO
IF SCHEMA_ID('dat')  IS NULL EXEC('CREATE SCHEMA dat');
IF SCHEMA_ID('cfg')  IS NULL EXEC('CREATE SCHEMA cfg');
IF SCHEMA_ID('stg')  IS NULL EXEC('CREATE SCHEMA stg');
IF SCHEMA_ID('ops')  IS NULL EXEC('CREATE SCHEMA ops');
IF SCHEMA_ID('mail') IS NULL EXEC('CREATE SCHEMA mail');
GO

/* ---------------------------------------------------------------------
   HISTÓRICO DE FOLIOS (tabla fija)
   Sustituye a tab7 (consecutivo), historia (altas) y PURGA/DEVOL (bajas).
   --------------------------------------------------------------------- */
IF OBJECT_ID('dat.FOLIO_CONSECUTIVO') IS NULL
CREATE TABLE dat.FOLIO_CONSECUTIVO (
    CLIENTE       VARCHAR(10)  NOT NULL CONSTRAINT PK_FOLIO_CONSECUTIVO PRIMARY KEY,
    ULTIMO_FOLIO  INT          NOT NULL,
    FE_ACT        DATETIME2(0) NOT NULL CONSTRAINT DF_FOLIO_CONSECUTIVO_FE DEFAULT SYSDATETIME()
);
GO
IF OBJECT_ID('dat.HISTORIA_FOLIO') IS NULL
CREATE TABLE dat.HISTORIA_FOLIO (
    ID            BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_HISTORIA_FOLIO PRIMARY KEY,
    CLIENTE       VARCHAR(10)   NOT NULL,
    CUENTA        VARCHAR(20)   NOT NULL,            -- crédito del banco (DAT.CUENTA)
    FOLIO         INT           NOT NULL,
    CUENTA2       VARCHAR(28)   NOT NULL,            -- cuenta en CYBER ('486-'+FOLIO)
    SEGMENTO2     VARCHAR(20)   NULL,
    SUB_CTE       VARCHAR(3)    NOT NULL,            -- NVA / REA
    ESTATUS       CHAR(1)       NOT NULL CONSTRAINT DF_HISTORIA_FOLIO_EST DEFAULT 'A',  -- A=activa, B=baja
    FE_ALTA       DATE          NOT NULL,
    FE_BAJA       DATE          NULL,
    MOTIVO_BAJA   VARCHAR(60)   NULL,
    ID_CORRIDA_ALTA INT         NULL,
    ID_CORRIDA_BAJA INT         NULL,
    DATOS_BAJA    NVARCHAR(MAX) NULL,                -- foto JSON del registro del DAT al darse de baja
    CONSTRAINT CK_HISTORIA_FOLIO_EST CHECK (ESTATUS IN ('A','B')),
    CONSTRAINT CK_HISTORIA_FOLIO_SUB CHECK (SUB_CTE IN ('NVA','REA'))
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_HISTORIA_FOLIO_CUENTA')
    CREATE INDEX IX_HISTORIA_FOLIO_CUENTA ON dat.HISTORIA_FOLIO (CLIENTE, CUENTA, FE_ALTA DESC) INCLUDE (FOLIO, ESTATUS);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_HISTORIA_FOLIO_FOLIO_ACTIVO')
    CREATE UNIQUE INDEX UX_HISTORIA_FOLIO_FOLIO_ACTIVO ON dat.HISTORIA_FOLIO (CLIENTE, FOLIO) WHERE ESTATUS = 'A';
GO

/* ---------------------------------------------------------------------
   OPERACIÓN
   --------------------------------------------------------------------- */
IF OBJECT_ID('ops.CORRIDA') IS NULL
CREATE TABLE ops.CORRIDA (
    ID_CORRIDA     INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_CORRIDA PRIMARY KEY,
    CLIENTE        VARCHAR(10)   NOT NULL,
    PROCESO        VARCHAR(10)   NOT NULL,           -- ASIG / ACT
    FECHA_PROCESO  DATE          NOT NULL,
    HORA_LLEGADA   TIME(0)       NULL,               -- hora en que llegó la información del banco
    INICIO         DATETIME2(0)  NOT NULL CONSTRAINT DF_CORRIDA_INICIO DEFAULT SYSDATETIME(),
    FIN            DATETIME2(0)  NULL,
    ESTATUS        VARCHAR(15)   NOT NULL CONSTRAINT DF_CORRIDA_ESTATUS DEFAULT 'EN_PROCESO',
    USUARIO        SYSNAME       NOT NULL CONSTRAINT DF_CORRIDA_USUARIO DEFAULT SUSER_SNAME(),
    MENSAJE        NVARCHAR(4000) NULL,
    CONSTRAINT CK_CORRIDA_PROCESO CHECK (PROCESO IN ('ASIG','ACT')),
    CONSTRAINT CK_CORRIDA_ESTATUS CHECK (ESTATUS IN ('EN_PROCESO','OK','ERROR','CANCELADA'))
);
GO
IF OBJECT_ID('ops.BITACORA') IS NULL
CREATE TABLE ops.BITACORA (
    ID          BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_BITACORA PRIMARY KEY,
    ID_CORRIDA  INT            NOT NULL,
    FECHA       DATETIME2(0)   NOT NULL CONSTRAINT DF_BITACORA_FECHA DEFAULT SYSDATETIME(),
    PASO        VARCHAR(80)    NOT NULL,
    ESTATUS     VARCHAR(15)    NOT NULL,             -- INICIO / OK / AVISO / ERROR
    REGISTROS   INT            NULL,
    MENSAJE     NVARCHAR(4000) NULL
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_BITACORA_CORRIDA')
    CREATE INDEX IX_BITACORA_CORRIDA ON ops.BITACORA (ID_CORRIDA, ID);
GO
IF OBJECT_ID('ops.ARCHIVO_CARGADO') IS NULL
CREATE TABLE ops.ARCHIVO_CARGADO (
    ID_CORRIDA   INT           NOT NULL,
    ID_ARCHIVO   INT           NOT NULL,
    RUTA         NVARCHAR(500) NULL,
    LEIDOS       INT           NULL,
    INSERTADOS   INT           NULL,
    RECHAZADOS   INT           NULL,
    ESTATUS      VARCHAR(15)   NOT NULL,             -- CARGADO / NO_RECIBIDO / ERROR
    FECHA        DATETIME2(0)  NOT NULL CONSTRAINT DF_ARCHIVO_CARGADO_FECHA DEFAULT SYSDATETIME(),
    CONSTRAINT PK_ARCHIVO_CARGADO PRIMARY KEY (ID_CORRIDA, ID_ARCHIVO)
);
GO
IF OBJECT_ID('ops.RECHAZO') IS NULL
CREATE TABLE ops.RECHAZO (
    ID          BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_RECHAZO PRIMARY KEY,
    ID_CORRIDA  INT            NOT NULL,
    ORIGEN      VARCHAR(100)   NOT NULL,             -- código de archivo o de regla
    FILA        INT            NULL,
    MOTIVO      NVARCHAR(1000) NOT NULL,
    DATOS       NVARCHAR(MAX)  NULL,                 -- registro en JSON
    FECHA       DATETIME2(0)   NOT NULL CONSTRAINT DF_RECHAZO_FECHA DEFAULT SYSDATETIME()
);
GO
IF OBJECT_ID('ops.DEVOLUCION') IS NULL
CREATE TABLE ops.DEVOLUCION (
    ID_CORRIDA  INT          NOT NULL,
    CLIENTE     VARCHAR(10)  NOT NULL,
    CUENTA      VARCHAR(20)  NOT NULL,
    SEGMENTO2   VARCHAR(20)  NULL,
    MOTIVO      VARCHAR(100) NOT NULL,
    ORIGEN      VARCHAR(100) NOT NULL,
    PROCESADA   BIT          NOT NULL CONSTRAINT DF_DEVOLUCION_PROC DEFAULT 0,
    FECHA       DATETIME2(0) NOT NULL CONSTRAINT DF_DEVOLUCION_FECHA DEFAULT SYSDATETIME(),
    CONSTRAINT PK_DEVOLUCION PRIMARY KEY (ID_CORRIDA, CUENTA)
);
GO
IF OBJECT_ID('ops.SALIDA_LINEA') IS NULL
CREATE TABLE ops.SALIDA_LINEA (
    ID_CORRIDA  INT            NOT NULL,
    ARCHIVO     VARCHAR(50)    NOT NULL,
    NUM         INT            NOT NULL,
    LINEA       NVARCHAR(4000) NOT NULL,
    CONSTRAINT PK_SALIDA_LINEA PRIMARY KEY (ID_CORRIDA, ARCHIVO, NUM)
);
GO
/* Sentencias para CYBER (Oracle). Se generan aquí y se ejecutan con sqlplus
   o por linked server cuando el operador autoriza el arribo. */
IF OBJECT_ID('ops.CYBER_SCRIPT') IS NULL
CREATE TABLE ops.CYBER_SCRIPT (
    ID_CORRIDA  INT            NOT NULL,
    SCRIPT      VARCHAR(50)    NOT NULL,             -- ACT_SALDOS / ACT_VENCIDO / ACT_PAGMIN / RETIRO ...
    NUM         INT            NOT NULL,
    SENTENCIA   NVARCHAR(4000) NOT NULL,
    CONSTRAINT PK_CYBER_SCRIPT PRIMARY KEY (ID_CORRIDA, SCRIPT, NUM)
);
GO
/* Pagos recibidos: se conservan para no arribar dos veces el mismo pago
   (llave CUENTA2 + IMPORTE + FECHA, regla del documento de actualización). */
IF OBJECT_ID('ops.PAGO') IS NULL
CREATE TABLE ops.PAGO (
    ID          BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_PAGO PRIMARY KEY,
    CLIENTE     VARCHAR(10)    NOT NULL,
    CUENTA2     VARCHAR(28)    NOT NULL,
    IMPORTE     DECIMAL(18,2)  NOT NULL,
    FECHA       DATE           NOT NULL,
    TRX         VARCHAR(50)    NULL,
    EMPRESA     VARCHAR(50)    NULL,
    ID_CORRIDA  INT            NOT NULL,
    ESTATUS     VARCHAR(15)    NOT NULL CONSTRAINT DF_PAGO_ESTATUS DEFAULT 'NUEVO',   -- NUEVO / ARRIBADO
    FE_REG      DATETIME2(0)   NOT NULL CONSTRAINT DF_PAGO_FE DEFAULT SYSDATETIME()
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_PAGO_LLAVE')
    CREATE UNIQUE INDEX UX_PAGO_LLAVE ON ops.PAGO (CLIENTE, CUENTA2, IMPORTE, FECHA);
GO
