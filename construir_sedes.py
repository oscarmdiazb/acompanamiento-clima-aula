#!/usr/bin/env python3
"""Construye sedes.js: dirección, barrio y coordenadas de cada sede visitada.

Fuente: directorio oficial de sedes de la SED
  data/final/SIMAT/4.-DIR-31-MAR-2025_01042025.csv

CÓMO SE CRUZA — y por qué importa
---------------------------------
El `dane` de la agenda tiene **14 dígitos**: los 12 primeros son el DANE del
ESTABLECIMIENTO y los 2 últimos el **consecutivo de la sede**. Por ejemplo
`11100107595702` = establecimiento `111001075957` (Colegio San Carlos), sede
número **2** (SAN CARLOS). Cruzar por esos dos campos es exacto.

La versión anterior no sabía esto: buscaba el 14 dígitos como si fuera el DANE
del establecimiento, no encontraba nada, y caía en un respaldo que buscaba el
NOMBRE DE LA SEDE en toda Bogotá. Como los nombres se repiten, tres colegios
salieron publicados con la dirección de otro colegio al otro lado de la ciudad
(San Carlos con una dirección de Usaquén, José Martí con una de Bosa). Gente de
la SED iba a viajar a la dirección equivocada.

Por eso ahora, además del cruce exacto:
  · los respaldos NUNCA salen del mismo establecimiento, y
  · toda coincidencia se descarta si la LOCALIDAD no es la misma que la de la
    visita. Es barato y habría atajado los tres errores.

Salida: sedes.js  ->  const SEDES = { "<dane de la agenda>": {dir, barrio, loc, tel, lat, lon} }
No lleva ningún dato de estudiantes.
"""
import csv, json, re, unicodedata, urllib.request
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
    d = json.load(urllib.request.urlopen(req, timeout=60))
    return [v for lista in (d.get("details") or {}).values() for v in lista]


def leer_directorio():
    """(por_sede, por_est, por_colegio) — todo con la localidad, para poder verificar."""
    por_sede, por_est, por_colegio = {}, {}, {}
    with open(DIR_CSV, encoding="utf-8") as f:
        for r in csv.DictReader(f):
            direccion = (r.get("sede_direccion") or "").strip()
            if not direccion:
                continue
            info = {
                "dir": direccion,
                "barrio": (r.get("barriogeo") or "").strip().title(),
                "tel": (r.get("telefono") or "").strip(),
                "loc": (r.get("nombre_localidad") or "").strip(),
            }
            # Coordenadas, solo si caen dentro de Bogotá: el archivo trae ceros.
            try:
                lat = float((r.get("sede_latitud") or "").replace(",", "."))
                lon = float((r.get("sede_longitud") or "").replace(",", "."))
                if 3.5 < lat < 5.2 and -75.0 < lon < -73.8:
                    info["lat"], info["lon"] = round(lat, 6), round(lon, 6)
            except ValueError:
                pass

            est = (r.get("dane12_establecimiento_educativo") or "").strip()
            try:
                consec = int((r.get("consecutivo") or "0").strip())
            except ValueError:
                consec = 0
            por_sede[(est, consec)] = info
            por_est.setdefault(est, {})[norm(r.get("nombre_sede_educativa"))] = info
            nom = norm(r.get("nombre_establecimiento_educativo"))
            if nom and (consec == 1 or nom not in por_colegio):
                por_colegio[nom] = info
    return por_sede, por_est, por_colegio


def buscar(v, por_sede, por_est, por_colegio):
    """Devuelve (info, cómo_se_encontró) o (None, motivo)."""
    dane = str(v.get("dane") or "").strip()
    sede = norm(v.get("sede"))

    if dane.startswith("EXTRA"):
        # Filas sintéticas del operativo: no traen DANE real. Solo queda el nombre
        # del colegio, y con la localidad no se puede verificar (viene «EXTRA»).
        nom = norm(re.sub(r"^\s*R3\s*[·.-]\s*", "", v.get("colegio") or ""))
        return (por_colegio.get(nom), "nombre de colegio (fila sintética)")

    est, consec = dane[:12], dane[12:]
    if consec.isdigit():
        i = por_sede.get((est, int(consec)))
        if i:
            return i, "DANE de establecimiento + consecutivo de sede"
    i = (por_est.get(est) or {}).get(sede)
    if i:
        return i, "nombre de sede dentro del mismo establecimiento"
    cand = por_est.get(est) or {}
    if len(cand) == 1:
        return next(iter(cand.values())), "único sede del establecimiento"
    i = por_sede.get((est, 1))
    if i:
        return i, "sede principal del establecimiento"
    return None, f"el establecimiento {est} no está en el directorio"


def main():
    por_sede, por_est, por_colegio = leer_directorio()
    sedes, sin, descartadas = {}, [], []

    for v in visitas():
        dane = str(v.get("dane") or "").strip()
        if dane in sedes:
            continue
        info, como = buscar(v, por_sede, por_est, por_colegio)
        if not info:
            sin.append((v.get("colegio"), v.get("sede"), dane, como))
            continue
        # Guardia de localidad: si no coinciden, la dirección es de otro colegio.
        loc_v = norm(v.get("localidad"))
        if loc_v and loc_v != "EXTRA" and norm(info["loc"]) != loc_v:
            descartadas.append((v.get("colegio"), dane, v.get("localidad"), info["loc"], como))
            continue
        sedes[dane] = info

    SALIDA.write_text(
        "// sedes.js — dirección, barrio y coordenadas de cada sede visitada.\n"
        "// Generado por construir_sedes.py desde el directorio oficial de sedes de la SED.\n"
        "// La llave es el `dane` tal como viene en la agenda (14 dígitos: 12 del\n"
        "// establecimiento + 2 del consecutivo de la sede). No lleva datos de estudiantes.\n"
        "const SEDES = " + json.dumps(sedes, ensure_ascii=False, indent=1, sort_keys=True) + ";\n",
        encoding="utf-8")

    print(f"sedes con dirección:   {len(sedes)}")
    print(f"con coordenadas:       {sum(1 for x in sedes.values() if 'lat' in x)}")
    if descartadas:
        print(f"\n⛔ DESCARTADAS por localidad distinta ({len(descartadas)}) — "
              f"habrían mandado a la gente al colegio equivocado:")
        for col, d, lv, ld, como in descartadas:
            print(f"   {col}  ({d})  visita dice {lv} · directorio dice {ld}  [{como}]")
    if sin:
        print(f"\nsin dirección ({len(sin)}):")
        for col, sede, d, motivo in sin:
            print(f"   {col} / {sede} ({d}) — {motivo}")


if __name__ == "__main__":
    main()
