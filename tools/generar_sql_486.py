"""Genera sql/05_tabla_dat_486.sql y sql/90_semilla_486.sql.

Uso:  python tools/generar_sql_486.py mapeos/mapeo_486.xlsx

Lee del mapeo la estructura del DAT (hoja MAPEOS, archivo DAT_GENERAL) y los
anchos de SCBSDOS. El resto de la semilla (archivos, columnas, homologaciones,
reglas, salidas, correo) está definido abajo, tomado de paso.prg, asig_bases.prg,
asi486.prg, saldos.prg y de los mapeos actualizados.
"""
import re
import sys
from pathlib import Path

import openpyxl

RAIZ = Path(__file__).resolve().parent.parent
CLIENTE = "486"
RUTA_Q = "\\\\192.168.50.13\\q"   # unidad Q: (01/11); el servicio de SQL Server no ve unidades mapeadas
RUTA_ENTRADA = RUTA_Q + "\\CYBER\\C_486\\{AAAA}\\{MES}\\{DD}\\"   # carpeta del día (cfg.fn_ruta): Q:\CYBER\C_486\2026\octubre\28\
PERFIL_DBMAIL = "asig.486.cdmx"             # perfil de Database Mail (confirmado 30/10)


def q(v):
    """Literal SQL (NVARCHAR)."""
    if v is None:
        return "NULL"
    if isinstance(v, (int, float)):
        return str(v)
    return "N'" + str(v).replace("'", "''") + "'"


def patron(nombre, fecha=False):
    """Patrón LIKE a partir del encabezado: escapa _ % [ y opcionalmente cambia la fecha por %."""
    p = nombre.replace("[", "[[]").replace("%", "[%]").replace("_", "[_]")
    if fecha:
        p = re.sub(r"\d{2}/\d{2}/\d{4}", "%", p)
        # "ESTATUS 01 ENE" -> "ESTATUS [0-9][0-9] %": evita confundirlo con "ESTATUS SOLUCIONES 02 DE ENE 2026"
        p = re.sub(r"\d{2} (ENE|FEB|MAR|ABR|MAY|JUN|JUL|AGO|SEP|OCT|NOV|DIC)\w*", "[0-9][0-9] %", p)
    return p


# ---------------------------------------------------------------- DAT
def leer_mapeo(xlsx):
    wb = openpyxl.load_workbook(xlsx, read_only=True)
    dat, scb = [], []
    for r in wb["MAPEOS"].iter_rows(min_row=2, values_only=True):
        if r[0] == "DAT_GENERAL":
            dat.append((r[1], r[5], int(r[6])))
        elif r[0] == "SCBSDOS":
            scb.append((r[1], int(r[6])))
    return dat, scb


def tipo_sql(t, n):
    return {"C": f"VARCHAR({n})", "N": "DECIMAL(18,2)", "D": "DATE"}[t]


def sql_dat(dat):
    cols = []
    for campo, t, n in dat:
        nulo = "NOT NULL" if campo == "CUENTA" else "NULL"
        cols.append(f"    {campo:<12} {tipo_sql(t, n):<14} {nulo}")
    cols += [
        "    ID_CORRIDA_ALTA INT          NULL",
        "    ID_CORRIDA_ULT  INT          NULL",
        "    FE_ULT_ACT      DATETIME2(0) NULL",
        "    ETIQUETA6       VARCHAR(15)  NULL",
        "    CTA_BANCO       VARCHAR(20)  NULL",
    ]
    vista = ", ".join("d.CUENTA2 AS CUENTA" if c == "CUENTA" else "ISNULL(d.CTA_BANCO, d.CUENTA) AS CUENTA3" if c == "CUENTA3" else f"d.{c}" for c, _, _ in dat)
    return f"""USE [BNABAJ_486];   -- base del 486 (si la instalas con otro nombre, cámbialo aquí)
GO
/* =====================================================================
   Banbaj · 05 Tabla fija DAT del cliente 486 (generado por tools/generar_sql_486.py)
   Misma estructura que DAT.DBF (hoja DAT_GENERAL del mapeo) + 3 columnas de control.
   ===================================================================== */
SET NOCOUNT ON;
GO
IF OBJECT_ID('dat.DAT_486') IS NULL
CREATE TABLE dat.DAT_486 (
{(','+chr(10)).join(cols)},
    CONSTRAINT PK_DAT_486 PRIMARY KEY (CUENTA)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_DAT_486_CUENTA2')
    CREATE UNIQUE INDEX UX_DAT_486_CUENTA2 ON dat.DAT_486 (CUENTA2) WHERE CUENTA2 IS NOT NULL;
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_DAT_486_DES_PROD')
    CREATE INDEX IX_DAT_486_DES_PROD ON dat.DAT_486 (DES_PROD);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_DAT_486_RIESGO')
    CREATE INDEX IX_DAT_486_RIESGO ON dat.DAT_486 (RIESGO, SEGMENTO2);
GO
/* Lo que resdat.PRG copiaba a Q:\\MIS\\SERTEC98\\CLIENTES\\486\\DAT: el DAT con CUENTA = '486-folio' y CUENTA3 = crédito */
CREATE OR ALTER VIEW ops.v_DAT_486_MIS
AS
SELECT {vista}
FROM dat.DAT_486 d;
GO
/* Copia del DAT por corrida (retroceso). Misma estructura + ID_CORRIDA_RESPALDO. */
IF OBJECT_ID('ops.RESPALDO_DAT_486') IS NULL
BEGIN
    SELECT TOP (0) CAST(0 AS INT) AS ID_CORRIDA_RESPALDO, * INTO ops.RESPALDO_DAT_486 FROM dat.DAT_486;
    CREATE CLUSTERED INDEX CX_RESPALDO_DAT_486 ON ops.RESPALDO_DAT_486 (ID_CORRIDA_RESPALDO);
END;
GO
/* 19/11: ETIQUETA6 (REE por la base maestra; sustituye a la lista TOP). Al final en el DAT y en el respaldo,
   que se copian con SELECT * */
IF COL_LENGTH('dat.DAT_486', 'ETIQUETA6') IS NULL ALTER TABLE dat.DAT_486 ADD ETIQUETA6 VARCHAR(15) NULL;
IF COL_LENGTH('ops.RESPALDO_DAT_486', 'ETIQUETA6') IS NULL ALTER TABLE ops.RESPALDO_DAT_486 ADD ETIQUETA6 VARCHAR(15) NULL;
GO
/* 20/11: la llave única (CUENTA) es el riesgo en todos los segmentos. CTA_BANCO es la cuenta del banco que va a CYBER
   (DMSSNUM del SCBSDOS, SCBPAG, listas de etiquetas): en TDC la armada (últimos 4 dígitos de PRIME+4DIG + RFC), en
   Consumo e Hipotecario el crédito. NULL = registro de antes del cambio (ops.sp_llave_riesgo_migrar lo llena). */
IF COL_LENGTH('dat.DAT_486', 'CTA_BANCO') IS NULL ALTER TABLE dat.DAT_486 ADD CTA_BANCO VARCHAR(20) NULL;
IF COL_LENGTH('ops.RESPALDO_DAT_486', 'CTA_BANCO') IS NULL ALTER TABLE ops.RESPALDO_DAT_486 ADD CTA_BANCO VARCHAR(20) NULL;
GO
"""


# ---------------------------------------------------------------- archivos de entrada
# (CODIGO, PROCESO, SEGMENTO2, PATRON_NOMBRE, NUM_COLUMNAS, TABLA, LLAVE_DAT, OBLIG, ORDEN, ACTIVO, COMENTARIO)
# Decisión 15/11: la asignación toma las bases maestras en .csv y la actualización sus archivos en .txt
# (los .txt del banco vienen separados por comas, con comillas opcionales, igual que un CSV).
ARCHIVOS = [
    ("MAESTRA_TDC", "ASIG", "TDC", "BASE MAESTRA[_]TARJETA%.csv", 100, "stg.ENT_MAESTRA_TDC", "RIESGO", 0, 10, 1,
     "Base maestra TDC guardada como CSV. Llave única y devolución por RIESGO (ACC_NUM, 20/11)."),
    ("MAESTRA_CONSUMO", "ASIG", "CONSUMO", "BASE MAESTRA[_]CONSUMO%.csv", 115, "stg.ENT_MAESTRA_CONSUMO", "RIESGO", 0, 20, 1,
     "Base maestra Consumo guardada como CSV. Devolución por RIESGO (llave única desde el 20/11; antes DES_PROD)."),
    ("MAESTRA_HIPO", "ASIG", "HIPOTECARIO", "BASE MAESTRA[_]HIPOTECARIO%.csv", 118, "stg.ENT_MAESTRA_HIPO", "RIESGO", 0, 30, 1,
     "Sin archivo de ejemplo: columnas tomadas de la hoja RAW, confirmar NUM_COLUMNAS y encabezados."),
    ("SALDOS_TDC", "ACT", "TDC", "SERTEC[_]Saldos[_]tdc%.txt", 8, "stg.ENT_SALDOS_TDC", "RIESGO", 0, 10, 1,
     "Cruce por ACC_NUM = DAT.RIESGO."),
    ("SALDOS_CONS", "ACT", "CONSUMO", "SERTEC[_]Saldos[_]Cons%.txt", 12, "stg.ENT_SALDOS_CONS", "DES_PROD", 0, 20, 1,
     "Cruce por CYBER = DAT.DES_PROD. La primera columna viene sin nombre."),
    ("SALDOS_HIP", "ACT", "HIPOTECARIO", "SERTEC[_]Saldos[_]Hip%.txt", 12, "stg.ENT_SALDOS_HIP", "CUENTA", 0, 30, 0,
     "PENDIENTE: no hay ejemplo del archivo; activar cuando se defina su mapeo (A-06)."),
    ("PAGOS", "ACT", None, "SERTEC[_]Pagos%.txt", 6, "stg.ENT_PAGOS", "RIESGO", 0, 40, 1,
     "Pagos del día. Importes con '$' y miles."),
]

C = lambda n: (f"VARCHAR({n})", f"LEFT({{v}}, {n})")
N = ("DECIMAL(18,2)", "cfg.fn_importe({v})")
PVS = ("VARCHAR(4)", "CAST(cfg.fn_entero({v}) AS VARCHAR(4))")
F = lambda fmt: ("DATE", f"cfg.fn_fecha({{v}}, '{fmt}')")

# Teléfonos y domicilio comunes a las tres bases (hoja RAW)
TELS_DOM = [
    ("TEL1", "TEL_CERT"), ("TEL2", "TEL_JLL"), ("TEL3", "TEL CELULAR"), ("TEL4", "TEL FIJO"), ("TEL5", "TEL EMPLEO"),
    ("DIRECC1", "CALLE"), ("DIRECC2", "COL"), ("DIRECC4", "CIUDAD"), ("ESTADO", "ESTADO"), ("DIRECC3", "CP"),
]
ANCHO = {"TEL": 15, "DIRECC1": 45, "DIRECC2": 40, "DIRECC3": 5, "DIRECC4": 30, "ESTADO": 19, "CORREO": 100}


def ancho(campo):
    for k, v in ANCHO.items():
        if campo.startswith(k):
            return v
    raise KeyError(campo)


def tel_dom(extra_tels):
    out = [(c, h, ("VARCHAR(5)", "LEFT(cfg.fn_solo_digitos({v}), 5)") if c == "DIRECC3" else C(ancho(c)), 0, False,
            "Solo dígitos" if c == "DIRECC3" else None) for c, h in TELS_DOM]
    out += [(c, h, C(15), 0, False, None) for c, h in extra_tels]
    return out


