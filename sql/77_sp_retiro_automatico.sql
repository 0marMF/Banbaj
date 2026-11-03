/* =====================================================================
   Banbaj · 77 Retiro automático (decisión 02/11)
   ---------------------------------------------------------------------
   Las devoluciones que detectan la asignación (cuentas del DAT que no vienen
   en la base maestra) y la actualización (reglas de retiro) se aplican solas,
   salvo que en algún segmento superen el tope:
     asignación     RETIRO_TOPE_PCT_ASIG (50) % de las cuentas del segmento en el DAT
     actualización  RETIRO_TOPE_PCT_ACT  (50) % de las cuentas del segmento en el DAT
   Si lo superan, quedan en ops.DEVOLUCION para revisión y se manda el correo
   de hallazgos (HALLAZGO_486) solo al equipo de asignaciones.

   Después de aplicar un retiro, ops.sp_retiro_cerrar hace sin intervención:
     1. Escribe los archivos de la corrida, arma el ZIP con contraseña y manda
        el correo único de devolución (Operación con el ZIP, AEM en copia oculta).
     2. Ejecuta el script RETIRO en CYBER (dmstatus = 'R') por el servidor vinculado.
     3. Copia el archivo de devolución MX_G1MCT_DVBJIG_* a RUTA_DEVOLUCION_CYBER.
   Cada paso corre una vez (bitácora RETIRO ARCHIVOS / RETIRO CYBER / RETIRO DEVOL CYBER).
   Si uno falla queda ERROR, se avisa con HALLAZGO_486 y se repite a mano:
     EXEC ops.sp_retiro_cerrar <corrida>;      -- solo repite lo que no quedó OK
   Parámetro RETIRO_AUTOMATICO = 0 para volver al retiro manual.
   ===================================================================== */
SET NOCOUNT ON;
GO

/* ¿Se aplican solas las devoluciones de la corrida? Se llama justo después de detectarlas,
   con el DAT todavía como estaba (antes de las altas). */
