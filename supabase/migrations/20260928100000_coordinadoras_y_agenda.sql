-- Dos cosas (28-sep-2026):
--
-- 1. La persona que se apunta tiene que saber a quién llamar si la visita se
--    cancela o pasa algo: se muestra la COORDINADORA de esa visita y su celular.
--    El nombre ya existe en clima_facilitadores (Ana María, Andrea, Daniela,
--    Diana); el teléfono no existía en ninguna parte, así que se crea aquí.
--    Estos teléfonos SÍ son públicos: son el contacto de trabajo del rol y salen
--    en la página, que es el punto.
--
-- 2. La consola del equipo necesita ver quién de la SED acompaña cada visita,
--    CON su celular. Eso no puede salir por la anon key, así que va por una
--    función aparte con clave compartida, igual que ?tipo=contactos de clima2026.

create table if not exists public.sed_coordinadoras (
  nombre     text primary key,     -- tal como aparece en clima_facilitadores
  telefono   text,
  nota       text,
  updated_at timestamptz not null default now()
);
alter table public.sed_coordinadoras enable row level security;

-- Se siembran las cuatro que hoy tienen visitas, sin teléfono todavía.
insert into public.sed_coordinadoras (nombre) values
  ('Ana María'), ('Andrea'), ('Daniela'), ('Diana')
on conflict (nombre) do nothing;

-- Clave para la consola. Este repo es PÚBLICO, así que aquí solo queda un
-- marcador: la clave real se pone a mano y se guarda en
-- Encuesta/seguimiento_largo_plazo_r1r2/seguimiento/.sed_key (modo 600, fuera de git).
--
--   update sed_config set valor = '<clave nueva>' where clave = 'clave_agenda';
insert into public.sed_config (clave, valor)
values ('clave_agenda', 'PONER-CLAVE-REAL')
on conflict (clave) do nothing;

-- ---------------------------------------------------------------- lectura

create or replace function public.sed_get(p_token text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_tok  text := trim(coalesce(p_token, ''));
  v_cupo int  := coalesce((select valor::int from sed_config where clave = 'cupo_por_visita'), 1);
  v_ap   jsonb;
  v_co   jsonb;
begin
  -- Quien acompaña cada visita: nombre y equipo. Ni el token ni el celular salen.
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
  from sed_coordinadoras where coalesce(telefono, '') <> '';

  return jsonb_build_object(
    'ok', true,
    'cupo', v_cupo,
    'apuntados', v_ap,
    'coordinadoras', v_co,
    'total_cupos', (select count(*) from sed_acompanamientos where estado = 'confirmado')
  );
end $$;

-- ------------------------------------------------- agenda completa (consola)

create or replace function public.sed_agenda(p_clave text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_ok boolean;
begin
  select p_clave = valor into v_ok from sed_config where clave = 'clave_agenda';
  if not coalesce(v_ok, false) then
    return jsonb_build_object('ok', false, 'error', 'clave incorrecta');
  end if;
  return jsonb_build_object(
    'ok', true,
    'acompanamientos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'visita_id', visita_id, 'fecha', fecha, 'hora', hora,
        'dane', dane, 'jornada', jornada, 'clase', clase, 'colegio', colegio,
        'nombre', nombre, 'equipo', equipo, 'telefono', telefono,
        'creado_at', creado_at) order by fecha, hora)
      from sed_acompanamientos where estado = 'confirmado'), '[]'::jsonb),
    'coordinadoras', coalesce((
      select jsonb_object_agg(nombre, coalesce(telefono, ''))
      from sed_coordinadoras), '{}'::jsonb)
  );
end $$;

revoke all on function public.sed_get(text)    from public;
revoke all on function public.sed_agenda(text) from public;
grant execute on function public.sed_get(text)    to anon, authenticated;
grant execute on function public.sed_agenda(text) to anon, authenticated;