# (CAMPO, ENCABEZADO o None si es derivado, (TIPO, TRANSFORMACION), OBLIGATORIO, ENCABEZADO_CON_FECHA, COMENTARIO)
COLUMNAS = {
    "MAESTRA_TDC": [
        ("PRIME4DIG", "PRIME+4DIG", C(30), 1, False, "Base para armar la cuenta del banco (CTA_BANCO)"),
        ("CUENTA", None, ("VARCHAR(20)", "{v}"), 0, False, "Derivado: = RIESGO (ACC_NUM). Llave única desde el 20/11"),
        ("CTA_BANCO", None, ("VARCHAR(20)", "{v}"), 0, False, "Derivado: últimos 4 dígitos de PRIME+4DIG + RFC (regla del mapeo); es la cuenta que va a CYBER (DMSSNUM)"),
        ("RIESGO", "ACC_NUM", C(35), 1, False, None),
        ("NOMBRE1", "NAME2", C(50), 0, False, None),
        ("NAME1", "NAME1", C(50), 0, False, "Respaldo: si NAME2 viene vacío o '-' se usa NAME1 (regla que hacía la macro)"),
        ("ESTRA3", "Tipo de TDC", C(15), 0, False, None),
        ("GARAN", "GARANTIZADA", C(15), 0, False, "1 / 0 -> GARANTIZADA / vacío (homologación)"),
        ("PVS", "Dias Vencidos VEN4/CCAS 00/00/0000", PVS, 0, True, None),
        ("RFC", "RFC", C(25), 0, False, None),
        ("PAG_MIN", "Pago mínimo 00/00/0000", N, 0, True, None),
        ("SDO_VDO", "Saldo PRIME total asignado al 00/00/0000", N, 0, True, None),
        ("SDO_ACT", "Saldo actualizado VEN4/CCAS al 00/00/0000", N, 2, True, "Obligatorio pero admite vacío (2): en el layout del 11/11 viene vacío en VEN2 y VEN3 y la homologación toma el saldo PRIME"),
        ("SALDO1", "MONTO A CUBRIR 1 PAGO LIQUIDACION", N, 0, False, None),
        ("SALDO2", "MONTO A CUBRIR PLAZOS PAGO LIQUIDACION", N, 0, False, "Layout del 11/11/2026: antes 'MONTO A CUBRIR PLAZOS PAGO <= 6 LIQUIDACION'"),
        ("ENFOQUE", "ENFOQUE_LIQUIDACION_1_PAGO", C(60), 0, False, "Lo usa la regla de TRAMO 90+ (CAS / VEN). ETIQUETA y REE ya no salen de la base: llegan por etiquetado y estructura (30/10)"),
        ("ETIQUETA6", "ENFOQUE_PLAN DE PAGOS", C(60), 0, False, "19/11 (correo 'Etiquetado REE', columna CJ): APLICA PLAN DE PAGOS -> ETIQUETA6 = REE (catálogo ETIQUETA6_TDC)"),
        ("CORREO1", "EMAIL 1", C(100), 0, False, None),
        ("CORREO2", "EMAIL 2", C(100), 0, False, None),
        ("SEGMENTO", "Estatus al 00/00/0000", C(30), 0, True, None),
        ("TRAMO", "Tramo 00/00/0000", C(20), 0, True, None),
        ("ETIQUETA1", "COSECHAS", C(10), 0, False, None),
        ("DES_PROD", None, ("VARCHAR(40)", "{v}"), 0, False, "Derivado: = CUENTA"),
        ("SEGMENTO2", None, ("VARCHAR(20)", "{v}"), 0, False, "Derivado"),
        ("ESTATUS2", None, ("VARCHAR(5)", "{v}"), 0, False, "Derivado: VIG / VEN / CAS / REE"),
        ("SALDO3", None, ("DECIMAL(18,2)", "{v}"), 0, False, "Derivado: SALDO2 / 3"),
        ("TIPO", None, ("VARCHAR(25)", "{v}"), 0, False, "Derivado: 'TDC_' + ESTATUS2"),
    ] + tel_dom([("TEL6", "BURO_TEL_1"), ("TEL7", "BURO_TEL_2"), ("TEL8", "BURO_TEL_3"), ("TEL9", "BURO_TEL_4"),
                 ("TEL10", "BURO_TEL_5"), ("TEL11", "TEL_CASA"), ("TEL12", "TEL_CEL"), ("TEL13", "TEL_TRAB")]),
    "MAESTRA_CONSUMO": [
        ("CUENTA", "CREDITO", C(20), 1, False, None),
        ("DES_PROD", "CRÉDITO CYBER", C(40), 1, False, None),
        ("NOMBRE1", "NOMBRE", C(50), 0, False, None),
        ("RFC", "RFC", C(25), 0, False, None),
        ("ESTRA3", "TIPO DE CRÉDITO", C(15), 0, False, "Se homologa antes de recortar: ver TIPO_CREDITO"),
        ("TIPO_CREDITO", "TIPO DE CRÉDITO", C(60), 0, False, "Texto completo para homologar ESTRA3"),
        ("TIPO", "CARTERA", C(25), 0, False, None),
        ("ETIQUETA6", "ENFOQUE_REESTRUCTURA", C(60), 0, False, "19/11 (correo 'Etiquetado REE'): APLICA RESTRUCTURA -> ETIQUETA6 = REE (catálogo ETIQUETA6_CONSUMO)"),
        ("CAPITAL", "CAPITAL AL 00/00/0000", N, 0, True, None),
        ("SDO_ACT", "ADEUDO TOTAL AL 00/00/0000", N, 1, True, None),
        ("SDO_VDO", "MONTO VENCIDO AL 00/00/0000", N, 0, True, None),
        ("SALDO1", "MONTO A 1 PAGO LIQUIDACION", N, 0, False, None),
        ("SALDO2", "MONTO A PAGO LIQUIDACION PLAZOS", N, 0, False, "Layout del 13/11/2026: antes 'MONTO A PAGO LIQUIDACION PLAZOS <= 6 MESES'"),
        ("PVS", "DIAS MORA AL 00/00/0000", PVS, 0, True, None),
        ("SEGMENTO", "ESTATUS AL 00/00/0000", C(30), 0, True, None),
        ("TRAMO", "TRAMO AL 00/00/0000", C(20), 0, True, None),
        ("CORREO1", "CORREO1", C(100), 0, False, None),
        ("CORREO2", "CORREO2", C(100), 0, False, None),
        ("ETIQUETA1", "COSECHAS", C(10), 0, False, None),
        ("RIESGO", None, ("VARCHAR(35)", "{v}"), 0, False, "Derivado: = CUENTA"),
        ("CTA_BANCO", None, ("VARCHAR(20)", "{v}"), 0, False, "Derivado: = CUENTA (cuenta del banco para CYBER)"),
        ("NOMBRE2", None, ("VARCHAR(20)", "{v}"), 0, False, "Derivado: = RFC"),
        ("SEGMENTO2", None, ("VARCHAR(20)", "{v}"), 0, False, "Derivado"),
        ("SALDO3", None, ("DECIMAL(18,2)", "{v}"), 0, False, "Derivado: SALDO2 / 3"),
    ] + tel_dom([("TEL6", "BURO_TEL_1"), ("TEL7", "BURO_TEL_2"), ("TEL8", "BURO_TEL_3"), ("TEL9", "BURO_TEL_4"),
                 ("TEL10", "BURO_TEL_5"), ("TEL11", "TEL_CASA"), ("TEL12", "TEL_CEL"), ("TEL13", "TEL_TRAB")]),
    "MAESTRA_HIPO": [
        ("CUENTA", "CREDITO", C(20), 1, False, None),
        ("DES_PROD", "CRÉDITO CYBER", C(40), 1, False, None),
        ("NOMBRE1", "NOMBRE", C(50), 0, False, None),
        ("RFC", "RFC", C(25), 0, False, None),
        ("ESTRA3", "TIPO DE CRÉDITO", C(15), 0, False, None),
        ("SEGMENTO", "ESTATUS 01 ENE", C(30), 0, True, None),
        ("PVS", "DÍAS MORA 01 ENE", PVS, 0, True, None),
        ("TRAMO", "TRAMO 01 ENE", C(20), 0, True, None),
        ("SDO_VDO", "MONTO VENCIDO  QUERY 01 ENE", N, 0, True, None),
        ("SDO_ACT", "ADEUDO TOTAL  QUERY  01 ENE", N, 1, True, None),
        ("CAPITAL", "CAPITAL  01 ENE", N, 0, True, None),
        ("ETIQUETA5", "ENFOQUE_LIQUIDACION", C(60), 0, False, "Se homologa a LIQ / REG / REG-LIQ"),
        ("SALDO1", "MONTO A 1 PAGO LIQUIDACION", N, 0, False, None),
        ("SALDO2", "MONTO PAGO PLAZO LIQUIDACION", N, 0, False, None),
        ("CORREO1", "CORREO1", C(100), 0, False, None),
        ("CORREO2", "CORREO2", C(100), 0, False, None),
        ("ETIQUETA1", "COSECHAS", C(10), 0, False, None),
        ("RIESGO", None, ("VARCHAR(35)", "{v}"), 0, False, "Derivado: = CUENTA"),
        ("CTA_BANCO", None, ("VARCHAR(20)", "{v}"), 0, False, "Derivado: = CUENTA (cuenta del banco para CYBER)"),
        ("SEGMENTO2", None, ("VARCHAR(20)", "{v}"), 0, False, "Derivado"),
        ("TIPO", None, ("VARCHAR(25)", "{v}"), 0, False, "Derivado: HIPO_CAS / HIPO_VEN / HIPO_VIG"),
    ] + tel_dom([("TEL6", "TEL_FIJO OMNI"), ("TEL7", "TEL_MOVIL OMNI"), ("TEL8", "BURO_TEL_1"), ("TEL9", "BURO_TEL_2"),
                 ("TEL10", "BURO_TEL_3"), ("TEL11", "BURO_TEL_4"), ("TEL12", "BURO_TEL_5"), ("TEL13", "TEL_CASA"),
                 ("TEL14", "TEL_CEL"), ("TEL15", "TEL_TRAB"), ("TEL16", "BURO_TEL_6")]),
    "SALDOS_TDC": [
        ("RIESGO", "ACC_NUM", C(35), 1, False, None),
        ("CYBER", "CYBER", C(20), 0, False, None),
        ("SDO_ACT", "SALDO", N, 1, False, None),
        ("SEG", "ESTATUS", C(15), 0, False, None),
        ("PAG_MIN", "PAGO-MIN", N, 0, False, None),
        ("FECHA", "FECHA_CORTE", F("AAAA-MM-DD"), 0, False, "Llega 'AAAA-MM-DD hh:mm:ss' o '-'"),
    ],
    "SALDOS_CONS": [
        ("RIESGO", "CREDITO", C(35), 0, False, None),
        ("DES_PROD", "CYBER", C(40), 1, False, None),
        ("SDO_VDO", "MONTO_VENCIDO", N, 0, False, None),
        ("SDO_ACT", "SALDO_DEUDOR", N, 1, False, "Texto con miles y espacios; ' - ' = 0"),
        ("PAG_MIN", "PAGO-MIN", N, 0, False, None),
        ("PVS", "DIAS_MORA", PVS, 0, False, None),
        ("SEG", "TRAMO", C(15), 0, False, None),
        ("FECHA", "FECHA", F("AAAAMMDD"), 0, False, None),
    ],
    "SALDOS_HIP": [
        ("CUENTA", "CREDITO", C(20), 1, False, "PENDIENTE de confirmar con el archivo real"),
        ("SDO_ACT", "SALDO_DEUDOR", N, 1, False, "PENDIENTE"),
    ],
    "PAGOS": [
        ("RIESGO", "CREDITO", C(35), 1, False, None),
        ("IMPORTE", "IMPORTE", N, 1, False, "Llega con '$' y separador de miles"),
        ("FECHA", "FECHA", F("AAAA-MM-DD"), 1, False, None),
        ("TRX", "TRX", C(50), 0, False, None),
        ("EMPRESA", "EMPRESA", C(50), 0, False, None),
    ],
}

# ---------------------------------------------------------------- homologación
# (TABLA, CAMPO, VALOR, CONDICION, DESCRIPCION, REQ)
# Catálogos estáticos (decisión 17/11): el valor sale de cfg.CATALOGO, que edita el equipo de asignaciones
def K(catalogo, campo):
    return f"cfg.fn_catalogo('{{CLIENTE}}', '{catalogo}', t.{campo})"


def KH(campo, catalogo, desc, req=None):
    """Homologación por catálogo: el campo toma la etiqueta del catálogo si su valor está en él."""
    return (campo, K(catalogo, campo), f"{K(catalogo, campo)} IS NOT NULL", f"{desc} (catálogo {catalogo})", req)


MORA = [
    ("ETIQUETA1", "REPLACE(t.ETIQUETA1, '-', '')", "t.ETIQUETA1 LIKE '%-%'", "Quita '-' (asig_bases)", None),
    KH("ETIQUETA1", "COSECHA_MORA", "COSECHA -> MORA", "REQ 2023-067064"),
]
AI = "COLLATE Latin1_General_CI_AI"
HOMOLOGACION = (
    [("stg.ENT_MAESTRA_TDC",) + x for x in [
        ("SEGMENTO2", "'TDC'", None, "Segmento", None),
        ("CTA_BANCO", "LEFT(RIGHT(LTRIM(RTRIM(t.PRIME4DIG)), 4) + LTRIM(RTRIM(ISNULL(t.RFC, ''))), 20)", None,
         "Cuenta del banco TDC (va a CYBER) = últimos 4 dígitos de PRIME+4DIG + RFC (regla del mapeo)", None),
        ("CUENTA", "LEFT(NULLIF(LTRIM(RTRIM(t.RIESGO)), ''), 20)", None,
         "Llave única = riesgo (ACC_NUM): folios, reasignadas y retiros (20/11)", "Cambio 20/11"),
        ("NOMBRE1", "t.NAME1", "t.NOMBRE1 IS NULL OR LTRIM(RTRIM(t.NOMBRE1)) IN ('', '-')",
         "Si NAME2 viene vacío o '-' se usa NAME1 (regla que hacía la macro)", None),
        ("DES_PROD", "t.CTA_BANCO", None, "DES_PROD = cuenta del banco (paso.prg)", None),
        KH("GARAN", "GARANTIA_TDC", "Garantizada 1 / 0", "REQ 2021-024042"),
    ] + MORA + [
        ("SDO_ACT", "t.SDO_VDO", "t.SDO_ACT IS NULL OR t.SDO_ACT <= 0",
         "Saldo actual vacío o <= 0 toma el saldo PRIME (asig_bases; en el layout del 11/11 VEN2 y VEN3 lo traen vacío)", None),
        ("ESTATUS2", K("TRAMO_TDC", "TRAMO"), f"NULLIF({K('TRAMO_TDC', 'TRAMO')}, '') IS NOT NULL",
         "Estatus por tramo: 1-29 VIG, 30-89 VEN, CASTIGADA CAS (catálogo TRAMO_TDC; acepta el tramo como número o como rango '30-59')", None),
        ("ESTATUS2", K("ENFOQUE_TDC_90", "ENFOQUE"), f"t.TRAMO = '90+' AND NULLIF({K('ENFOQUE_TDC_90', 'ENFOQUE')}, '') IS NOT NULL",
         "90+: liquidación CAS, contención o enfoque de varias palabras VEN (catálogo ENFOQUE_TDC_90, sin acentos)", None),
        ("ESTATUS2", "'REE'", f"t.TRAMO = '0' AND {K('ESTATUS_TDC', 'SEGMENTO')} = 'REE'", "Reestructura: BCOB, BOPE, FALL con tramo 0 (catálogo ESTATUS_TDC)", None),
        ("SALDO3", "ROUND(t.SALDO2 / 3, 2)", None, "SALDO3 = SALDO2 / 3", None),
        ("TIPO", "LEFT('TDC_' + ISNULL(t.ESTATUS2, ''), 25)", None, "TIPO = TDC_ + estatus", None),
        ("ETIQUETA6", K("ETIQUETA6_TDC", "ETIQUETA6"), None, "REE por plan de pagos (catálogo ETIQUETA6_TDC; fuera del catálogo queda vacía)", "Correo 19/11"),
    ]]
    + [("stg.ENT_MAESTRA_CONSUMO",) + x for x in [
        ("SEGMENTO2", "'CONSUMO'", None, "Segmento", None),
        ("RIESGO", "t.CUENTA", None, "RIESGO = CUENTA", None),
        ("CTA_BANCO", "t.CUENTA", None, "Cuenta del banco = crédito", None),
        ("NOMBRE2", "LEFT(t.RFC, 20)", None, "NOMBRE2 = RFC", None),
        ("ESTRA3", K("TIPO_CREDITO_CONSUMO", "TIPO_CREDITO"), f"{K('TIPO_CREDITO_CONSUMO', 'TIPO_CREDITO')} IS NOT NULL",
         "Tipo de crédito (catálogo TIPO_CREDITO_CONSUMO; sin valor en el catálogo se queda el texto recortado)", None),
        KH("TIPO", "CARTERA_CONSUMO", "Cartera"),
        KH("SEGMENTO", "ESTATUS_CONSUMO", "Estatus", "REQ 2022-035011"),
    ] + MORA + [
        ("SALDO3", "ROUND(t.SALDO2 / 3, 2)", None, "SALDO3 = SALDO2 / 3", None),
        ("TIPO", "LEFT(ISNULL(t.TIPO, '') + '_' + ISNULL(t.SEGMENTO, ''), 25)", None, "TIPO = cartera + estatus", None),
        ("ETIQUETA6", K("ETIQUETA6_CONSUMO", "ETIQUETA6"), None, "REE por reestructura (catálogo ETIQUETA6_CONSUMO; fuera del catálogo queda vacía)", "Correo 19/11"),
    ]]
    + [("stg.ENT_MAESTRA_HIPO",) + x for x in [
        ("SEGMENTO2", "'HIPOTECARIO'", None, "Segmento", None),
        ("RIESGO", "t.CUENTA", None, "RIESGO = CUENTA", "REQ 2023-067064"),
        ("CTA_BANCO", "t.CUENTA", None, "Cuenta del banco = crédito", None),
        ("TIPO", K("TIPO_HIPO", "SEGMENTO"), f"{K('TIPO_HIPO', 'SEGMENTO')} IS NOT NULL", "Tipo por estatus (catálogo TIPO_HIPO)", "REQ 2023-067064"),
    ] + MORA + [
        KH("ETIQUETA5", "ENFOQUE_HIPO", "Enfoque", "REQ 2023-067064"),
    ]]
    + [("stg.LAYOUT_486",) + x for x in [
        ("PVS", "'0'", "t.PVS IS NULL OR t.PVS LIKE '%/%' OR t.PVS LIKE '%-%'", "PVS sin dato -> 0", None),
        ("DIRECC3", "LEFT(cfg.fn_solo_digitos(t.DIRECC3), 5)", "t.DIRECC3 LIKE '%[^0-9]%'", "CP sin letras", None),
        ("DIRECC3", "'0' + t.DIRECC3", "LEN(t.DIRECC3) = 4", "CP a 5 dígitos", None),
        ("DIRECC4", "REPLACE(t.DIRECC4, '\\', '')", "t.DIRECC4 LIKE '%\\%'", "Quita '\\' de la ciudad", None),
        ("DIRECC2", "''", "EXISTS (SELECT 1 FROM cfg.EXCLUSION e WHERE e.CLIENTE = '{CLIENTE}' AND e.TIPO = 'DIRECCION' AND e.ACTIVO = 1 AND e.VALOR IN (t.CUENTA, t.CUENTA2, t.CTA_BANCO) AND e.VALOR2 = t.DIRECC1)", "Dirección mala (dirmal)", None),
        ("DIRECC3", "''", "EXISTS (SELECT 1 FROM cfg.EXCLUSION e WHERE e.CLIENTE = '{CLIENTE}' AND e.TIPO = 'DIRECCION' AND e.ACTIVO = 1 AND e.VALOR IN (t.CUENTA, t.CUENTA2, t.CTA_BANCO) AND e.VALOR2 = t.DIRECC1)", "Dirección mala (dirmal)", None),
        ("DIRECC4", "''", "EXISTS (SELECT 1 FROM cfg.EXCLUSION e WHERE e.CLIENTE = '{CLIENTE}' AND e.TIPO = 'DIRECCION' AND e.ACTIVO = 1 AND e.VALOR IN (t.CUENTA, t.CUENTA2, t.CTA_BANCO) AND e.VALOR2 = t.DIRECC1)", "Dirección mala (dirmal)", None),
        ("EDO", "''", "EXISTS (SELECT 1 FROM cfg.EXCLUSION e WHERE e.CLIENTE = '{CLIENTE}' AND e.TIPO = 'DIRECCION' AND e.ACTIVO = 1 AND e.VALOR IN (t.CUENTA, t.CUENTA2, t.CTA_BANCO) AND e.VALOR2 = t.DIRECC1)", "Dirección mala (dirmal)", None),
        ("DIRECC1", "''", "EXISTS (SELECT 1 FROM cfg.EXCLUSION e WHERE e.CLIENTE = '{CLIENTE}' AND e.TIPO = 'DIRECCION' AND e.ACTIVO = 1 AND e.VALOR IN (t.CUENTA, t.CUENTA2, t.CTA_BANCO) AND e.VALOR2 = t.DIRECC1)", "Dirección mala (dirmal); va al final porque DIRECC1 es parte de la condición", None),
    ]]
)


