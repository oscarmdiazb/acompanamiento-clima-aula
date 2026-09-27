#!/usr/bin/env bash
# Publica el sitio.
#
# Sube el ?v= de los <script> a la fecha y hora de hoy antes de empujar. Sin eso,
# un navegador que ya abrió la página sigue sirviendo su copia vieja de sedes.js
# y muestra colegios sin dirección. Ya pasó una vez.
#
#   ./publicar.sh "Mensaje del commit"
set -euo pipefail
cd "$(dirname "$0")"
V=$(date +%Y%m%d%H%M)
sed -i '' -E "s|(<script src=\"[^\"]+\.js)\?v=[0-9]+\"|\1?v=${V}\"|g" index.html
git add -A
if git diff --cached --quiet; then echo "nada que publicar"; exit 0; fi
git commit -q -m "${1:-Actualización del sitio}

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
git push -q origin main
echo "publicado · https://oscarmdiazb.github.io/acompanamiento-clima-aula/   (v=$V)"
