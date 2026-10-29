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
RUTA_ENTRADA = "Q:\\CYBER\\C_486\\{AAAA}\\{MES}\\{DD}\\"   # carpeta del día (cfg.fn_ruta): Q:\CYBER\C_486\2026\octubre\28\
PERFIL_DBMAIL = "Asignaciones486"           # perfil de Database Mail


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
    ]
    vista = ", ".join("d.CUENTA2 AS CUENTA" if c == "CUENTA" else "d.CUENTA AS CUENTA3" if c == "CUENTA3" else f"d.{c}" for c, _, _ in dat)
    return f"""/* =====================================================================
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
"""


# ---------------------------------------------------------------- archivos de entrada
# (CODIGO, PROCESO, SEGMENTO2, PATRON_NOMBRE, NUM_COLUMNAS, TABLA, LLAVE_DAT, OBLIG, ORDEN, ACTIVO, COMENTARIO)
ARCHIVOS = [
    ("MAESTRA_TDC", "ASIG", "TDC", "BASE MAESTRA[_]TARJETA%.csv", 96, "stg.ENT_MAESTRA_TDC", "RIESGO", 0, 10, 1,
     "Base maestra TDC guardada como CSV. Devolución por RIESGO (asig_bases)."),
    ("MAESTRA_CONSUMO", "ASIG", "CONSUMO", "BASE MAESTRA[_]CONSUMO%.csv", 107, "stg.ENT_MAESTRA_CONSUMO", "DES_PROD", 0, 20, 1,
     "Base maestra Consumo guardada como CSV. Devolución por DES_PROD (asig_bases)."),
    ("MAESTRA_HIPO", "ASIG", "HIPOTECARIO", "BASE MAESTRA[_]HIPOTECARIO%.csv", 118, "stg.ENT_MAESTRA_HIPO", "DES_PROD", 0, 30, 1,
     "Sin archivo de ejemplo: columnas tomadas de la hoja RAW, confirmar NUM_COLUMNAS y encabezados."),
    ("SALDOS_TDC", "ACT", "TDC", "SERTEC[_]Saldos[_]tdc%", 8, "stg.ENT_SALDOS_TDC", "RIESGO", 0, 10, 1,
     "Cruce por ACC_NUM = DAT.RIESGO."),
    ("SALDOS_CONS", "ACT", "CONSUMO", "SERTEC[_]Saldos[_]Cons%", 12, "stg.ENT_SALDOS_CONS", "DES_PROD", 0, 20, 1,
     "Cruce por CYBER = DAT.DES_PROD. La primera columna viene sin nombre."),
    ("SALDOS_HIP", "ACT", "HIPOTECARIO", "SERTEC[_]Saldos[_]Hip%", 12, "stg.ENT_SALDOS_HIP", "CUENTA", 0, 30, 0,
     "PENDIENTE: no hay ejemplo del archivo; activar cuando se defina su mapeo (A-06)."),
    ("PAGOS", "ACT", None, "SERTEC[_]Pagos%", 6, "stg.ENT_PAGOS", "RIESGO", 0, 40, 1,
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
        ("PRIME4DIG", "PRIME+4DIG", C(30), 1, False, "Base para armar la CUENTA"),
        ("CUENTA", None, ("VARCHAR(20)", "{v}"), 0, False, "Derivado: últimos 4 dígitos de PRIME+4DIG + RFC (regla del mapeo, la aplicaba la macro)"),
        ("RIESGO", "ACC_NUM", C(35), 1, False, None),
        ("NOMBRE1", "NAME2", C(50), 0, False, None),
        ("ESTRA3", "Tipo de TDC", C(15), 0, False, None),
        ("GARAN", "GARANTIZADA", C(15), 0, False, "1 / 0 -> GARANTIZADA / vacío (homologación)"),
        ("PVS", "Dias Vencidos VEN4/CCAS 00/00/0000", PVS, 0, True, None),
        ("RFC", "RFC", C(25), 0, False, None),
        ("PAG_MIN", "Pago mínimo 00/00/0000", N, 0, True, None),
        ("SDO_VDO", "Saldo PRIME total asignado al 00/00/0000", N, 0, True, None),
        ("SDO_ACT", "Saldo actualizado VEN4/CCAS al 00/00/0000", N, 1, True, None),
        ("SALDO1", "MONTO A CUBRIR 1 PAGO LIQUIDACION", N, 0, False, None),
        ("SALDO2", "MONTO A CUBRIR PLAZOS PAGO <= 6 LIQUIDACION", N, 0, False, None),
        ("ENFOQUE", "ENFOQUE_LIQUIDACION_1_PAGO", C(60), 0, False, "POR CONFIRMAR: columna 'enfoque' que usa la regla de TRAMO 90+"),
        ("ETIQUETA", "COVID", C(15), 0, False, "POR CONFIRMAR: etiqueta covid"),
        ("REE", "Reestructura", C(15), 0, False, "POR CONFIRMAR"),
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
        ("CAPITAL", "CAPITAL AL 00/00/0000", N, 0, True, None),
        ("SDO_ACT", "ADEUDO TOTAL AL 00/00/0000", N, 1, True, None),
        ("SDO_VDO", "MONTO VENCIDO AL 00/00/0000", N, 0, True, None),
        ("SALDO1", "MONTO A 1 PAGO LIQUIDACION", N, 0, False, None),
        ("SALDO2", "MONTO A PAGO LIQUIDACION PLAZOS <= 6 MESES", N, 0, False, None),
        ("PVS", "DIAS MORA AL 00/00/0000", PVS, 0, True, None),
        ("SEGMENTO", "ESTATUS AL 00/00/0000", C(30), 0, True, None),
        ("TRAMO", "TRAMO AL 00/00/0000", C(20), 0, True, None),
        ("ETIQUETA", "ESTATUS COVID", C(15), 0, False, "POR CONFIRMAR: etiqueta covid"),
        ("REE", "STATUS REESTRUCTURA", C(15), 0, False, "POR CONFIRMAR"),
        ("CORREO1", "CORREO1", C(100), 0, False, None),
        ("CORREO2", "CORREO2", C(100), 0, False, None),
        ("ETIQUETA1", "COSECHAS", C(10), 0, False, None),
        ("RIESGO", None, ("VARCHAR(35)", "{v}"), 0, False, "Derivado: = CUENTA"),
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
MORA = [
    ("ETIQUETA1", "REPLACE(t.ETIQUETA1, '-', '')", "t.ETIQUETA1 LIKE '%-%'", "Quita '-' (asig_bases)", None),
    ("ETIQUETA1", "'MORA 1'", "t.ETIQUETA1 = 'COSECHA 1'", "COSECHA -> MORA", "REQ 2023-067064"),
    ("ETIQUETA1", "'MORA 2'", "t.ETIQUETA1 = 'COSECHA 2'", "COSECHA -> MORA", "REQ 2023-067064"),
    ("ETIQUETA1", "'MORA 3'", "t.ETIQUETA1 = 'COSECHA 3'", "COSECHA -> MORA", "REQ 2023-067064"),
]
AI = "COLLATE Latin1_General_CI_AI"
HOMOLOGACION = (
    [("stg.ENT_MAESTRA_TDC",) + x for x in [
        ("SEGMENTO2", "'TDC'", None, "Segmento", None),
        ("CUENTA", "LEFT(RIGHT(LTRIM(RTRIM(t.PRIME4DIG)), 4) + LTRIM(RTRIM(ISNULL(t.RFC, ''))), 20)", None,
         "Cuenta TDC = últimos 4 dígitos de PRIME+4DIG + RFC (regla del mapeo)", None),
        ("DES_PROD", "t.CUENTA", None, "DES_PROD = CUENTA (paso.prg)", None),
        ("GARAN", "'GARANTIZADA'", "t.GARAN = '1'", "Garantizada", "REQ 2021-024042"),
        ("GARAN", "''", "t.GARAN = '0'", "No garantizada", "REQ 2021-024042"),
    ] + MORA + [
        ("SDO_ACT", "t.SDO_VDO", "t.SDO_ACT <= 0", "Saldo actual <= 0 toma el saldo PRIME (asig_bases)", None),
        ("ESTATUS2", "'VIG'", "TRY_CONVERT(INT, t.TRAMO) BETWEEN 1 AND 29", "Tramo 1-29", None),
        ("ESTATUS2", "'VEN'", "TRY_CONVERT(INT, t.TRAMO) BETWEEN 30 AND 89", "Tramo 30-89", None),
        ("ESTATUS2", "'CAS'", "t.TRAMO = '90+' AND t.ENFOQUE LIKE '%LIQUIDACION%'", "90+ con enfoque liquidación", None),
        ("ESTATUS2", "'VEN'", "t.TRAMO = '90+' AND t.ENFOQUE LIKE '% %'",
         "90+ con enfoque de varias palabras. ORDEN LEGADO: se aplica después de CAS y puede sobrescribirlo", None),
        ("ESTATUS2", "'VEN'", "t.TRAMO = '90+' AND t.ENFOQUE LIKE '%CONTENCION%'", "90+ contención", None),
        ("ESTATUS2", "'CAS'", "t.TRAMO = 'CASTIGADA'", "Castigada", None),
        ("ESTATUS2", "'REE'", "t.TRAMO = '0' AND t.SEGMENTO IN ('BCOB', 'BOPE', 'FALL')", "Reestructura", None),
        ("SALDO3", "ROUND(t.SALDO2 / 3, 2)", None, "SALDO3 = SALDO2 / 3", None),
        ("TIPO", "LEFT('TDC_' + ISNULL(t.ESTATUS2, ''), 25)", None, "TIPO = TDC_ + estatus", None),
    ]]
    + [("stg.ENT_MAESTRA_CONSUMO",) + x for x in [
        ("SEGMENTO2", "'CONSUMO'", None, "Segmento", None),
        ("RIESGO", "t.CUENTA", None, "RIESGO = CUENTA", None),
        ("NOMBRE2", "LEFT(t.RFC, 20)", None, "NOMBRE2 = RFC", None),
        ("ESTRA3", f"'NOMINA'", f"t.TIPO_CREDITO {AI} LIKE '%ADELANTO DE NOMINA%'", "Tipo de crédito", None),
        ("ESTRA3", "'AUTO'", f"t.TIPO_CREDITO {AI} LIKE '%AUTO%'", "Tipo de crédito", None),
        ("ESTRA3", "'AUTO PPF'", f"t.ESTRA3 {AI} LIKE '%AUTO PAGOS FIJOS%'",
         "ORDEN LEGADO: se evalúa sobre ESTRA3 ya convertido a 'AUTO', nunca se cumple (H-22)", None),
        ("ESTRA3", "'AUTO REE'", f"t.ESTRA3 {AI} LIKE '%AUTO REESTRUCTURADO%'", "Igual que AUTO PPF (H-22)", None),
        ("ESTRA3", "'NOMINA REE'", f"t.TIPO_CREDITO {AI} = 'NOMINA REESTRUCTURADA'", "Tipo de crédito", None),
        ("ESTRA3", "'NOMINA REV'", f"t.TIPO_CREDITO {AI} IN ('NOMINA REVOLVENTE', 'NOMINA REVOLVENTE RENOVADA')", "Tipo de crédito", None),
        ("ESTRA3", "'PERSONAL'", f"t.TIPO_CREDITO {AI} LIKE '%PERSONAL%'", "Tipo de crédito", None),
        ("ESTRA3", "'PERSONAL PPF'", f"t.ESTRA3 {AI} = 'PERSONAL PAGOS FIJOS'", "Nunca se cumple (H-22)", None),
        ("ESTRA3", "'PERSONAL REE'", f"t.ESTRA3 {AI} = 'PERSONAL REESTRUCTURADO'", "Nunca se cumple (H-22)", None),
        ("TIPO", "'NOMINA'", f"t.TIPO {AI} LIKE '%ANTICIPO NOMINA%'", "Cartera", None),
        ("TIPO", "'AUTO'", f"t.TIPO {AI} LIKE '%AUTO%'", "Cartera", None),
        ("TIPO", "'NOMINA'", f"t.TIPO {AI} = 'NOMINA'", "Cartera", None),
        ("TIPO", "'PERS'", f"t.TIPO {AI} IN ('PERSONAL', 'RS TDC')", "Cartera", None),
        ("SEGMENTO", "'VIG'", "t.SEGMENTO = 'VIGENTE'", "Estatus", "REQ 2022-035011"),
        ("SEGMENTO", "'VEN'", "t.SEGMENTO = 'VENCIDA'", "Estatus", "REQ 2022-035011"),
        ("SEGMENTO", "'CAS'", "t.SEGMENTO = 'CASTIGADA'", "Estatus", "REQ 2022-035011"),
        ("SEGMENTO", "'REE'", "t.SEGMENTO = 'PAGO SOSTENIDO'", "Estatus", "REQ 2022-035011"),
    ] + MORA + [
        ("SALDO3", "ROUND(t.SALDO2 / 3, 2)", None, "SALDO3 = SALDO2 / 3", None),
        ("TIPO", "LEFT(ISNULL(t.TIPO, '') + '_' + ISNULL(t.SEGMENTO, ''), 25)", None, "TIPO = cartera + estatus", None),
    ]]
    + [("stg.ENT_MAESTRA_HIPO",) + x for x in [
        ("SEGMENTO2", "'HIPOTECARIO'", None, "Segmento", None),
        ("RIESGO", "t.CUENTA", None, "RIESGO = CUENTA", "REQ 2023-067064"),
        ("TIPO", "'HIPO_CAS'", "t.SEGMENTO IN ('CAS', 'CASTIGA', 'CCAS')", "Estatus", "REQ 2023-067064"),
        ("TIPO", "'HIPO_VEN'", "t.SEGMENTO IN ('VENCIDA', 'VEN4', '90+', 'VEN')", "Estatus", "REQ 2023-067064"),
        ("TIPO", "'HIPO_VIG'", "t.SEGMENTO IN ('VIG', 'VEN3', '60-89', 'VEN2', 'VIGENTE')", "Estatus", "REQ 2023-067064"),
    ] + MORA + [
        ("ETIQUETA5", "'LIQ'", f"t.ETIQUETA5 {AI} = 'LIQUIDACION'", "Enfoque", "REQ 2023-067064"),
        ("ETIQUETA5", "'REG-LIQ'", f"t.ETIQUETA5 {AI} IN ('REGULARIZACION Y LIQUIDACION', 'LIQUIDACION Y REGULARIZACION')", "Enfoque", "REQ 2023-067064"),
        ("ETIQUETA5", "'REG'", f"t.ETIQUETA5 {AI} = 'REGULARIZACION'", "Enfoque", "REQ 2023-067064"),
    ]]
    + [("stg.LAYOUT_486",) + x for x in [
        ("PVS", "'0'", "t.PVS IS NULL OR t.PVS LIKE '%/%' OR t.PVS LIKE '%-%'", "PVS sin dato -> 0", None),
        ("DIRECC3", "LEFT(cfg.fn_solo_digitos(t.DIRECC3), 5)", "t.DIRECC3 LIKE '%[^0-9]%'", "CP sin letras", None),
        ("DIRECC3", "'0' + t.DIRECC3", "LEN(t.DIRECC3) = 4", "CP a 5 dígitos", None),
        ("DIRECC4", "REPLACE(t.DIRECC4, '\\', '')", "t.DIRECC4 LIKE '%\\%'", "Quita '\\' de la ciudad", None),
        ("DIRECC2", "''", "EXISTS (SELECT 1 FROM cfg.EXCLUSION e WHERE e.CLIENTE = '{CLIENTE}' AND e.TIPO = 'DIRECCION' AND e.ACTIVO = 1 AND e.VALOR IN (t.CUENTA, t.CUENTA2) AND e.VALOR2 = t.DIRECC1)", "Dirección mala (dirmal)", None),
        ("DIRECC3", "''", "EXISTS (SELECT 1 FROM cfg.EXCLUSION e WHERE e.CLIENTE = '{CLIENTE}' AND e.TIPO = 'DIRECCION' AND e.ACTIVO = 1 AND e.VALOR IN (t.CUENTA, t.CUENTA2) AND e.VALOR2 = t.DIRECC1)", "Dirección mala (dirmal)", None),
        ("DIRECC4", "''", "EXISTS (SELECT 1 FROM cfg.EXCLUSION e WHERE e.CLIENTE = '{CLIENTE}' AND e.TIPO = 'DIRECCION' AND e.ACTIVO = 1 AND e.VALOR IN (t.CUENTA, t.CUENTA2) AND e.VALOR2 = t.DIRECC1)", "Dirección mala (dirmal)", None),
        ("EDO", "''", "EXISTS (SELECT 1 FROM cfg.EXCLUSION e WHERE e.CLIENTE = '{CLIENTE}' AND e.TIPO = 'DIRECCION' AND e.ACTIVO = 1 AND e.VALOR IN (t.CUENTA, t.CUENTA2) AND e.VALOR2 = t.DIRECC1)", "Dirección mala (dirmal)", None),
        ("DIRECC1", "''", "EXISTS (SELECT 1 FROM cfg.EXCLUSION e WHERE e.CLIENTE = '{CLIENTE}' AND e.TIPO = 'DIRECCION' AND e.ACTIVO = 1 AND e.VALOR IN (t.CUENTA, t.CUENTA2) AND e.VALOR2 = t.DIRECC1)", "Dirección mala (dirmal); va al final porque DIRECC1 es parte de la condición", None),
    ]]
)

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
REGLAS = [
    ("ASIG", "POST_CARGA", "SDO_ACT_CONSUMO_CERO", "stg.ENT_MAESTRA_CONSUMO", "t.SDO_ACT <= 0", "FILAS", "ALERTAR",
     "Cuentas de Consumo con saldo actual <= 0 en la base maestra: reportarlo al banco", "ALERTA_SDO_ACT_CONS_486", 10, None),
    ("ASIG", "PRE_ALTA", "EXCLUSION_CUENTAS", "stg.LAYOUT_486",
     "t.ES_EXISTENTE = 0 AND EXISTS (SELECT 1 FROM cfg.EXCLUSION e WHERE e.CLIENTE = '{CLIENTE}' AND e.TIPO = 'CUENTA' AND e.ACTIVO = 1 AND e.VALOR = t.CUENTA)",
     "FILAS", "EXCLUIR", "Cuenta en la lista de exclusión (exc486)", None, 10, "Yolanda Osornio 02/09/2020"),
    ("ACT", "POST_CARGA", "PAGOS_NEGATIVOS", "stg.ENT_PAGOS", "t.IMPORTE < 0", "FILAS", "EXCLUIR",
     "Llegaron pagos negativos: no se arriban (no salen en SCBPAG) y se avisa a Operación", "PAGOS_NEGATIVOS_486", 10, None),
    ("ACT", "POST_CARGA", "PAGOS_T1", "stg.ENT_PAGOS", "t.FECHA = DATEADD(DAY, -1, CAST('{FECHA}' AS DATE))", "SIN_FILAS", "ALERTAR",
     "No hay pagos con fecha de ayer (T-1)", "PAGOS_NO_ACTUALIZADOS_486", 20, None),
    ("ACT", "RETIRO", "RETIRO_TDC", "stg.SALDOS_486",
     "t.SEGMENTO2 = 'TDC' AND (t.SEG IN ('CERR', 'NORM', '0', '-') OR t.SDO_ACT <= 0)", "FILAS", "DEVOLVER",
     "TDC cerrada, normalizada o sin saldo", None, 10, "REQ 2021-028883"),
    ("ACT", "RETIRO", "RETIRO_CONSUMO", "stg.SALDOS_486",
     "t.SEGMENTO2 = 'CONSUMO' AND (t.SEG IN ('0', '-') OR t.SDO_ACT <= 0)", "FILAS", "DEVOLVER",
     "Consumo sin tramo o sin saldo", None, 20, "REQ 2021-028883"),
    ("ACT", "RETIRO", "RETIRO_DAT_SIN_SALDO", "dat.DAT_486", "t.CLIENTE = '{CLIENTE}' AND t.SDO_ACT <= 0", "FILAS", "DEVOLVER",
     "Cuenta del DAT con saldo actual <= 0", None, 30, "REQ 2025-099547"),
]

PARAMETROS = [
    ("PREFIJO_CUENTA2", "486-", "Prefijo de la cuenta en CYBER"),
    ("TOPE_DEVOLUCION_PCT", "", "Vacío = sin tope: la base maestra se trabaja como llega. Con un número (ej. 10) se detiene si la devolución de un segmento supera ese %"),
    ("DMSTATUS_RETIRO", "R", "dmstatus que se pone en CYBER al retirar (prog15.prg: u8activo = 'R')"),
    ("RESPALDOS_A_CONSERVAR", "15", "Corridas con respaldo del DAT que se conservan para retroceso"),
    ("ALERTA_NUEVAS", "100", "Más cuentas nuevas que esto dispara la alerta (aem_alerta)"),
    ("DIAS_FE_REG", "30", "FE_REG = FE_REC + días"),
    ("NEGATIVO_MODO", "ABS_LEGADO", "ABS_LEGADO (como hoy) | CERO | SIGNO. Pendiente de decidir (H-01)"),
    ("LADAS_2_DIGITOS", "33,55,56,81", "Ladas de 2 dígitos (telbnx.prg); el resto son de 3"),
    ("LADAS_044", "55,56", "Celulares de estas ladas van con área 044; el resto con 045"),
    ("TEL_DAT_LADAS_2", "33,55,81", "op9.prg: ladas de 2 dígitos al guardar los teléfonos de cuentas nuevas en el DAT"),
    ("TEL_DAT_AREA_MOVIL", "045", "op9.prg: área de los celulares al guardarlos en el DAT"),
    ("CORREOS_INVALIDOS", "notiene@hotmail.com,notiene@gmail.com,notienecorreo@hotmail.com,notiene@mail.com,notiene@email.com",
     "email.PRG: correos que no se mandan a CYBER"),
    ("CORREOS_EXCLUIR_MALOS", "1", "1 = EMAILMALO también se quita de sub_mail.TXT (decisión: sí se aplica)"),
    ("CYBER_BANDERA_CORREOS", "416", "id_proc de RCVRY.RPT_LOG_CYBER_REG que se enciende y apaga al actualizar correos (ACTIVA/INACTIVA_BANDERA.SQL)"),
    ("CYBER_PROC_CORREOS", "RCVRY.JSP_CORREOS_486", "Procedimiento de CYBER que purga y agrega los correos (INSERTA_MAIL.sql)"),
    ("STATUS_NO_BLANQUEAR", "GS,PP,LQ,NP,PR,CD,CC,FA", "status.prg: status que no se blanquean (REQ 2021-051124)"),
    ("DIAS_BLANQUEO_STATUS", "1-10", "status.prg: días del mes en que se blanquea status"),
    ("ETIQUETADO_CAMPOS", "SALDO1,SALDO2,SALDO3,RIESGO,PVS,TIPO,CAPITAL,SEGMENTO,PAG_MIN,ETIQUETA,TRAMO,SEG,SDO_VDO,NOMBRE2",
     "eti486.prg: columnas del DAT que Operación puede etiquetar"),
    ("CYBER_PROC_TELEFONOS", "RCVRY.JSP_TELEFONOS_REMESA_486", "Procedimiento de CYBER que purga y agrega los teléfonos (ACTUALIZA_PHONE.SQL)"),
    ("CAMPOS_ACTUALIZA_EXISTENTES",
     "TEL1,TEL2,TEL3,TEL4,TEL5,TEL6,TEL7,TEL8,TEL9,TEL10,TEL11,TEL12,TEL13,CORREO1,CORREO2,"
     "DIRECC1,DIRECC2,DIRECC3,DIRECC4,DIRECC5,ESTADO,PVS,TRAMO,ETIQUETA1,SALDO1,SALDO2,SALDO3",
     "Campos que se actualizan en el DAT cuando la cuenta ya existe (paso.prg + asig_bases)"),
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
    "U1EXT2": ("TEXTO", "cfg.fn_etiqueta('{CLIENTE}', 'TOP', d.CUENTA2)"),
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
    "DMSSNUM": ("TEXTO", "d.CUENTA"),
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
    "U1USO4": ("TEXTO", "cfg.fn_etiqueta('{CLIENTE}', 'STATUS', d.CUENTA)"),
    "U1STATUS": ("TEXTO", "d.SUB_CTE"),
    "DMADL1": ("TEXTO", "LTRIM(d.FOLIO)"),
    "DMP1": ("TEXTO", "cfg.fn_etiqueta('{CLIENTE}', 'DM1', d.CUENTA)"),
    "DMP2": ("TEXTO", "COALESCE(cfg.fn_etiqueta('{CLIENTE}', 'ETI', d.CUENTA), d.ETIQUETA5)"),
    "U1ESTRATG2": ("TEXTO", "d.TRAMO"),
    "U1ESTRATG3": ("TEXTO", "d.ESTRA3"),
}

# ---------------------------------------------------------------- otros archivos planos
# (ARCHIVO, PROCESO, ORDEN, ORIGEN, ORDEN_LINEAS, SEPARADOR, NOMBRE, DESCRIPCION)
BAJA_RETIRO = ("dat.HISTORIA_FOLIO d WHERE d.CLIENTE = @cliente AND d.ID_CORRIDA_BAJA = @id_corrida AND d.ESTATUS = 'B' "
               "AND EXISTS (SELECT 1 FROM ops.DEVOLUCION v WHERE v.ID_CORRIDA = @id_corrida AND v.CUENTA = d.CUENTA)")
SALIDAS_ARCHIVO = [
    ("SCBSDOS", "ASIG", 10, None, "d.CUENTA2", None, "SCBSDOS.TXT", "Cuentas del DAT para CYBER (asi486.prg)"),
    ("SCBTEL", "ASIG", 20, "ops.TELEFONO d WHERE d.ID_CORRIDA = @id_corrida", "d.CUENTA2, d.TIPOTEL, d.AREA, d.TELEFONO", None,
     "SCBTEL.TXT", "Teléfonos (TELSAN) de ancho fijo"),
    ("TEL_SUBMST", "ASIG", 30, "ops.TELEFONO d WHERE d.ID_CORRIDA = @id_corrida", "d.CUENTA2, d.AREA, d.TELEFONO", "|",
     "sub_mst.TXT", "Teléfonos para cargar en RCVRY.JSP_TAB_TEL_REMESA_486 (act_phone.prg)"),
    ("GESCAR_NVA", "ASIG", 40, "dat.HISTORIA_FOLIO d WHERE d.CLIENTE = @cliente AND d.ID_CORRIDA_ALTA = @id_corrida AND d.SUB_CTE = 'NVA'",
     "d.CUENTA2", None, "SCBACTH_486NU.TXT", "Gescar de cuentas nuevas (ges_nuevas_rea.prg, REQ 2021-062065)"),
    ("GESCAR_REA", "ASIG", 50, "dat.HISTORIA_FOLIO d WHERE d.CLIENTE = @cliente AND d.ID_CORRIDA_ALTA = @id_corrida AND d.SUB_CTE = 'REA'",
     "d.CUENTA2", None, "SCBACTH_486REA.TXT", "Gescar de cuentas reasignadas (ges_nuevas_rea.prg)"),
    ("MAIL_SUBMAIL", "ASIG", 35, "ops.CORREO d WHERE d.ID_CORRIDA = @id_corrida", "d.CUENTA2, d.CORREO", "|",
     "sub_mail.TXT", "Correos para cargar en RCVRY.JSP_TAB_MAIL_REMESA_486 (email.PRG -> act_mail.prg)"),
    ("GESCAR_SINTEL", "SINTEL", 10,
     "dat.HISTORIA_FOLIO d WHERE d.CLIENTE = @cliente AND d.ID_CORRIDA_ALTA = @id_corrida "
     "AND NOT EXISTS (SELECT 1 FROM ops.TELEFONO_CYBER t WHERE t.ID_CORRIDA = @id_corrida AND t.CUENTA2 = d.CUENTA2)",
     "d.CUENTA2", None, "SCBACTH_SINTEL.TXT",
     "Gescar de nuevas y reasignadas sin teléfono activo en CYBER (ges486.prg); lo genera ops.sp_gescar_sin_telefono"),
    ("SCBSDOS_ACT", "ACT", 10, None, "d.CUENTA2", None, "SCBSDOS.TXT", "Cuentas del DAT después de la actualización"),
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
FIRMA = ("<p><font face='Book Antiqua' color='#1C3D7B'><b>Asignaciones</b></font> | "
         "<font face='Book Antiqua' color='#255BBF' size='2'>Especialista</font> | "
         "<font face='Book Antiqua' color='#1C3D5B'><b>SERTEC</b></font> | "
         "<font face='Book Antiqua' color='#255BBF' size='2'>CDMX | Tel. (55) 5276 8513 Ext. 1416 | asig.486.cdmx@sertec.com.mx</font></p>")
AVISO = ("<p><font size='1' color='#255BBF'>Este correo, así como los archivos adjuntos que pueda contener, es confidencial y "
         "únicamente para la persona o entidad a la que fue dirigido. Si usted lo recibe por error, destrúyalo de inmediato. "
         "Consulte nuestro sitio de internet en www.sertec.com.mx para conocer nuestro Aviso de Privacidad.</font></p>")
CUERPO = "<html><body><font face='Book Antiqua'><p><b>{texto}</b></p>{extra}<p>Saludos.</p></font>{{{{FRAG:FIRMA_ASIG_486}}}}{{{{FRAG:AVISO_CONFIDENCIALIDAD}}}}</body></html>"

BUZON = "asig.486.cdmx@sertec.com.mx"
INTERNOS_BCC = ["asignaciones.cdmx1@sertec.com.mx", "asignaciones3@sertec.com.mx", "asig.cdmx@sertec.com.mx"]
LISTAS = {
    "PAGOS_NO_ACTUALIZADOS_486": ("Aviso de pagos a T-1 sin actualizar (mail_pagos.prg)",
        [(e, "TO") for e in ["erika.ramos@sertec.com.mx", "administrativo.mc4@sertec.com.mx", "administrativo.mc5@sertec.com.mx",
                             "supervisor.mc4@sertec.com.mx", "supervisorbackoffice.mc@sertec.com.mx"]]
        + [(e, "BCC") for e in INTERNOS_BCC]),
    "RETIROS_ACT_486": ("Retiros por actualización (saldos.prg)",
        [(e, "TO") for e in ["soluciones.486@sertec.com.mx", "supervisor.mc@sertec.com.mx", "supervisor.mc3@sertec.com.mx",
                             "supervisorbackoffice.mc@sertec.com.mx", "soluciones_banbajio@sertec.com.mx"]]
        + [(e, "BCC") for e in INTERNOS_BCC]),
    "OPERACION_ASIG_486": ("Confirmación de asignación a Operación (MAIL.prg) y saldo <= 0 en Consumo (mail_sdo_act_cons.prg)",
        [(e, "TO") for e in ["erika.ramos@sertec.com.mx", "administrativo.mc4@sertec.com.mx", "administrativo.mc5@sertec.com.mx", "supervisor.mc4@sertec.com.mx", "supervisorbackoffice.mc@sertec.com.mx"]] + [(e, "BCC") for e in INTERNOS_BCC]),
    "ASIG_EXPRESS_486": ("Asignación express (correo_486.prg)",
        [(e, "TO") for e in ["supervisor.mc5@sertec.com.mx", "erika.ramos@sertec.com.mx"]]
        + [(e, "CC") for e in ["carlos.landa@sertec.com.mx", "aem.control1@sertec.com.mx", "aem.consultoria2@sertec.com.mx",
                               "aem.consultoria3@sertec.com.mx", "aem.consultoria1@sertec.com.mx", "aem.entregables1@sertec.com.mx",
                               "supervisor.aem.cdmx2@sertec.com.mx", "supervisor.aem.cdmx3@sertec.com.mx", "supervisor.aem.cdmx@sertec.com.mx",
                               "aem.operativa1@sertec.com.mx", "aem.operativa2@sertec.com.mx"]]
        + [(e, "BCC") for e in INTERNOS_BCC]),
    "ACTUALIZACION_486": ("Confirmación de actualización (correo.prg)",
        [(e, "TO") for e in ["administrativo.mc@sertec.com.mx", "administrativo.mc2@sertec.com.mx", "supervisor.mc2@sertec.com.mx",
                             "supervisor.mc4@sertec.com.mx", "supervisor.mc3@sertec.com.mx", "supervisor.mc@sertec.com.mx",
                             "administrativo.mc3@sertec.com.mx", "erika.ramos@sertec.com.mx"]]
        + [(e, "CC") for e in ["administrativo.mc6@sertec.com.mx", "supervisor.mc6@sertec.com.mx", "supervisorbackoffice.mc@sertec.com.mx",
                               "administrativo.mc4@sertec.com.mx"]]
        + [(e, "BCC") for e in INTERNOS_BCC]),
    "RETIROS_OPERACION_486": ("Notificación de retiros a Operación (correo_486noti.prg)",
        [(e, "TO") for e in ["supervisor.mc4@sertec.com.mx", "erika.ramos@sertec.com.mx"]]
        + [(e, "CC") for e in ["supervisorbackoffice.mc3@sertec.com.mx", "administrativo.mc6@sertec.com.mx",
                               "supervisorbackoffice.mc2@sertec.com.mx", "supervisorbackoffice.mc@sertec.com.mx",
                               "administrativo.mc4@sertec.com.mx"]]
        + [(e, "BCC") for e in INTERNOS_BCC]),
    "AEM_486": ("Alerta de asignación grande (aem_alerta.prg)",
        [(e, "TO") for e in ["supervisor.aem.cdmx4@sertec.com.mx", "aem.control1@sertec.com.mx", "aem.proyectos1@sertec.com.mx",
                             "aem.consultoria1@sertec.com.mx", "supervisor.aem.cdmx2@sertec.com.mx"]]
        + [("asig.cdmx@sertec.com.mx", "BCC")]),
    "OPERACION_PAGOS_486": ("PENDIENTE: destinatarios de Operación para el aviso de pagos negativos", [(BUZON, "TO")]
        + [(e, "BCC") for e in INTERNOS_BCC]),
    "ASIGNACIONES_486": ("Equipo de asignaciones: alertas y errores del proceso", [(BUZON, "TO")] + [(e, "BCC") for e in INTERNOS_BCC]),
}
PLANTILLAS = [
    ("PAGOS_NO_ACTUALIZADOS_486", "PAGOS_NO_ACTUALIZADOS_486", "Los pagos de la Boveda no estan actualizados {{FECHA}}",
     "Los pagos de Banco Bajío no traen movimientos a T-1. Favor de revisar.", "", "High"),
    ("RETIROS_ACT_486", "RETIROS_ACT_486", "Retiros actualizacion, {{FECHA}}",
     "Se comparte archivo retiro por actualizacion, FAVOR DE REVISAR.", "", "Normal"),
    ("CONFIRMACION_ASIG_486", "OPERACION_ASIG_486", "Asignación BANCO BAJIO del día {{FECHA_PROCESO}}",
     "Se realiza asignación BANCO BAJIO. Favor de revisar y confirmar misma vía.", "<p>{{RESUMEN}}</p>", "Normal"),
    ("ASIG_EXPRESS_486", "ASIG_EXPRESS_486", "Se realiza Asignacion Express Banco Bajio, {{FECHA}}",
     "Asignacion Banco Bajio en Cyber; dat actualizado en ftp, FAVOR DE CONSTRUIR.", "", "Normal"),
    ("CONFIRMACION_ACT_486", "ACTUALIZACION_486", "Se realiza Actualizacion de Banco Bajio, {{FECHA}}",
     "Actualizacion de Banco Bajio en Cyber; dat actualizado en ftp, FAVOR DE REVISAR.", "", "Normal"),
    ("NOTIFICACION_RETIRO_486", "RETIROS_OPERACION_486", "Actualización de Banco Bajio, {{FECHA}}",
     "Se realiza actualización de Saldos, pagos y devolución del cliente 486.", "", "Normal"),
    ("ALERTA_NUEVAS_486", "AEM_486", "Asignaciones grande de 486 {{FECHA}}",
     "Se recibe una asignacion con mas de 100 registros nuevos, favor de construir al finalizar.",
     "<p>Nuevas: {{NUEVAS}} · umbral: {{UMBRAL}}</p>", "High"),
    ("ALERTA_SDO_ACT_CONS_486", "OPERACION_ASIG_486", "EXISTEN CUENTAS NUEVAS DE CONSUMO CON SDO_ACT MENORES O IGUALES A CERO {{FECHA}}",
     "La base maestra de Consumo trae cuentas con saldo actual menor o igual a cero. Reportarlo al banco.",
     "<p>Registros: {{REGISTROS}}</p>", "High"),
    ("DEVOLUCION_MASIVA_486", "ASIGNACIONES_486", "Asignación 486 detenida: devolución masiva en {{SEGMENTO}}",
     "La base maestra recibida dejaría fuera demasiadas cuentas del DAT. La asignación se detuvo.",
     "<p>Segmento: {{SEGMENTO}} · devoluciones: {{DEVOLUCIONES}} de {{TOTAL_DAT}} ({{PORCENTAJE}}%, tope {{TOPE}}%)</p>", "High"),
    ("PAGOS_NEGATIVOS_486", "OPERACION_PAGOS_486", "Banco Bajío: llegaron pagos negativos {{FECHA}}",
     "En el archivo de pagos de Banco Bajío llegaron pagos negativos. No se arribaron a CYBER.",
     "<p>Pagos negativos: {{REGISTROS}}</p><pre>{{DETALLE}}</pre>", "High"),
    ("ERROR_PROCESO_486", "ASIGNACIONES_486", "Error en {{PROCESO}} (corrida {{ID_CORRIDA}})",
     "El proceso terminó con error.", "<p>{{ERROR}}{{MENSAJE}}</p>", "High"),
]


# ---------------------------------------------------------------- escritura
def sql_semilla(scb, dat):
    L = ["/* =====================================================================",
         "   Banbaj · 90 Semilla del cliente 486 (generado por tools/generar_sql_486.py)",
         "   Re-ejecutable: borra y vuelve a cargar la configuración del 486.",
         "   Revisar antes de producción: RUTA de cfg.ARCHIVO, PERFIL_DBMAIL,",
         "   TOPE_DEVOLUCION_PCT y los campos marcados POR CONFIRMAR / PENDIENTE.",
         "   ===================================================================== */",
         "SET NOCOUNT ON;", "SET XACT_ABORT ON;", "BEGIN TRANSACTION;", ""]
    cli = q(CLIENTE)
    L += [f"DELETE c FROM cfg.ARCHIVO_COLUMNA c JOIN cfg.ARCHIVO a ON a.ID_ARCHIVO = c.ID_ARCHIVO WHERE a.CLIENTE = {cli};",
          f"DELETE FROM cfg.ARCHIVO WHERE CLIENTE = {cli};",
          f"DELETE FROM cfg.HOMOLOGACION WHERE CLIENTE = {cli};",
          f"DELETE FROM cfg.REGLA WHERE CLIENTE = {cli};",
          f"DELETE FROM cfg.SALIDA WHERE CLIENTE = {cli};",
          f"DELETE FROM cfg.SALIDA_ARCHIVO WHERE CLIENTE = {cli};",
          f"DELETE FROM cfg.PARAMETRO WHERE CLIENTE = {cli};",
          "DELETE FROM cfg.CP_ESTADO;", ""]

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
            L.append(f"INSERT INTO cfg.ARCHIVO_COLUMNA (ID_ARCHIVO, CAMPO_DESTINO, PATRON_ENCABEZADO, TIPO_SQL, TRANSFORMACION, OBLIGATORIO, COMENTARIO) "
                     f"VALUES (@id, {q(campo)}, {q(pat_c)}, {q(tipo)}, {q(trf)}, {obl_c}, {q(comc)});")
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
        activo, comillas, encabezado = (list(resto) + [1, 0, 0])[:3] if resto else (1, 0, 0)
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
    for cod, html in (("FIRMA_ASIG_486", FIRMA), ("AVISO_CONFIDENCIALIDAD", AVISO)):
        L.append(f"IF NOT EXISTS (SELECT 1 FROM mail.FRAGMENTO WHERE CODIGO = {q(cod)}) "
                 f"INSERT INTO mail.FRAGMENTO (CODIGO, HTML) VALUES ({q(cod)}, {q(html)});")
    for lista, (desc, dests) in LISTAS.items():
        L.append(f"IF NOT EXISTS (SELECT 1 FROM mail.LISTA WHERE CODIGO = {q(lista)}) "
                 f"INSERT INTO mail.LISTA (CODIGO, CLIENTE, DESCRIPCION) VALUES ({q(lista)}, {cli}, {q(desc)});")
        for email, tipo in dests:
            L.append(f"IF NOT EXISTS (SELECT 1 FROM mail.DESTINATARIO WHERE LISTA = {q(lista)} AND EMAIL = {q(email)} AND TIPO = '{tipo}') "
                     f"INSERT INTO mail.DESTINATARIO (LISTA, EMAIL, TIPO) VALUES ({q(lista)}, {q(email)}, '{tipo}');")
    for cod, lista, asunto, texto, extra, imp in PLANTILLAS:
        cuerpo = CUERPO.format(texto=texto, extra=extra)
        L.append(f"IF NOT EXISTS (SELECT 1 FROM mail.PLANTILLA WHERE CODIGO = {q(cod)}) "
                 f"INSERT INTO mail.PLANTILLA (CODIGO, LISTA, PERFIL_DBMAIL, ASUNTO, CUERPO_HTML, IMPORTANCIA) "
                 f"VALUES ({q(cod)}, {q(lista)}, {q(PERFIL_DBMAIL)}, {q(asunto)}, {q(cuerpo)}, '{imp}');")
    L += ["", "COMMIT TRANSACTION;", "GO", ""]
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
    (RAIZ / "sql" / "05_tabla_dat_486.sql").write_text(sql_dat(dat), encoding="utf-8")
    (RAIZ / "sql" / "90_semilla_486.sql").write_text(sql_semilla(scb, dat), encoding="utf-8")
    print("ok:", len(dat), "campos DAT,", len(scb), "campos SCBSDOS")


if __name__ == "__main__":
    main()
