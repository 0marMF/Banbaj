*!* =====================================================================
*!* Banbaj · Exporta los DBF del 486 a CSV para la migración inicial
*!* (una sola vez). Después, en SQL Server:
*!*     EXEC ops.sp_migrar_486 @carpeta = N'C:\MIGRA486\';                 && revisa
*!*     EXEC ops.sp_migrar_486 @carpeta = N'C:\MIGRA486\', @confirmar = 1; && carga
*!* Al terminar, borra C:\MIGRA486 (trae datos de clientes).
*!* PURGA y DEVOL no se migran (decisión).
*!* =====================================================================
SET SAFETY OFF
SET DELETED ON          && los registros borrados no se exportan
SET CENTURY ON
SET DATE YMD
CLOSE TABLES ALL

lcDestino = "C:\MIGRA486\"
IF !DIRECTORY(lcDestino)
    MKDIR (lcDestino)
ENDIF

DIMENSION laF[15, 2]
laF[1, 1]  = "DAT"       && laF[n, 2] = ruta del DBF (tomada de los .prg; ajústala si cambió)
laF[1, 2]  = "O:\DAT\GPO1\486\DAT.DBF"
laF[2, 1]  = "TAB7"
laF[2, 2]  = "O:\DAT\GPO1\486\TAB7.DBF"
laF[3, 1]  = "HISTORIA"
laF[3, 2]  = "O:\HISTORIA\GPO1\486\HISTORIA.DBF"
laF[4, 1]  = "PAGTOT"
laF[4, 2]  = "O:\PRG\GPO1\486\PAGOS\PAGTOT.DBF"
laF[5, 1]  = "ETI"
laF[5, 2]  = "O:\PRG\MEXGPO1\ASI486\ETI.DBF"
laF[6, 1]  = "DM1"
laF[6, 2]  = "O:\PRG\MEXGPO1\ASI486\DM1.DBF"
laF[7, 1]  = "TOP"
laF[7, 2]  = "O:\PRG\MEXGPO1\ASI486\TOP.DBF"
laF[8, 1]  = "STATUS"
laF[8, 2]  = "O:\PRG\MEXGPO1\ASI486\STATUS.DBF"
laF[9, 1]  = "EXC486"
laF[9, 2]  = "O:\PRG\GPO1\486\EXC486.DBF"
laF[10, 1] = "DIRMAL"
laF[10, 2] = "O:\ASIGNA\DIRMAL.DBF"
laF[11, 1] = "EMAILMALO"
laF[11, 2] = "O:\ASIGNA\EMAILMALO.DBF"
laF[12, 1] = "BLACKLIST"
laF[12, 2] = "O:\PRG\MEXGPO1\ASI486\BLACKLIST_486.DBF"
laF[13, 1] = "TELBAJ"
laF[13, 2] = "\\192.168.50.108\T\CYBER_SISTEMAS\CYBER\TELEFONOS\TELBAJ_G1.DBF"
laF[14, 1] = "LADA"
laF[14, 2] = "O:\PRG\MEXGPO1\ASI486\LADA.DBF"
laF[15, 1] = "PNC"
laF[15, 2] = "\\192.168.50.108\T\CYBER_SISTEMAS\CYBER\PNM\PNC.DBF"

lcReporte = ""
FOR i = 1 TO ALEN(laF, 1)
    IF FILE(laF[i, 2])
        USE (laF[i, 2]) IN 0 SHARED NOUPDATE ALIAS fuente
        SELECT fuente
        COPY TO (lcDestino + laF[i, 1] + ".csv") TYPE CSV
        lcReporte = lcReporte + PADR(laF[i, 1], 12) + TRANSFORM(RECCOUNT()) + " registros" + CHR(13)
        USE IN fuente
    ELSE
        lcReporte = lcReporte + PADR(laF[i, 1], 12) + "NO SE ENCONTRÓ " + laF[i, 2] + CHR(13)
    ENDIF
ENDFOR
MESSAGEBOX(lcReporte, 64, "CSV en " + lcDestino)
