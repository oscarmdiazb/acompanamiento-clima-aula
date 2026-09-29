#!/usr/bin/env python3
"""Construye sedes.js: direccion + barrio + telefono de cada sede visitada.

Fuente: directorio oficial de sedes de la SED
  data/final/SIMAT/4.-DIR-31-MAR-2025_01042025.csv
Cruce:  DANE12 del establecimiento + nombre de la sede (normalizado).

Salida: sedes.js  ->  const SEDES = { "<dane12>|<sede normalizada>": {dir, barrio, tel}, ... }
No lleva ningun dato de estudiantes.
"""
import csv, json, re, sys, unicodedata, urllib.request
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[1]
DIR_CSV = RAIZ / "data/final/SIMAT/4.-DIR-31-MAR-2025_01042025.csv"
SALIDA = Path(__file__).resolve().parent / "sedes.js"

API = "https://sxfbzcnsbcvitaenwpct.supabase.co/rest/v1/rpc/api_get"
ANON = ("eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InN4ZmJ6Y25zYmN2"
        "aXRhZW53cGN0Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODkxNTUzODksImV4cCI6MjEwNDczMTM4OX0"
        ".AwTQ4lNfFQXEOWUcgOcyI3QUxsYP7-GFo7zuPkHuOJM")


def norm(s):
    s = unicodedata.normalize("NFKD", (s or "")).encode("ascii", "ignore").decode()
    s = re.sub(r"\b(COLEGIO|IED|CED|SEDE|INSTITUCION EDUCATIVA DISTRITAL)\b", " ", s.upper())
    return re.sub(r"[^A-Z0-9]+", " ", s).strip()


def visitas():
    req = urllib.request.Request(API, headers={"apikey": ANON, "Authorization": "Bearer " + ANON})
    d = json.load(urllib.request.urlopen(req, timeout=30))
    out = []
    for slot, lista in d.get("details", {}).items():
        for v in lista:
            out.append(v)
    return out


def main():
    # directorio -> por establecimiento
    por_est, por_nombre, por_colegio = {}, {}, {}
    with open(DIR_CSV, encoding="utf-8") as f:
        for r in csv.DictReader(f):
            info = {
                "dir": (r.get("sede_direccion") or "").strip(),
                "barrio": (r.get("barriogeo") or "").strip().title(),
                "tel": (r.get("telefono") or "").strip(),
                "loc": (r.get("nombre_localidad") or "").strip(),
            }
            # Coordenadas de la sede, para el mapa. Solo se guardan si caen dentro
            # de Bogota; el directorio trae algunas en cero o cambiadas de orden.
            try:
                lat = float((r.get("sede_latitud") or "").replace(",", "."))
                lon = float((r.get("sede_longitud") or "").replace(",", "."))
                if 3.5 < lat < 5.2 and -75.0 < lon < -73.8:
                    info["lat"], info["lon"] = round(lat, 6), round(lon, 6)
            except ValueError:
                pass
            if not info["dir"]:
                continue
            est = (r.get("dane12_establecimiento_educativo") or "").strip()
            sede = norm(r.get("nombre_sede_educativa"))
            por_est.setdefault(est, {})[sede] = info
            por_nombre.setdefault(sede, info)
            # sede principal del establecimiento, para cruzar por nombre de colegio
            nom_est = norm(r.get("nombre_establecimiento_educativo"))
            if nom_est and ((r.get("ordendesede") or "").strip() in ("1", "01")
                            or nom_est not in por_colegio):
                por_colegio.setdefault(nom_est, info)

    sedes, sin = {}, []
    for v in visitas():
        dane, sede = (v.get("dane") or "").strip(), norm(v.get("sede"))
        # Las filas sinteticas del operativo (EXTRA, EXTRA-R3, EXTRA-R3REV) no traen
        # una sede real: su campo "sede" es una nota. Se cruzan por nombre de colegio.
        extra = dane.startswith("EXTRA")
        clave = f"R3|{norm(v.get('colegio'))}" if extra else f"{dane}|{sede}"
        if clave in sedes:
            continue
        cand = {} if extra else por_est.get(dane, {})
        info = cand.get(sede)
        if info is None and len(cand) == 1:          # una sola sede: no hay ambiguedad
            info = next(iter(cand.values()))
        if info is None and not extra:
            info = por_nombre.get(sede)               # por nombre de sede
        if info is None:
            # Se cruza por el nombre del colegio, quitando el prefijo "R3 · ".
            nom = norm(re.sub(r"^\s*R3\s*[·.-]\s*", "", v.get("colegio") or ""))
            info = por_colegio.get(nom) or por_nombre.get(nom)
            if info is None and len(nom) >= 8:
                # "CULTURA POPULAR" vs "DE CULTURA POPULAR": se acepta la coincidencia
                # parcial SOLO si un unico colegio del directorio la cumple.
                cs = [k for k in por_colegio if nom in k or k in nom]
                if len(cs) == 1:
                    info = por_colegio[cs[0]]
        if info:
            sedes[clave] = info
        else:
            sin.append((v.get("colegio"), v.get("sede"), dane))

    SALIDA.write_text(
        "// sedes.js — direccion y barrio de cada sede visitada.\n"
        "// Generado por construir_sedes.py desde el directorio oficial de sedes de la SED\n"
        "// (data/final/SIMAT/4.-DIR-31-MAR-2025_01042025.csv). No contiene datos de estudiantes.\n"
        "// Clave: \"<dane12 del establecimiento>|<nombre de sede normalizado>\".\n"
        "const SEDES = " + json.dumps(sedes, ensure_ascii=False, indent=1, sort_keys=True) + ";\n",
        encoding="utf-8")

    con_coord = sum(1 for v in sedes.values() if "lat" in v)
    print(f"sedes con direccion: {len(sedes)}")
    print(f"sedes con coordenadas: {con_coord}")
    print(f"sin direccion:       {len(sin)}")
    for c in sin[:15]:
        print("   -", c)


if __name__ == "__main__":
    main()
