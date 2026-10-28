/* =====================================================================
   Banbaj · 05 Tabla fija DAT del cliente 486 (generado por tools/generar_sql_486.py)
   Misma estructura que DAT.DBF (hoja DAT_GENERAL del mapeo) + 3 columnas de control.
   ===================================================================== */
SET NOCOUNT ON;
GO
IF OBJECT_ID('dat.DAT_486') IS NULL
CREATE TABLE dat.DAT_486 (
    FOLIO        VARCHAR(10)    NULL,
    CLIENTE      VARCHAR(3)     NULL,
    SUB_CTE      VARCHAR(10)    NULL,
    NOMBRE1      VARCHAR(50)    NULL,
    NOMBRE2      VARCHAR(20)    NULL,
    RFC          VARCHAR(25)    NULL,
    DIRECC1      VARCHAR(45)    NULL,
    DIRECC2      VARCHAR(40)    NULL,
    DIRECC3      VARCHAR(5)     NULL,
    DIRECC4      VARCHAR(30)    NULL,
    DIRECC5      VARCHAR(6)     NULL,
    GESTOR1      VARCHAR(10)    NULL,
    CUENTA       VARCHAR(20)    NOT NULL,
    TIPO         VARCHAR(25)    NULL,
    TIPO2        VARCHAR(25)    NULL,
    TEL1         VARCHAR(15)    NULL,
    TEL2         VARCHAR(15)    NULL,
    TEL3         VARCHAR(15)    NULL,
    SDO_ACT      DECIMAL(18,2)  NULL,
    CAPITAL      DECIMAL(18,2)  NULL,
    FE_ASIG      DATE           NULL,
    FE_REC       DATE           NULL,
    FE_REG       DATE           NULL,
    CICLO        VARCHAR(10)    NULL,
    PVS          VARCHAR(4)     NULL,
    GESTOR2      VARCHAR(5)     NULL,
    ESTADO       VARCHAR(19)    NULL,
    SUCURSAL     VARCHAR(20)    NULL,
    AREA         VARCHAR(16)    NULL,
    EDO          VARCHAR(4)     NULL,
    CUENTA2      VARCHAR(28)    NULL,
    RIESGO       VARCHAR(35)    NULL,
    DES_PROD     VARCHAR(40)    NULL,
    STATUS       VARCHAR(6)     NULL,
    SALDO1       DECIMAL(18,2)  NULL,
    SALDO2       DECIMAL(18,2)  NULL,
    SALDO3       DECIMAL(18,2)  NULL,
    MAIL         VARCHAR(45)    NULL,
    SEGMENTO     VARCHAR(30)    NULL,
    PAG_MIN      DECIMAL(18,2)  NULL,
    SDO_VDO      DECIMAL(18,2)  NULL,
    BUCKET       VARCHAR(30)    NULL,
    TRAMO        VARCHAR(20)    NULL,
    TRABAJO      VARCHAR(30)    NULL,
    MODALLIDAD   VARCHAR(30)    NULL,
    SEG          VARCHAR(15)    NULL,
    CUENTA3      VARCHAR(20)    NULL,
    ESTRA4       VARCHAR(15)    NULL,
    ESTRA3       VARCHAR(15)    NULL,
    TEL4         VARCHAR(15)    NULL,
    TEL5         VARCHAR(15)    NULL,
    TEL6         VARCHAR(15)    NULL,
    TEL7         VARCHAR(15)    NULL,
    TEL8         VARCHAR(15)    NULL,
    TEL9         VARCHAR(15)    NULL,
    TEL10        VARCHAR(15)    NULL,
    TEL11        VARCHAR(15)    NULL,
    TEL12        VARCHAR(15)    NULL,
    TEL13        VARCHAR(15)    NULL,
    TEL14        VARCHAR(15)    NULL,
    TEL15        VARCHAR(15)    NULL,
    TEL16        VARCHAR(15)    NULL,
    SEGMENTO2    VARCHAR(20)    NULL,
    GARAN        VARCHAR(15)    NULL,
    REE          VARCHAR(15)    NULL,
    ETIQUETA     VARCHAR(15)    NULL,
    ETIQUETA5    VARCHAR(20)    NULL,
    ETIQUETA1    VARCHAR(10)    NULL,
    CORREO1      VARCHAR(100)   NULL,
    CORREO2      VARCHAR(100)   NULL,
    ID_CORRIDA_ALTA INT          NULL,
    ID_CORRIDA_ULT  INT          NULL,
    FE_ULT_ACT      DATETIME2(0) NULL,
    CONSTRAINT PK_DAT_486 PRIMARY KEY (CUENTA)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_DAT_486_CUENTA2')
    CREATE UNIQUE INDEX UX_DAT_486_CUENTA2 ON dat.DAT_486 (CUENTA2) WHERE CUENTA2 IS NOT NULL;
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_DAT_486_DES_PROD')
    CREATE INDEX IX_DAT_486_DES_PROD ON dat.DAT_486 (DES_PROD);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_DAT_486_RIESGO')
    CREATE INDEX IX_DAT_486_RIESGO ON dat.DAT_486 (RIESGO, SEGMENTO2);
GO
