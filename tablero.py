#!/usr/bin/env python3
"""Tablero de control del acompañamiento de la SED, en Excel.

Cruza la agenda de visitas (aplicativo de reservas) con quién se apuntó
(aplicativo de acompañamiento) y escribe un .xlsx con cuatro hojas:

    Resumen      cifras del día y reparto por equipo
    Faltan       las visitas sin acompañante, por fecha — la lista de trabajo
    Por colegio  una fila por IE: cuántas visitas, cuántas cubiertas, quién va
    Por visita   el detalle completo, con celular de quien acompaña

    python3 tablero.py                 # salidas/seguimiento_acompanamiento_<fecha>.xlsx
    python3 tablero.py --salida x.xlsx

El celular sale SOLO en este archivo, nunca en la página. Compártalo con
cuidado: lleva nombres y celulares de funcionarias.
"""
import argparse, datetime as dt, json, re, sys, unicodedata, urllib.parse, urllib.request
from collections import defaultdict
from pathlib import Path

AQUI = Path(__file__).resolve().parent
RAIZ = AQUI.parent
CLAVE_ARCHIVO = RAIZ / "Encuesta/seguimiento_largo_plazo_r1r2/seguimiento/.sed_key"

SB = "https://sxfbzcnsbcvitaenwpct.supabase.co/rest/v1/rpc"
ANON = ("eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InN4ZmJ6Y25zYmN2"
        "aXRhZW53cGN0Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODkxNTUzODksImV4cCI6MjEwNDczMTM4OX0"
        ".AwTQ4lNfFQXEOWUcgOcyI3QUxsYP7-GFo7zuPkHuOJM")

MESES = ["", "enero", "febrero", "marzo", "abril", "mayo", "junio", "julio",
         "agosto", "septiembre", "octubre", "noviembre", "diciembre"]
DIAS = ["lunes", "martes", "miércoles", "jueves", "viernes", "sábado", "domingo"]


def pedir(nombre, query=""):
    r = urllib.request.Request(f"{SB}/{nombre}" + (f"?{query}" if query else ""),
                               headers={"apikey": ANON, "Authorization": "Bearer " + ANON})
    with urllib.request.urlopen(r, timeout=60) as f:
        return json.load(f)


def norm(s):
    s = unicodedata.normalize("NFKD", (s or "")).encode("ascii", "ignore").decode()
    return re.sub(r"[^A-Z0-9]+", " ", s.upper()).strip()


def titulo(s):
    t = (s or "").lower()
    t = re.sub(r"(^|[\s(·\-/])([a-záéíóúñ])", lambda m: m.group(1) + m.group(2).upper(), t)
    for g in ("IED", "CED", "CEDID", "SED", "OCE"):
        t = re.sub(rf"\b{g[0]}{g[1:].lower()}\b", g, t)
    return t


def bonita(iso):
    d = dt.date.fromisoformat(iso)
    return f"{DIAS[d.weekday()]} {d.day} de {MESES[d.month]}"


def hora12(h):
    H, M = (int(x) for x in h.split(":"))
    return f"{(H % 12) or 12}:{M:02d} {'a.m.' if H < 12 else 'p.m.'}"


def llave_aula(dane, jornada, clase):
    """La MISMA llave que usa la página: el apuntado sigue al aula, no a la fecha.
    Si el colegio corre la visita de día, el acompañante se va con ella."""
    return (f"{str(dane or '').strip()}|{str(jornada or '').strip().upper()}|"
            f"{str(clase or '').strip().lstrip('0') or '0'}")


