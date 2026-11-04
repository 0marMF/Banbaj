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
    RIESGO        VARCHAR(35)   NULL,                -- crédito con el que llegan los pagos (DAT.RIESGO)
    SUB_CTE       VARCHAR(3)    NOT NULL,            -- NVA / REA
    ESTATUS       CHAR(1)       NOT NULL CONSTRAINT DF_HISTORIA_FOLIO_EST DEFAULT 'A',  -- A=activa, B=baja
    FE_ALTA       DATE          NULL,                -- vacía en los periodos migrados de historia.dbf (decisión 03/11)
    FE_BAJA       DATE          NULL,
    MOTIVO_BAJA   VARCHAR(60)   NULL,
    ID_CORRIDA_ALTA INT         NULL,
    ID_CORRIDA_BAJA INT         NULL,
    DATOS_BAJA    NVARCHAR(MAX) NULL,                -- foto JSON del registro del DAT al darse de baja
    CONSTRAINT CK_HISTORIA_FOLIO_EST CHECK (ESTATUS IN ('A','B')),
    CONSTRAINT CK_HISTORIA_FOLIO_SUB CHECK (SUB_CTE IN ('NVA','REA'))
);
GO
/* Bases creadas antes del 03/11: FE_ALTA pasa a aceptar vacío (el índice se vuelve a crear abajo) */
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dat.HISTORIA_FOLIO') AND name = 'FE_ALTA' AND is_nullable = 0)
BEGIN
    IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_HISTORIA_FOLIO_CUENTA' AND object_id = OBJECT_ID('dat.HISTORIA_FOLIO'))
        DROP INDEX IX_HISTORIA_FOLIO_CUENTA ON dat.HISTORIA_FOLIO;
    ALTER TABLE dat.HISTORIA_FOLIO ALTER COLUMN FE_ALTA DATE NULL;
END;
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
    PROCESO        VARCHAR(10)   NOT NULL,           -- ASIG / ACT / RET (retiro por solicitud) / ETI (etiquetado manual)
    FECHA_PROCESO  DATE          NOT NULL,
    HORA_LLEGADA   TIME(0)       NULL,               -- hora en que llegó la información del banco
    INICIO         DATETIME2(0)  NOT NULL CONSTRAINT DF_CORRIDA_INICIO DEFAULT SYSDATETIME(),
    FIN            DATETIME2(0)  NULL,
    ESTATUS        VARCHAR(15)   NOT NULL CONSTRAINT DF_CORRIDA_ESTATUS DEFAULT 'EN_PROCESO',
    USUARIO        SYSNAME       NOT NULL CONSTRAINT DF_CORRIDA_USUARIO DEFAULT SUSER_SNAME(),
    MENSAJE        NVARCHAR(4000) NULL,
    CONSTRAINT CK_CORRIDA_PROCESO CHECK (PROCESO IN ('ASIG','ACT','RET','ETI')),
    CONSTRAINT CK_CORRIDA_ESTATUS CHECK (ESTATUS IN ('EN_PROCESO','OK','ERROR','CANCELADA','REVERTIDA')),
    REVERTIDA_AUTO BIT          NOT NULL CONSTRAINT DF_CORRIDA_REV_AUTO DEFAULT 0   -- 1 = falló y se revirtió sola (conserva ERROR / CANCELADA)
);
GO
IF COL_LENGTH('ops.CORRIDA', 'REVERTIDA_AUTO') IS NULL
    ALTER TABLE ops.CORRIDA ADD REVERTIDA_AUTO BIT NOT NULL CONSTRAINT DF_CORRIDA_REV_AUTO DEFAULT 0;
GO
/* Bases creadas antes: se agregan 'RET' y 'ETI' al check */
IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_CORRIDA_PROCESO' AND definition NOT LIKE '%ETI%')
BEGIN
    ALTER TABLE ops.CORRIDA DROP CONSTRAINT CK_CORRIDA_PROCESO;
    ALTER TABLE ops.CORRIDA ADD CONSTRAINT CK_CORRIDA_PROCESO CHECK (PROCESO IN ('ASIG','ACT','RET','ETI'));
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
/* Correos que se arriban a CYBER en la asignación (antes email.PRG -> sub_mail.TXT).
   CYBER (RCVRY.JSP_CORREOS_486) purga y agrega. */
