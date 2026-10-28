"""Genera archivos de prueba con datos FICTICIOS y los encabezados reales del banco.

Uso: python tests/generar_datos_prueba.py tests/datos

Estructura:
  asig/      bases maestras TDC y Consumo (asignación del 02/11/2026)
  act_ok/    saldos TDC, saldos Consumo y pagos (actualización del 03/11/2026)
  act_neg/   pagos con un importe negativo (la actualización debe cancelarse)
"""
import csv
import json
import sys
from pathlib import Path

AQUI = Path(__file__).resolve().parent
FECHA_ENC = "31/10/2026"


def escribir(ruta, encabezados, filas):
    ruta.parent.mkdir(parents=True, exist_ok=True)
    # SQL Server en Linux no admite CODEPAGE en BULK INSERT y lee los archivos como OEM (437; no tiene Ó mayúscula).
    # En producción (Windows) los CSV de Excel vienen en Windows-1252 y se leen con CODEPAGE='ACP'.
    with open(ruta, "w", encoding="cp437", errors="replace", newline="") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(encabezados)
        for fila in filas:
            w.writerow([fila.get(h, "") for h in encabezados])


def main(destino):
    destino = Path(destino)
    enc = json.loads((AQUI / "encabezados_maestras.json").read_text(encoding="utf-8"))
    tdc_h = [h.replace("{F}", FECHA_ENC) for h in enc["TDC"]]
    con_h = [h.replace("{F}", FECHA_ENC) for h in enc["CONSUMO"]]
    F = FECHA_ENC

    def tdc(prime, acc, nombre, sdo_act, sdo_vdo, tramo, estatus, cosecha="", tel="", enfoque="", cp="06600"):
        return {
            "PRIME+4DIG": prime, "ACC_NUM": acc, "NAME2": nombre, "Tipo de TDC": "CLASICA", "GARANTIZADA": "0",
            f"Dias Vencidos VEN4/CCAS {F}": "120", "RFC": "XAXX010101000",
            f"Pago mínimo {F}": "150.00", f"Saldo PRIME total asignado al {F}": sdo_vdo,
            f"Saldo actualizado VEN4/CCAS al {F}": sdo_act,
            "MONTO A CUBRIR 1 PAGO LIQUIDACION": "3000.00", "MONTO A CUBRIR PLAZOS PAGO <= 6 LIQUIDACION": "4500.00",
            "ENFOQUE_LIQUIDACION_1_PAGO": enfoque, "TEL_CERT": tel, "CALLE": "CALLE FICTICIA 1", "COL": "Colonia Prueba",
            "CIUDAD": "Ciudad Prueba", "ESTADO": "CDMX", "CP": cp,
            f"Estatus al {F}": estatus, f"Tramo {F}": tramo, "COSECHAS": cosecha,
        }

    escribir(destino / "asig" / "BASE MAESTRA_TARJETA 31-10-2026 - SERTEC.csv", tdc_h, [
        tdc("10000000011111", "1000000001", "CLIENTE PRUEBA UNO", "1000.00", "1100.00", "45", "VEN4", "COSECHA 2", "5599999999"),
        tdc("10000000033333", "1000000003", "CLIENTE PRUEBA TRES", "0", "750.00", "45", "VEN4"),
        tdc("10000000044444", "1000000004", "CLIENTE PRUEBA CUATRO", "2000.00", "2000.00", "CASTIGADA", "CCAS"),
        tdc("10000000055555", "1000000005", "CLIENTE PRUEBA MALO", "abc", "10.00", "45", "VEN4"),
    ])

    def con(credito, nombre, adeudo, vencido, tipo_cred, cartera, estatus, tramo, dias, tel="", cp="06600", cosecha=""):
        return {
            "CREDITO": credito, "CRÉDITO CYBER": f"9{credito[1:]}-CRN-{credito}", "NOMBRE": nombre, "RFC": "XAXX010101000",
            "TIPO DE CRÉDITO": tipo_cred, "CARTERA": cartera, f"CAPITAL AL {F}": "1000.00",
            f"ADEUDO TOTAL AL {F}": adeudo, f"MONTO VENCIDO AL {F}": vencido,
            "MONTO A 1 PAGO LIQUIDACION": "900.00", "MONTO A PAGO LIQUIDACION PLAZOS <= 6 MESES": "1200.00",
            f"DIAS MORA AL {F}": dias, f"ESTATUS AL {F}": estatus, f"TRAMO AL {F}": tramo,
            "TEL_CERT": tel, "CALLE": "CALLE FICTICIA 2", "COL": "Colonia Prueba", "CIUDAD": "Ciudad Prueba",
            "ESTADO": "CDMX", "CP": cp, "COSECHAS": cosecha,
        }

    c4 = con("20000004", "CLIENTE PRUEBA C4", "$1,234.50", " -   ", "Adelanto de Nómina", "Anticipo Nómina", "VIGENTE", "1-29", "10", cp="6600")
    escribir(destino / "asig" / "BASE MAESTRA_CONSUMO 31-10-2026 - SERTEC.csv", con_h, [
        con("20000001", "CLIENTE PRUEBA C1", "5000.00", "800.00", "PERSONAL", "PERSONAL", "VENCIDA", "90+", "96", tel="5577777777"),
        con("20000003", "CLIENTE PRUEBA C3", "3000.00", "300.00", "PERSONAL", "PERSONAL", "VENCIDA", "90+", "96", tel="5533333333"),
        c4, c4,
        con("20000005", "CLIENTE PRUEBA C5", "0", "0", "AUTO", "AUTO", "CASTIGADA", "CASTIGADA", "400"),
        con("20000008", "CLIENTE PRUEBA EXCLUIDO", "700.00", "70.00", "PERSONAL", "PERSONAL", "VENCIDA", "90+", "96"),
        con("20000009", "CLIENTE PRUEBA REASIGNADO", "900.00", "90.00", "Nómina revolvente", "Nómina", "VENCIDA", "60-89", "70"),
    ])

    escribir(destino / "act_ok" / "SERTEC_Saldos_tdc.csv",
             ["ACCT_NUM", "CYBER", "ACC_NUM", "SALDO", "ESTATUS", "PAGO-MIN", "FECHA_CORTE", "DESPACHO"], [
        {"ACCT_NUM": "4000000000011111", "CYBER": "10000000011111", "ACC_NUM": "1000000001", "SALDO": "500.00",
         "ESTATUS": "NORM", "PAGO-MIN": "50.00", "FECHA_CORTE": "2026-10-25 00:00:00.0", "DESPACHO": "SERTEC"},
        {"ACCT_NUM": "4000000000033333", "CYBER": "10000000033333", "ACC_NUM": "1000000003", "SALDO": "900.50",
         "ESTATUS": "VEN4", "PAGO-MIN": "90.10", "FECHA_CORTE": "-", "DESPACHO": "SERTEC"},
        {"ACCT_NUM": "4000000000099999", "CYBER": "19999999999999", "ACC_NUM": "1999999999", "SALDO": "10.00",
         "ESTATUS": "VEN4", "PAGO-MIN": "1.00", "FECHA_CORTE": "-", "DESPACHO": "SERTEC"},
    ])
    cons_h = ["", "CREDITO", "CYBER", "MONTO_VENCIDO", "SALDO_DEUDOR", "FECHA-PAGO", "PROX_AMOR_A_VEN", "PAGO-MIN",
              "DIAS_MORA", "TRAMO", "DESPACHO", "FECHA"]

    def sc(i, credito, vencido, deudor, pagmin, dias, tramo):
        return {"": str(i), "CREDITO": credito, "CYBER": f"9{credito[1:]}-CRN-{credito}", "MONTO_VENCIDO": vencido,
                "SALDO_DEUDOR": deudor, "FECHA-PAGO": "20261030", "PROX_AMOR_A_VEN": "", "PAGO-MIN": pagmin,
                "DIAS_MORA": dias, "TRAMO": tramo, "DESPACHO": "SERTEC", "FECHA": "20261102"}
    escribir(destino / "act_ok" / "SERTEC_Saldos_Cons.csv", cons_h, [
        sc(1, "20000001", " 2,000.00 ", " 12,345.67 ", "700.5", "120", "90+"),
        sc(2, "20000003", " 300.00 ", " 5,000.00 ", "100", "96", "0"),
        sc(3, "20000004", " -   ", " -   ", "0", "0", "30-59"),
    ])
    pagos_h = ["CREDITO", "IMPORTE", "FECHA", "TRX", "EMPRESA", "DESPACHO"]
    escribir(destino / "act_ok" / "SERTEC_Pagos.csv", pagos_h, [
        {"CREDITO": "20000001", "IMPORTE": "$1,000.00", "FECHA": "2026-11-02", "TRX": "RECUPERACION", "EMPRESA": "CONSUMO", "DESPACHO": "SERTEC"},
        {"CREDITO": "20000004", "IMPORTE": "500.00", "FECHA": "2026-11-02", "TRX": "RECUPERACION", "EMPRESA": "CONSUMO", "DESPACHO": "SERTEC"},
        {"CREDITO": "20000004", "IMPORTE": "500.00", "FECHA": "2026-11-02", "TRX": "RECUPERACION", "EMPRESA": "CONSUMO", "DESPACHO": "SERTEC"},
        {"CREDITO": "29999999", "IMPORTE": "10.00", "FECHA": "2026-11-02", "TRX": "RECUPERACION", "EMPRESA": "CONSUMO", "DESPACHO": "SERTEC"},
    ])
    escribir(destino / "act_neg" / "SERTEC_Pagos.csv", pagos_h, [
        {"CREDITO": "20000001", "IMPORTE": "-100.00", "FECHA": "2026-11-02", "TRX": "AJUSTE", "EMPRESA": "CONSUMO", "DESPACHO": "SERTEC"},
    ])
    # Etiquetas TOP que comparte Operación: folio + etiqueta
    escribir(destino / "etiquetas" / "TOP.csv", ["FOLIO", "ETIQUETA"], [
        {"FOLIO": "100001", "ETIQUETA": "REE"},
        {"FOLIO": "486-100003", "ETIQUETA": "REE"},
        {"FOLIO": "999999", "ETIQUETA": "REE"},
        {"FOLIO": "100002", "ETIQUETA": ""},
        {"FOLIO": "100001", "ETIQUETA": "REE"},
    ])
    print("datos de prueba en", destino)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else AQUI / "datos")