# ---------------------------------------------------------------- catálogos estáticos (decisión 17/11)
# Lo que antes estaba escrito en la homologación ahora vive en cfg.CATALOGO, que edita el equipo de asignaciones
# (cfg.sp_catalogo_alta). La semilla solo agrega lo que falta: nunca cambia ni borra lo que el equipo puso.
# Valor de origen sin acentos ni mayúsculas; admite % y [0-9]. El exacto gana; entre patrones gana el ORDEN menor.
# (CATALOGO, DESCRIPCION, ORIGEN, DESTINO, [(VALOR_ORIGEN, VALOR_DESTINO, ORDEN)])
CATALOGOS = [
    ("ESTATUS_TDC", "Estatus de TDC válidos; BCOB, BOPE y FALL con tramo 0 son reestructura",
     "MAESTRA_TDC · Estatus al <fecha>", "ESTATUS2 = REE (solo con tramo 0); '' = válido sin etiqueta",
     [("CCAS", "", 100), ("VEN2", "", 100), ("VEN3", "", 100), ("VEN4", "", 100),
      ("BCOB", "REE", 100), ("BOPE", "REE", 100), ("FALL", "REE", 100)]),
    ("TRAMO_TDC", "Tramo de TDC -> estatus (VIG / VEN / CAS); 90+ se decide por el enfoque (ENFOQUE_TDC_90)",
     "MAESTRA_TDC · Tramo <fecha>", "ESTATUS2 (y TIPO = 'TDC_' + ESTATUS2); '' = válido sin etiqueta",
     [("1-29", "VIG", 100), ("30-59", "VEN", 100), ("60-89", "VEN", 100), ("CASTIGADA", "CAS", 100), ("90+", "", 100), ("0", "", 100),
      ("[1-9]", "VIG", 10), ("[1-2][0-9]", "VIG", 10), ("[3-8][0-9]", "VEN", 10)]),
    ("ENFOQUE_TDC_90", "Enfoque de liquidación de TDC en tramo 90+ -> estatus. Legado: varias palabras gana sobre liquidación",
     "MAESTRA_TDC · ENFOQUE_LIQUIDACION_1_PAGO", "ESTATUS2 cuando el tramo es 90+",
     [("%CONTENCION%", "VEN", 10), ("% %", "VEN", 20), ("%LIQUIDACION%", "CAS", 30)]),
    ("GARANTIA_TDC", "Tarjeta garantizada", "MAESTRA_TDC · GARANTIZADA", "GARAN",
     [("1", "GARANTIZADA", 100), ("0", "", 100)]),
    ("ESTATUS_CONSUMO", "Estatus de Consumo -> segmento corto", "MAESTRA_CONSUMO · ESTATUS AL <fecha>", "SEGMENTO (y TIPO = cartera + '_' + SEGMENTO)",
     [("VIGENTE", "VIG", 100), ("VENCIDA", "VEN", 100), ("CASTIGADA", "CAS", 100), ("PAGO SOSTENIDO", "REE", 100)]),
    ("CARTERA_CONSUMO", "Cartera de Consumo -> tipo", "MAESTRA_CONSUMO · CARTERA", "TIPO",
     [("NOMINA", "NOMINA", 100), ("PERSONAL", "PERS", 100), ("RS TDC", "PERS", 100),
      ("%AUTO%", "AUTO", 20), ("%ANTICIPO NOMINA%", "NOMINA", 30)]),
    ("TIPO_CREDITO_CONSUMO", "Tipo de crédito de Consumo -> clasificación. Las reglas AUTO PPF / AUTO REE / PERSONAL PPF / "
     "PERSONAL REE del legado nunca se cumplían (H-22): si se necesitan, se agregan aquí",
     "MAESTRA_CONSUMO · TIPO DE CRÉDITO", "ESTRA3 (sin valor en el catálogo se queda el texto recortado a 15)",
     [("NOMINA REESTRUCTURADA", "NOMINA REE", 100), ("NOMINA REVOLVENTE", "NOMINA REV", 100), ("NOMINA REVOLVENTE RENOVADA", "NOMINA REV", 100),
      ("%PERSONAL%", "PERSONAL", 10), ("%AUTO%", "AUTO", 20), ("%ADELANTO DE NOMINA%", "NOMINA", 30)]),
    ("TIPO_HIPO", "Estatus de Hipotecario -> tipo", "MAESTRA_HIPO · ESTATUS <fecha>", "TIPO",
     [("CAS", "HIPO_CAS", 100), ("CASTIGA", "HIPO_CAS", 100), ("CCAS", "HIPO_CAS", 100),
      ("VENCIDA", "HIPO_VEN", 100), ("VEN4", "HIPO_VEN", 100), ("90+", "HIPO_VEN", 100), ("VEN", "HIPO_VEN", 100),
      ("VIG", "HIPO_VIG", 100), ("VEN3", "HIPO_VIG", 100), ("60-89", "HIPO_VIG", 100), ("VEN2", "HIPO_VIG", 100), ("VIGENTE", "HIPO_VIG", 100)]),
    ("ENFOQUE_HIPO", "Enfoque de liquidación de Hipotecario", "MAESTRA_HIPO · ENFOQUE_LIQUIDACION", "ETIQUETA5",
     [("LIQUIDACION", "LIQ", 100), ("REGULARIZACION Y LIQUIDACION", "REG-LIQ", 100), ("LIQUIDACION Y REGULARIZACION", "REG-LIQ", 100),
      ("REGULARIZACION", "REG", 100)]),
    ("COSECHA_MORA", "Cosecha de la base maestra -> mora (después de quitar '-')", "MAESTRA_* · COSECHAS", "ETIQUETA1",
     [("COSECHA 1", "MORA 1", 100), ("COSECHA 2", "MORA 2", 100), ("COSECHA 3", "MORA 3", 100)]),
    ("ETIQUETA6_TDC", "Elegible a REE en TDC (correo 'Etiquetado REE', 19/11). Cualquier otro valor deja ETIQUETA6 vacía",
     "MAESTRA_TDC · ENFOQUE_PLAN DE PAGOS", "ETIQUETA6 (U1EXT2 del SCBSDOS)",
     [("APLICA PLAN DE PAGOS", "REE", 100)]),
    ("ETIQUETA6_CONSUMO", "Elegible a REE en Consumo (correo 'Etiquetado REE', 19/11). Cualquier otro valor deja ETIQUETA6 vacía",
     "MAESTRA_CONSUMO · ENFOQUE_REESTRUCTURA", "ETIQUETA6 (U1EXT2 del SCBSDOS)",
     [("APLICA RESTRUCTURA", "REE", 100), ("APLICA REESTRUCTURA", "REE", 100)]),
    # Blanqueo de ETIQUETA6 por tramo (correo 'RE: Etiquetado REE', 23/11): SEG del archivo de saldos (ETIQUETA3 en el DAT de Operación)
    ("ETIQUETA6_SEG_TDC", "Tramo de TDC (SEG del archivo de saldos; ETIQUETA3 de Operación) y si conserva el REE. Solo VEN2 y VEN3 son elegibles; "
     "un tramo que no está aquí también blanquea (ops.sp_etiqueta6_blanqueo)",
     "SALDOS_TDC · ESTATUS -> DAT.SEG", "SI = conserva ETIQUETA6; NO = se blanquea",
     [("VEN2", "SI", 100), ("VEN3", "SI", 100), ("VEN4", "NO", 100), ("CCAS", "NO", 100)]),
    ("ETIQUETA6_SEG_CONSUMO", "Tramo de Consumo (SEG del archivo de saldos; ETIQUETA3 de Operación) y si conserva el REE. Elegibles de 1-29 a 90+; "
     "un tramo que no está aquí también blanquea (ops.sp_etiqueta6_blanqueo)",
     "SALDOS_CONS · TRAMO -> DAT.SEG", "SI = conserva ETIQUETA6; NO = se blanquea",
     [("1-29", "SI", 100), ("30-59", "SI", 100), ("60-89", "SI", 100), ("90+", "SI", 100), ("CASTIGADA", "NO", 100)]),
]

# ---------------------------------------------------------------- reglas
# estructura.prg: REE del DAT en la actualización (se aplica en orden; la última que cumple gana).
# VAL(TRAMO) de FoxPro = número al inicio del texto ('60-89' -> 60, '90+' -> 90, vacío -> 0).
# Las comparaciones de FoxPro distinguen mayúsculas (CS) y '=' compara el inicio del texto.
VT = "ISNULL(TRY_CONVERT(INT, LEFT(LTRIM(t.TRAMO), PATINDEX('%[^0-9]%', LTRIM(ISNULL(t.TRAMO, '')) + 'x') - 1)), 0)"
CS = "COLLATE Latin1_General_CS_AS"
TDC_, NOM_, AUT_, PER_ = "t.SEGMENTO2 = 'TDC'", f"t.TIPO {CS} LIKE '%NOMINA%'", f"t.TIPO {CS} LIKE '%AUTO%'", f"t.TIPO {CS} LIKE '%PERS%'"
COVID_ = f"t.ETIQUETA {CS} LIKE 'COVID%'"
T90_, TCAS_ = f"t.TRAMO {CS} LIKE '90+%'", f"t.TRAMO {CS} LIKE 'CASTIGADA%'"
REEST, VACIO = "'REEST'", "NULL"
ESTRUCTURA_REE = [
    ("REE", REEST, f"{TDC_} AND {VT} BETWEEN 60 AND 89", "TDC tramo 60-89", None),
    ("REE", REEST, f"{COVID_} AND {TDC_} AND {VT} BETWEEN 1 AND 89", "TDC COVID tramo 1-89", None),
    ("REE", VACIO, f"{T90_} AND {TDC_}", "TDC 90+", None),
    ("REE", VACIO, f"{TCAS_} AND {TDC_}", "TDC castigada", None),
    ("REE", VACIO, f"(t.TRAMO IS NULL OR LTRIM(t.TRAMO) = '' OR t.TRAMO LIKE ' %') AND {TDC_}", "TDC sin tramo", None),
    ("REE", VACIO, f"t.GARAN {CS} LIKE 'garantizada%' AND {TDC_}", "TDC garantizada", None),
    ("REE", REEST, f"{NOM_} AND {VT} BETWEEN 1 AND 88", "Nómina tramo 1-88", None),
    ("REE", VACIO, f"{NOM_} AND {VT} >= 89", "Nómina tramo >= 89", None),
    ("REE", VACIO, f"{NOM_} AND {T90_}", "Nómina 90+", None),
    ("REE", VACIO, f"{NOM_} AND {TCAS_}", "Nómina castigada", None),
    ("REE", REEST, f"{AUT_} AND {VT} BETWEEN 60 AND 89", "Auto tramo 60-89", None),
    ("REE", VACIO, f"{AUT_} AND {VT} > 89", "Auto tramo > 89", None),
    ("REE", REEST, f"{COVID_} AND {AUT_} AND {VT} BETWEEN 1 AND 89", "Auto COVID tramo 1-89", None),
    ("REE", VACIO, f"{COVID_} AND {AUT_} AND {VT} > 89", "Auto COVID tramo > 89", None),
    ("REE", VACIO, f"{T90_} AND {AUT_}", "Auto 90+", None),
    ("REE", VACIO, f"{TCAS_} AND {AUT_}", "Auto castigada", None),
    ("REE", REEST, f"{PER_} AND {VT} BETWEEN 60 AND 89", "Personal tramo 60-89", None),
    ("REE", VACIO, f"{PER_} AND {VT} > 89", "Personal tramo > 89", None),
    ("REE", REEST, f"{COVID_} AND {PER_} AND {VT} BETWEEN 1 AND 89", "Personal COVID tramo 1-89", None),
    ("REE", VACIO, f"{COVID_} AND {PER_} AND {VT} > 89", "Personal COVID tramo > 89", None),
    ("REE", VACIO, f"{T90_} AND {PER_}", "Personal 90+", None),
    ("REE", VACIO, f"{TCAS_} AND {PER_}", "Personal castigada", None),
]
HOMOLOGACION = HOMOLOGACION + [("dat.DAT_486",) + x for x in ESTRUCTURA_REE]

# (PROCESO, PASO, CODIGO, TABLA, CONDICION, EVALUA, ACCION, MENSAJE, PLANTILLA, ORDEN, REQ)
CIENTIFICA = lambda *cols: " OR ".join(f"t.{c} LIKE '%[0-9][Ee][+-][0-9]%'" for c in cols)
REGLAS = [
    ("ASIG", "POST_CARGA", "TDC_NOTACION_CIENTIFICA", "stg.ENT_MAESTRA_TDC", CIENTIFICA("PRIME4DIG", "RIESGO"), "FILAS", "CANCELAR",
     "La base maestra TDC trae cuentas en notación científica (Excel cortó el número al guardar el CSV)", "MAESTRA_NUMEROS_EXCEL_486", 1, None),
    ("ASIG", "POST_CARGA", "CONSUMO_NOTACION_CIENTIFICA", "stg.ENT_MAESTRA_CONSUMO", CIENTIFICA("CUENTA"), "FILAS", "CANCELAR",
     "La base maestra Consumo trae créditos en notación científica (Excel cortó el número al guardar el CSV)", "MAESTRA_NUMEROS_EXCEL_486", 2, None),
    ("ASIG", "POST_CARGA", "HIPO_NOTACION_CIENTIFICA", "stg.ENT_MAESTRA_HIPO", CIENTIFICA("CUENTA", "RIESGO"), "FILAS", "CANCELAR",
     "La base maestra Hipotecario trae créditos en notación científica (Excel cortó el número al guardar el CSV)", "MAESTRA_NUMEROS_EXCEL_486", 3, None),
    ("ASIG", "POST_CARGA", "SDO_ACT_CONSUMO_CERO", "stg.ENT_MAESTRA_CONSUMO", "t.SDO_ACT <= 0", "FILAS", "ALERTAR",
     "Cuentas de Consumo con saldo actual <= 0 en la base maestra: reportarlo al banco", "ALERTA_SDO_ACT_CONS_486", 10, None),
    ("ASIG", "PRE_ALTA", "EXCLUSION_CUENTAS", "stg.LAYOUT_486",
     "t.ES_EXISTENTE = 0 AND EXISTS (SELECT 1 FROM cfg.EXCLUSION e WHERE e.CLIENTE = '{CLIENTE}' AND e.TIPO = 'CUENTA' AND e.ACTIVO = 1 AND e.VALOR IN (t.CUENTA, t.CTA_BANCO))",
     "FILAS", "EXCLUIR", "Cuenta en la lista de exclusión (exc486)", None, 10, "Yolanda Osornio 02/09/2020"),
    ("ACT", "POST_CARGA", "PAGOS_NEGATIVOS", "stg.ENT_PAGOS", "t.IMPORTE < 0", "FILAS", "EXCLUIR",
     "Llegaron pagos negativos: no se arriban (no salen en SCBPAG) y se avisa al equipo de asignaciones", "PAGOS_NEGATIVOS_486", 10, None),
    ("ACT", "POST_CARGA", "PAGOS_T1", "stg.ENT_PAGOS", "t.FECHA = cfg.fn_dia_habil_anterior(CAST('{FECHA}' AS DATE))", "SIN_FILAS", "ALERTAR",
     "No hay pagos del día hábil anterior (T-1; el lunes es el viernes). Solo bitácora: el correo se retiró (30/10)", None, 20, None),
    ("ACT", "RETIRO", "RETIRO_TDC", "stg.SALDOS_486",
     "t.SEGMENTO2 = 'TDC' AND (t.SEG IN ('CERR', 'NORM', '0', '-') OR t.SDO_ACT <= 0)", "FILAS", "DEVOLVER",
     "TDC cerrada, normalizada o sin saldo", None, 10, "REQ 2021-028883"),
    ("ACT", "RETIRO", "RETIRO_CONSUMO", "stg.SALDOS_486",
     "t.SEGMENTO2 = 'CONSUMO' AND (t.SEG IN ('0', '-') OR t.SDO_ACT <= 0)", "FILAS", "DEVOLVER",
     "Consumo sin tramo o sin saldo", None, 20, "REQ 2021-028883"),
    ("ACT", "RETIRO", "RETIRO_DAT_SIN_SALDO", "dat.DAT_486", "t.CLIENTE = '{CLIENTE}' AND t.SDO_ACT <= 0", "FILAS", "DEVOLVER",
     "Cuenta del DAT con saldo actual <= 0", None, 30, "REQ 2025-099547"),
]


# ---------------------------------------------------------------- validación de datos de la entrada (decisión 17/11)
# (CODIGO, CAMPO, TIPO, VALOR, PCT_MAX, DESCRIPCION). La semilla solo agrega las que faltan: el equipo ajusta
# VALOR, PCT_MAX y ACTIVO en cfg.VALIDACION_DATO. Tolerancias calibradas con las bases reales del 11 y 13/11
# (teléfonos de 10 dígitos sin letras; correos mal formados < 0.2 %; saldos de hasta 1.2 millones; sin cuentas repetidas).
TOPE_SALDO = {"TDC": "10000000", "CONSUMO": "10000000", "HIPO": "50000000"}


def v_importes(cod, campos, tope, negativos=True):
    out = []
    for c in campos:
        out += [(cod, c, "IMPORTE", None, 0, "Texto que no es importe en una columna de saldo"),
                (cod, c, "MAXIMO", tope, 0, "Importe fuera de rango: suele ser una cuenta o un teléfono en la columna de saldo")]
        if negativos:
            out.append((cod, c, "NO_NEGATIVO", None, 1, "Saldos negativos: unos cuantos se toleran, muchos indican un archivo mal armado"))
    return out


def v_contacto(cod, tels, correos=("CORREO1", "CORREO2")):
    return ([(cod, t, "TELEFONO", "10-12", 2, "Teléfono con letras o con un número de dígitos fuera de rango") for t in tels]
            + [(cod, c, "CORREO", None, 2, "Correo sin forma de correo (sin @, con espacios o sin dominio)") for c in correos])


