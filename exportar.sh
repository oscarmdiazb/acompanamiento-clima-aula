#!/usr/bin/env bash
# Saca la lista de acompañamientos: quién acompaña cada visita, de qué equipo.
#
#   ./exportar.sh            -> imprime en pantalla
#   ./exportar.sh salida.csv -> guarda en CSV
#
# Ojo: la página solo pide nombre y equipo. No hay correo ni celular de nadie;
# para contactar a alguien hay que pasar por su equipo.
set -euo pipefail
SQL="select fecha, hora, localidad, colegio, sede, jornada, clase, nombre, equipo, creado_at
     from sed_acompanamientos
     where estado = 'confirmado'
     order by fecha, hora, colegio;"
cd ~/oscar-personal-apps
if [ $# -ge 1 ]; then
  supabase db query --linked --output csv "$SQL" > "$OLDPWD/$1"
  echo "escrito: $1"
else
  supabase db query --linked "$SQL"
fi
