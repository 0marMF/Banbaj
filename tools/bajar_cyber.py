"""Baja de CYBER (Oracle) lo que se necesita para cruzar y lo carga directo a SQL Server, sin archivos en la máquina.

    python tools/bajar_cyber.py status    --corrida 125 --oracle 192.168.90.10:1521/sertecp --conexion "<ODBC SQL Server>"
    python tools/bajar_cyber.py correos   --corrida 125 --oracle … --conexion …
    python tools/bajar_cyber.py telefonos --corrida 125 --oracle … --conexion …
    python tools/bajar_cyber.py pagos     --corrida 130 --oracle … --conexion …   (después de arribar SCBPAG)

    status     STATUS.SQL (status.prg)          -> stg.CYBER_STATUS   -> ops.sp_blanqueo_status
    correos    cyadd.sql  (email.PRG)           -> stg.CYBER_CORREO   -> ops.sp_correos_nuevos
    telefonos  TELs_486.sql (ges486.prg)        -> stg.CYBER_TELEFONO -> ops.sp_gescar_sin_telefono
    pagos      BAJ.sql (saldos.prg)             -> stg.CYBER_PAGO     -> ops.sp_cuadrar_pagos

El usuario y la contraseña de Oracle se escriben a mano al correr (la contraseña no se ve
en pantalla) y nunca se guardan. --oracle es solo host:puerto/servicio; si se pasa como
usuario@host:puerto/servicio, solo se pide la contraseña. --solo-bajar carga la tabla de paso sin ejecutar el procedimiento.
--forzar (solo status) blanquea aunque no sea día 1 a 10. --thick usa Oracle Instant Client
(para versiones de Oracle anteriores a 12.1). --fecha (solo pagos, AAAA-MM-DD) cuadra
los pagos registrados ese día; por omisión, hoy (como BAJ.sql).

Requiere: pip install oracledb pyodbc
"""
import argparse
import getpass
import os
import sys

CONSULTAS = {
    "status": {
        "sql": """select DMCOMPANY, DMADL1, DMACCT, DMACRC2, DMACAC2, TO_CHAR(DMACDT2, 'DD/MM/YYYY HH24:MI:SS'), DMACSC2, DMSSNUM
                  from RCVRY.delqmst
                  where DMACCTG = '1' and DMCOMPANY = :cliente and DMSTATUS is null""",
        "tabla": "stg.CYBER_STATUS",
        "columnas": ["CLIENTE", "FOLIO", "CUENTA", "STATUS", "ACCION", "FECHA", "PESO", "DMSSNUM"],
        "proc": "EXEC ops.sp_blanqueo_status @id_corrida = ?, @forzar = ?",
    },
    "correos": {
        "sql": """select a.ADACCT, a.ADADDR1
                  from RCVRY.Address a
                  join RCVRY.delqmst d on d.DMACCTG = a.ADACCTG and d.DMACCT = a.ADACCT
                  where d.DMACCTG = '1' and d.DMCOMPANY = :cliente and d.DMSTATUS is null and a.ADTYPE = '3'""",
        "tabla": "stg.CYBER_CORREO",
        "columnas": ["CUENTA", "CORREO"],
        "proc": "EXEC ops.sp_correos_nuevos @id_corrida = ?, @cyber_sin_datos = ?",
    },
    "telefonos": {
        "sql": """select p.PHACCT, p.PHAREACODE, p.PHPHONE
                  from RCVRY.delqmst d
                  join RCVRY.phone p on p.PHACCTG = d.DMACCTG and p.PHACCT = d.DMACCT
                  where d.DMACCTG = '1' and d.DMCOMPANY = :cliente and p.PHSTATUS = 'A'""",
        "tabla": "stg.CYBER_TELEFONO",
        "columnas": ["CUENTA", "LADA", "TEL"],
        "proc": "EXEC ops.sp_gescar_sin_telefono @id_corrida = ?",
    },
    "pagos": {
        "sql": """select PMACCT, TO_CHAR(PMAMOUNT, 'FM999999999990.00'), TO_CHAR(PMEDATE, 'DD/MM/YYYY')
                  from RCVRY.pmtfil
                  where PMACCTG = '1' and PMACCT in (select DMACCT from RCVRY.delqmst where DMCOMPANY = :cliente)
                    and TRUNC(PMEDATE) = TO_DATE(:fecha, 'YYYY-MM-DD')""",
        "tabla": "stg.CYBER_PAGO",
        "columnas": ["CUENTA", "MONTO", "FECHA"],
        "proc": "EXEC ops.sp_cuadrar_pagos @id_corrida = ?",
    },
}