TELS13 = [f"TEL{i}" for i in range(1, 14)]
VALIDACIONES = (
    [("MAESTRA_TDC", "*", "VOLUMEN", "30-300", 0, "Renglones contra la última carga buena (archivo cortado o duplicado)"),
     ("MAESTRA_TDC", "RIESGO", "LLAVE_UNICA", None, 0, "ACC_NUM repetido (es la llave única desde el 20/11)"),
     ("MAESTRA_TDC", "RIESGO", "DIGITOS", "1-20", 0, "ACC_NUM con letras o de más de 20 dígitos (la llave única mide 20)"),
     ("MAESTRA_TDC", "*", "ARCHIVO_IGUAL", None, 0, "Idéntico al último archivo bueno de otro día (el banco reenvió el anterior)"),
     ("MAESTRA_TDC", "RIESGO", "NO_VACIO", None, 1, "ACC_NUM vacío"),
     ("MAESTRA_TDC", "SDO_VDO", "NO_VACIO", None, 5, "Saldo PRIME vacío (la columna se corrió o cambió)"),
     ("MAESTRA_TDC", "SEGMENTO", "CATALOGO", "ESTATUS_TDC", 0, "Estatus que no está en el catálogo"),
     ("MAESTRA_TDC", "TRAMO", "CATALOGO", "TRAMO_TDC", 0, "Tramo que no está en el catálogo"),
     ("MAESTRA_TDC", "GARAN", "CATALOGO", "GARANTIA_TDC", 0, "GARANTIZADA distinto de 1 / 0"),
     ("MAESTRA_TDC", "PVS", "ENTERO", None, 0, "Días vencidos que no son número")]
    + v_importes("MAESTRA_TDC", ["SDO_ACT", "SDO_VDO", "PAG_MIN", "SALDO1", "SALDO2"], TOPE_SALDO["TDC"])
    + v_contacto("MAESTRA_TDC", TELS13)
    + [("MAESTRA_CONSUMO", "*", "VOLUMEN", "30-300", 0, "Renglones contra la última carga buena (archivo cortado o duplicado)"),
       ("MAESTRA_CONSUMO", "CUENTA", "LLAVE_UNICA", None, 0, "Crédito repetido (es la llave única)"),
       ("MAESTRA_CONSUMO", "CUENTA", "DIGITOS", "1-20", 0, "Crédito con letras o de más de 20 dígitos (la llave única mide 20)"),
       ("MAESTRA_CONSUMO", "*", "ARCHIVO_IGUAL", None, 0, "Idéntico al último archivo bueno de otro día (el banco reenvió el anterior)"),
       ("MAESTRA_CONSUMO", "DES_PROD", "LLAVE_UNICA", None, 0, "Crédito CYBER repetido"),
       ("MAESTRA_CONSUMO", "CUENTA", "NO_VACIO", None, 1, "Crédito vacío"),
       ("MAESTRA_CONSUMO", "SDO_ACT", "NO_VACIO", None, 5, "Adeudo total vacío (la columna se corrió o cambió)"),
       ("MAESTRA_CONSUMO", "SEGMENTO", "CATALOGO", "ESTATUS_CONSUMO", 0, "Estatus que no está en el catálogo"),
       ("MAESTRA_CONSUMO", "TIPO", "CATALOGO", "CARTERA_CONSUMO", 0, "Cartera que no está en el catálogo"),
       ("MAESTRA_CONSUMO", "TIPO_CREDITO", "CATALOGO", "TIPO_CREDITO_CONSUMO", 0, "Tipo de crédito que no está en el catálogo"),
       ("MAESTRA_CONSUMO", "PVS", "ENTERO", None, 0, "Días de mora que no son número")]
    + v_importes("MAESTRA_CONSUMO", ["CAPITAL", "SDO_ACT", "SDO_VDO", "SALDO1", "SALDO2"], TOPE_SALDO["CONSUMO"])
    + v_contacto("MAESTRA_CONSUMO", TELS13)
    + [("MAESTRA_HIPO", "*", "VOLUMEN", "30-300", 0, "Renglones contra la última carga buena (archivo cortado o duplicado)"),
       ("MAESTRA_HIPO", "CUENTA", "LLAVE_UNICA", None, 0, "Crédito repetido (es la llave única)"),
       ("MAESTRA_HIPO", "*", "ARCHIVO_IGUAL", None, 0, "Idéntico al último archivo bueno de otro día (el banco reenvió el anterior)"),
       ("MAESTRA_HIPO", "DES_PROD", "LLAVE_UNICA", None, 0, "Crédito CYBER repetido"),
       ("MAESTRA_HIPO", "CUENTA", "NO_VACIO", None, 1, "Crédito vacío"),
       ("MAESTRA_HIPO", "SDO_ACT", "NO_VACIO", None, 5, "Adeudo total vacío (la columna se corrió o cambió)"),
       ("MAESTRA_HIPO", "SEGMENTO", "CATALOGO", "TIPO_HIPO", 0, "Estatus que no está en el catálogo"),
       ("MAESTRA_HIPO", "PVS", "ENTERO", None, 0, "Días de mora que no son número")]
    + v_importes("MAESTRA_HIPO", ["SDO_VDO", "SDO_ACT", "CAPITAL", "SALDO1", "SALDO2"], TOPE_SALDO["HIPO"])
    + v_contacto("MAESTRA_HIPO", [f"TEL{i}" for i in range(1, 17)])
    # Actualización: un saldo negativo o cero es un criterio de retiro (cfg.REGLA RETIRO_*), no se valida aquí
    + [("SALDOS_TDC", "*", "VOLUMEN", "30-300", 0, "Renglones contra la última carga buena (archivo cortado o duplicado)"),
       ("SALDOS_TDC", "RIESGO", "NO_VACIO", None, 1, "ACC_NUM vacío"),
       ("SALDOS_TDC", "RIESGO", "LLAVE_UNICA", None, 0, "ACC_NUM repetido en saldos (20/11: para y avisa)"),
       ("SALDOS_TDC", "RIESGO", "CRUCE_DAT", "RIESGO", 30, "ACC_NUM que no está en el DAT: más del 30 % = archivo de otro segmento o de otro cliente"),
       ("SALDOS_TDC", "*", "ARCHIVO_IGUAL", None, 0, "Idéntico al último archivo bueno de otro día (el banco reenvió el anterior)")]
    + v_importes("SALDOS_TDC", ["SDO_ACT", "PAG_MIN"], TOPE_SALDO["TDC"], negativos=False)
    + [("SALDOS_CONS", "*", "VOLUMEN", "30-300", 0, "Renglones contra la última carga buena (archivo cortado o duplicado)"),
       ("SALDOS_CONS", "DES_PROD", "NO_VACIO", None, 1, "Crédito CYBER vacío"),
       ("SALDOS_CONS", "DES_PROD", "LLAVE_UNICA", None, 0, "Crédito CYBER repetido en saldos (20/11: para y avisa)"),
       ("SALDOS_CONS", "DES_PROD", "CRUCE_DAT", "DES_PROD", 30, "Crédito CYBER que no está en el DAT: más del 30 % = archivo de otro segmento o de otro cliente"),
       ("SALDOS_CONS", "*", "ARCHIVO_IGUAL", None, 0, "Idéntico al último archivo bueno de otro día (el banco reenvió el anterior)"),
       ("SALDOS_CONS", "PVS", "ENTERO", None, 0, "Días de mora que no son número")]
    + v_importes("SALDOS_CONS", ["SDO_ACT", "SDO_VDO", "PAG_MIN"], TOPE_SALDO["CONSUMO"], negativos=False)
    + v_importes("SALDOS_HIP", ["SDO_ACT"], TOPE_SALDO["HIPO"], negativos=False)
    # Pagos: los negativos ya se excluyen y se avisan (cfg.REGLA PAGOS_NEGATIVOS); el volumen cambia mucho de un día a otro
    + [("PAGOS", "RIESGO", "NO_VACIO", None, 1, "Crédito vacío")]
    + v_importes("PAGOS", ["IMPORTE"], TOPE_SALDO["CONSUMO"], negativos=False)
)

# Campos de CYBER para las vistas (19/11): columna de d = DELQMST, u = UDA1 o r = RPT_DAT_486_1 (tal como esté en CYBER:
# no se ejecuta PROC_DAT_486, decisión 19/11)
CYBER_CAMPOS = [
    ("ESTATUS", "d.DMACRC2", "Estatus de la cuenta en CYBER (DELQMST.DMACRC2, la misma tabla donde se validan los saldos)"),
    ("ABAN_SR", "r.ABAN_SR", "Días desde la última gestión de usuario que empieza con 1 o a. r = CYBER_TABLA_ABANDONO (de fábrica RPT_DAT_486_1, como la dejó PROC_DAT_486 la última vez que se corrió en CYBER)"),
    ("ABAN_CR", "r.ABAN_CR", "Días desde la última gestión de usuario que empieza con z (RPT_DAT_486_1)"),
    ("SDO_CYBER", "d.DMCURBAL", "Saldo actual en CYBER (DELQMST.DMCURBAL)"),
]

# Vistas de usuarios (18/11): qué ve cada usuario externo. El equipo de asignaciones las edita en
# cfg.VISTA_USUARIO / cfg.VISTA_COLUMNA; la semilla solo agrega lo que falta. ORIGEN: DAT, CYBER (columna de
# cfg.CYBER_CAMPO, que se baja directo de DELQMST / RPT_DAT_486_1 sin ejecutar el store desde el 19/11), MAESTRA (encabezado de la base maestra) o CONSTANTE.
VISTAS = [
    # vista, ver retiros, activa, descripción, [(encabezado, origen, campo)]
    ("AEM", 1, 1, "Equipo de AEM (MAPEO_USUARIOS.xlsx, 18/11). También ve las cuentas retiradas del día (antes MX_G1MCT_DVBJIG_* en Cyber_00)", [
        ("GRUPO", "CONSTANTE", "1"),
        ("CUENTA", "DAT", "CUENTA2"),
        ("CLIENTE", "DAT", "CLIENTE"),
        ("FOLIO", "DAT", "FOLIO"),
        ("NOMBRE1", "DAT", "NOMBRE1"),
        ("PVS", "DAT", "PVS"),
        ("SDO_ACT", "DAT", "SDO_ACT"),
        ("ESTATUS_CYBER", "CYBER", "ESTATUS"),
        ("FE_ASIG", "DAT", "FE_ASIG"),
        ("ESTADO", "DAT", "ESTADO"),
        ("ABANDONO_SR", "CYBER", "ABAN_SR"),
        ("ETIQUETA03", "DAT", "TIPO"),
        ("ETIQUETA01", "DAT", "ETIQUETA1"),
        ("ETIQUETA02", "DAT", "ESTRA3"),
        ("ETIQUETA50", "DAT", "RFC"),
        ("ETIQUETA04", "DAT", "SEG"),
        ("CAPITAL", "DAT", "CAPITAL"),
        ("SALDO01", "DAT", "SALDO1"),
        ("SALDO02", "DAT", "SALDO2"),
        ("SALDO03", "DAT", "SALDO3"),
    ]),
    ("MIS", 0, 0, "Equipo de MIS: usa datos de las bases maestras que no están en el DAT. El equipo de asignaciones agrega sus columnas (cfg.sp_vista_columna_alta) y la activa", []),
]

