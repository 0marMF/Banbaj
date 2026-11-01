*!* =====================================================================
*!* Banbaj · Exporta los DBF del 486 a CSV para la migración inicial
*!* (una sola vez). Después, en SQL Server:
*!*     EXEC ops.sp_migrar_486 @carpeta = N'C:\MIGRA486\';                 && revisa
*!*     EXEC ops.sp_migrar_486 @carpeta = N'C:\MIGRA486\', @confirmar = 1; && carga
*!* Al terminar, borra C:\MIGRA486 (trae datos de clientes). No los subas a
*!* ningún repositorio.
*!*
*!* Solo se exportan los campos que usa la migración (laF[n, 3]); si un campo
*!* no existe en el DBF se omite y se avisa. "*" = todos los campos (DAT).
*!* No se migran: PURGA y DEVOL (decisión); TELBAJ y PNC (se leen de CYBER en
*!* cada asignación); LADA (ningún proceso la usa).
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

*!* laF[n, 1] = nombre del CSV, laF[n, 2] = ruta del DBF (tomada de los .prg; ajústala si cambió),
*!* laF[n, 3] = campos que se usan
DIMENSION laF[12, 3]
laF[1, 1]  = "DAT"
laF[1, 2]  = "O:\DAT\GPO1\486\DAT.DBF"
laF[1, 3]  = "*"
laF[2, 1]  = "TAB7"
laF[2, 2]  = "O:\DAT\GPO1\486\TAB7.DBF"
laF[2, 3]  = "FOLIO"
laF[3, 1]  = "HISTORIA"
laF[3, 2]  = "O:\HISTORIA\GPO1\486\HISTORIA.DBF"
laF[3, 3]  = "CUENTA,FOLIO,CUENTA2,RIESGO,SEGMENTO2,SUB_CTE,FE_ASIG,FECHA"
laF[4, 1]  = "PAGTOT"
laF[4, 2]  = "O:\PRG\GPO1\486\PAGOS\PAGTOT.DBF"
laF[4, 3]  = "CUENTA,FE_PAG,MONT,FE_REG"
laF[5, 1]  = "ETI"
laF[5, 2]  = "O:\PRG\MEXGPO1\ASI486\ETI.DBF"
laF[5, 3]  = "CUENTA,ETIQUETA"
laF[6, 1]  = "DM1"
laF[6, 2]  = "O:\PRG\MEXGPO1\ASI486\DM1.DBF"
laF[6, 3]  = "CUENTA,ETIQUETA"
laF[7, 1]  = "TOP"
laF[7, 2]  = "O:\PRG\MEXGPO1\ASI486\TOP.DBF"
laF[7, 3]  = "CUENTA2,ETIQUETA"
laF[8, 1]  = "STATUS"
laF[8, 2]  = "O:\PRG\MEXGPO1\ASI486\STATUS.DBF"
laF[8, 3]  = "CUENTA,ESTATUS"
laF[9, 1]  = "EXC486"
laF[9, 2]  = "O:\PRG\GPO1\486\EXC486.DBF"
laF[9, 3]  = "CUENTA"
laF[10, 1] = "DIRMAL"
laF[10, 2] = "O:\ASIGNA\DIRMAL.DBF"
laF[10, 3] = "CUENTA,DIRECC1"
laF[11, 1] = "EMAILMALO"
laF[11, 2] = "O:\ASIGNA\EMAILMALO.DBF"
laF[11, 3] = "EMAIL,CUENTA"
laF[12, 1] = "BLACKLIST"
laF[12, 2] = "O:\PRG\MEXGPO1\ASI486\BLACKLIST_486.DBF"
laF[12, 3] = "TELEFONO,TEL,OS,FECHA,STATUS"      && sin STATUS en el DBF, todo cuenta como X

lcReporte = ""
FOR i = 1 TO ALEN(laF, 1)
    IF FILE(laF[i, 2])
        USE (laF[i, 2]) IN 0 SHARED NOUPDATE ALIAS fuente
        SELECT fuente
        IF laF[i, 3] == "*"
            COPY TO (lcDestino + laF[i, 1] + ".csv") TYPE CSV
            lcFaltan = ""
        ELSE
            *!* Solo los campos que existen en el DBF
            lcCampos = ""
            lcFaltan = ""
            FOR j = 1 TO GETWORDCOUNT(laF[i, 3], ",")
                lcCampo = ALLTRIM(GETWORDNUM(laF[i, 3], j, ","))
                IF TYPE("fuente." + lcCampo) <> "U"
                    lcCampos = lcCampos + IIF(EMPTY(lcCampos), "", ",") + lcCampo
                ELSE
                    lcFaltan = lcFaltan + IIF(EMPTY(lcFaltan), "", ",") + lcCampo
                ENDIF
            ENDFOR
            IF EMPTY(lcCampos)
                lcReporte = lcReporte + PADR(laF[i, 1], 12) + "NINGUNO DE LOS CAMPOS " + laF[i, 3] + " EXISTE" + CHR(13)
                USE IN fuente
                LOOP
            ENDIF
            COPY TO (lcDestino + laF[i, 1] + ".csv") FIELDS &lcCampos TYPE CSV
        ENDIF
        lcReporte = lcReporte + PADR(laF[i, 1], 12) + TRANSFORM(RECCOUNT()) + " registros" ;
                  + IIF(EMPTY(lcFaltan), "", "  (no existen: " + lcFaltan + ")") + CHR(13)
        USE IN fuente
    ELSE
        lcReporte = lcReporte + PADR(laF[i, 1], 12) + "NO SE ENCONTRÓ " + laF[i, 2] + CHR(13)
    ENDIF
ENDFOR
MESSAGEBOX(lcReporte, 64, "CSV en " + lcDestino)
