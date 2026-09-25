#!/usr/bin/env bash
# Saca la lista de acompañamientos CON los datos de contacto de cada persona.
# Esos datos NO salen por la página pública: solo por aquí.
#
#   ./exportar.sh            -> imprime en pantalla
#   ./exportar.sh salida.csv -> guarda en CSV
set -euo pipefail
SQL="select a.fecha, a.hora, a.localidad, a.colegio, a.sede, a.jornada, a.clase,
            p.nombre, p.dependencia, p.email, p.telefono, a.creado_at
     from sed_acompanamientos a join sed_personas p on p.email = a.email
     where a.estado = 'confirmado'
     order by a.fecha, a.hora, a.colegio;"
cd ~/oscar-personal-apps
if [ $# -ge 1 ]; then
  supabase db query --linked --output csv "$SQL" > "$OLDPWD/$1"
  echo "escrito: $1"
else
  supabase db query --linked "$SQL"
fi
