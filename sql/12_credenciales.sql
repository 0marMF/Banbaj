/* =====================================================================
   Banbaj · 12 Credenciales (usuario y contraseña de Oracle/CYBER y otras)
   ---------------------------------------------------------------------
   Para depositar o cambiar una credencial se escribe en la "tabla" de captura:

       INSERT INTO cfg.CAPTURA_CREDENCIAL (SISTEMA, USUARIO, CLAVE)
       VALUES ('CYBER_ORACLE', 'mi_usuario', 'mi_contraseña');

   Si el SISTEMA ya existe, se reemplaza. La contraseña se guarda cifrada en
   cfg.CREDENCIAL (AES-256 con llave de la base de datos) y nunca se muestra:
   SELECT * FROM cfg.CAPTURA_CREDENCIAL enseña '********'.
   Para borrar:  DELETE FROM cfg.CAPTURA_CREDENCIAL WHERE SISTEMA = 'CYBER_ORACLE';

   Sistemas que usa el 486:
     CYBER_ORACLE   usuario y contraseña de Oracle para el servidor vinculado CYBER
                    (después de capturarla: EXEC cfg.sp_cyber_conectar)

   Nota: la llave se protege con la llave maestra del servidor. Si la base se
   restaura en otro servidor, las contraseñas no se pueden leer: vuelve a
   capturarlas.
   ===================================================================== */
SET NOCOUNT ON;
GO

/* Llaves de cifrado (una vez por base de datos) */
IF NOT EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = '##MS_DatabaseMasterKey##')
BEGIN
    DECLARE @p NVARCHAR(200) = N'Bb1!' + CONVERT(NVARCHAR(100), CRYPT_GEN_RANDOM(32), 2);   -- nadie la necesita: la abre la llave del servidor
    DECLARE @sql NVARCHAR(400) = N'CREATE MASTER KEY ENCRYPTION BY PASSWORD = ' + QUOTENAME(@p, '''') + N';';
    EXEC (@sql);
END;
GO
IF NOT EXISTS (SELECT 1 FROM sys.certificates WHERE name = 'CERT_BANBAJ_CREDENCIAL')
    CREATE CERTIFICATE CERT_BANBAJ_CREDENCIAL WITH SUBJECT = 'Banbaj: credenciales', EXPIRY_DATE = '2099-12-31';
GO
IF NOT EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = 'LLAVE_BANBAJ_CREDENCIAL')
    CREATE SYMMETRIC KEY LLAVE_BANBAJ_CREDENCIAL WITH ALGORITHM = AES_256 ENCRYPTION BY CERTIFICATE CERT_BANBAJ_CREDENCIAL;
GO

IF OBJECT_ID('cfg.CREDENCIAL') IS NULL
CREATE TABLE cfg.CREDENCIAL (
    SISTEMA     VARCHAR(30)     NOT NULL CONSTRAINT PK_CREDENCIAL PRIMARY KEY,
    USUARIO     NVARCHAR(128)   NOT NULL,
    CLAVE       VARBINARY(512)  NOT NULL,             -- cifrada con LLAVE_BANBAJ_CREDENCIAL
    FE_ACT      DATETIME2(0)    NOT NULL CONSTRAINT DF_CREDENCIAL_FE DEFAULT SYSDATETIME(),
    ACT_POR     SYSNAME         NOT NULL CONSTRAINT DF_CREDENCIAL_POR DEFAULT SUSER_SNAME()
);
GO

/* Vista de captura: se escribe aquí como si fuera tabla */
CREATE OR ALTER VIEW cfg.CAPTURA_CREDENCIAL
AS
SELECT SISTEMA, USUARIO, CAST(N'********' AS NVARCHAR(256)) AS CLAVE, FE_ACT, ACT_POR
FROM cfg.CREDENCIAL;
GO

CREATE OR ALTER TRIGGER cfg.TR_CAPTURA_CREDENCIAL_GUARDAR ON cfg.CAPTURA_CREDENCIAL
INSTEAD OF INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM inserted WHERE NULLIF(LTRIM(RTRIM(SISTEMA)), '') IS NULL OR NULLIF(LTRIM(RTRIM(USUARIO)), N'') IS NULL
                                         OR NULLIF(CLAVE, N'') IS NULL OR CLAVE = N'********')
        THROW 50800, 'Indica SISTEMA, USUARIO y CLAVE (la contraseña real, no ********).', 1;
    OPEN SYMMETRIC KEY LLAVE_BANBAJ_CREDENCIAL DECRYPTION BY CERTIFICATE CERT_BANBAJ_CREDENCIAL;
    MERGE cfg.CREDENCIAL AS t
    USING (SELECT UPPER(LTRIM(RTRIM(SISTEMA))) AS SISTEMA, LTRIM(RTRIM(USUARIO)) AS USUARIO,
                  ENCRYPTBYKEY(KEY_GUID('LLAVE_BANBAJ_CREDENCIAL'), CLAVE) AS CLAVE
           FROM inserted) AS s
       ON t.SISTEMA = s.SISTEMA
    WHEN MATCHED THEN UPDATE SET USUARIO = s.USUARIO, CLAVE = s.CLAVE, FE_ACT = SYSDATETIME(), ACT_POR = SUSER_SNAME()
    WHEN NOT MATCHED THEN INSERT (SISTEMA, USUARIO, CLAVE) VALUES (s.SISTEMA, s.USUARIO, s.CLAVE);
    CLOSE SYMMETRIC KEY LLAVE_BANBAJ_CREDENCIAL;
END;
GO

CREATE OR ALTER TRIGGER cfg.TR_CAPTURA_CREDENCIAL_BORRAR ON cfg.CAPTURA_CREDENCIAL
INSTEAD OF DELETE
AS
BEGIN
    SET NOCOUNT ON;
    DELETE c FROM cfg.CREDENCIAL c JOIN deleted d ON d.SISTEMA = c.SISTEMA;
END;
GO

/* Uso interno: regresa usuario y contraseña en claro (solo para los procedimientos de Banbaj) */
CREATE OR ALTER PROCEDURE cfg.sp_credencial_leer
    @sistema VARCHAR(30),
    @usuario NVARCHAR(128) OUTPUT,
    @clave   NVARCHAR(256) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    OPEN SYMMETRIC KEY LLAVE_BANBAJ_CREDENCIAL DECRYPTION BY CERTIFICATE CERT_BANBAJ_CREDENCIAL;
    SELECT @usuario = USUARIO, @clave = CONVERT(NVARCHAR(256), DECRYPTBYKEY(CLAVE))
    FROM cfg.CREDENCIAL WHERE SISTEMA = UPPER(@sistema);
    CLOSE SYMMETRIC KEY LLAVE_BANBAJ_CREDENCIAL;
    IF @usuario IS NULL
    BEGIN
        DECLARE @msg NVARCHAR(400) = CONCAT(N'No hay credencial para ', @sistema,
            N'. Captúrala con: INSERT INTO cfg.CAPTURA_CREDENCIAL (SISTEMA, USUARIO, CLAVE) VALUES (''', @sistema, N''', ''usuario'', ''contraseña'');');
        THROW 50801, @msg, 1;
    END;
    IF @clave IS NULL THROW 50802, 'La contraseña guardada no se puede leer (¿la base se restauró en otro servidor?). Vuelve a capturarla.', 1;
END;
GO