IF OBJECT_ID('ops.CORREO') IS NULL
CREATE TABLE ops.CORREO (
    ID_CORRIDA  INT           NOT NULL,
    CUENTA2     VARCHAR(28)   NOT NULL,
    CORREO      VARCHAR(100)  NOT NULL,
    CAMPO_DAT   VARCHAR(10)   NOT NULL,
    CONSTRAINT PK_CORREO PRIMARY KEY (ID_CORRIDA, CUENTA2, CORREO)
);
GO
/* Status de CYBER para el blanqueo (antes status.prg: STATUS.SQL -> C:\STATUSBAJ.txt -> CYBSTATUS) */
IF OBJECT_ID('ops.STATUS_CYBER') IS NULL
CREATE TABLE ops.STATUS_CYBER (
    ID_CORRIDA  INT           NOT NULL,             -- corrida de asignación a la que pertenece
    NUM         INT           NOT NULL,
    CLIENTE     VARCHAR(10)   NULL,
    FOLIO       VARCHAR(20)   NULL,
    CUENTA      VARCHAR(28)   NULL,                 -- DMACCT (486-folio)
    STATUS      VARCHAR(10)   NULL,                 -- DMACRC2
    ACCION      VARCHAR(10)   NULL,                 -- DMACAC2
    FECHA       VARCHAR(30)   NULL,                 -- DMACDT2
    PESO        VARCHAR(10)   NULL,                 -- DMACSC2
    DMSSNUM     VARCHAR(28)   NULL,                 -- crédito del banco
    BLANQUEA    BIT           NOT NULL CONSTRAINT DF_STATUS_CYBER_B DEFAULT 0,
    MOTIVO      VARCHAR(60)   NULL,
    CONSTRAINT PK_STATUS_CYBER PRIMARY KEY (ID_CORRIDA, NUM)
);
GO
/* Lo que bajó de CYBER para cruzar: correos que ya tiene (email.PRG: cyadd.sql) y
   cuentas con teléfono activo (ges486.prg: TELs_486.sql) */
IF OBJECT_ID('ops.CORREO_CYBER') IS NULL
CREATE TABLE ops.CORREO_CYBER (
    ID_CORRIDA  INT           NOT NULL,
    CUENTA2     VARCHAR(28)   NOT NULL,
    CORREO      VARCHAR(100)  NOT NULL,
    CONSTRAINT PK_CORREO_CYBER PRIMARY KEY (ID_CORRIDA, CUENTA2, CORREO)
);
GO
IF OBJECT_ID('ops.TELEFONO_CYBER') IS NULL
CREATE TABLE ops.TELEFONO_CYBER (
    ID_CORRIDA  INT           NOT NULL,
    CUENTA2     VARCHAR(28)   NOT NULL,
    TELEFONOS   INT           NOT NULL,
    CONSTRAINT PK_TELEFONO_CYBER PRIMARY KEY (ID_CORRIDA, CUENTA2)
);
GO
/* Paso para lo que se baja de CYBER (ops.sp_bajar_cyber): no se guardan archivos en la máquina.
   Cada procedimiento copia lo que necesita a ops.* y vacía la tabla de paso. */
IF OBJECT_ID('stg.CYBER_STATUS') IS NULL
CREATE TABLE stg.CYBER_STATUS (CLIENTE NVARCHAR(10) NULL, FOLIO NVARCHAR(20) NULL, CUENTA NVARCHAR(28) NULL, STATUS NVARCHAR(10) NULL,
                               ACCION NVARCHAR(10) NULL, FECHA NVARCHAR(30) NULL, PESO NVARCHAR(10) NULL, DMSSNUM NVARCHAR(28) NULL);
GO
IF OBJECT_ID('stg.CYBER_CORREO') IS NULL
CREATE TABLE stg.CYBER_CORREO (CUENTA NVARCHAR(28) NULL, CORREO NVARCHAR(300) NULL);
GO
IF OBJECT_ID('stg.CYBER_TELEFONO') IS NULL
CREATE TABLE stg.CYBER_TELEFONO (CUENTA NVARCHAR(28) NULL, LADA NVARCHAR(10) NULL, TEL NVARCHAR(20) NULL);
GO
/* Para el arribo automático: cuentas activas del 486 en CYBER (DELQMST) y teléfonos que dejó el arribo del SCBTEL (PHONE_G1) */
IF OBJECT_ID('stg.CYBER_DELQMST_ACT') IS NULL
CREATE TABLE stg.CYBER_DELQMST_ACT (CUENTA NVARCHAR(28) NULL, DOMICILIO NVARCHAR(200) NULL);
GO
IF COL_LENGTH('stg.CYBER_DELQMST_ACT', 'DOMICILIO') IS NULL
    ALTER TABLE stg.CYBER_DELQMST_ACT ADD DOMICILIO NVARCHAR(200) NULL;
GO
/* Lo que le faltaba a CYBER al terminar la asignación (foto antes de que existan los archivos).
   El arribo automático da por subido el SCBSDOS / SCBTEL cuando ya llegó lo pendiente,
   así funciona igual con cero o con muchas cuentas nuevas.
   TIPO: CUENTA (no activa en DELQMST), DOMICILIO (DMADDR1 distinto al enviado), TELEFONO (no está en PHONE_G1) */
