-- El equipo deja de ser texto libre (29-sep-2026).
--
-- Con 32 personas apuntadas ya había DIEZ maneras de escribir dos equipos:
-- «Promoción y prevención», «promoción y prevención», «PyP», «Equipo de
-- Promoción y prevención», «Promoción y Prevención OCE»… Así no se puede
-- agrupar nada, y la SED pidió la lista cerrada.
--
-- La lista vive en sed_config para poder cambiarla sin tocar la página.

insert into public.sed_config (clave, valor) values
  ('equipos', '["Promoción y Prevención","Aulas con Emoción","Atención y Seguimiento","Entornos","Monitoreo y Evaluación"]')
on conflict (clave) do update set valor = excluded.valor;

-- Se guarda lo que la persona escribió antes, por si hay que revisar.
alter table public.sed_acompanamientos add column if not exists equipo_raw text;
update public.sed_acompanamientos set equipo_raw = equipo where equipo_raw is null;

-- Normalización de lo ya registrado. «Equipo Oficina para la Convivencia
-- Escolar» es toda la oficina, no uno de los cinco equipos: queda marcado
-- como «Sin definir» para que alguien lo confirme, no se adivina.
update public.sed_acompanamientos set equipo = case
  when lower(unaccent_simple(equipo)) like '%promocion%'  then 'Promoción y Prevención'
  when lower(equipo) like '%pyp%'                          then 'Promoción y Prevención'
  when lower(unaccent_simple(equipo)) like '%atencion%'   then 'Atención y Seguimiento'
  when lower(unaccent_simple(equipo)) like '%emocion%'    then 'Aulas con Emoción'
  when lower(unaccent_simple(equipo)) like '%entorno%'    then 'Entornos'
  when lower(unaccent_simple(equipo)) like '%monitoreo%'  then 'Monitoreo y Evaluación'
  else 'Sin definir' end
where estado = 'confirmado';