def cargar(hoy):
    agenda = pedir("api_get")
    if not CLAVE_ARCHIVO.exists():
        sys.exit(f"⛔ falta la clave en {CLAVE_ARCHIVO}")
    clave = CLAVE_ARCHIVO.read_text(encoding="utf-8").strip()
    ac = pedir("sed_agenda", "p_clave=" + urllib.parse.quote(clave))
    if not ac.get("ok"):
        sys.exit(f"⛔ sed_agenda: {ac.get('error')}")

    # coordinadora por aula, con la misma llave que usa la página
    facis = {}
    for k, v in (agenda.get("facilitadores") or {}).items():
        d, j, c = (k.split("|") + ["", "", ""])[:3]
        facis[llave_aula(d, j, c)] = v
    tel_coord = ac.get("coordinadoras") or {}

    apuntados = {a["visita_id"]: a for a in ac.get("acompanamientos") or []}

    visitas = []
    for slot, lista in (agenda.get("details") or {}).items():
        fecha, hora = slot.split(" ")
        for v in lista:
            if str(v.get("dane", "")).startswith("EXTRA"):
                continue                       # operativo de Ronda 3, no es seguimiento
            llave = llave_aula(v["dane"], v.get("jornada"), v.get("clase"))
            a = apuntados.get(llave) or {}
            coord = facis.get(llave, "")
            visitas.append({
                "fecha": fecha, "hora": hora, "localidad": v.get("localidad", ""),
                "colegio": titulo(v.get("colegio", "")), "sede": titulo(v.get("sede", "")),
                "jornada": v.get("jornada", ""), "curso": v.get("clase", ""),
                "dane": v.get("dane", ""),
                "coordinadora": coord, "tel_coordinadora": tel_coord.get(coord, ""),
                "acompanante": a.get("nombre", ""), "equipo": a.get("equipo", ""),
                "telefono": a.get("telefono", ""),
                "apuntado_el": (a.get("creado_at") or "")[:16],
                # Una visita que ya pasó sin acompañante no es una tarea pendiente:
                # es una cita perdida. Marcarla FALTA hace pensar que hay que cubrirla.
                "estado": ("Con acompañante" if a
                           else ("Ya pasó" if fecha < hoy else "FALTA")),
            })
    visitas.sort(key=lambda x: (x["fecha"], x["hora"], x["colegio"]))
    return visitas