PARAMETROS = [
    ("PREFIJO_CUENTA2", "486-", "Prefijo de la cuenta en CYBER"),
    ("CYBER_TABLA_ABANDONO", "RCVRY.RPT_DAT_486_1", "Tabla de CYBER de donde las vistas toman ABAN_SR y ABAN_CR (alias r de cfg.CYBER_CAMPO; 19/11: RPT_DAT_486_1 tal como la dejó PROC_DAT_486, sin ejecutarlo). Para tomarlos de otra tabla, cambiar este parámetro y CYBER_LLAVE_ABANDONO"),
    ("CYBER_LLAVE_ABANDONO", "CUENTA", "Columna de CYBER_TABLA_ABANDONO con la cuenta (486-folio) que se cruza con DELQMST.DMACCT"),
    ("VISTAS_USUARIO", "1", "1 (18/11) = al terminar la actualización y la asignación, y cuando suben los saldos, se bajan de CYBER los campos de las vistas (directo de DELQMST y RPT_DAT_486_1, sin ejecutar el store desde el 19/11) y se arma la tabla de cada usuario (cfg.VISTA_USUARIO: AEM, MIS); 0 = no se actualizan"),
    ("VALIDAR_LAYOUT", "1", "1 (17/11) = si a un archivo le falta cualquier campo que toma el proceso (cfg.ARCHIVO_COLUMNA, obligatorio u opcional), la corrida se detiene antes de tocar el DAT y se avisa al equipo de asignaciones (VALIDACION_ENTRADA_486); 0 = como antes: solo los obligatorios detienen"),
    ("VALIDAR_DATOS", "1", "1 (17/11) = cada archivo se revisa con las reglas de cfg.VALIDACION_DATO (importes, teléfonos, correos, catálogos, cuentas repetidas, volumen); si una supera su tolerancia, la corrida se detiene antes de tocar el DAT y se avisa (VALIDACION_ENTRADA_486); 0 = no se revisan"),
    ("TOPE_DEVOLUCION_PCT", "", "Vacío = sin tope: la base maestra se trabaja como llega. Con un número (ej. 10) se detiene si la devolución de un segmento supera ese %"),
    ("DMSTATUS_RETIRO", "R", "dmstatus que se pone en CYBER al retirar (prog15.prg: u8activo = 'R')"),
    ("ASIG_REQUIERE_ACT", "1", "1 = la asignación solo corre si la actualización del mismo día terminó OK (la asignación siempre llega después)"),
    ("RESPALDOS_A_CONSERVAR", "15", "Corridas con respaldo del DAT que se conservan para retroceso"),
    ("ALERTA_NUEVAS", "100", "Más cuentas nuevas que esto dispara la alerta (aem_alerta)"),
    ("DIAS_FE_REG", "30", "FE_REG = FE_REC + días"),
    ("NEGATIVO_MODO", "CERO", "Importes negativos en SCBSDOS (DMCURBAL, U1PAGMIN, DMAMTDLQ) y scripts de saldos: CERO (decisión 30/10: saldo <= 0 se retira, sube en cero antes del retiro) | ABS_LEGADO | SIGNO"),
    ("LADAS_2_DIGITOS", "33,55,56,81", "Ladas de 2 dígitos (telbnx.prg); el resto son de 3"),
    ("LADAS_044", "55,56", "Celulares de estas ladas van con área 044; el resto con 045"),
    ("TEL_INVALIDOS", "1000000000,9999999999,0999999999,1111111111,4444444444,5555555555,5000000000",
     "Teléfonos que nunca se mandan (telbnx.prg + G4_025_TELEFONOS); además se descartan los que empiezan con 0"),
    ("TEL_EXIGIR_PNM", "1", "1 = el teléfono que no está en el plan de numeración se descarta (G4_025_TELEFONOS, decisión 01/11); 0 = sale como fijo (telbnx.prg)"),
    ("ARRIBO_AUTOMATICO", "1", "1 (07/11: proceso autónomo; orden del 17/11 y 19/11) = con los saldos arriba el job manda los gescar de nuevas, reasignadas y sin teléfono y corre la depuración de teléfonos (con bandera); si cuadra avisa para subir el SCBTEL y corre la de correos; al final confirma. 0 = a mano con ops.sp_arribar_cyber y ops.sp_arribo_gescar_sintel"),
    ("ARCHIVOS_DESPUES_SALDOS", "GESCAR_NVA,GESCAR_REA,GESCAR_SINTEL", "Con ARRIBO_AUTOMATICO = 1, archivos de la asignación que se escriben y avisan hasta que suben los saldos (paso ARRIBO SALDOS). GESCAR_SINTEL siempre espera a los saldos (19/11)"),
    ("ARCHIVOS_DESPUES_DEPURACION_TEL", "SCBTEL", "Con ARRIBO_AUTOMATICO = 1, archivos que se escriben y avisan hasta que la depuración de teléfonos queda OK (el store inactiva lo que no está en la remesa y el SCBTEL activa lo nuestro)"),
    ("ARRIBO_MIN_PCT", "95", "% de lo pendiente al terminar la asignación (cuentas y domicilios en DELQMST, teléfonos en PHONE_G1) que ya debe estar en CYBER para dar por subido el SCBSDOS o el SCBTEL"),
    ("CYBER_REMESA_TEL_COLUMNAS", "CUENTA,AREA,TELEFONO,TIPOTEL", "Columnas de RCVRY.JSP_TAB_TEL_REMESA_486 en el orden de sub_mst.TXT (confirmar con LOAD_TEL_REMESA.CTL)"),
    ("CYBER_REMESA_MAIL_COLUMNAS", "CUENTA,CORREO", "Columnas de RCVRY.JSP_TAB_MAIL_REMESA_486 en el orden de sub_mail.TXT (confirmar con LOAD_MAIL_REMESA.CTL)"),
    ("CYBER_HOSTUP_EXPR", "to_char(DMHOSTUP, 'YYYYMMDD')", "Validación de saldos del equipo (val.txt, 15/11): expresión de Oracle con la fecha de DMHOSTUP en AAAAMMDD; el arribo agrupa las cuentas activas del 486 por ella. Si DMHOSTUP no es DATE, ajustarla (ej. DMHOSTUP si ya viene como texto AAAAMMDD). Vacío = se detecta el SCBSDOS por cuentas y domicilios pendientes"),
    ("ARRIBO_SDOS_MIN_PCT", "100", "% de las cuentas del SCBSDOS que deben tener DMHOSTUP del día para dar por subidos los saldos (100 = que el número coincida)"),
    ("CYBER_COLUMNA_DOMICILIO", "DMADDR1", "Columna de RCVRY.DELQMST con el domicilio del SCBSDOS; el arribo automático la usa para saber si ya subió el SCBSDOS aunque no haya cuentas nuevas (vacío = no se compara)"),
    ("RETIRO_AUTOMATICO", "1", "1 = las devoluciones de la asignación y la actualización se aplican solas si no superan el tope, y después se escriben los archivos, ZIP y correo, se ejecuta RETIRO en CYBER y se copia la devolución a RUTA_DEVOLUCION_CYBER; 0 = manual"),
    ("RETIRO_TOPE_PCT_ASIG", "50", "En la asignación, si la devolución de un segmento supera este % de sus cuentas en el DAT, el retiro queda manual y se manda HALLAZGO_486"),
    ("RETIRO_TOPE_PCT_ACT", "50", "En la actualización, si la devolución de un segmento supera este % de sus cuentas en el DAT, el retiro queda manual y se manda HALLAZGO_486"),
    ("RETIRO_CYBER_AUTOMATICO", "1", "1 (07/11) = el cierre del retiro también ejecuta RETIRO en CYBER; la copia de la devolución a Cyber_00 sigue a mano mientras RUTA_DEVOLUCION_CYBER esté vacío. 0 = RETIRO en CYBER a mano (EXEC ops.sp_retiro_cerrar <id>, @con_cyber = 1)"),
    ("RUTA_DEVOLUCION_CYBER", "", "Carpeta donde CYBER toma el archivo de devolución MX_G1MCT_DVBJIG_* (\\\\192.168.50.1\\Cyber_00\\dev\\). Vacío (03/11: el servidor no tiene acceso a Cyber_00) = se copia a mano desde la carpeta de la corrida"),
    ("AVISO_ARCHIVOS", "1", "1 = en cuanto se escriben los planos que se suben a CYBER se manda ARCHIVOS_LISTOS_486 al equipo de asignaciones (ops.sp_aviso_archivos)"),
    ("ARCHIVOS_ARRIBO", "SCBSDOS,SCBSDOS_ETI,SCBTEL,GESCAR_NVA,GESCAR_REA,GESCAR_SINTEL,GESCAR_RETIRO,SCBPAG", "Archivos planos que el equipo de asignaciones sube con el cargador de CYBER (van en el aviso de archivos listos)"),
    ("EXPORTAR_AUTOMATICO", "1", "1 = cada corrida escribe sus archivos y scripts al terminar OK (ops.sp_exportar_salidas); 0 = a mano"),
    ("ETIQUETA6_BLANQUEO", "1", "1 (23/11) = la actualización y la asignación quitan el REE (ETIQUETA6) a las cuentas cuyo tramo (SEG) ya no es elegible (catálogos ETIQUETA6_SEG_TDC y ETIQUETA6_SEG_CONSUMO); 0 = apagado"),
    ("ACT_CYBER_AUTOMATICO", "1", "1 (07/11) = al terminar la actualización el job ejecuta en CYBER ACT_SALDOS, ACT_VENCIDO, ACT_PAGMIN y ACT_PVS_REE (ops.sp_act_cyber); 0 = a mano"),
    ("BLANQUEO_AUTOMATICO", "1", "1 (07/11) = el blanqueo de status (días DIAS_BLANQUEO_STATUS) se baja, se arma y se ejecuta en CYBER en cuanto subió el SCBSDOS (ops.sp_blanqueo_automatico); 0 = a mano"),
    ("CONFIRMACION_AUTOMATICA", "1", "1 (07/11) = al terminar OK las depuraciones de correos y teléfonos se marca el fin del arribo y se manda CONFIRMACION_ASIG_486 (ops.sp_confirmar_asignacion); 0 = a mano"),
    ("CUADRE_AUTOMATICO", "1", "1 = el job cuadra los pagos del SCBPAG contra CYBER y solo avisa (HALLAZGO_486) si a la hora límite falta alguno (ops.sp_cuadre_automatico)"),
    ("CUADRE_PAGOS_HORA_LIMITE", "17:00", "Hora a la que el cuadre automático deja de esperar al SCBPAG y avisa los pagos que no subieron"),
    ("CYBER_SENTENCIAS_POR_BLOQUE", "200", "Sentencias por bloque PL/SQL al ejecutar en CYBER"),
    ("CYBER_VALIDADOR_TELEFONOS", "1", "1 = el script TEL_BORRA inserta el renglón del día en RCVRY.JSP_VALIDADOR_TELEFONOS con el total de teléfonos (JSP_TELEFONOS_REMESA_486 lo completa)"),
    ("TELBAJ_LINKED_SERVER", "192.168.50.53", "Servidor vinculado al SQL Server de CYBER donde están telbaj, telbaj1 y TENOVA1 (como G4_025_TELEFONOS)"),
    ("TELBAJ_GRUPO", "1", "Grupo del 486 en telbaj (TELBAJ_G1)"),
    ("TELBAJ_TABLAS", "cyber.dbo.telbaj,cyber.dbo.telbaj1,tenova.dbo.TENOVA1", "Tablas de quejas en ese servidor (columnas grupo, cuenta, telo, telpho)"),
    ("PNM_TABLA", "CYBER.dbo.CAT_PNM", "Plan de numeración vigente en la misma instancia (columnas LADA, SERIE, NUMINI, NUMFIN, TIPORED); vacío = solo lo migrado"),
    ("TEL_DAT_LADAS_2", "33,55,81", "op9.prg: ladas de 2 dígitos al guardar los teléfonos de cuentas nuevas en el DAT"),
    ("TEL_DAT_AREA_MOVIL", "045", "op9.prg: área de los celulares al guardarlos en el DAT"),
    ("CORREOS_INVALIDOS", "notiene@hotmail.com,notiene@gmail.com,notienecorreo@hotmail.com,notiene@mail.com,notiene@email.com",
     "email.PRG: correos que no se mandan a CYBER"),
    ("CORREOS_EXCLUIR_MALOS", "1", "1 = EMAILMALO también se quita de sub_mail.TXT (decisión: sí se aplica)"),
    ("CYBER_BANDERA_CORREOS", "416", "id_proc de RCVRY.RPT_LOG_CYBER_REG que se enciende y apaga al actualizar correos (ACTIVA/INACTIVA_BANDERA.SQL)"),
    ("CYBER_PROC_CORREOS", "RCVRY.JSP_CORREOS_486", "Procedimiento de CYBER que purga y agrega los correos (INSERTA_MAIL.sql)"),
    ("STATUS_NO_BLANQUEAR", "GS,PP,LQ,NP,PR,CD,CC,FA", "status.prg: status que no se blanquean (REQ 2021-051124)"),
    ("DIAS_BLANQUEO_STATUS", "1-10", "status.prg: días del mes en que se blanquea status"),
    ("ETIQUETADO_CAMPOS", "SALDO1,SALDO2,SALDO3,RIESGO,PVS,TIPO,CAPITAL,SEGMENTO,PAG_MIN,ETIQUETA,TRAMO,SEG,SDO_VDO,NOMBRE2,ESTRA3,DES_PROD,ETIQUETA1,ETIQUETA5",
     "ops.sp_etiquetar_campo: columnas del DAT que Operación puede etiquetar"),
    ("ETIQUETADO_ALIAS", "SEG_CICLO=TRAMO,CLASIFICA=ESTRA3,ETIQUETA2=DES_PROD,ETIQUETA3=SEG,ETIQUETA4=RIESGO,LEYENDA=NOMBRE2,"
     "SALDO_VEN=SDO_VDO,ETIQUETA10=ETIQUETA,MORA=ETIQUETA1",
     "ETIQUETAS486.xlsx: nombre en el DAT de Operación = columna de nuestro DAT (ETIQUETA6 sale de la base maestra: REE, catálogos ETIQUETA6_TDC y ETIQUETA6_CONSUMO)"),
    ("CORREO_PRUEBA_PARA", "", "Pruebas de entorno (20/11): si tiene una dirección, todos los correos van solo ahí con [PRUEBA] en el asunto. Lo pone y lo quita ops.sp_prueba_modo; vacío en producción"),
    ("CYBER_SOLO_LECTURA", "0", "Pruebas de entorno (20/11): 1 = ningún script se ejecuta en CYBER (solo queda en la bitácora); las consultas sí. Lo pone y lo quita ops.sp_prueba_modo; 0 en producción"),
    ("RUTA_SALIDA", "C:\\BANBAJ\\486\\SALIDA\\", "ops.sp_exportar_salidas: carpeta de los archivos planos (se crea <AAAAMMDD>_corrida<ID>)"),
    ("RETROCESO_AUTOMATICO", "1", "1 = si una corrida falla, el DAT, histórico, folios y base maestra regresan solos a como estaban (ops.sp_retroceso_automatico); 0 = se dejan para revisar a mano"),
    ("RUTA_MIS", RUTA_Q + "\\MIS\\SERTEC98\\CLIENTES\\486\\", "ops.sp_exportar_salidas deja aquí también DAT486_<fecha>.csv (antes prog15.prg copiaba el DAT). Q: = \\\\192.168.50.13\\q"),
    ("CARPETA_ZIP", "C:\\", "ops.sp_exportar_salidas: carpeta del ZIP de retiros (C:\\RETIROS_PAG_486_<fecha><hora>.zip, como saldos.prg)"),
    ("RUTA_7ZIP", "C:\\Program Files\\7-Zip\\7z.exe", "7-Zip instalado en el servidor de SQL Server (ZIP con contraseña de retiros)"),
    ("CYBER_LINKED_SERVER", "CYBER", "Servidor vinculado a Oracle (cfg.sp_cyber_conectar / ops.sp_bajar_cyber)"),
    ("CYBER_ORACLE_ORIGEN", "", "PENDIENTE: Oracle de CYBER como host:puerto/servicio (ej. 10.0.0.5:1521/servicio)"),
    ("CYBER_ORACLE_PROVEEDOR", "OraOLEDB.Oracle", "Proveedor OLE DB de Oracle instalado en el servidor de SQL Server"),
    ("CYBER_PROC_TELEFONOS", "RCVRY.JSP_TELEFONOS_REMESA_486", "Procedimiento de CYBER que purga y agrega los teléfonos (ACTUALIZA_PHONE.SQL) con TEL_DEPURACION = ACTUAL"),
    ("TEL_VALIDAR_LADA", "1", "1 (19/11) = solo van a CYBER (SCBTEL y remesa) los teléfonos cuya lada y longitud están en cfg.PHNVAL, la copia de la tabla de ladas que admite el cargador; 0 = no se revisa"),
    ("CYBER_TABLA_LADAS", "RCVRY.PHNVAL", "Tabla de CYBER con las ladas válidas (VTCOMUNA, VTARECOD, VTLENGTH) que copia ops.sp_phnval_actualizar una vez al mes"),
    ("LADAS_MIN_FILAS", "100", "Si la tabla de ladas de CYBER llega con menos renglones que esto, no se toca cfg.PHNVAL (protege contra una bajada vacía o cortada)"),
    ("TEL_DEPURACION", "ACTUAL", "ACTUAL = remesa completa y store de hoy (CYBER_PROC_TELEFONOS); SCBTEL con todos. DIFERENCIA (19/11, cuando el DBA instale RCVRY.JSP_TAB_TEL_DEPURA_486 y JSP_TELEFONOS_DEPURA_486) = se baja la foto de PHONE, se compara aquí y a CYBER solo sube lo que cambia; el SCBTEL lleva solo los nuevos"),
    ("CYBER_PROC_TEL_DEPURA", "RCVRY.JSP_TELEFONOS_DEPURA_486", "Store de depuración de teléfonos con TEL_DEPURACION = DIFERENCIA (cyber/486/oracle/JSP_TELEFONOS_DEPURA_486.sql)"),
    ("CYBER_BANDERA_TELEFONOS", "416", "id_proc de RCVRY.RPT_LOG_CYBER_REG que se enciende antes de la depuración de teléfonos y se apaga al terminar o si falla (bitácora en RCVRY.RPT_LOG_CYBER); la misma de los correos"),
    ("TEL_GESTORES_QUEJA", "HOMS,HPHPI,BLACK,ZZZTE", "Gestores (PHSTCOLLID) de queja: con TEL_DEPURACION = DIFERENCIA sus teléfonos no se inactivan ni se activan"),
    ("TEL_DEPURA_MAX_INACTIVAR_PCT", "30", "Con TEL_DEPURACION = DIFERENCIA, si se inactivaría más de este % de los teléfonos activos de la foto de CYBER, no se toca CYBER y llega un hallazgo"),
    ("CAMPOS_ACTUALIZA_EXISTENTES",
     "TEL1,TEL2,TEL3,TEL4,TEL5,TEL6,TEL7,TEL8,TEL9,TEL10,TEL11,TEL12,TEL13,CORREO1,CORREO2,"
     "DIRECC1,DIRECC2,DIRECC3,DIRECC4,DIRECC5,ESTADO,PVS,TRAMO,ETIQUETA1,SALDO1,SALDO2,SALDO3,ETIQUETA6",
     "Campos que se actualizan en el DAT cuando la cuenta ya existe (paso.prg + asig_bases). ETIQUETA6 (19/11): la elegibilidad a REE cambia con cada base"),
]

CP_ESTADO = [("01000", "19999", "CDMX"), ("20000", "20999", "AGS"), ("21000", "22999", "BC"), ("23000", "23999", "BCS"),
             ("24000", "24999", "CAM"), ("25000", "27999", "COAH"), ("28000", "28999", "COL"), ("29000", "30999", "CHIS"),
             ("31000", "33999", "CHIH"), ("34000", "35999", "DGO"), ("36000", "38999", "GTO"), ("39000", "41999", "GRO"),
             ("42000", "43999", "HGO"), ("44000", "49999", "JAL"), ("50000", "57999", "MEX"), ("58000", "61999", "MICH"),
             ("62000", "62999", "MOR"), ("63000", "63999", "NAY"), ("64000", "67999", "NL"), ("68000", "71999", "OAX"),
             ("72000", "75999", "PUE"), ("76000", "76999", "QRO"), ("77000", "77999", "QROO"), ("78000", "79999", "SLP"),
             ("80000", "82999", "SIN"), ("83000", "85999", "SON"), ("86000", "86999", "TAB"), ("87000", "89999", "TAMP"),
             ("90000", "90999", "TLAX"), ("91000", "96999", "VER"), ("97000", "97999", "YUC"), ("98000", "99999", "ZAC")]

# ---------------------------------------------------------------- SCBSDOS (asi486.prg)
# CAMPO -> (FORMATO, EXPRESION sobre d)
SCB_EXPR = {
    "DMACCTG": ("CONSTANTE", "'1'"),
    "CUENTA": ("TEXTO", "d.CUENTA2"),
    "U1ASIGDTE": ("FECHA_MMDDAAAA", "d.FE_REC"),
    "DMCURBAL": ("IMPORTE", "d.SDO_ACT"),
    "U1PAGMIN": ("IMPORTE", "d.PAG_MIN"),
    "DMAMTDLQ": ("IMPORTE", "d.SDO_VDO"),
    "DMNAME": ("TEXTO", "d.NOMBRE1"),
    "DMADDR1": ("TEXTO", "d.DIRECC1"),
    "DMADDR2": ("TEXTO", "UPPER(d.DIRECC2)"),
    "DMCITY": ("TEXTO", "UPPER(REPLACE(d.DIRECC4, '\\', ''))"),
    "DMZIP": ("TEXTO", "CASE WHEN LEN(d.DIRECC3) = 4 THEN '0' + d.DIRECC3 ELSE d.DIRECC3 END"),
    "DMPHONE": ("TEXTO", "d.ETIQUETA1"),     # eti486 ya no se usa: solo lo que llega en la base
    "DMBPHONE": ("TEXTO", "d.SEG"),
    "U1EXT2": ("TEXTO", "d.ETIQUETA6"),
    "DMCPHONE": ("TEXTO", "d.GARAN"),
    "DMSTATE": ("TEXTO", "cfg.fn_cp_estado(CASE WHEN LEN(d.DIRECC3) = 4 THEN '0' + d.DIRECC3 ELSE d.DIRECC3 END)"),
    "DMPTSCOR": ("TEXTO", "d.SUB_CTE"),
    "U1FEDEV": ("FECHA_MMDDAAAA", "d.FE_REG"),
    "U1PROGRAMA": ("TEXTO", "d.SEGMENTO"),
    "U1ESTRATG1": ("TEXTO", "d.TIPO"),
    "U1PRODUCTO": ("TEXTO", "d.NOMBRE2"),
    "U1FTECAR": ("CONSTANTE", "'BANCO BAJIO'"),
    "U1FOLIO": ("TEXTO", "LTRIM(d.FOLIO)"),
    "U1ESTRATG4": ("TEXTO", "d.RIESGO"),
    "DMSSNUM": ("TEXTO", "ISNULL(d.CTA_BANCO, d.CUENTA)"),
    "U1EMAIL": ("TEXTO", "d.DES_PROD"),
    "U1ACTASIG": ("IMPORTE_SIGNO", "d.SALDO1"),
    "U1VDOASIG": ("IMPORTE_SIGNO", "d.SALDO2"),
    "U1MINASIG": ("IMPORTE_SIGNO", "d.SALDO3"),
    "DMCOMPANY": ("TEXTO", "d.CLIENTE"),
    "U1ARCOD1": ("TEXTO", "d.PVS"),
    "U1ARCOD2": ("TEXTO", "d.ETIQUETA"),
    "U1ARCOD3": ("TEXTO", "d.REE"),
    "U1USO1": ("TEXTO", "CONVERT(VARCHAR(20), CAST(d.SALDO1 AS DECIMAL(13,2)))"),
    "U1USO2": ("TEXTO", "CONVERT(VARCHAR(20), CAST(d.SALDO2 AS DECIMAL(13,2)))"),
    "U1USO3": ("TEXTO", "CONVERT(VARCHAR(20), CAST(d.SALDO3 AS DECIMAL(13,2)))"),
    "U1USO4": ("TEXTO", "COALESCE(cfg.fn_etiqueta('{CLIENTE}', 'STATUS', d.CTA_BANCO), cfg.fn_etiqueta('{CLIENTE}', 'STATUS', d.CUENTA))"),
    "U1STATUS": ("TEXTO", "d.SUB_CTE"),
    "DMADL1": ("TEXTO", "LTRIM(d.FOLIO)"),
    "DMP1": ("TEXTO", "COALESCE(cfg.fn_etiqueta('{CLIENTE}', 'DM1', d.CTA_BANCO), cfg.fn_etiqueta('{CLIENTE}', 'DM1', d.CUENTA))"),
    "DMP2": ("TEXTO", "COALESCE(cfg.fn_etiqueta('{CLIENTE}', 'ETI', d.CTA_BANCO), cfg.fn_etiqueta('{CLIENTE}', 'ETI', d.CUENTA), d.ETIQUETA5)"),
    "U1ESTRATG2": ("TEXTO", "d.TRAMO"),
    "U1ESTRATG3": ("TEXTO", "d.ESTRA3"),
}

