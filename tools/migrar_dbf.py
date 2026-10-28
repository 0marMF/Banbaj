"""Migra las tablas DBF del cliente 486 a SQL Server.

    # 1) Revisar (no escribe nada): lee cada DBF, valida campos y muestra conteos y avisos
    python tools/migrar_dbf.py --config tools/migracion_486.json

    # 2) Cargar
    python tools/migrar_dbf.py --config tools/migracion_486.json \
        --conexion "DRIVER={ODBC Driver 18 for SQL Server};SERVER=srv;DATABASE=Banbaj;Trusted_Connection=yes;TrustServerCertificate=yes"

    # Si las tablas destino ya tienen datos hay que pedir --reemplazar.
    # --solo DAT,ETIQUETAS,...  limita a algunos destinos.

Destinos (se cargan en una sola transacción; si algo falla no queda nada a medias):
    DAT          DAT.DBF                                  -> dat.DAT_486
    HISTORIA     DAT.DBF (activas) + PURGA.DBF (bajas)    -> dat.HISTORIA_FOLIO
    CONSECUTIVO  TAB7.DBF (máximo folio)                  -> dat.FOLIO_CONSECUTIVO
    ETIQUETAS    ETI486, ETI, DM1, TOP, STATUS            -> cfg.ETIQUETA
    EXCLUSIONES  EXC486, DIRMAL, EMAILMALO, BLACKLIST, TELBAJ + teléfonos del banco -> cfg.EXCLUSION
    LADA         LADA.DBF                                 -> cfg.LADA
    PNC          PNC.DBF                                  -> cfg.PLAN_NUMERACION

Requiere: pip install dbfread pyodbc  (pyodbc solo para cargar)
"""
import argparse
import datetime as dt
import json
import sys
from decimal import Decimal
from pathlib import Path

from dbfread import DBF

MIGRACION = "MIGRACION DBF"
# Teléfonos de dueños del banco excluidos en telbnx.prg (REQ 2022-004456)
TELEFONOS_BANCO = ["4777140350", "4777140308", "4777147689"]

# Etiquetas: tipo -> (campo llave, tipo de llave, campo valor)   (cruces de asi486.prg)
ETIQUETAS = {
    "ETI486": ("CUENTA2", "CUENTA2", "MORA"),
    "ETI":    ("CUENTA", "CUENTA", "ETIQUETA"),
    "DM1":    ("CUENTA", "CUENTA", "ETIQUETA"),
    "TOP":    ("CUENTA2", "CUENTA2", "ETIQUETA"),
    "STATUS": ("CUENTA", "CUENTA", "ESTATUS"),
}


class ErrorFuente(Exception):
    pass


# ------------------------------------------------------------------ lectura
def leer(ruta):
    p = Path(ruta)
    if not p.exists():
        raise FileNotFoundError(ruta)
    tabla = DBF(str(p), encoding="cp1252", char_decode_errors="replace", ignore_missing_memofile=True)
    campos = [f.name.upper() for f in tabla.fields]
    filas = []
    for r in tabla:                      # dbfread omite los registros marcados como borrados
        fila = {}
        for k, v in r.items():
            if isinstance(v, str):
                v = v.strip() or None
            fila[k.upper()] = v
        filas.append(fila)
    return campos, filas


def exigir(nombre, campos, requeridos):
    falta = [c for c in requeridos if c not in campos]
    if falta:
        raise ErrorFuente(f"{nombre}: faltan los campos {falta}. Campos del archivo: {campos}")


def primero(fila, *nombres):
    for n in nombres:
        if n in fila and fila[n] not in (None, ""):
            return fila[n]
    return None


def folio_int(v):
    try:
        return int(str(v).strip())
    except (TypeError, ValueError):
        return None


# ------------------------------------------------------------------ transformaciones
def destino_dat(cfg, fuentes, avisos):
    campos, filas = fuentes["DAT"]
    exigir("DAT", campos, ["CUENTA", "FOLIO", "CUENTA2"])
    vistas, salida = set(), []
    for f in filas:
        if not f.get("CUENTA"):
            avisos.append("DAT: registro sin CUENTA omitido")
            continue
        if f["CUENTA"] in vistas:
            avisos.append(f"DAT: CUENTA repetida omitida ({f['CUENTA'][:4]}…)")
            continue
        vistas.add(f["CUENTA"])
        salida.append(f)
    return campos, salida


