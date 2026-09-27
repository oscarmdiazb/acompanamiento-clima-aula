#!/usr/bin/env bash
# Cuenta cuántas visitas siguen sin acompañante. Compara la agenda de reservas
# contra los acompañamientos confirmados. Úselo para saber a quién hay que empujar.
set -euo pipefail
K="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InN4ZmJ6Y25zYmN2aXRhZW53cGN0Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODkxNTUzODksImV4cCI6MjEwNDczMTM4OX0.AwTQ4lNfFQXEOWUcgOcyI3QUxsYP7-GFo7zuPkHuOJM"
U="https://sxfbzcnsbcvitaenwpct.supabase.co/rest/v1/rpc"
H=(-H "apikey: $K" -H "Authorization: Bearer $K")
curl -s "$U/api_get" "${H[@]}" > /tmp/_agenda.json
curl -s "$U/sed_get"  "${H[@]}" > /tmp/_acomp.json
/usr/bin/python3 - <<'PY'
import json, datetime
ag = json.load(open("/tmp/_agenda.json")); ac = json.load(open("/tmp/_acomp.json"))
hoy = datetime.datetime.now().strftime("%Y-%m-%d")
ap = ac.get("apuntados", {})
libres, total = [], 0
for slot, lista in ag.get("details", {}).items():
    fecha = slot.split(" ")[0]
    if fecha < hoy: continue
    for v in lista:
        if str(v.get("dane", "")).startswith("EXTRA"):
            continue                      # filas del operativo, no son de seguimiento
        total += 1
        vid = f"{slot}|{v['dane']}|{v['clase']}"
        if not ap.get(vid):
            libres.append((slot, v.get("localidad"), v.get("colegio")))
print(f"visitas por venir: {total}")
print(f"sin acompanante:   {len(libres)}\n")
for s, l, c in sorted(libres):
    print(f"  {s}  {l or '?':<22} {c}")
PY
