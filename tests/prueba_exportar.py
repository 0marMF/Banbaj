"""Prueba de tools/exportar_salidas.py contra la base de tests/pruebas.sql (corridas 2 = asignación, 3 = actualización).

Uso: python tests/prueba_exportar.py "<cadena ODBC>"
"""
import os
import subprocess
import sys
import tempfile
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent


def main(conexion):
    res = []

    def ok(nombre, cond, detalle=""):
        res.append(bool(cond))
        print(("OK    " if cond else "FALLA ") + nombre + (f"  [{detalle}]" if detalle else ""))

    tmp = Path(tempfile.mkdtemp())
    for corrida in (2, 3):
        r = subprocess.run([sys.executable, str(RAIZ / "tools" / "exportar_salidas.py"), "--conexion", conexion,
                            "--corrida", str(corrida), "--carpeta", str(tmp)], capture_output=True, text=True)
        print(r.stdout)
        ok(f"Exporta la corrida {corrida}", r.returncode == 0, r.stderr[-300:])

    asig = tmp / "20261102_corrida2"
    act = tmp / "20261103_corrida3"

    def lineas(ruta):
        datos = ruta.read_bytes()
        return datos, datos.split(b"\r\n")[:-1]

    for nombre, ancho, n in [("SCBSDOS.TXT", 1559, 8), ("SCBTEL.TXT", 137, 7), ("SCBACTH_486NU.TXT", 119, 4),
                             ("SCBACTH_486REA.TXT", 119, 1), ("SCBACTH_486.TXT", 119, 2)]:
        ruta = asig / nombre
        if not ruta.exists():
            ok(f"{nombre}: existe", False)
            continue
        datos, ls = lineas(ruta)
        ok(f"{nombre}: {n} líneas de {ancho} con CRLF", len(ls) == n and all(len(x) == ancho for x in ls)
           and datos.count(b"\n") == datos.count(b"\r\n"), f"{len(ls)} líneas, anchos {sorted({len(x) for x in ls})}")

    datos, ls = lineas(asig / "sub_mst.TXT") if (asig / "sub_mst.TXT").exists() else (b"", [])
    ok("sub_mst.TXT: delimitado por | sin comillas", len(ls) == 7 and ls[0] == b"486-100|01477|7001234|4", ls[:1])

    devol = list(asig.glob("MX_G1MCT_DVBJIG_20261102_*"))
    ok("Devolución para CYBER con fecha y hora en el nombre", len(devol) == 1 and lineas(devol[0])[1][0].rstrip() == b"486-101")
    ok("Lista de retiros para operación", (asig / "RETIROS_486_20261102.csv").exists())

    # ZIP con contraseña de los retiros (saldos.prg: RETIROS_PAG_486_*.zip)
    tmpz = Path(tempfile.mkdtemp())
    env = dict(os.environ, BANBAJ_ZIP_CLAVE="Prueba{MM}{AAAA}")
    r = subprocess.run([sys.executable, str(RAIZ / "tools" / "exportar_salidas.py"), "--conexion", conexion, "--corrida", "2",
                        "--carpeta", str(tmpz), "--solo", "RETIROS", "--zip", "RETIROS", "--carpeta-zip", str(tmpz)], capture_output=True, text=True, env=env)
    zips = list(tmpz.glob("RETIROS_PAG_486_*.zip"))
    contenido = b""
    if zips:
        import pyzipper, datetime as dt
        clave = dt.date.today().strftime("Prueba%m%Y").encode()
        with pyzipper.AESZipFile(zips[0]) as z:
            z.setpassword(clave)
            contenido = z.read("RETIROS_486_20261102.csv")
    original = (asig / "RETIROS_486_20261102.csv").read_bytes() if (asig / "RETIROS_486_20261102.csv").exists() else None
    ok("ZIP de retiros con contraseña (mismo contenido que el CSV)", r.returncode == 0 and len(zips) == 1 and contenido and contenido == original,
       (r.stdout + r.stderr)[-300:])
    ok("Scripts de CYBER (retiro y teléfonos)", (asig / "cyber" / "RETIRO.sql").exists() and (asig / "cyber" / "TEL_ACTUALIZA.sql").exists())

    mis = asig / "DAT486_20261102.csv"
    datos, ls = lineas(mis) if mis.exists() else (b"", [])
    ok("DAT para MIS en CSV con encabezado", len(ls) == 9 and ls[0].startswith(b"FOLIO,CLIENTE,SUB_CTE") and ls[1].startswith(b'"100","486"'))

    ruta = act / "SCBPAG.TXT"
    datos, ls = lineas(ruta) if ruta.exists() else (b"", [])
    ok("SCBPAG.TXT: 4 líneas de 104", len(ls) == 4 and all(len(x) == 104 for x in ls))
    ok("Scripts de saldos para CYBER", all((act / "cyber" / f"{s}.sql").exists() for s in ("ACT_SALDOS", "ACT_VENCIDO", "ACT_PAGMIN")))
    sql = (act / "cyber" / "ACT_SALDOS.sql").read_bytes() if (act / "cyber" / "ACT_SALDOS.sql").exists() else b""
    ok("Script termina en commit y exit", sql.endswith(b"commit;\r\nexit;\r\n"))

    print(f"EXPORTAR: {sum(res)} de {len(res)} OK")
    return 0 if all(res) else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