# --------------------------------------------------------------------- Excel
def escribir(visitas, salida, hoy):
    from openpyxl import Workbook
    from openpyxl.styles import Alignment, Font, PatternFill
    from openpyxl.utils import get_column_letter

    AZUL = PatternFill("solid", fgColor="0F4C81")
    AMBAR = PatternFill("solid", fgColor="FEF3C7")
    VERDE = PatternFill("solid", fgColor="E7F6EF")
    BLANCO = Font(color="FFFFFF", bold=True, size=11)

    wb = Workbook()

    def hoja(nombre, encabezados, filas, anchos, pintar=None):
        ws = wb.create_sheet(nombre)
        ws.append(encabezados)
        for c in ws[1]:
            c.fill, c.font = AZUL, BLANCO
            c.alignment = Alignment(vertical="center", wrap_text=True)
        ws.row_dimensions[1].height = 30
        for f in filas:
            ws.append(f)
        for i, a in enumerate(anchos, start=1):
            ws.column_dimensions[get_column_letter(i)].width = a
        ws.freeze_panes = "A2"
        if filas:
            ws.auto_filter.ref = f"A1:{get_column_letter(len(encabezados))}{len(filas)+1}"
        if pintar:
            for r in range(2, len(filas) + 2):
                relleno = pintar(filas[r - 2])
                if relleno:
                    for c in range(1, len(encabezados) + 1):
                        ws.cell(row=r, column=c).fill = relleno
        return ws

    futuras = [v for v in visitas if v["fecha"] >= hoy]
    faltan = [v for v in futuras if v["estado"] == "FALTA"]
    pasadas = [v for v in visitas if v["fecha"] < hoy]
    por_equipo = defaultdict(int)
    for v in visitas:
        if v["equipo"]:
            por_equipo[v["equipo"]] += 1

    # ---- Resumen
    ws = wb.active
    ws.title = "Resumen"
    ws["A1"] = "Acompañamiento de la SED · Encuesta de Clima de Aula"
    ws["A1"].font = Font(bold=True, size=15, color="0F4C81")
    ws["A2"] = f"Corte: {bonita(hoy)} de 2026"
    ws["A2"].font = Font(italic=True, color="6B7280")
    filas = [
        ("Visitas en total", len(visitas)),
        ("  · ya pasaron", len(pasadas)),
        ("Visitas por venir", len(futuras)),
        ("  · con acompañante", len(futuras) - len(faltan)),
        ("  · SIN acompañante", len(faltan)),
        ("Colegios con visita", len({v["colegio"] for v in visitas})),
        ("Personas de la SED apuntadas", len({v["acompanante"] for v in visitas if v["acompanante"]})),
    ]
    r = 4
    for k, n in filas:
        ws.cell(row=r, column=1, value=k)
        ws.cell(row=r, column=2, value=n).font = Font(bold=True)
        r += 1
    r += 1
    ws.cell(row=r, column=1, value="Visitas tomadas por equipo").font = Font(bold=True, size=12)
    r += 1
    for e, n in sorted(por_equipo.items(), key=lambda x: -x[1]):
        ws.cell(row=r, column=1, value=e)
        ws.cell(row=r, column=2, value=n)
        r += 1
    if not por_equipo:
        ws.cell(row=r, column=1, value="(nadie se ha apuntado todavía)")
    ws.column_dimensions["A"].width = 38
    ws.column_dimensions["B"].width = 12

    # ---- Faltan
    hoja("Faltan", ["Fecha", "Hora", "Localidad", "Colegio (IE)", "Curso",
                    "Coordina", "Celular coordinadora"],
         [[bonita(v["fecha"]), hora12(v["hora"]), titulo(v["localidad"]), v["colegio"],
           v["curso"], v["coordinadora"], v["tel_coordinadora"]] for v in faltan],
         [22, 12, 20, 46, 9, 14, 20],
         pintar=lambda f: AMBAR)

    # ---- Por colegio
    por_col = defaultdict(list)
    for v in visitas:
        por_col[(v["colegio"], v["localidad"])].append(v)
    filas = []
    for (col, loc), vs in sorted(por_col.items()):
        con = [v for v in vs if v["acompanante"]]
        pend = [v for v in vs if v["estado"] == "FALTA"]
        filas.append([
            col, titulo(loc), len(vs), len(con), len(pend),
            ", ".join(sorted({bonita(v["fecha"]) for v in vs})),
            ", ".join(sorted({v["coordinadora"] for v in vs if v["coordinadora"]})),
            ", ".join(sorted({v["acompanante"] for v in con})),
            ", ".join(sorted({v["equipo"] for v in con if v["equipo"]})),
        ])
    hoja("Por colegio",
         ["Colegio (IE)", "Localidad", "Visitas por hacer", "Con acompañante",
          "Faltan", "Fechas", "Coordina", "Acompañan (SED)", "Equipos"],
         filas, [46, 20, 10, 10, 8, 34, 14, 34, 28],
         pintar=lambda f: AMBAR if f[4] else VERDE)

    # ---- Por visita
    hoja("Por visita",
         ["Fecha", "Hora", "Localidad", "Colegio (IE)", "Sede", "Jornada", "Curso",
          "Coordina", "Celular coordinadora", "Estado", "Acompaña (SED)", "Equipo",
          "Celular", "Se apuntó el"],
         [[bonita(v["fecha"]), hora12(v["hora"]), titulo(v["localidad"]), v["colegio"],
           v["sede"], v["jornada"], v["curso"], v["coordinadora"], v["tel_coordinadora"],
           v["estado"], v["acompanante"], v["equipo"], v["telefono"], v["apuntado_el"]]
          for v in visitas],
         [22, 12, 20, 46, 30, 10, 9, 14, 20, 18, 28, 26, 16, 18],
         pintar=lambda f: AMBAR if f[9] == "FALTA" else (VERDE if f[9] == "Con acompañante" else None))

    salida.parent.mkdir(parents=True, exist_ok=True)
    wb.save(salida)
    return len(futuras), len(faltan)


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--salida", default="")
    a = ap.parse_args()
    hoy = dt.datetime.now(dt.timezone(dt.timedelta(hours=-5))).date().isoformat()
    visitas = cargar(hoy)
    salida = Path(a.salida) if a.salida else AQUI / "salidas" / f"seguimiento_acompanamiento_{hoy}.xlsx"
    n, faltan = escribir(visitas, salida, hoy)
    print(f"visitas por venir: {n} · sin acompañante: {faltan}")
    print(f"→ {salida}")


if __name__ == "__main__":
    main()
