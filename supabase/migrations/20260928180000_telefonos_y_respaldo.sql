-- Teléfonos de las coordinadoras y respaldo de campo (28-sep-2026).
--
-- Los números son de trabajo y SÍ salen en la página, que es pública: es el
-- punto, la persona que se apunta tiene que poder escribirles.
--
-- `rol`: 'coordinadora' = coordina esa visita (el nombre cruza con
-- clima_facilitadores). 'campo' = respaldo, a quien se escribe si la
-- coordinadora no contesta. Hoy solo Rei.

alter table public.sed_coordinadoras add column if not exists rol text not null default 'coordinadora';

insert into public.sed_coordinadoras (nombre, telefono, rol) values
  ('Ana María', '+57 310 5810876', 'coordinadora'),
  ('Andrea',    '+57 322 4373961', 'coordinadora'),
  ('Daniela',   '+57 315 2691190', 'coordinadora'),
  ('Diana',     '+57 300 4927218', 'coordinadora'),
  ('Rei',       '+57 314 2287378', 'campo')
on conflict (nombre) do update
  set telefono = excluded.telefono, rol = excluded.rol, updated_at = now();

update public.sed_coordinadoras set nota = 'Coordinador de campo' where nombre = 'Rei';

create or replace function public.sed_get(p_token text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_tok  text := trim(coalesce(p_token, ''));
  v_cupo int  := coalesce((select valor::int from sed_config where clave = 'cupo_por_visita'), 1);
  v_ap   jsonb;
  v_co   jsonb;
  v_re   jsonb;
begin
  select coalesce(jsonb_object_agg(visita_id, gente), '{}'::jsonb) into v_ap
  from (
    select visita_id,
           jsonb_agg(jsonb_build_object(
             'nombre', nombre,
             'equipo', equipo,
             'mio', (token = v_tok and v_tok <> '')
           ) order by creado_at) as gente
    from sed_acompanamientos where estado = 'confirmado'
    group by visita_id
  ) t;

  -- Coordinadoras: nombre -> teléfono. Solo las que ya tienen número.
  select coalesce(jsonb_object_agg(nombre, telefono), '{}'::jsonb) into v_co
  from sed_coordinadoras
  where rol = 'coordinadora' and coalesce(telefono, '') <> '';

  -- Respaldo de campo: a quién escribir si la coordinadora no contesta.
  select to_jsonb(x) into v_re from (
    select nombre, telefono, coalesce(nota, 'Coordinador de campo') as nota
    from sed_coordinadoras
    where rol = 'campo' and coalesce(telefono, '') <> ''
    order by nombre limit 1) x;

  return jsonb_build_object(
    'ok', true,
    'cupo', v_cupo,
    'apuntados', v_ap,
    'coordinadoras', v_co,
    'respaldo', v_re,
    'total_cupos', (select count(*) from sed_acompanamientos where estado = 'confirmado')
  );
end $$;

revoke all on function public.sed_get(text) from public;
grant execute on function public.sed_get(text) to anon, authenticated;