CREATE OR ALTER PROCEDURE ops.sp_retiro_decidir
    @id_corrida INT,
    @aplicar    BIT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @cliente VARCHAR(10), @proceso VARCHAR(10), @tope DECIMAL(9,2), @n INT, @msg NVARCHAR(4000), @tabla NVARCHAR(MAX), @accion NVARCHAR(4000);
    SELECT @cliente = CLIENTE, @proceso = PROCESO FROM ops.CORRIDA WHERE ID_CORRIDA = @id_corrida;
    SET @aplicar = 0;
    IF ISNULL(cfg.fn_param(@cliente, 'RETIRO_AUTOMATICO'), '0') <> '1' RETURN;
    SET @n = (SELECT COUNT(*) FROM ops.DEVOLUCION WHERE ID_CORRIDA = @id_corrida AND PROCESADA = 0);
    IF @n = 0 RETURN;

    SET @tope = ISNULL(TRY_CONVERT(DECIMAL(9,2), cfg.fn_param(@cliente, CASE WHEN @proceso = 'ASIG' THEN 'RETIRO_TOPE_PCT_ASIG' ELSE 'RETIRO_TOPE_PCT_ACT' END)), 50);

    SELECT ISNULL(NULLIF(d.SEGMENTO2, ''), '(sin segmento)') AS SEG, COUNT(*) AS TOTAL,
           SUM(CASE WHEN v.CUENTA IS NOT NULL THEN 1 ELSE 0 END) AS DEV
    INTO #s
    FROM dat.DAT_486 d
    LEFT JOIN ops.DEVOLUCION v ON v.ID_CORRIDA = @id_corrida AND v.CUENTA = d.CUENTA AND v.PROCESADA = 0
    GROUP BY ISNULL(NULLIF(d.SEGMENTO2, ''), '(sin segmento)');
    DELETE FROM #s WHERE DEV = 0;

    SET @msg = (SELECT STRING_AGG(CONCAT(SEG, N': ', DEV, N' de ', TOTAL, N' (', CAST(100.0 * DEV / TOTAL AS DECIMAL(6,2)), N'%)'), N' · ') FROM #s);

    IF EXISTS (SELECT 1 FROM #s WHERE 100.0 * DEV / TOTAL > @tope)
    BEGIN
        SET @msg = CONCAT(N'Devolución de ', @n, N' cuentas supera el tope de ', @tope, N'% en algún segmento: ', @msg, N'. Queda para revisión.');
        EXEC ops.sp_log @id_corrida, 'RETIRO AUTOMATICO', 'AVISO', @n, @msg;
        SET @tabla = (SELECT SEG AS [Segmento], CAST(TOTAL AS NVARCHAR(12)) AS [Cuentas en el DAT], CAST(DEV AS NVARCHAR(12)) AS [A retirar],
                             CONCAT(CAST(100.0 * DEV / TOTAL AS DECIMAL(6,2)), N'%') AS [Porcentaje],
                             CASE WHEN 100.0 * DEV / TOTAL > @tope THEN N'SUPERA EL TOPE' ELSE N'dentro del tope' END AS [Resultado]
                      FROM #s ORDER BY DEV DESC FOR JSON PATH);
        SET @accion = CONCAT(N'Revisar las cuentas con SELECT * FROM ops.DEVOLUCION WHERE ID_CORRIDA = ', @id_corrida,
                             N' (puede ser una base maestra incompleta o un archivo de saldos mal formado). ',
                             N'Si el retiro es correcto: EXEC ops.sp_retiro ', @id_corrida, N'; y luego EXEC ops.sp_retiro_cerrar ', @id_corrida,
                             N'; (archivos, ZIP y correo de devolución, RETIRO en CYBER y copia de la devolución). Si no, no hacer nada: las cuentas siguen en el DAT.');
        EXEC mail.sp_hallazgo @id_corrida, N'Retiro detenido: supera el tope', @msg, @accion, @tabla;
        RETURN;
    END;

    SET @aplicar = 1;
    SET @msg = CONCAT(N'Se aplica solo (tope ', @tope, N'%): ', @msg);
    EXEC ops.sp_log @id_corrida, 'RETIRO AUTOMATICO', 'OK', @n, @msg;
END;
GO

/* Pasos después de aplicar un retiro: archivos + ZIP + correo, RETIRO en CYBER y copia de la devolución.
   Repite solo los pasos que no han quedado OK. */
CREATE OR ALTER PROCEDURE ops.sp_retiro_cerrar
    @id_corrida   INT,
    @solo_mostrar BIT = 0,
    @resultado    NVARCHAR(400) = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @cliente VARCHAR(10), @srv SYSNAME, @ruta NVARCHAR(400), @msg NVARCHAR(4000), @n INT, @tabla NVARCHAR(MAX), @accion NVARCHAR(4000),
            @ok_a BIT, @ok_c BIT, @ok_d BIT;
    SELECT @cliente = CLIENTE FROM ops.CORRIDA WHERE ID_CORRIDA = @id_corrida;
    IF @cliente IS NULL THROW 50770, 'La corrida no existe.', 1;
    SET @srv = ISNULL(cfg.fn_param(@cliente, 'CYBER_LINKED_SERVER'), 'CYBER');
    SET @ruta = NULLIF(LTRIM(RTRIM(cfg.fn_param(@cliente, 'RUTA_DEVOLUCION_CYBER'))), N'');
    SET @ok_a = CASE WHEN EXISTS (SELECT 1 FROM ops.BITACORA WHERE ID_CORRIDA = @id_corrida AND PASO = 'RETIRO ARCHIVOS' AND ESTATUS = 'OK') THEN 1 ELSE 0 END;
    SET @ok_c = CASE WHEN EXISTS (SELECT 1 FROM ops.BITACORA WHERE ID_CORRIDA = @id_corrida AND PASO = 'RETIRO CYBER' AND ESTATUS = 'OK') THEN 1 ELSE 0 END;
    SET @ok_d = CASE WHEN @ruta IS NULL OR EXISTS (SELECT 1 FROM ops.BITACORA WHERE ID_CORRIDA = @id_corrida AND PASO = 'RETIRO DEVOL CYBER' AND ESTATUS = 'OK') THEN 1 ELSE 0 END;

    IF NOT EXISTS (SELECT 1 FROM ops.DEVOLUCION WHERE ID_CORRIDA = @id_corrida AND PROCESADA = 1)
    BEGIN
        SET @resultado = N'SIN RETIRO APLICADO';
        SELECT @resultado AS RETIRO;
        RETURN;
    END;

    IF @solo_mostrar = 1
    BEGIN
        SELECT 1 AS PASO, 'RETIRO ARCHIVOS' AS QUE, N'Archivos de la corrida, ZIP con contraseña y correo único de devolución' AS DETALLE,
               CASE WHEN @ok_a = 1 THEN 'HECHO' ELSE 'PENDIENTE' END AS ESTADO
        UNION ALL
        SELECT 2, 'RETIRO CYBER', CONCAT(N'Script RETIRO en CYBER por [', @srv, N'] (', (SELECT COUNT(*) FROM ops.CYBER_SCRIPT WHERE ID_CORRIDA = @id_corrida AND SCRIPT = 'RETIRO'), N' líneas)'),
               CASE WHEN @ok_c = 1 THEN 'HECHO' ELSE 'PENDIENTE' END
        UNION ALL
        SELECT 3, 'RETIRO DEVOL CYBER', ISNULL(N'Copia de MX_G1MCT_DVBJIG_* en ' + @ruta, N'Sin RUTA_DEVOLUCION_CYBER: no se copia'),
               CASE WHEN @ruta IS NULL THEN 'NO APLICA' WHEN @ok_d = 1 THEN 'HECHO' ELSE 'PENDIENTE' END;
        RETURN;
    END;
    IF @@TRANCOUNT > 0 THROW 50771, 'El cierre del retiro no puede correr dentro de una transacción.', 1;

    /* 1. Archivos, ZIP y correo de devolución */
    IF @ok_a = 0
    BEGIN
    BEGIN TRY
        EXEC ops.sp_exportar_salidas @id_corrida, @zip = 'RETIROS', @enviar_zip = 1;
        EXEC ops.sp_log @id_corrida, 'RETIRO ARCHIVOS', 'OK', NULL, N'Archivos escritos, ZIP y correo de devolución enviados';
        SET @ok_a = 1;
    END TRY
    BEGIN CATCH
        SET @msg = ERROR_MESSAGE();
        EXEC ops.sp_log @id_corrida, 'RETIRO ARCHIVOS', 'ERROR', NULL, @msg;
    END CATCH;
    END;

    /* 2. dmstatus = 'R' en CYBER */
    IF @ok_c = 0
    BEGIN
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM sys.servers WHERE name = @srv)
        BEGIN
            SET @msg = CONCAT(N'No existe el servidor vinculado ', @srv, N'. Captura la credencial CYBER_ORACLE y corre EXEC cfg.sp_cyber_conectar;');
            THROW 50823, @msg, 1;
        END;
        EXEC ops.sp_cyber_ejecutar @id_corrida, 'RETIRO', @sentencias = @n OUTPUT;
        EXEC ops.sp_log @id_corrida, 'RETIRO CYBER', 'OK', @n, N'dmstatus de retiro en RCVRY.delqmst';
        SET @ok_c = 1;
    END TRY
    BEGIN CATCH
        SET @msg = ERROR_MESSAGE();
        EXEC ops.sp_log @id_corrida, 'RETIRO CYBER', 'ERROR', NULL, @msg;
    END CATCH;
    END;

    /* 3. Archivo de devolución en la carpeta de CYBER */
    IF @ok_d = 0
    BEGIN
    BEGIN TRY
        EXEC ops.sp_exportar_salidas @id_corrida, @carpeta = @ruta, @solo = N'DEVOL_CYBER', @sin_scripts = 1, @sin_subcarpeta = 1;
        SET @msg = CONCAT(N'Devolución copiada a ', @ruta);
        EXEC ops.sp_log @id_corrida, 'RETIRO DEVOL CYBER', 'OK', NULL, @msg;
        SET @ok_d = 1;
    END TRY
    BEGIN CATCH
        SET @msg = ERROR_MESSAGE();
        EXEC ops.sp_log @id_corrida, 'RETIRO DEVOL CYBER', 'ERROR', NULL, @msg;
    END CATCH;
    END;

    SET @resultado = CASE WHEN @ok_a = 1 AND @ok_c = 1 AND @ok_d = 1 THEN N'RETIRO CERRADO' ELSE N'RETIRO CON PASOS PENDIENTES' END;
    IF @resultado <> N'RETIRO CERRADO'
    BEGIN
        SET @tabla = (SELECT b.PASO AS [Paso], b.ESTATUS AS [Estatus], ISNULL(b.MENSAJE, N'') AS [Mensaje]
                      FROM ops.BITACORA b
                      WHERE b.ID_CORRIDA = @id_corrida AND b.PASO IN ('RETIRO ARCHIVOS', 'RETIRO CYBER', 'RETIRO DEVOL CYBER')
                        AND b.ID = (SELECT MAX(x.ID) FROM ops.BITACORA x WHERE x.ID_CORRIDA = b.ID_CORRIDA AND x.PASO = b.PASO)
                      ORDER BY b.ID FOR JSON PATH);
        SET @msg = CONCAT(N'El retiro ya se aplicó en el DAT, pero quedaron pasos sin terminar',
                          CASE WHEN @ok_a = 0 THEN N' · archivos/ZIP/correo' ELSE N'' END,
                          CASE WHEN @ok_c = 0 THEN N' · RETIRO en CYBER' ELSE N'' END,
                          CASE WHEN @ok_d = 0 THEN N' · copia de la devolución' ELSE N'' END, N'.');
        SET @accion = CONCAT(N'Corregir la causa (ver la tabla) y correr EXEC ops.sp_retiro_cerrar ', @id_corrida, N'; solo repite lo que no quedó OK.');
        EXEC mail.sp_hallazgo @id_corrida, N'Retiro con pasos pendientes', @msg, @accion, @tabla;
    END;
    SELECT @resultado AS RETIRO, @id_corrida AS CORRIDA;
END;
GO