# ---------------------------------------------------------------- otros archivos planos
# (ARCHIVO, PROCESO, ORDEN, ORIGEN, ORDEN_LINEAS, SEPARADOR, NOMBRE, DESCRIPCION)
BAJA_RETIRO = ("dat.HISTORIA_FOLIO d WHERE d.CLIENTE = @cliente AND d.ID_CORRIDA_BAJA = @id_corrida AND d.ESTATUS = 'B' "
               "AND EXISTS (SELECT 1 FROM ops.DEVOLUCION v WHERE v.ID_CORRIDA = @id_corrida AND v.CUENTA = d.CUENTA)")
SALIDAS_ARCHIVO = [
    ("SCBSDOS", "ASIG", 10, None, "d.CUENTA2", None, "SCBSDOS.TXT", "Cuentas del DAT para CYBER (asi486.prg)"),
    ("SCBTEL", "ASIG", 20, "ops.TELEFONO d WHERE d.ID_CORRIDA = @id_corrida AND (d.NUEVO = 1 OR NOT EXISTS (SELECT 1 FROM ops.TELEFONO x WHERE x.ID_CORRIDA = d.ID_CORRIDA AND x.NUEVO IS NOT NULL))", "d.CUENTA2, d.TIPOTEL, d.AREA, d.TELEFONO", None,
     "SCBTEL.TXT", "Teléfonos (TELSAN) de ancho fijo"),
    ("TEL_SUBMST", "ASIG", 30, "ops.TELEFONO d WHERE d.ID_CORRIDA = @id_corrida", "d.CUENTA2, d.AREA, d.TELEFONO", "|",
     "sub_mst.TXT", "Teléfonos para cargar en RCVRY.JSP_TAB_TEL_REMESA_486 (act_phone.prg)"),
    ("GESCAR_NVA", "ASIG", 40, "dat.HISTORIA_FOLIO d WHERE d.CLIENTE = @cliente AND d.ID_CORRIDA_ALTA = @id_corrida AND d.SUB_CTE = 'NVA'",
     "d.CUENTA2", None, "SCBACTH_486NU.TXT", "Gescar de cuentas nuevas (ges_nuevas_rea.prg, REQ 2021-062065)"),
    ("GESCAR_REA", "ASIG", 50, "dat.HISTORIA_FOLIO d WHERE d.CLIENTE = @cliente AND d.ID_CORRIDA_ALTA = @id_corrida AND d.SUB_CTE = 'REA'",
     "d.CUENTA2", None, "SCBACTH_486REA.TXT", "Gescar de cuentas reasignadas (ges_nuevas_rea.prg)"),
    ("MAIL_SUBMAIL", "ASIG", 35, "ops.CORREO d WHERE d.ID_CORRIDA = @id_corrida", "d.CUENTA2, d.CORREO", "|",
     "sub_mail.TXT", "Correos para cargar en RCVRY.JSP_TAB_MAIL_REMESA_486 (email.PRG -> act_mail.prg)"),
    ("GESCAR_SINTEL", "ASIG", 60,
     "dat.HISTORIA_FOLIO d WHERE d.CLIENTE = @cliente AND d.ID_CORRIDA_ALTA = @id_corrida "
     "AND NOT EXISTS (SELECT 1 FROM ops.TELEFONO t WHERE t.ID_CORRIDA = @id_corrida AND t.CUENTA2 = d.CUENTA2)",
     "d.CUENTA2", None, "SCBACTH_SINTEL.TXT",
     "Gescar de nuevas y reasignadas sin teléfono (ges486.prg); 19/11: de nuestros teléfonos, se escribe al subir los saldos"),
    ("SCBSDOS_ACT", "ACT", 10, None, "d.CUENTA2", None, "SCBSDOS.TXT", "Apagado (30/10): la actualización sube PVS y REE con el script ACT_PVS_REE", 0),
    ("SCBSDOS_ETI", "ETI", 10, None, "d.CUENTA2", None, "SCBSDOS.TXT", "SCBSDOS de etiquetado del DAT (eti486.prg) o fuera de proceso"),
    ("BLANQUEO_LISTA", "BLANQUEO", 10, "ops.STATUS_CYBER d WHERE d.ID_CORRIDA = @id_corrida AND d.BLANQUEA = 1", "d.CUENTA", ",",
     "BLANQUEA_486_{AAAAMMDD}.csv", "Cuentas a las que se blanquea el status (status.prg)"),
    ("SCBPAG", "ACT", 20, "dat.PAGO_ARRIBADO d WHERE d.CLIENTE = @cliente AND d.ID_CORRIDA = @id_corrida AND d.ORIGEN = 'CORRIDA'",
     "d.FE_PAG, d.ID", None, "SCBPAG.TXT", "Arribo de pagos (pagos.prg)"),
    ("DEVOL_CYBER", "RETIRO", 10, BAJA_RETIRO, "d.CUENTA2", None, "MX_G1MCT_DVBJIG_{AAAAMMDD}_{HHMMSS}",
     "Devolución para CYBER: una CUENTA2 por línea (prog15.prg, \\\\192.168.50.1\\Cyber_00\\dev)"),
    ("GESCAR_RETIRO", "RETIRO", 20, BAJA_RETIRO, "d.CUENTA2", None, "SCBACTH_486.TXT", "Gescar de retiro (ges_retiro.prg)"),
    ("RETIROS", "RETIRO", 30, BAJA_RETIRO, "d.FOLIO", ",", "RETIROS_486_{AAAAMMDD}.csv", "Folios retirados para operación"),
]
# Copia del DAT para MIS (antes DBF en Q:\\MIS\\SERTEC98\\CLIENTES\\486\\DAT y B:\\asignaciones\\dats\\dat486)
_MIS_ORIGEN = "ops.v_DAT_486_MIS d WHERE d.CLIENTE = @cliente"
DAT_MIS_ARCHIVOS = [
    (f"DAT_MIS_{p}", p if p != "RET" else "RETIRO", 90, _MIS_ORIGEN, "d.CUENTA", ",", "DAT486_{AAAAMMDD}.csv",
     "DAT del 486 en CSV para MIS (resdat.PRG / prog15.prg)", 1, 1, 1)
    for p in ("ASIG", "ACT", "RET", "ETI")
]
GESCAR = lambda comentario: [  # SCBACTH: 119 posiciones
    ("IDENTIFICA", 3, "CONSTANTE", "'200'"), ("GRUPO", 1, "CONSTANTE", "'1'"), ("CUENTA", 25, "TEXTO", "d.CUENTA2"),
    ("FECHA1", 8, "FECHA_MMDDAAAA", "@fecha"), ("BLANCO", 1, "CONSTANTE", "''"), ("HORA", 8, "TEXTO", "@hora"),
    ("SECU", 3, "CONSTANTE", "'000'"), ("ACCION", 2, "CONSTANTE", "'RS'"), ("RESULTADO", 2, "CONSTANTE", "'R1'"),
    ("CARTA", 2, "CONSTANTE", "''"), ("ORIGEN", 8, "CONSTANTE", "'aaxrh'"), ("COMENTARIO", 56, "CONSTANTE", f"'{comentario}'"),
]
FECHA_HORA = "CONCAT(cfg.fn_fecha_mmddaaaa(@fecha), ' ', @hora)"
CAMPOS_SALIDA = {
    "SCBTEL": [  # 137 posiciones (TELSAN copiado SDF)
        ("CAMPO", 3, "CONSTANTE", "'503'"), ("GRUPO", 1, "CONSTANTE", "'1'"), ("CUENTA", 25, "TEXTO", "d.CUENTA2"),
        ("NOCLIENTE", 25, "CONSTANTE", "''"), ("TIPOTEL", 1, "TEXTO", "d.TIPOTEL"), ("AREA", 5, "TEXTO", "d.AREA"),
        ("TELEFONO", 13, "TEXTO", "d.TELEFONO"), ("EXT", 8, "CONSTANTE", "''"), ("FECHA_G", 17, "TEXTO", FECHA_HORA),
        ("GESTOR", 8, "CONSTANTE", "'HOSP'"), ("ESTATUS", 1, "CONSTANTE", "'A'"), ("FECHA_A", 17, "TEXTO", FECHA_HORA),
        ("GESTOR2", 8, "CONSTANTE", "'HOSP'"), ("OTROS", 5, "CONSTANTE", "'00000'"),
    ],
    "TEL_SUBMST": [("CUENTA", 0, "TEXTO", "d.CUENTA2"), ("AREA", 0, "TEXTO", "d.AREA"), ("TELEFONO", 0, "TEXTO", "d.TELEFONO"),
                   ("TIPOTEL", 0, "TEXTO", "d.TIPOTEL")],
    "GESCAR_NVA": GESCAR("CUENTA NUEVA ASIGNADA."),
    "GESCAR_REA": GESCAR("CUENTA REASIGNADA."),
    "GESCAR_RETIRO": GESCAR("RETIRO DE CUENTA."),
    "GESCAR_SINTEL": [c if c[0] != "ORIGEN" else ("ORIGEN", 8, "CONSTANTE", "'zzasg'") for c in GESCAR("CUENTA SIN NUMERO TELEFONICO")],
    "MAIL_SUBMAIL": [("CUENTA", 0, "TEXTO", "d.CUENTA2"), ("CORREO", 0, "TEXTO", "d.CORREO")],
    "BLANQUEO_LISTA": [("FOLIO", 0, "TEXTO", "d.FOLIO"), ("CUENTA", 0, "TEXTO", "d.CUENTA"), ("STATUS", 0, "TEXTO", "d.STATUS"),
                       ("ACCION", 0, "TEXTO", "d.ACCION")],
    "SCBPAG": [  # 104 posiciones
        ("IDE", 3, "CONSTANTE", "'500'"), ("GRUPO", 1, "CONSTANTE", "'1'"), ("CUENTA", 25, "TEXTO", "d.CUENTA"),
        ("FE_PAG", 8, "FECHA_MMDDAAAA", "d.FE_PAG"), ("MONT", 15, "IMPORTE", "d.IMPORTE"), ("SEGMENTO", 6, "CONSTANTE", "'pbank'"),
        ("AGEN", 8, "CONSTANTE", "'SERTEC'"), ("FE_REG", 8, "FECHA_MMDDAAAA", "d.FE_REG"), ("TRAN", 15, "CONSTANTE", "'PAGO'"),
        ("MOREAL", 15, "IMPORTE", "d.IMPORTE"),
    ],
    "DEVOL_CYBER": [("CUENTA2", 28, "TEXTO", "d.CUENTA2")],
    "RETIROS": [("FOLIO", 0, "TEXTO", "d.FOLIO"), ("CUENTA2", 0, "TEXTO", "d.CUENTA2"), ("MOTIVO", 0, "TEXTO", "d.MOTIVO_BAJA")],
}
ANCHOS_ESPERADOS = {"GESCAR_SINTEL": 119, "SCBTEL": 137, "GESCAR_NVA": 119, "GESCAR_REA": 119, "GESCAR_RETIRO": 119, "SCBPAG": 104, "DEVOL_CYBER": 28}

# ---------------------------------------------------------------- correo
# Diseño de los correos (26/11): formato HTML que compartió el equipo (Documento1.txt de Banbaj_banc), con el buzón del 486
# y la paleta de BanBajío: morado #a54686 y rojo #ed1c24 del logotipo; grises neutros del formato de ejemplo.
# Todo con estilos en línea y tablas (Outlook no respeta CSS externo). El cuerpo de las plantillas lo arma el código:
# la semilla lo actualiza en cada instalación (el asunto, la lista y la importancia los puede cambiar el equipo).
COLOR = {"morado": "#a54686", "morado_osc": "#7d3466", "rojo": "#ed1c24", "fondo": "#f0f2f5", "texto": "#475569",
         "texto_fuerte": "#1e293b", "tenue": "#64748b", "borde": "#e2e8f0", "tarjeta": "#f8fafc", "pie": "#f1f5f9"}
FUENTE = "Segoe UI, Arial, sans-serif"   # sin comillas: va dentro de style='…'
FIRMA = (
    f"<table border='0' cellpadding='0' cellspacing='0' width='100%' style='margin-top:28px;border-top:1px solid {COLOR['pie']};'>"
    f"<tr><td style='padding-top:24px;'><table border='0' cellpadding='0' cellspacing='0'><tr>"
    f"<td style='border-left:3px solid {COLOR['rojo']};padding-left:18px;font-family:{FUENTE};'>"
    f"<div style='color:{COLOR['texto_fuerte']};font-size:17px;font-weight:700;'>Especialista Asignaciones</div>"
    f"<div style='color:{COLOR['morado']};font-size:12px;font-weight:700;text-transform:uppercase;letter-spacing:1px;margin-top:2px;'>TI SERTEC | CDMX</div>"
    f"<div style='font-size:13px;color:{COLOR['tenue']};margin-top:12px;line-height:1.5;'>"
    f"<strong>Tel:</strong> (0155) 7099 0104 | <strong>Ext:</strong> 1416<br>"
    f"<strong>Email:</strong> <a href='mailto:asig.486.cdmx@sertec.com.mx' style='color:{COLOR['morado']};text-decoration:none;'>asig.486.cdmx@sertec.com.mx</a><br>"
    f"<a href='http://www.sertec.com.mx' style='color:{COLOR['morado_osc']};text-decoration:none;font-weight:700;font-size:11px;'>WWW.SERTEC.COM.MX</a>"
    f"</div></td></tr></table></td></tr></table>")
AVISO = (
    f"<div style='color:#94a3b8;font-size:10px;line-height:1.5;text-align:justify;font-family:{FUENTE};'>"
    f"<p style='margin:0 0 10px 0;'><strong>CONFIDENCIALIDAD:</strong> Este mensaje es exclusivamente para el destinatario. "
    f"Si lo recibe por error, por favor elimínelo de inmediato. Consulte nuestro Aviso de Privacidad en www.sertec.com.mx.</p>"
    f"<p style='margin:0;'><strong>CONFIDENTIALITY:</strong> This email is intended solely for the addressee. If received in error, please destroy immediately.</p></div>")


def cuerpo_correo(titulo, texto, extra, importancia):
    """Cuerpo HTML de una plantilla con el diseño del equipo. Los marcadores {{…}} los reemplaza mail.sp_enviar."""
    alerta = importancia == "High"
    icono = "!" if alerta else "&#x2713;"
    franja = (f"<tr><td style='background-color:{COLOR['rojo']};height:6px;line-height:6px;font-size:0;'>&nbsp;</td></tr>" if alerta else "")
    tarjeta = (f"<table border='0' cellpadding='0' cellspacing='0' width='100%' style='background-color:{COLOR['tarjeta']};"
               f"border:1px solid {COLOR['borde']};border-radius:16px;margin:4px 0 8px 0;'>"
               f"<tr><td style='padding:22px 24px;color:#334155;font-size:14px;line-height:1.6;font-family:{FUENTE};'>{extra}</td></tr></table>"
               if extra else "")
    return (
        "<!DOCTYPE html PUBLIC \"-//W3C//DTD HTML 4.01 Transitional//EN\" \"http://www.w3.org/TR/html4/loose.dtd\">"
        "<html><head><meta http-equiv='Content-Type' content='text/html; charset=UTF-8'>"
        "<meta name='viewport' content='width=device-width, initial-scale=1.0'>"
        f"<title>{titulo}</title><style>p{{margin:0 0 10px 0;}} table.datos td, table.datos th{{font-family:{FUENTE};}}</style></head>"
        f"<body style='margin:0;padding:0;background-color:{COLOR['fondo']};font-family:{FUENTE};'>"
        f"<table border='0' cellpadding='0' cellspacing='0' width='100%' style='background-color:{COLOR['fondo']};'>"
        "<tr><td align='center' style='padding:32px 10px;'>"
        "<table border='0' cellpadding='0' cellspacing='0' width='600' style='width:600px;max-width:100%;background-color:#ffffff;"
        "border-radius:20px;overflow:hidden;box-shadow:0 10px 30px rgba(0,0,0,0.05);'>"
        f"{franja}"
        f"<tr><td align='center' style='background-color:{COLOR['morado']};padding:36px 40px;'>"
        "<table border='0' cellpadding='0' cellspacing='0'>"
        "<tr><td align='center' style='font-size:36px;color:#ffffff;line-height:1;'>"
        f"<div style='background-color:rgba(255,255,255,0.18);width:64px;height:64px;line-height:64px;border-radius:50%;text-align:center;font-weight:700;'>{icono}</div></td></tr>"
        f"<tr><td align='center' style='padding-top:18px;'><h1 style='margin:0;color:#ffffff;font-size:22px;font-weight:600;letter-spacing:0.5px;font-family:{FUENTE};'>{titulo}</h1>"
        f"<div style='color:#f6e6f1;font-size:13px;margin-top:6px;font-family:{FUENTE};'>Banco del Bajío · cliente 486</div></td></tr>"
        "</table></td></tr>"
        f"<tr><td style='padding:36px 44px;color:{COLOR['texto']};font-size:15px;line-height:1.6;font-family:{FUENTE};'>"
        "<p style='margin:0 0 15px 0;'>Buen día,</p>"
        f"<p style='margin:0 0 22px 0;color:{COLOR['texto_fuerte']};'><strong>{texto}</strong></p>"
        f"{tarjeta}"
        f"<p style='margin:14px 0 0 0;color:#94a3b8;font-size:12px;'>Banbaj 486 · {{{{FECHA}}}}</p>"
        "<p style='margin:20px 0 0 0;'>Saludos.</p>"
        "{{FRAG:FIRMA_ASIG_486}}"
        "</td></tr>"
        f"<tr><td style='background-color:{COLOR['pie']};padding:26px 44px;'>{{{{FRAG:AVISO_CONFIDENCIALIDAD}}}}</td></tr>"
        "</table></td></tr></table></body></html>")