def destino_historia(cfg, fuentes, avisos):
    cli = cfg["cliente"]
    filas = []
    _, dat = fuentes["DAT"]
    activas = set()
    for f in dat:
        fol = folio_int(f.get("FOLIO"))
        if f.get("CUENTA") is None or fol is None:
            continue
        activas.add((f["CUENTA"], fol))
        sub = f.get("SUB_CTE") if f.get("SUB_CTE") in ("NVA", "REA") else "NVA"
        filas.append((cli, f["CUENTA"], fol, f.get("CUENTA2") or f"{cli}-{fol}", f.get("SEGMENTO2"), sub, "A",
                      f.get("FE_ASIG") or dt.date(1900, 1, 1), None, None))
    if "PURGA" in fuentes:
        campos, purga = fuentes["PURGA"]
        exigir("PURGA", campos, ["CUENTA", "FOLIO"])
        vistas = set()
        for f in purga:
            fol = folio_int(f.get("FOLIO"))
            if f.get("CUENTA") is None or fol is None:
                avisos.append("PURGA: registro sin CUENTA o FOLIO numérico omitido")
                continue
            k = (f["CUENTA"], fol)
            if k in activas or k in vistas:
                continue
            vistas.add(k)
            sub = f.get("SUB_CTE") if f.get("SUB_CTE") in ("NVA", "REA") else "NVA"
            fe_baja = primero(f, "FE_BAJA", "FECHA_BAJA", "FE_PURGA", "FE_DEV", "FECHA")
            if not isinstance(fe_baja, dt.date):
                fe_baja = None
            filas.append((cli, f["CUENTA"], fol, f.get("CUENTA2") or f"{cli}-{fol}", f.get("SEGMENTO2"), sub, "B",
                          f.get("FE_ASIG") or dt.date(1900, 1, 1), fe_baja, "MIGRACION PURGA"))
    else:
        avisos.append("HISTORIA: sin PURGA, las cuentas que regresen no se reconocerán como REA")
    return ["CLIENTE", "CUENTA", "FOLIO", "CUENTA2", "SEGMENTO2", "SUB_CTE", "ESTATUS", "FE_ALTA", "FE_BAJA", "MOTIVO_BAJA"], filas


def destino_consecutivo(cfg, fuentes, avisos):
    maximos = {}
    if "TAB7" in fuentes:
        campos, tab7 = fuentes["TAB7"]
        exigir("TAB7", campos, ["FOLIO"])
        maximos["TAB7"] = max((folio_int(f.get("FOLIO")) or 0 for f in tab7), default=0)
    for k in ("DAT", "PURGA"):
        if k in fuentes:
            maximos[k] = max((folio_int(f.get("FOLIO")) or 0 for f in fuentes[k][1]), default=0)
    if not maximos:
        raise ErrorFuente("CONSECUTIVO: no hay TAB7 ni DAT para calcular el último folio")
    ultimo = max(maximos.values())
    if maximos.get("TAB7", ultimo) < ultimo:
        avisos.append(f"CONSECUTIVO: TAB7 ({maximos['TAB7']}) es menor que el folio más alto usado ({ultimo}); se toma {ultimo}")
    return ["CLIENTE", "ULTIMO_FOLIO"], [(cfg["cliente"], ultimo)]


def destino_etiquetas(cfg, fuentes, avisos):
    cli = cfg["cliente"]
    filas, tipos = [], []
    for tipo, (llave, _, valor) in ETIQUETAS.items():
        if tipo not in fuentes:
            continue
        campos, datos = fuentes[tipo]
        exigir(tipo, campos, [llave, valor])
        tipos.append(tipo)
        ultimo = {}
        for f in datos:
            if f.get(llave) and f.get(valor):
                ultimo[f[llave]] = f[valor]          # si se repite, gana el último
        filas += [(cli, tipo, k[:30], str(v)[:100]) for k, v in ultimo.items()]
    return ["CLIENTE", "TIPO", "LLAVE", "VALOR"], filas, tipos


