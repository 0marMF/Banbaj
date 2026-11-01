/* =====================================================================
   Banbaj · Instalación 3 de 3 · Rutas, Oracle y credenciales (en la base Banbaj)
   ---------------------------------------------------------------------
   Reemplaza cada <<…>> antes de correrlo; el script se detiene si queda alguno.
   Las contraseñas se guardan cifradas; borra este archivo editado al terminar
   (no lo subas al repositorio con las contraseñas escritas).
   ===================================================================== */
SET NOCOUNT ON;
DECLARE @ruta_q        NVARCHAR(400) = N'<<\\servidor\recurso>>',          -- ruta UNC de la unidad Q: (sin diagonal final)
        @oracle        NVARCHAR(400) = N'<<host:1521/servicio>>',          -- Oracle de CYBER
        @usuario_ora   NVARCHAR(128) = N'<<usuario Oracle>>',
        @clave_ora     NVARCHAR(256) = N'<<contraseña Oracle>>',
        @clave_zip     NVARCHAR(256) = N'<<contraseña ZIP, ej. *Bajio{MM}{AAAA}>>';

IF CONCAT(@ruta_q, @oracle, @usuario_ora, @clave_ora, @clave_zip) LIKE N'%<<%'
    THROW 50999, 'Faltan valores <<…>> por reemplazar en este script.', 1;

/* Rutas: la unidad Q: no existe para el servicio de SQL Server; se usa la ruta UNC */
UPDATE cfg.ARCHIVO SET RUTA = REPLACE(RUTA, N'Q:', @ruta_q) WHERE CLIENTE = '486' AND RUTA LIKE N'Q:%';
UPDATE cfg.PARAMETRO SET VALOR = REPLACE(VALOR, N'Q:', @ruta_q) WHERE CLIENTE = '486' AND CLAVE = 'RUTA_MIS';
UPDATE cfg.PARAMETRO SET VALOR = @oracle WHERE CLIENTE = '486' AND CLAVE = 'CYBER_ORACLE_ORIGEN';

/* Credenciales (se cifran al guardarse) */
INSERT INTO cfg.CAPTURA_CREDENCIAL (SISTEMA, USUARIO, CLAVE) VALUES ('CYBER_ORACLE', @usuario_ora, @clave_ora);
INSERT INTO cfg.CAPTURA_CREDENCIAL (SISTEMA, USUARIO, CLAVE) VALUES ('ZIP_RETIROS', N'zip', @clave_zip);

/* Servidor vinculado a CYBER y prueba */
EXEC cfg.sp_cyber_conectar;
EXEC ops.sp_bajar_cyber 'STATUS', @solo_bajar = 1;          -- debe decir "STATUS: n registros bajados"

SELECT CLAVE, VALOR FROM cfg.PARAMETRO WHERE CLIENTE = '486' AND CLAVE IN ('RUTA_MIS', 'CYBER_ORACLE_ORIGEN', 'RUTA_SALIDA', 'CARPETA_ZIP', 'RUTA_7ZIP');
SELECT DISTINCT RUTA FROM cfg.ARCHIVO WHERE CLIENTE = '486';
SELECT SISTEMA, USUARIO, CLAVE FROM cfg.CAPTURA_CREDENCIAL;