def texto(v):
    if v is None:
        return None
    v = str(v).strip()
    return v or None


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("que", choices=list(CONSULTAS))
    ap.add_argument("--corrida", type=int, help="corrida de asignación (obligatoria salvo con --solo-bajar)")
    ap.add_argument("--oracle", required=True, help="host:puerto/servicio (el usuario y la contraseña se piden al correr)")
    ap.add_argument("--conexion", required=True, help="cadena ODBC de SQL Server")
    ap.add_argument("--cliente", default="486")
    ap.add_argument("--solo-bajar", action="store_true")
    ap.add_argument("--forzar", action="store_true")
    ap.add_argument("--thick", action="store_true")
    ap.add_argument("--fecha", default=None, help="solo pagos: día a cuadrar AAAA-MM-DD (por omisión hoy)")
    a = ap.parse_args()
    if not a.solo_bajar and a.corrida is None:
        ap.error("--corrida es obligatoria (o usa --solo-bajar)")

    import oracledb
    import pyodbc

    c = CONSULTAS[a.que]
    if "@" in a.oracle:
        usuario, _, dsn = a.oracle.partition("@")
    else:
        usuario, dsn = input("Usuario de Oracle: ").strip(), a.oracle
    clave = getpass.getpass(f"Contraseña de Oracle para {usuario}: ")
    if a.thick:
        oracledb.init_oracle_client()

    print(f"== CYBER: {a.que}")
    with oracledb.connect(user=usuario, password=clave, dsn=dsn) as ora:
        cur = ora.cursor()
        cur.arraysize = 5000
        binds = {"cliente": a.cliente}
        if a.que == "pagos":
            import datetime as dt
            binds["fecha"] = a.fecha or dt.date.today().isoformat()
        cur.execute(c["sql"], **binds)
        filas = [[texto(v) for v in r] for r in cur.fetchall()]
    print(f"   {len(filas)} registros bajados")

    cn = pyodbc.connect(a.conexion, autocommit=False)
    sq = cn.cursor()
    try:
        sq.execute(f"TRUNCATE TABLE {c['tabla']}")
        if filas:
            sq.fast_executemany = True
            sq.executemany(f"INSERT INTO {c['tabla']} ({', '.join(c['columnas'])}) VALUES ({', '.join('?' * len(c['columnas']))})", filas)
        cn.commit()
        print(f"   cargados en {c['tabla']}")
        if a.solo_bajar:
            return 0
        params = [a.corrida]
        if a.que == "status":
            params.append(1 if a.forzar else 0)
        elif a.que == "correos":
            params.append(1 if not filas else 0)      # la consulta corrió y no trajo correos: todos son nuevos
        sq.execute(c["proc"], *params)
        while True:                                   # muestra el resumen que regresa el procedimiento
            if sq.description:
                cols = [d[0] for d in sq.description]
                for r in sq.fetchall():
                    print("   " + " · ".join(f"{k}: {v}" for k, v in zip(cols, r)))
            if not sq.nextset():
                break
        cn.commit()
        print("Listo. Exporta los archivos y scripts de la corrida con tools/exportar_salidas.py.")
        return 0
    except Exception as e:
        cn.rollback()
        print(f"ERROR: {e}")
        return 1
    finally:
        cn.close()


if __name__ == "__main__":
    sys.exit(main())
