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
    PROCESO        VARCHAR(10)   NOT NULL,           -- ASIG / ACT / RET (retiro por solicitud)
    FECHA_PROCESO  DATE          NOT NULL,
    HORA_LLEGADA   TIME(0)       NULL,               -- hora en que llegó la información del banco
    INICIO         DATETIME2(0)  NOT NULL CONSTRAINT DF_CORRIDA_INICIO DEFAULT SYSDATETIME(),
    FIN            DATETIME2(0)  NULL,
    ESTATUS        VARCHAR(15)   NOT NULL CONSTRAINT DF_CORRIDA_ESTATUS DEFAULT 'EN_PROCESO',
    USUARIO        SYSNAME       NOT NULL CONSTRAINT DF_CORRIDA_USUARIO DEFAULT SUSER_SNAME(),
    MENSAJE        NVARCHAR(4000) NULL,
    CONSTRAINT CK_CORRIDA_PROCESO CHECK (PROCESO IN ('ASIG','ACT','RET')),
    CONSTRAINT CK_CORRIDA_ESTATUS CHECK (ESTATUS IN ('EN_PROCESO','OK','ERROR','CANCELADA','REVERTIDA'))
);
GO
/* Bases creadas antes del retiro por solicitud: se agrega 'RET' al check */
IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_CORRIDA_PROCESO' AND definition NOT LIKE '%RET%')
BEGIN
    ALTER TABLE ops.CORRIDA DROP CONSTRAINT CK_CORRIDA_PROCESO;
    ALTER TABLE ops.CORRIDA ADD CONSTRAINT CK_CORRIDA_PROCESO CHECK (PROCESO IN ('ASIG','ACT','RET'));
END;
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
/* Respaldo por corrida para el retroceso (ops.sp_revertir_corrida).
   La copia del DAT va en ops.RESPALDO_DAT_486 (se crea junto con el DAT). */
IF OBJECT_ID('ops.RESPALDO_CONTROL') IS NULL
CREATE TABLE ops.RESPALDO_CONTROL (
    ID_CORRIDA    INT          NOT NULL CONSTRAINT PK_RESPALDO_CONTROL PRIMARY KEY,
    CLIENTE       VARCHAR(10)  NOT NULL,
    ULTIMO_FOLIO  INT          NULL,
    REGISTROS     INT          NOT NULL,
    FECHA         DATETIME2(0) NOT NULL CONSTRAINT DF_RESPALDO_CONTROL_FECHA DEFAULT SYSDATETIME()
);
GO
/* Pagos arribados (antes PAGTOT.DBF). Tabla fija: de PAGTOT solo importan los campos
   con los que se valida que un pago no se arribe dos veces (pagos.prg):
   CUENTA + FE_PAG + importe. IDE '500', GRUPO '1', SEGMENTO 'pbank', AGEN 'SERTEC'
   y TRAN 'PAGO' son constantes del layout SCBPAG y no se guardan; MOREAL repite MONT.
   ID_CORRIDA = 0 y ORIGEN = 'PAGTOT' para lo migrado. */
IF OBJECT_ID('dat.PAGO_ARRIBADO') IS NULL
CREATE TABLE dat.PAGO_ARRIBADO (
    ID          BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_PAGO_ARRIBADO PRIMARY KEY,
    CLIENTE     VARCHAR(10)    NOT NULL,
    CUENTA      VARCHAR(25)    NOT NULL,              -- crédito del banco (DAT.CUENTA), como va en SCBPAG
    CUENTA2     VARCHAR(28)    NULL,                  -- 486-folio (para cuadrar contra lo que baja de CYBER)
    FE_PAG      DATE           NOT NULL,
    IMPORTE     DECIMAL(15,2)  NOT NULL,
    FE_REG      DATE           NULL,                  -- día en que se arribó
    ID_CORRIDA  INT            NOT NULL,
    ORIGEN      VARCHAR(10)    NOT NULL CONSTRAINT DF_PAGO_ARRIBADO_ORIGEN DEFAULT 'CORRIDA'   -- CORRIDA / PAGTOT
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_PAGO_ARRIBADO_LLAVE')
    CREATE INDEX IX_PAGO_ARRIBADO_LLAVE ON dat.PAGO_ARRIBADO (CLIENTE, CUENTA, FE_PAG, IMPORTE);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_PAGO_ARRIBADO_CORRIDA')
    CREATE INDEX IX_PAGO_ARRIBADO_CORRIDA ON dat.PAGO_ARRIBADO (ID_CORRIDA);
GO
/* Teléfonos que se arriban a CYBER en la asignación (antes TELSAN.DBF): uno por
   cuenta + área + teléfono. CYBER (RCVRY.JSP_TELEFONOS_REMESA_486) purga y agrega. */
IF OBJECT_ID('ops.TELEFONO') IS NULL
CREATE TABLE ops.TELEFONO (
    ID_CORRIDA  INT          NOT NULL,
    CUENTA2     VARCHAR(28)  NOT NULL,
    AREA        VARCHAR(5)   NOT NULL,
    TELEFONO    VARCHAR(13)  NOT NULL,
    TIPOTEL     CHAR(1)      NOT NULL,                -- 1 = TEL1, 2 = TEL2, 4 = otro fijo, 5 = celular
    CAMPO_DAT   VARCHAR(10)  NOT NULL,                -- TEL1..TEL16 de donde salió
    CONSTRAINT PK_TELEFONO PRIMARY KEY (ID_CORRIDA, CUENTA2, AREA, TELEFONO)
);
GO
