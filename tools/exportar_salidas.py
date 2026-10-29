"""Escribe en disco los archivos planos y los scripts de CYBER de una corrida, para arribarlos a mano.

    python tools/exportar_salidas.py --conexion "DRIVER={ODBC Driver 18 for SQL Server};SERVER=srv;DATABASE=Banbaj;Trusted_Connection=yes;TrustServerCertificate=yes" \
        --corrida 125 --carpeta "D:\\Banbaj\\486\\salida"

    --corrida      sin ella, la última corrida OK del cliente
    --solo         archivos separados por coma (ej. SCBPAG,SCBTEL)
    --sin-scripts  no escribe los .sql de CYBER

Cada archivo usa el nombre, la codificación y el fin de línea de cfg.SALIDA_ARCHIVO
(por defecto Windows-1252 y CRLF, como COPY TO … SDF de FoxPro). Se crea una
subcarpeta <AAAAMMDD>_corrida<ID>; los scripts de CYBER van en cyber/ con commit y exit.
Un archivo sin líneas no se escribe (se avisa).

Requiere: pip install pyodbc
"""
import argparse
import datetime as dt
import sys
from pathlib import Path


def nombre_archivo(patron, fecha, ahora, corrida):
    return (patron.replace("{AAAAMMDD}", fecha.strftime("%Y%m%d"))
                  .replace("{MMDDAAAA}", fecha.strftime("%m%d%Y"))
                  .replace("{HHMMSS}", ahora.strftime("%H%M%S"))
                  .replace("{CORRIDA}", str(corrida)))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--conexion", required=True)
    ap.add_argument("--cliente", default="486")
    ap.add_argument("--corrida", type=int)
    ap.add_argument("--carpeta", default=".")
    ap.add_argument("--solo")
    ap.add_argument("--sin-scripts", action="store_true")
    a = ap.parse_args()

    import pyodbc
    cn = pyodbc.connect(a.conexion)
    cur = cn.cursor()

    if a.corrida is None:
        cur.execute("SELECT TOP (1) ID_CORRIDA FROM ops.CORRIDA WHERE CLIENTE = ? AND ESTATUS = 'OK' ORDER BY ID_CORRIDA DESC", a.cliente)
        r = cur.fetchone()
        if not r:
            print("No hay corridas OK.")
            return 1
        a.corrida = r[0]
    cur.execute("SELECT CLIENTE, PROCESO, FECHA_PROCESO, ESTATUS FROM ops.CORRIDA WHERE ID_CORRIDA = ?", a.corrida)
    r = cur.fetchone()
    if not r:
        print(f"La corrida {a.corrida} no existe.")
        return 1
    cliente, proceso, fecha, estatus = r
    if estatus not in ("OK",):
        print(f"Aviso: la corrida {a.corrida} está en estatus {estatus}.")
    ahora = dt.datetime.now()
    destino = Path(a.carpeta) / f"{fecha:%Y%m%d}_corrida{a.corrida}"
    destino.mkdir(parents=True, exist_ok=True)
    solo = {x.strip().upper() for x in a.solo.split(",")} if a.solo else None

    print(f"Corrida {a.corrida} ({proceso} {fecha:%d/%m/%Y}) -> {destino}")
    cur.execute("""
        SELECT l.ARCHIVO, COUNT(*) AS N, MAX(s.NOMBRE), MAX(s.FIN_DE_LINEA), MAX(s.CODIFICACION),
               MAX(CAST(s.ENCABEZADO AS INT)), MAX(s.SEPARADOR)
        FROM ops.SALIDA_LINEA l
        LEFT JOIN cfg.SALIDA_ARCHIVO s ON s.CLIENTE = ? AND s.ARCHIVO = l.ARCHIVO
        WHERE l.ID_CORRIDA = ?
        GROUP BY l.ARCHIVO ORDER BY l.ARCHIVO""", cliente, a.corrida)
    archivos = cur.fetchall()
    escritos = 0
    for archivo, n, patron, fin, cod, encabezado, sep in archivos:
        if solo and archivo.upper() not in solo:
            continue
        nombre = nombre_archivo(patron or f"{archivo}.TXT", fecha, ahora, a.corrida)
        eol = "\r\n" if (fin or "CRLF") == "CRLF" else "\n"
        cur.execute("SELECT LINEA FROM ops.SALIDA_LINEA WHERE ID_CORRIDA = ? AND ARCHIVO = ? ORDER BY NUM", a.corrida, archivo)
        lineas = [x[0] for x in cur.fetchall()]
        if encabezado:
            cur.execute("SELECT CAMPO FROM cfg.SALIDA WHERE CLIENTE = ? AND ARCHIVO = ? AND ACTIVO = 1 ORDER BY ORDEN", cliente, archivo)
            lineas.insert(0, (sep or ",").join(x[0] for x in cur.fetchall()))
        ruta = destino / nombre
        with open(ruta, "w", encoding=cod or "cp1252", errors="replace", newline="") as f:
            for linea in lineas:
                f.write(linea + eol)
        escritos += 1
        print(f"  {nombre:<40} {len(lineas):>8} líneas  ({archivo})")

    # Archivos que se generaron sin líneas (ej. gescar REA cuando no hubo reasignadas)
    cur.execute("SELECT MENSAJE FROM ops.BITACORA WHERE ID_CORRIDA = ? AND PASO = 'SALIDA' AND ISNULL(REGISTROS, 0) = 0", a.corrida)
    for (msg,) in cur.fetchall():
        print(f"  sin líneas: {msg.split(' · ')[0]}")

    if not a.sin_scripts:
        cur.execute("SELECT SCRIPT, SENTENCIA FROM ops.CYBER_SCRIPT WHERE ID_CORRIDA = ? ORDER BY SCRIPT, NUM", a.corrida)
        scripts = {}
        for script, sentencia in cur.fetchall():
            scripts.setdefault(script, []).append(sentencia)
        if scripts:
            (destino / "cyber").mkdir(exist_ok=True)
        for script, sentencias in scripts.items():
            ruta = destino / "cyber" / f"{script}.sql"
            with open(ruta, "w", encoding="cp1252", errors="replace", newline="") as f:
                f.write("\r\n".join(sentencias) + "\r\n")
            print(f"  cyber/{script + '.sql':<34} {len(sentencias):>8} sentencias")

    print(f"Listo: {escritos} archivos.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