BUZON = "asig.486.cdmx@sertec.com.mx"
INTERNOS_BCC = ["asignaciones.cdmx1@sertec.com.mx", "asignaciones3@sertec.com.mx", "asig.cdmx@sertec.com.mx"]
AEM = ["aem.control1@sertec.com.mx", "supervisor.aem.cdmx@sertec.com.mx", "supervisor.aem.cdmx2@sertec.com.mx",
       "supervisor.aem.cdmx3@sertec.com.mx", "supervisor.aem.cdmx4@sertec.com.mx", "aem.operativa1@sertec.com.mx",
       "aem.operativa2@sertec.com.mx", "aem.entregables1@sertec.com.mx"]
# Correos del 486 (decisión 30/10): inicio y fin de asignación, alerta de más de 100 nuevas, devolución única y validaciones
LISTAS = {
    "OPERACION_ASIG_486": ("Equipo de Operación: inicio y fin de asignación (MAIL.prg), saldo <= 0 en Consumo y pagos negativos (mail_pagos.prg)",
        [(e, "TO") for e in ["erika.ramos@sertec.com.mx", "administrativo.mc4@sertec.com.mx", "administrativo.mc5@sertec.com.mx", "supervisor.mc4@sertec.com.mx", "supervisorbackoffice.mc@sertec.com.mx"]] + [(e, "BCC") for e in INTERNOS_BCC]),
    "DEVOLUCION_OPERACION_486": ("Devolución (asignación, actualización o solicitud) a Operación, con el ZIP (saldos.prg: Retiros actualizacion)",
        [(e, "TO") for e in ["soluciones.486@sertec.com.mx", "supervisor.mc@sertec.com.mx", "supervisor.mc3@sertec.com.mx",
                             "supervisorbackoffice.mc@sertec.com.mx", "soluciones_banbajio@sertec.com.mx"]]
        + [(e, "BCC") for e in INTERNOS_BCC]),
    "DEVOLUCION_AEM_486": ("Devolución: copia oculta al equipo de AEM, sin el ZIP (devfianey.prg)",
        [(e, "BCC") for e in AEM]),
    "AEM_486": ("Alerta de asignación grande (aem_alerta.prg)",
        [(e, "TO") for e in ["supervisor.aem.cdmx4@sertec.com.mx", "aem.control1@sertec.com.mx", "aem.proyectos1@sertec.com.mx",
                             "aem.consultoria1@sertec.com.mx", "supervisor.aem.cdmx2@sertec.com.mx"]]
        + [("asig.cdmx@sertec.com.mx", "BCC")]),
    "ASIGNACIONES_486": ("Equipo de asignaciones: validaciones (layout y datos de la entrada, pagos negativos, números cortados por Excel), hallazgos y archivos listos", [(BUZON, "TO")] + [(e, "BCC") for e in INTERNOS_BCC]),
}
TEXTO_DEVOLUCION = "Archivo de devolución actualizado ({{ORIGEN}}), favor de verificar."
EXTRA_DEVOLUCION = "<p>Cuentas devueltas: {{CUENTAS}} · corrida {{CORRIDA}}</p>"
# (CODIGO, LISTA, ASUNTO, TEXTO, EXTRA, IMPORTANCIA); el título del encabezado está en TITULOS
PLANTILLAS = [
    # Asignación
    ("INICIO_ASIG_486", "OPERACION_ASIG_486", "Inicia asignación BANCO BAJIO del día {{FECHA_PROCESO}}",
     "Se inicia la asignación BANCO BAJIO.", "<p>La base llegó a las {{HORA_LLEGADA}}.</p>", "Normal"),
    ("CONFIRMACION_ASIG_486", "OPERACION_ASIG_486", "Asignación BANCO BAJIO del día {{FECHA_PROCESO}}",
     "Se realiza asignación BANCO BAJIO. Favor de revisar y confirmar misma vía.", "<p>{{RESUMEN}}</p>", "Normal"),
    ("ALERTA_NUEVAS_486", "AEM_486", "Asignaciones grande de 486 {{FECHA}}",
     "Se recibe una asignacion con mas de 100 registros nuevos, favor de construir al finalizar.",
     "<p>Nuevas: {{NUEVAS}} · umbral: {{UMBRAL}}</p>", "High"),
    # Devolución única: Operación con el ZIP; AEM en copia oculta sin el ZIP (Database Mail no puede quitar el adjunto a una parte de los destinatarios)
    ("DEVOLUCION_486", "DEVOLUCION_OPERACION_486", "Devolucion del cliente BANCO BAJIO {{FECHA}}",
     TEXTO_DEVOLUCION, EXTRA_DEVOLUCION + "<p>Se adjunta el archivo de retiros.</p>", "Normal"),
    ("DEVOLUCION_486_AEM", "DEVOLUCION_AEM_486", "Devolucion del cliente BANCO BAJIO {{FECHA}}",
     TEXTO_DEVOLUCION, EXTRA_DEVOLUCION, "Normal"),
    # Validaciones
    ("ALERTA_SDO_ACT_CONS_486", "OPERACION_ASIG_486", "EXISTEN CUENTAS NUEVAS DE CONSUMO CON SDO_ACT MENORES O IGUALES A CERO {{FECHA}}",
     "La base maestra de Consumo trae cuentas con saldo actual menor o igual a cero. Reportarlo al banco.",
     "<p>Registros: {{REGISTROS}}</p>", "High"),
    ("PAGOS_NEGATIVOS_486", "ASIGNACIONES_486", "Banco Bajío: llegaron pagos negativos {{FECHA}}",
     "En el archivo de pagos de Banco Bajío llegaron pagos negativos. No se arribaron a CYBER.",
     "<p>Pagos negativos: {{REGISTROS}}</p><pre>{{DETALLE}}</pre>", "High"),
    # Hallazgos (decisión 02/11): lo que el proceso automático no resolvió solo; solo al equipo de asignaciones (mail.sp_hallazgo)
    ("HALLAZGO_486", "ASIGNACIONES_486", "Banbaj 486: {{TIPO}} (corrida {{ID_CORRIDA}}) {{FECHA}}",
     "Banbaj encontró algo que necesita revisión del equipo de asignaciones.",
     "<p><b>{{TIPO}}</b></p><p>{{DETALLE}}</p>{{HTML_TABLA}}<p><b>Qué hacer:</b> {{ACCION}}</p>"
     "<p>Proceso {{PROCESO}} · corrida {{ID_CORRIDA}} del {{FECHA_PROCESO}}</p>", "High"),
    # Aviso de archivos listos para arribar (decisión 03/11): solo al equipo de asignaciones (ops.sp_aviso_archivos)
    ("ARCHIVOS_LISTOS_486", "ASIGNACIONES_486", "Banbaj 486: archivos listos para arribar ({{PROCESO}}, corrida {{ID_CORRIDA}}) {{FECHA}}",
     "Ya están los archivos planos para arribar a CYBER.",
     "<p>Carpeta: <b>{{CARPETA}}</b></p>{{HTML_TABLA}}<p><b>Qué sigue:</b> {{SIGUE}}</p>"
     "<p>Proceso {{PROCESO}} · corrida {{ID_CORRIDA}} del {{FECHA_PROCESO}}</p>", "Normal"),
    # Validación de la entrada (decisión 17/11): layout y datos; solo al equipo de asignaciones (ops.sp_validacion_entrada_avisar)
    ("VALIDACION_ENTRADA_486", "ASIGNACIONES_486", "Banbaj 486: {{PROCESO}} detenida por la validación de la entrada {{FECHA}}",
     "Banbaj detuvo la corrida antes de tocar el DAT: la información que llegó no pasó la validación.",
     "<p>{{RESUMEN}}</p>{{HTML_LAYOUT}}{{HTML_NUEVOS}}{{HTML_DATOS}}<p><b>Qué hacer:</b></p><ol>{{HTML_PASOS}}</ol>"
     "<p>{{PROCESO}} · corrida {{ID_CORRIDA}} del {{FECHA_PROCESO}}</p>", "High"),
    ("MAESTRA_NUMEROS_EXCEL_486", "ASIGNACIONES_486", "Asignación 486 detenida: base maestra con números cortados por Excel {{FECHA}}",
     "La base maestra se guardó como CSV con cuentas en notación científica (ej. 1.23457E+15). Formatea esas columnas como Texto en Excel, vuelve a guardar el CSV y corre de nuevo.",
     "<p>Registros: {{REGISTROS}}</p>", "High"),
]
TITULOS = {'INICIO_ASIG_486': 'Inicio de asignación',
           'CONFIRMACION_ASIG_486': 'Asignación realizada',
           'ALERTA_NUEVAS_486': 'Asignación grande',
           'DEVOLUCION_486': 'Devolución',
           'DEVOLUCION_486_AEM': 'Devolución',
           'ALERTA_SDO_ACT_CONS_486': 'Consumo con saldo menor o igual a cero',
           'PAGOS_NEGATIVOS_486': 'Pagos negativos',
           'HALLAZGO_486': '{{TIPO}}',
           'ARCHIVOS_LISTOS_486': 'Archivos listos para arribar',
           'VALIDACION_ENTRADA_486': 'Validación de la entrada',
           'MAESTRA_NUMEROS_EXCEL_486': 'Base maestra con números cortados'}
# Parámetros que escribe el proceso, no la semilla: cuándo se pasó a la llave por riesgo (no se revierte antes de esa corrida)
# y si ya se limpió la migración o las pruebas de entorno (sql/80 y sql/85 ya no vuelven a crear nada)
PARAMETROS_ESTADO = ["LLAVE_RIESGO_MIGRADA", "MIGRACION_LIMPIA", "PRUEBAS_LIMPIAS"]
# Retirados (decisión 30/10): se borran de bases que ya los tengan
PLANTILLAS_RETIRADAS = ["ASIG_EXPRESS_486", "PAGOS_NO_ACTUALIZADOS_486", "RETIROS_ACT_486", "AVISO_DEVOLUCION_486", "NOTIFICACION_RETIRO_486",
                        "CONFIRMACION_ACT_486", "ERROR_PROCESO_486", "DEVOLUCION_MASIVA_486",
                        "SALDOS_NO_ACTUALIZADOS_486", "SALDOS_IGUALES_DAT_486", "PAGOS_NO_SUBIERON_486"]
LISTAS_RETIRADAS = ["OPERACION_PAGOS_486", "ASIG_EXPRESS_486", "PAGOS_NO_ACTUALIZADOS_486", "RETIROS_ACT_486", "ACTUALIZACION_486", "RETIROS_OPERACION_486"]