def destino_exclusiones(cfg, fuentes, avisos, cuentas_486):
    cli = cfg["cliente"]
    filas = [(cli, "TELEFONO", t, None, "Teléfono de dueños del banco", MIGRACION) for t in TELEFONOS_BANCO]

    def del_486(c):
        return c and (c.startswith(f"{cli}-") or c in cuentas_486)

    reglas = [  # fuente, tipo, campo valor, campo valor2, motivo, filtrar por cuenta en valor2/valor
        ("EXC486", "CUENTA", "CUENTA", None, "Exclusión de cuentas (exc486)", None),
        ("DIRMAL", "DIRECCION", "CUENTA", "DIRECC1", "Dirección mala (dirmal)", "VALOR"),
        ("EMAILMALO", "CORREO", "EMAIL", "CUENTA", "Correo malo (EMAILMALO)", "VALOR2"),
        ("BLACKLIST", "TELEFONO", "TEL", None, "Lista negra de teléfonos (REQ 2024-095288)", None),
        ("TELBAJ", "TELEFONO", "TEL", "CUENTA", "Teléfono dado de baja para la cuenta (TELBAJ_G1)", "VALOR2"),
    ]
    for fuente, tipo, cv, cv2, motivo, filtro in reglas:
        if fuente not in fuentes:
            continue
        campos, datos = fuentes[fuente]
        exigir(fuente, campos, [c for c in (cv, cv2) if c])
        antes = len(filas)
        vistas = set()
        for f in datos:
            v, v2 = f.get(cv), (f.get(cv2) if cv2 else None)
            if not v:
                continue
            if filtro == "VALOR" and not del_486(v):
                continue
            if filtro == "VALOR2" and not del_486(v2):
                continue
            k = (tipo, str(v).lower() if tipo == "CORREO" else v, v2)
            if k in vistas:
                continue
            vistas.add(k)
            filas.append((cli, tipo, str(k[1])[:200], (str(v2)[:200] if v2 else None), motivo, MIGRACION))
        avisos.append(f"{fuente}: {len(filas) - antes} de {len(datos)} registros aplican al {cli}")
    return ["CLIENTE", "TIPO", "VALOR", "VALOR2", "MOTIVO", "REQ"], filas


def destino_lada(cfg, fuentes, avisos):
    campos, datos = fuentes["LADA"]
    exigir("LADA", campos, ["CP", "LADA"])
    u = {}
    for f in datos:
        if f.get("CP") and f.get("LADA"):
            u[str(f["CP"]).zfill(5)[:5]] = str(f["LADA"])[:5]
    return ["CP", "LADA"], list(u.items())


def destino_pnc(cfg, fuentes, avisos):
    campos, datos = fuentes["PNC"]
    exigir("PNC", campos, ["LADA", "SERIE", "N_INI", "N_FIN", "TIPORED"])
    u = {}
    for f in datos:
        if f.get("LADA") and f.get("SERIE") and f.get("N_INI") is not None:
            u[(f["LADA"], f["SERIE"], int(f["N_INI"]))] = (int(f["N_FIN"]), f["TIPORED"])
    return ["LADA", "SERIE", "N_INI", "N_FIN", "TIPORED"], [k + v for k, v in u.items()]


# ------------------------------------------------------------------ carga
def columnas_sql(cur, tabla):
    esquema, nombre = tabla.split(".")
    cur.execute("SELECT c.name FROM sys.columns c WHERE c.object_id = OBJECT_ID(?) ORDER BY c.column_id", f"{esquema}.{nombre}")
    return [r[0].upper() for r in cur.fetchall()]


def insertar(cur, tabla, columnas, filas):
    if not filas:
        return 0
    cur.fast_executemany = True
    sql = f"INSERT INTO {tabla} ({', '.join('[' + c + ']' for c in columnas)}) VALUES ({', '.join('?' * len(columnas))})"
    cur.executemany(sql, [list(f) for f in filas])
    return len(filas)