IF OBJECT_ID('ops.ARRIBO_PENDIENTE') IS NULL
CREATE TABLE ops.ARRIBO_PENDIENTE (
    ID_CORRIDA  INT           NOT NULL,
    TIPO        VARCHAR(10)   NOT NULL,
    CUENTA      NVARCHAR(28)  NOT NULL,
    AREA        NVARCHAR(10)  NULL,
    TELEFONO    NVARCHAR(20)  NULL,
    VALOR       NVARCHAR(200) NULL,
    INDEX IX_ARRIBO_PENDIENTE CLUSTERED (ID_CORRIDA, TIPO, CUENTA)
);
GO
IF OBJECT_ID('stg.CYBER_PHONE_G1') IS NULL
CREATE TABLE stg.CYBER_PHONE_G1 (CUENTA NVARCHAR(28) NULL, AREA NVARCHAR(10) NULL, TELEFONO NVARCHAR(20) NULL);
GO
/* Pagos que CYBER registró en el día (BAJ.sql: RCVRY.pmtfil), para cuadrar contra lo arribado */
IF OBJECT_ID('stg.CYBER_PAGO') IS NULL
CREATE TABLE stg.CYBER_PAGO (CUENTA NVARCHAR(28) NULL, MONTO NVARCHAR(30) NULL, FECHA NVARCHAR(20) NULL);
GO
/* Base maestra completa (todas las columnas, tal como llegó): por segmento se guardan
   dos versiones, la vigente (VIGENTE = 1) y la anterior (VIGENTE = 0). Cuando llega una
   nueva, la vigente pasa a anterior y la anterior se borra; si la corrida se revierte,
   la anterior vuelve a ser la vigente. La historia por cuenta
   queda en dat.HISTORIA_FOLIO. Los procesos solo toman las columnas de cfg.ARCHIVO_COLUMNA.
   Un renglón del archivo = un renglón con DATOS en JSON {"encabezado": "valor", …}.
   Consulta: SELECT JSON_VALUE(DATOS, '$."ACC_NUM"') FROM dat.BASE_RECIBIDA WHERE … */
IF OBJECT_ID('dat.BASE_RECIBIDA_ARCHIVO') IS NULL
CREATE TABLE dat.BASE_RECIBIDA_ARCHIVO (
    ID_CORRIDA   INT            NOT NULL,
    CODIGO       VARCHAR(50)    NOT NULL,
    CLIENTE      VARCHAR(10)    NOT NULL,
    ARCHIVO      NVARCHAR(512)  NOT NULL,
    ENCABEZADOS  NVARCHAR(MAX)  NOT NULL,          -- arreglo JSON con los encabezados en orden
    REGISTROS    INT            NOT NULL,
    FE_CARGA     DATETIME2(0)   NOT NULL CONSTRAINT DF_BASE_RECIBIDA_ARCHIVO_FE DEFAULT SYSDATETIME(),
    VIGENTE      BIT            NOT NULL CONSTRAINT DF_BASE_RECIBIDA_ARCHIVO_VIG DEFAULT 1,
    CONSTRAINT PK_BASE_RECIBIDA_ARCHIVO PRIMARY KEY (ID_CORRIDA, CODIGO)
);
GO
IF COL_LENGTH('dat.BASE_RECIBIDA_ARCHIVO', 'VIGENTE') IS NULL
    ALTER TABLE dat.BASE_RECIBIDA_ARCHIVO ADD VIGENTE BIT NOT NULL CONSTRAINT DF_BASE_RECIBIDA_ARCHIVO_VIG DEFAULT 1;
GO
IF OBJECT_ID('dat.BASE_RECIBIDA') IS NULL
CREATE TABLE dat.BASE_RECIBIDA (
    ID_CORRIDA  INT            NOT NULL,
    CODIGO      VARCHAR(50)    NOT NULL,
    FILA        INT            NOT NULL,           -- renglón del archivo
    DATOS       NVARCHAR(MAX)  NOT NULL,
    CONSTRAINT PK_BASE_RECIBIDA PRIMARY KEY (ID_CORRIDA, CODIGO, FILA)
);
GO
/* La base maestra vigente de cada segmento */
CREATE OR ALTER VIEW dat.v_BASE_VIGENTE
AS
SELECT a.CLIENTE, a.CODIGO, a.ID_CORRIDA, a.ARCHIVO, a.FE_CARGA, b.FILA, b.DATOS
FROM dat.BASE_RECIBIDA_ARCHIVO a
JOIN dat.BASE_RECIBIDA b ON b.ID_CORRIDA = a.ID_CORRIDA AND b.CODIGO = a.CODIGO
WHERE a.VIGENTE = 1;
GO
/* Bases creadas antes: RIESGO en el histórico (para arribar pagos de cuentas retiradas) */
IF COL_LENGTH('dat.HISTORIA_FOLIO', 'RIESGO') IS NULL
    ALTER TABLE dat.HISTORIA_FOLIO ADD RIESGO VARCHAR(35) NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_HISTORIA_FOLIO_RIESGO')
    CREATE INDEX IX_HISTORIA_FOLIO_RIESGO ON dat.HISTORIA_FOLIO (CLIENTE, RIESGO);
GO