# ---------------------------------------------------------------- escritura
def sql_semilla(scb, dat):
    L = ["USE [BNABAJ_486];   -- base del 486 (si la instalas con otro nombre, cámbialo aquí)", "GO",
         "/* =====================================================================",
         "   Banbaj · 90 Semilla del cliente 486 (generado por tools/generar_sql_486.py)",
         "   Re-ejecutable: borra y vuelve a cargar la configuración del 486.",
         "   Revisar antes de producción: RUTA de cfg.ARCHIVO, PERFIL_DBMAIL,",
         "   TOPE_DEVOLUCION_PCT y los campos marcados POR CONFIRMAR / PENDIENTE.",
         "   ===================================================================== */",
         "SET NOCOUNT ON;", "SET XACT_ABORT ON;", "BEGIN TRANSACTION;",
         "/* Lo que cambia la semilla no cuenta como cambio del equipo (triggers de cfg.ARCHIVO, cfg.ARCHIVO_COLUMNA, cfg.CATALOGO).",
         "   Si la semilla fallara a medias, cierra la ventana de SSMS antes de editar el layout a mano. */",
         "EXEC sp_set_session_context @key = N'SEMILLA', @value = 1;", ""]
    cli = q(CLIENTE)
    L += ["/* Layout que cambió el equipo de asignaciones (decisión 17/11): se guarda y se repone después de recargar */",
          "DROP TABLE IF EXISTS #arch_equipo; DROP TABLE IF EXISTS #col_equipo;",
          f"SELECT CODIGO, RUTA, PATRON_NOMBRE, ACTIVO, OBLIGATORIO, EDITADO_POR, FE_EDICION INTO #arch_equipo FROM cfg.ARCHIVO WHERE CLIENTE = {cli} AND EDITADO_POR IS NOT NULL;",
          "SELECT a.CODIGO, c.CAMPO_DESTINO, c.PATRON_ENCABEZADO, c.POSICION, c.ACTIVO, c.OBLIGATORIO, c.PERMITE_VACIO, c.EDITADO_POR, c.FE_EDICION",
          f"INTO #col_equipo FROM cfg.ARCHIVO_COLUMNA c JOIN cfg.ARCHIVO a ON a.ID_ARCHIVO = c.ID_ARCHIVO WHERE a.CLIENTE = {cli} AND c.EDITADO_POR IS NOT NULL;",
          f"DELETE c FROM cfg.ARCHIVO_COLUMNA c JOIN cfg.ARCHIVO a ON a.ID_ARCHIVO = c.ID_ARCHIVO WHERE a.CLIENTE = {cli};",
          f"DELETE FROM cfg.ARCHIVO WHERE CLIENTE = {cli};",
          f"DELETE FROM cfg.HOMOLOGACION WHERE CLIENTE = {cli};",
          f"DELETE FROM cfg.REGLA WHERE CLIENTE = {cli};",
          f"DELETE FROM cfg.SALIDA WHERE CLIENTE = {cli};",
          f"DELETE FROM cfg.SALIDA_ARCHIVO WHERE CLIENTE = {cli};",
          # Marcas de estado que deja el propio proceso (no son configuración): la semilla no las borra (26/11)
          f"DELETE FROM cfg.PARAMETRO WHERE CLIENTE = {cli} AND CLAVE NOT IN (" + ", ".join(q(x) for x in PARAMETROS_ESTADO) + ");",
          "DELETE FROM cfg.CP_ESTADO;",
          "-- Correos retirados (decisiones 29 y 30/10)",
          "DELETE FROM mail.PLANTILLA WHERE CODIGO IN (" + ", ".join(q(x) for x in PLANTILLAS_RETIRADAS) + ");",
          "DELETE FROM mail.DESTINATARIO WHERE LISTA IN (" + ", ".join(q(x) for x in LISTAS_RETIRADAS) + ");",
          "DELETE FROM mail.LISTA WHERE CODIGO IN (" + ", ".join(q(x) for x in LISTAS_RETIRADAS) + ");",
          "DELETE FROM mail.DESTINATARIO WHERE LISTA = N'DEVOLUCION_AEM_486';   -- antes TO/CC, ahora todo en copia oculta",
          f"UPDATE mail.PLANTILLA SET PERFIL_DBMAIL = {q(PERFIL_DBMAIL)} WHERE CODIGO LIKE N'%486%';", ""]

    L.append("/* Parámetros */")
    for k, v, d in PARAMETROS:
        L.append(f"INSERT INTO cfg.PARAMETRO (CLIENTE, CLAVE, VALOR, DESCRIPCION) VALUES ({cli}, {q(k)}, {q(v)}, {q(d)});")
    L.append("")

    L.append("/* CP -> estado */")
    for a, b, e in CP_ESTADO:
        L.append(f"INSERT INTO cfg.CP_ESTADO (CP_INI, CP_FIN, ESTADO) VALUES ('{a}', '{b}', '{e}');")
    L.append("")

    L.append("/* Archivos de entrada y sus columnas */")
    L.append("DECLARE @id INT;")
    for cod, proc, seg, pat, ncol, tabla, llave, obl, orden, act, com in ARCHIVOS:
        L.append(f"INSERT INTO cfg.ARCHIVO (CLIENTE, PROCESO, CODIGO, SEGMENTO2, RUTA, PATRON_NOMBRE, NUM_COLUMNAS, TABLA_DESTINO, GUARDAR_COMPLETO, "
                 f"LLAVE_DAT, OBLIGATORIO, ORDEN, ACTIVO, COMENTARIO) VALUES ({cli}, {q(proc)}, {q(cod)}, {q(seg)}, {q(RUTA_ENTRADA)}, "
                 f"{q(pat)}, {ncol}, {q(tabla)}, {1 if proc == 'ASIG' else 0}, {q(llave)}, {obl}, {orden}, {act}, {q(com)});")
        L.append("SET @id = SCOPE_IDENTITY();")
        for campo, enc, (tipo, trf), obl_c, con_fecha, comc in COLUMNAS[cod]:
            pat_c = patron(enc, con_fecha) if enc else None
            L.append(f"INSERT INTO cfg.ARCHIVO_COLUMNA (ID_ARCHIVO, CAMPO_DESTINO, PATRON_ENCABEZADO, TIPO_SQL, TRANSFORMACION, OBLIGATORIO, PERMITE_VACIO, COMENTARIO) "
                     f"VALUES (@id, {q(campo)}, {q(pat_c)}, {q(tipo)}, {q(trf)}, {1 if obl_c else 0}, {1 if obl_c == 2 else 0}, {q(comc)});")
        L.append("")
    L += ["/* Se repone lo que había cambiado el equipo */",
          "UPDATE a SET RUTA = e.RUTA, PATRON_NOMBRE = e.PATRON_NOMBRE, ACTIVO = e.ACTIVO, OBLIGATORIO = e.OBLIGATORIO,",
          "       EDITADO_POR = e.EDITADO_POR, FE_EDICION = e.FE_EDICION",
          f"FROM cfg.ARCHIVO a JOIN #arch_equipo e ON e.CODIGO = a.CODIGO WHERE a.CLIENTE = {cli};",
          "PRINT CONCAT('Archivos con ajustes del equipo conservados: ', @@ROWCOUNT);",
          "UPDATE c SET PATRON_ENCABEZADO = e.PATRON_ENCABEZADO, POSICION = e.POSICION, ACTIVO = e.ACTIVO, OBLIGATORIO = e.OBLIGATORIO,",
          "       PERMITE_VACIO = e.PERMITE_VACIO, EDITADO_POR = e.EDITADO_POR, FE_EDICION = e.FE_EDICION",
          "FROM cfg.ARCHIVO_COLUMNA c JOIN cfg.ARCHIVO a ON a.ID_ARCHIVO = c.ID_ARCHIVO",
          f"JOIN #col_equipo e ON e.CODIGO = a.CODIGO AND e.CAMPO_DESTINO = c.CAMPO_DESTINO WHERE a.CLIENTE = {cli};",
          "PRINT CONCAT('Campos con ajustes del equipo conservados: ', @@ROWCOUNT);", ""]

    L.append("/* Catálogos estáticos de etiquetado (decisión 17/11): solo se agrega lo que falta */")
    L.append(f"DELETE FROM cfg.CATALOGO_DEF WHERE CLIENTE = {cli};")
    for cat, desc, origen, destino, valores in CATALOGOS:
        L.append(f"INSERT INTO cfg.CATALOGO_DEF (CLIENTE, CATALOGO, DESCRIPCION, ORIGEN, DESTINO) VALUES ({cli}, {q(cat)}, {q(desc)}, {q(origen)}, {q(destino)});")
        for vo, vd, orden_c in valores:
            L.append(f"IF NOT EXISTS (SELECT 1 FROM cfg.CATALOGO WHERE CLIENTE = {cli} AND CATALOGO = {q(cat)} AND VALOR_ORIGEN = {q(vo)}) "
                     f"INSERT INTO cfg.CATALOGO (CLIENTE, CATALOGO, VALOR_ORIGEN, VALOR_DESTINO, ORDEN, ALTA_POR) VALUES ({cli}, {q(cat)}, {q(vo)}, {q(vd)}, {orden_c}, 'SEMILLA');")
    L.append("")
    L.append("/* Validación de datos de la entrada (decisión 17/11): solo se agregan las reglas que faltan */")
    for cod, campo, tipo_v, valor, pct, desc in VALIDACIONES:
        L.append(f"IF NOT EXISTS (SELECT 1 FROM cfg.VALIDACION_DATO WHERE CLIENTE = {cli} AND CODIGO = {q(cod)} AND CAMPO = {q(campo)} AND TIPO = {q(tipo_v)}) "
                 f"INSERT INTO cfg.VALIDACION_DATO (CLIENTE, CODIGO, CAMPO, TIPO, VALOR, PCT_MAX, DESCRIPCION) VALUES ({cli}, {q(cod)}, {q(campo)}, {q(tipo_v)}, {q(valor)}, {pct}, {q(desc)});")
    L.append("/* 20/11: PRIME+4DIG ya no es llave (la llave es el riesgo); se apaga su regla de repetidos */")
    L.append(f"UPDATE cfg.VALIDACION_DATO SET ACTIVO = 0 WHERE CLIENTE = {cli} AND CODIGO = 'MAESTRA_TDC' AND CAMPO = 'PRIME4DIG' AND TIPO = 'LLAVE_UNICA' AND ACTIVO = 1;")
    L.append("")

    L.append("/* Ladas válidas (19/11): copia inicial de PHNVAL de CYBER (tools/datos/PHNVAL.csv). Solo si cfg.PHNVAL está vacía:")
    L.append("   después la mantiene ops.sp_phnval_actualizar (job mensual) */")
    import csv as _csv
    with open(RAIZ / "tools" / "datos" / "PHNVAL.csv", encoding="cp1252", newline="") as f:
        filas = sorted({(r["VTARECOD"].strip(), int(r["VTLENGTH"]), r["VTCOMUNA"].strip()) for r in _csv.DictReader(f)
                        if r["VTARECOD"].strip().isdigit() and r["VTLENGTH"].strip().isdigit()}, key=lambda x: (x[0], x[1]))
    vistos, unicas = set(), []
    for a, n, c in filas:
        if (a, n) not in vistos:
            vistos.add((a, n)); unicas.append((a, n, c))
    L.append("IF NOT EXISTS (SELECT 1 FROM cfg.PHNVAL)")
    L.append("BEGIN")
    for i in range(0, len(unicas), 200):
        L.append("    INSERT INTO cfg.PHNVAL (VTARECOD, VTLENGTH, VTCOMUNA) VALUES")
        L.append(",\n".join(f"        ({q(a)}, {n}, {q(c)})" for a, n, c in unicas[i:i + 200]) + ";")
    L.append("    INSERT INTO cfg.PHNVAL_CARGA (FE_FIN, ESTATUS, FILAS, ALTAS, BAJAS, MENSAJE)")
    L.append(f"    VALUES (SYSDATETIME(), 'OK', {len(unicas)}, {len(unicas)}, 0, N'Copia inicial de la semilla (PHNVAL del 19/11/2026)');")
    L.append("END;")
    L.append("")

    L.append("/* Campos de CYBER para las vistas de usuarios (19/11): solo se agrega lo que falta */")
    for campo, expr, desc in CYBER_CAMPOS:
        L.append(f"IF NOT EXISTS (SELECT 1 FROM cfg.CYBER_CAMPO WHERE CAMPO = {q(campo)}) INSERT INTO cfg.CYBER_CAMPO (CAMPO, EXPRESION, DESCRIPCION) VALUES ({q(campo)}, {q(expr)}, {q(desc)});")
    L.append("")
    L.append("/* Vistas de usuarios (18/11): solo se agrega lo que falta */")
    for vista, ret, act, desc, cols in VISTAS:
        L.append(f"IF NOT EXISTS (SELECT 1 FROM cfg.VISTA_USUARIO WHERE CLIENTE = {cli} AND VISTA = {q(vista)}) "
                 f"INSERT INTO cfg.VISTA_USUARIO (CLIENTE, VISTA, VER_RETIROS, ACTIVO, DESCRIPCION, USUARIO) VALUES ({cli}, {q(vista)}, {ret}, {act}, {q(desc)}, 'SEMILLA');")
        for i, (enc, origen, campo) in enumerate(cols, 1):
            L.append(f"IF NOT EXISTS (SELECT 1 FROM cfg.VISTA_COLUMNA WHERE CLIENTE = {cli} AND VISTA = {q(vista)} AND ENCABEZADO = {q(enc)}) "
                     f"INSERT INTO cfg.VISTA_COLUMNA (CLIENTE, VISTA, ORDEN, ENCABEZADO, ORIGEN, CAMPO, USUARIO) VALUES ({cli}, {q(vista)}, {i * 10}, {q(enc)}, {q(origen)}, {q(campo)}, 'SEMILLA');")
    L.append("")

    L.append("/* Homologación */")
    orden = {}
    for tabla, campo, valor, cond, desc, req in HOMOLOGACION:
        proc = "ACT" if tabla == "dat.DAT_486" else "ASIG"
        orden[tabla] = orden.get(tabla, 0) + 10
        L.append(f"INSERT INTO cfg.HOMOLOGACION (CLIENTE, PROCESO, TABLA, ORDEN, CAMPO_DESTINO, VALOR, CONDICION, DESCRIPCION, REQ) "
                 f"VALUES ({cli}, '{proc}', {q(tabla)}, {orden[tabla]}, {q(campo)}, {q(valor)}, {q(cond)}, {q(desc)}, {q(req)});")
    L.append("")

    L.append("/* Reglas */")
    for proc, paso, cod, tabla, cond, ev, acc, msg, plant, orden_r, req in REGLAS:
        L.append(f"INSERT INTO cfg.REGLA (CLIENTE, PROCESO, PASO, CODIGO, TABLA, CONDICION, EVALUA, ACCION, MENSAJE, PLANTILLA_CORREO, ORDEN, REQ) "
                 f"VALUES ({cli}, {q(proc)}, {q(paso)}, {q(cod)}, {q(tabla)}, {q(cond)}, {q(ev)}, {q(acc)}, {q(msg)}, {q(plant)}, {orden_r}, {q(req)});")
    L.append("")

    L.append("/* Salida SCBSDOS (asi486.prg) */")
    for i, (campo, ancho_c) in enumerate(scb, 1):
        fmt, expr = SCB_EXPR.get(campo, ("CONSTANTE", "''"))
        L.append(f"INSERT INTO cfg.SALIDA (CLIENTE, ARCHIVO, ORDEN, CAMPO, ANCHO, FORMATO, EXPRESION) "
                 f"VALUES ({cli}, 'SCBSDOS', {i}, {q(campo)}, {ancho_c}, {q(fmt)}, {q(expr)});")
    L.append("")

    L.append("/* SCBSDOS también sale en la actualización (mismos campos) */")
    for copia in ("SCBSDOS_ACT", "SCBSDOS_ETI"):
        L.append(f"INSERT INTO cfg.SALIDA (CLIENTE, ARCHIVO, ORDEN, CAMPO, ANCHO, FORMATO, EXPRESION) "
                 f"SELECT CLIENTE, '{copia}', ORDEN, CAMPO, ANCHO, FORMATO, EXPRESION FROM cfg.SALIDA WHERE CLIENTE = {cli} AND ARCHIVO = 'SCBSDOS';")
    L.append("")
    L.append("/* Otros archivos planos (arribo manual a CYBER y operación) */")
    for arch, campos in CAMPOS_SALIDA.items():
        for i, (campo, ancho_c, fmt, expr) in enumerate(campos, 1):
            L.append(f"INSERT INTO cfg.SALIDA (CLIENTE, ARCHIVO, ORDEN, CAMPO, ANCHO, FORMATO, EXPRESION) "
                     f"VALUES ({cli}, {q(arch)}, {i}, {q(campo)}, {ancho_c}, {q(fmt)}, {q(expr)});")
    L.append("")
    L.append("/* Catálogo de archivos planos */")
    for arch, proc, orden_a, origen, orden_l, sep, nombre, desc, *resto in SALIDAS_ARCHIVO + DAT_MIS_ARCHIVOS:
        activo, comillas, encabezado = (list(resto) + [1, 0, 0][len(resto):])[:3]
        L.append(f"INSERT INTO cfg.SALIDA_ARCHIVO (CLIENTE, ARCHIVO, PROCESO, ORDEN, ORIGEN, ORDEN_LINEAS, SEPARADOR, NOMBRE, DESCRIPCION, ACTIVO, COMILLAS, ENCABEZADO) "
                 f"VALUES ({cli}, {q(arch)}, {q(proc)}, {orden_a}, {q(origen)}, {q(orden_l)}, {q(sep)}, {q(nombre)}, {q(desc)}, {activo}, {comillas}, {encabezado});")
    L.append("/* Copia del DAT para MIS en CSV (resdat.PRG): CUENTA = 486-folio, CUENTA3 = crédito */")
    for i, (campo, t, n) in enumerate(dat, 1):
        if t == "N":
            fmt, expr = "IMPORTE", f"d.{campo}"
        elif t == "D":
            fmt, expr = "TEXTO", f"CONVERT(VARCHAR(10), d.{campo}, 103)"
        else:
            fmt, expr = "TEXTO", f"d.{campo}"
        for arch, *_ in DAT_MIS_ARCHIVOS:
            L.append(f"INSERT INTO cfg.SALIDA (CLIENTE, ARCHIVO, ORDEN, CAMPO, ANCHO, FORMATO, EXPRESION) "
                     f"VALUES ({cli}, {q(arch)}, {i}, {q(campo)}, 0, {q(fmt)}, {q(expr)});")
    L.append("")
    L.append("/* Teléfonos de dueños del banco: nunca se arriban (telbnx.prg, REQ 2022-004456) */")
    for t in ("4777140350", "4777140308", "4777147689"):
        L.append(f"IF NOT EXISTS (SELECT 1 FROM cfg.EXCLUSION WHERE CLIENTE = {cli} AND TIPO = 'TELEFONO' AND VALOR = '{t}' AND VALOR2 IS NULL) "
                 f"INSERT INTO cfg.EXCLUSION (CLIENTE, TIPO, VALOR, MOTIVO, REQ) VALUES ({cli}, 'TELEFONO', '{t}', 'Teléfono de dueños del banco', 'REQ 2022-004456');")
    L.append("")

    L.append("/* Correo: fragmentos, listas, destinatarios y plantillas */")
    # Firma y aviso: diseño del 26/11; se actualizan también en servidores que ya los tenían
    for cod, html in (("FIRMA_ASIG_486", FIRMA), ("AVISO_CONFIDENCIALIDAD", AVISO)):
        L.append(f"IF NOT EXISTS (SELECT 1 FROM mail.FRAGMENTO WHERE CODIGO = {q(cod)}) "
                 f"BEGIN INSERT INTO mail.FRAGMENTO (CODIGO, HTML) VALUES ({q(cod)}, {q(html)}); END "
                 f"ELSE BEGIN UPDATE mail.FRAGMENTO SET HTML = {q(html)} WHERE CODIGO = {q(cod)}; END;")
    for lista, (desc, dests) in LISTAS.items():
        L.append(f"IF NOT EXISTS (SELECT 1 FROM mail.LISTA WHERE CODIGO = {q(lista)}) "
                 f"INSERT INTO mail.LISTA (CODIGO, CLIENTE, DESCRIPCION) VALUES ({q(lista)}, {cli}, {q(desc)});")
        for email, tipo in dests:
            L.append(f"IF NOT EXISTS (SELECT 1 FROM mail.DESTINATARIO WHERE LISTA = {q(lista)} AND EMAIL = {q(email)} AND TIPO = '{tipo}') "
                     f"INSERT INTO mail.DESTINATARIO (LISTA, EMAIL, TIPO) VALUES ({q(lista)}, {q(email)}, '{tipo}');")
    # El cuerpo (diseño) lo arma el código: se actualiza en cada instalación; asunto, lista e importancia no se tocan si ya existe
    for cod, lista, asunto, texto, extra, imp in PLANTILLAS:
        cuerpo = cuerpo_correo(TITULOS[cod], texto, extra, imp)
        L.append(f"IF NOT EXISTS (SELECT 1 FROM mail.PLANTILLA WHERE CODIGO = {q(cod)}) "
                 f"BEGIN INSERT INTO mail.PLANTILLA (CODIGO, LISTA, PERFIL_DBMAIL, ASUNTO, CUERPO_HTML, IMPORTANCIA) "
                 f"VALUES ({q(cod)}, {q(lista)}, {q(PERFIL_DBMAIL)}, {q(asunto)}, {q(cuerpo)}, '{imp}'); END "
                 f"ELSE BEGIN UPDATE mail.PLANTILLA SET CUERPO_HTML = {q(cuerpo)} WHERE CODIGO = {q(cod)}; END;")
    L += ["", "EXEC sp_set_session_context @key = N'SEMILLA', @value = NULL;", "COMMIT TRANSACTION;", "GO", ""]
    return "\n".join(L)


def main():
    xlsx = Path(sys.argv[1]) if len(sys.argv) > 1 else RAIZ / "mapeos" / "mapeo_486.xlsx"
    dat, scb = leer_mapeo(xlsx)
    assert sum(a for _, a in scb) == 1559, "SCBSDOS debe medir 1559"
    faltan = set(SCB_EXPR) - {c for c, _ in scb}
    assert not faltan, faltan
    for arch, ancho in ANCHOS_ESPERADOS.items():
        assert sum(c[1] for c in CAMPOS_SALIDA[arch]) == ancho, f"{arch} debe medir {ancho}"
    assert {a[0] for a in SALIDAS_ARCHIVO} - {"SCBSDOS", "SCBSDOS_ACT", "SCBSDOS_ETI"} == set(CAMPOS_SALIDA), "salidas sin campos"
    campos = {cod: {c[0] for c in cols} for cod, cols in COLUMNAS.items()}
    cats = {c[0] for c in CATALOGOS}
    for cod, campo, tipo_v, valor, pct, desc in VALIDACIONES:
        assert cod in campos and (campo == "*" or campo in campos[cod]), f"validación sobre un campo que no existe: {cod}.{campo}"
        assert tipo_v != "CATALOGO" or valor in cats, f"validación con un catálogo que no existe: {valor}"
    cols_dat = {c[0] for c in dat}
    for vista, ret, act, desc, cols in VISTAS:
        for enc, origen, campo in cols:
            assert origen in ("DAT", "CYBER", "MAESTRA", "CONSTANTE"), f"vista {vista}: origen inválido {origen}"
            assert origen != "DAT" or campo in cols_dat, f"vista {vista}: el DAT no tiene {campo}"
    usados = set(re.findall(r"fn_catalogo\('\{CLIENTE\}', '(\w+)'", " ".join(h[2] + " " + (h[3] or "") for h in HOMOLOGACION)))
    assert usados <= cats, f"homologación con catálogos que no existen: {usados - cats}"
    (RAIZ / "sql" / "05_tabla_dat_486.sql").write_text(sql_dat(dat), encoding="utf-8")
    (RAIZ / "sql" / "90_semilla_486.sql").write_text(sql_semilla(scb, dat), encoding="utf-8")
    print("ok:", len(dat), "campos DAT,", len(scb), "campos SCBSDOS")


if __name__ == "__main__":
    main()