def contar(cur, sql, *params):
    cur.execute(sql, *params)
    return cur.fetchone()[0]


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--config", required=True)
    ap.add_argument("--conexion", help="cadena ODBC; sin ella solo se revisa")
    ap.add_argument("--reemplazar", action="store_true", help="borra lo que haya en los destinos antes de cargar")
    ap.add_argument("--solo", help="destinos separados por coma: DAT,HISTORIA,CONSECUTIVO,ETIQUETAS,EXCLUSIONES,LADA,PNC")
    a = ap.parse_args()

    cfg = json.loads(Path(a.config).read_text(encoding="utf-8"))
    cli = cfg["cliente"]
    destinos = ["DAT", "HISTORIA", "CONSECUTIVO", "ETIQUETAS", "EXCLUSIONES", "LADA", "PNC"]
    if a.solo:
        destinos = [d.strip().upper() for d in a.solo.split(",")]

    # 1. Lectura
    fuentes, avisos = {}, []
    print("== Lectura de DBF")
    for nombre, ruta in cfg["fuentes"].items():
        if not ruta:
            continue
        try:
            fuentes[nombre] = leer(ruta)
            print(f"  {nombre:<10} {len(fuentes[nombre][1]):>8} registros  {ruta}")
        except FileNotFoundError:
            print(f"  {nombre:<10}      --- no encontrado: {ruta}")

    # 2. Transformación
    print("== Destinos")
    planes, errores = [], []
    cuentas_486 = set()
    if "DAT" in fuentes:
        for f in fuentes["DAT"][1]:
            cuentas_486.update(x for x in (f.get("CUENTA"), f.get("CUENTA2")) if x)

    def plan(nombre, fn, requiere):
        if nombre not in destinos:
            return
        if not any(r in fuentes for r in requiere):
            print(f"  {nombre:<12} omitido (no se encontró {', '.join(requiere)})")
            return
        try:
            res = fn()
            planes.append((nombre,) + tuple(res))
            print(f"  {nombre:<12} {len(res[1]):>8} filas")
        except ErrorFuente as e:
            errores.append(str(e))
            print(f"  {nombre:<12} ERROR: {e}")

    plan("DAT", lambda: destino_dat(cfg, fuentes, avisos), ["DAT"])
    plan("HISTORIA", lambda: destino_historia(cfg, fuentes, avisos), ["DAT"])
    plan("CONSECUTIVO", lambda: destino_consecutivo(cfg, fuentes, avisos), ["TAB7", "DAT"])
    plan("ETIQUETAS", lambda: destino_etiquetas(cfg, fuentes, avisos), list(ETIQUETAS))
    plan("EXCLUSIONES", lambda: destino_exclusiones(cfg, fuentes, avisos, cuentas_486),
         ["EXC486", "DIRMAL", "EMAILMALO", "BLACKLIST", "TELBAJ", "DAT"])
    plan("LADA", lambda: destino_lada(cfg, fuentes, avisos), ["LADA"])
    plan("PNC", lambda: destino_pnc(cfg, fuentes, avisos), ["PNC"])

    for av in dict.fromkeys(avisos):
        print("  aviso:", av)
    if errores:
        print("\nHay errores de estructura; corrige el config o los archivos antes de cargar.")
        return 1
    if not a.conexion:
        print("\nSolo revisión: no se escribió nada. Agrega --conexion para cargar.")
        return 0

    # 3. Carga (una transacción)
    import pyodbc
    cn = pyodbc.connect(a.conexion, autocommit=False)
    cur = cn.cursor()
    tablas = {"DAT": "dat.DAT_486", "HISTORIA": "dat.HISTORIA_FOLIO", "LADA": "cfg.LADA", "PNC": "cfg.PLAN_NUMERACION"}
    try:
        print("== Carga")
        for p in planes:
            nombre = p[0]
            if nombre == "DAT":
                cols_dbf, filas = p[1], p[2]
                cols = [c for c in cols_dbf if c in columnas_sql(cur, "dat.DAT_486")]
                previos = contar(cur, "SELECT COUNT(*) FROM dat.DAT_486")
                if previos and not a.reemplazar:
                    raise RuntimeError(f"dat.DAT_486 ya tiene {previos} registros; usa --reemplazar")
                cur.execute("DELETE FROM dat.DAT_486")
                n = insertar(cur, "dat.DAT_486", cols, [[f.get(c) for c in cols] for f in filas])
            elif nombre in ("HISTORIA", "LADA", "PNC"):
                previos = contar(cur, f"SELECT COUNT(*) FROM {tablas[nombre]}")
                if previos and not a.reemplazar:
                    raise RuntimeError(f"{tablas[nombre]} ya tiene {previos} registros; usa --reemplazar")
                cur.execute(f"DELETE FROM {tablas[nombre]}" + (" WHERE CLIENTE = ?" if nombre == "HISTORIA" else ""),
                            *([cli] if nombre == "HISTORIA" else []))
                n = insertar(cur, tablas[nombre], p[1], p[2])
            elif nombre == "CONSECUTIVO":
                cur.execute("DELETE FROM dat.FOLIO_CONSECUTIVO WHERE CLIENTE = ?", cli)
                n = insertar(cur, "dat.FOLIO_CONSECUTIVO", p[1], p[2])
            elif nombre == "ETIQUETAS":
                for t in p[3]:
                    cur.execute("DELETE FROM cfg.ETIQUETA WHERE CLIENTE = ? AND TIPO = ?", cli, t)
                n = insertar(cur, "cfg.ETIQUETA", p[1], p[2])
            elif nombre == "EXCLUSIONES":
                cur.execute("DELETE FROM cfg.EXCLUSION WHERE CLIENTE = ? AND REQ = ?", cli, MIGRACION)
                n = insertar(cur, "cfg.EXCLUSION", p[1], p[2])
            print(f"  {nombre:<12} {n:>8} filas cargadas")
        cn.commit()
        print("Listo: carga confirmada.")
        return 0
    except Exception as e:
        cn.rollback()
        print(f"ERROR, no se cargó nada (rollback): {e}")
        return 1
    finally:
        cn.close()


if __name__ == "__main__":
    sys.exit(main())
