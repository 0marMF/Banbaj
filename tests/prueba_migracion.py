"""Prueba de tools/migrar_dbf.py con DBF ficticios contra SQL Server.

Uso: python tests/prueba_migracion.py "<cadena ODBC a una base con los scripts sql/ ya ejecutados>"
Requiere: pip install dbf dbfread pyodbc
"""
import datetime as dt
import json
import subprocess
import sys
import tempfile
from pathlib import Path

import dbf
import pyodbc

RAIZ = Path(__file__).resolve().parent.parent


def tabla(ruta, specs, filas):
    t = dbf.Table(str(ruta), specs, codepage="cp1252")
    t.open(dbf.READ_WRITE)
    for f in filas:
        t.append(f)
    t.close()


def main(conexion):
    d = Path(tempfile.mkdtemp())
    tabla(d / "DAT.DBF", "FOLIO C(10); CLIENTE C(3); SUB_CTE C(10); NOMBRE1 C(50); CUENTA C(20); CUENTA2 C(28); "
                         "SEGMENTO2 C(20); FE_ASIG D; SDO_ACT N(13,2); ETIQUETA1 C(10)", [
        ("       100", "486", "NVA", "CLIENTE UNO", "20000001", "486-100", "CONSUMO", dt.date(2026, 10, 1), 1500.50, "MORA 1"),
        ("       101", "486", "REA", "CLIENTE DOS", "20000002", "486-101", "TDC", dt.date(2026, 10, 2), 0, ""),
    ])
    tabla(d / "PURGA.DBF", "FOLIO C(10); CUENTA C(20); CUENTA2 C(28); SEGMENTO2 C(20); SUB_CTE C(10); FE_ASIG D", [
        ("        90", "20000009", "486-90", "CONSUMO", "NVA", dt.date(2025, 1, 1)),
        ("        90", "20000009", "486-90", "CONSUMO", "NVA", dt.date(2025, 1, 1)),   # repetido
        ("       100", "20000001", "486-100", "CONSUMO", "NVA", dt.date(2026, 10, 1)),  # sigue activa: no es baja
    ])
    tabla(d / "TAB7.DBF", "FOLIO C(10)", [("        95",), ("       150",)])
    tabla(d / "HISTORIA.DBF", "FOLIO C(10); CUENTA C(20)", [("       160", "20000007"), ("        90", "20000009")])
    tabla(d / "PAGTOT.DBF", "IDE C(3); GRUPO C(1); CUENTA C(25); FE_PAG C(8); MONT C(15); SEGMENTO C(6); AGEN C(8); "
                            "FE_REG C(8); TRAN C(15); MOREAL C(15); FOLIO C(10); MONTO C(10); FECHA D", [
        ("500", "1", "20000001", "10022026", "000000001000.00", "pbank", "SERTEC", "10032026", "PAGO", "000000001000.00", "", "", None),
        ("500", "1", "20000001", "10022026", "000000001000.00", "pbank", "SERTEC", "10032026", "PAGO", "000000001000.00", "", "", None),
        ("500", "1", "2000000", "1C  0603", "2abc", "SERTE", "C  06032", "", "", "", "", "", None),   # renglón corrido
    ])
    tabla(d / "TOP.DBF", "CUENTA2 C(28); ETIQUETA C(15)", [("486-100", "REE"), ("486-999", "REE")])
    tabla(d / "EXC486.DBF", "CUENTA C(20)", [("20000008",)])
    tabla(d / "BLACKLIST.DBF", "TEL C(15)", [("5500000000",)])
    tabla(d / "TELBAJ.DBF", "CUENTA C(28); TEL C(15)", [("486-100", "5511111111"), ("307-55", "5522222222")])
    tabla(d / "LADA.DBF", "CP C(5); LADA C(5)", [("06600", "55"), ("37236", "477")])
    tabla(d / "PNC.DBF", "LADA C(3); SERIE C(5); N_INI N(5,0); N_FIN N(5,0); TIPORED C(12)",
          [("55", "1234", 0, 9999, "MOVIL"), ("477", "714", 0, 4999, "FIJO")])

    cfg = {"cliente": "486", "fuentes": {k: str(d / f"{k}.DBF") for k in
           ["DAT", "PURGA", "TAB7", "HISTORIA", "PAGTOT", "TOP", "EXC486", "BLACKLIST", "TELBAJ", "LADA", "PNC"]}}
    (d / "cfg.json").write_text(json.dumps(cfg), encoding="utf-8")
    cmd = [sys.executable, str(RAIZ / "tools" / "migrar_dbf.py"), "--config", str(d / "cfg.json")]

    resultados = []

    def ok(nombre, cond, detalle=""):
        resultados.append(cond)
        print(("OK    " if cond else "FALLA ") + nombre + (f"  [{detalle}]" if detalle else ""))

    r = subprocess.run(cmd, capture_output=True, text=True)
    print(r.stdout)
    ok("Revisión sin conexión no falla", r.returncode == 0, r.stderr[-300:])

    r = subprocess.run(cmd + ["--conexion", conexion], capture_output=True, text=True)
    print(r.stdout)
    ok("Primera carga", r.returncode == 0, (r.stdout + r.stderr)[-300:])

    r = subprocess.run(cmd + ["--conexion", conexion], capture_output=True, text=True)
    ok("Segunda carga sin --reemplazar se rechaza y no cambia nada", r.returncode == 1 and "rollback" in r.stdout)

    r = subprocess.run(cmd + ["--conexion", conexion, "--reemplazar"], capture_output=True, text=True)
    ok("Carga con --reemplazar", r.returncode == 0, (r.stdout + r.stderr)[-300:])

    cn = pyodbc.connect(conexion)
    q = lambda sql: cn.cursor().execute(sql).fetchone()[0]
    ok("DAT: 2 cuentas, folio sin espacios, vacío -> NULL",
       q("SELECT CONCAT(COUNT(*), '|', MAX(FOLIO), '|', SUM(CASE WHEN ETIQUETA1 IS NULL THEN 1 ELSE 0 END)) FROM dat.DAT_486") == "2|101|1")
    ok("DAT: importe y fecha", q("SELECT CONCAT(SDO_ACT, '|', FE_ASIG) FROM dat.DAT_486 WHERE CUENTA = '20000001'") == "1500.50|2026-10-01")
    ok("HISTORIA: 2 activas + 1 baja de PURGA (sin repetidos)",
       q("SELECT STRING_AGG(CONCAT(CUENTA, ':', ESTATUS), ',') WITHIN GROUP (ORDER BY CUENTA) FROM dat.HISTORIA_FOLIO")
       == "20000001:A,20000002:A,20000009:B")
    ok("CONSECUTIVO: máximo de TAB7 / DAT / PURGA / HISTORIA", q("SELECT ULTIMO_FOLIO FROM dat.FOLIO_CONSECUTIVO WHERE CLIENTE = '486'") == 160)
    ok("PAGOS: PAGTOT con solo cuenta, fecha e importe (renglón corrido omitido, iguales se conservan)",
       q("SELECT CONCAT(COUNT(*), '|', MIN(CUENTA), '|', MIN(FE_PAG), '|', MIN(IMPORTE), '|', MIN(ORIGEN), '|', MIN(FE_REG)) FROM dat.PAGO_ARRIBADO")
       == "2|20000001|2026-10-02|1000.00|PAGTOT|2026-10-03")
    ok("ETIQUETAS: TOP", q("SELECT STRING_AGG(CONCAT(TIPO, ':', LLAVE, ':', VALOR), ',') WITHIN GROUP (ORDER BY TIPO, LLAVE) "
                           "FROM cfg.ETIQUETA") == "TOP:486-100:REE,TOP:486-999:REE")
    ok("EXCLUSIONES: 3 del banco (semilla) + exc486 + blacklist + TELBAJ solo del 486",
       q("SELECT CONCAT(COUNT(*), '|', SUM(CASE WHEN VALOR2 = '486-100' THEN 1 ELSE 0 END), '|', "
         "SUM(CASE WHEN VALOR = '5522222222' THEN 1 ELSE 0 END)) FROM cfg.EXCLUSION") == "6|1|0")
    ok("LADA y PNC", q("SELECT CONCAT((SELECT COUNT(*) FROM cfg.LADA), '|', (SELECT COUNT(*) FROM cfg.PLAN_NUMERACION))") == "2|2")

    print(f"MIGRACION: {sum(resultados)} de {len(resultados)} OK")
    return 0 if all(resultados) else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
