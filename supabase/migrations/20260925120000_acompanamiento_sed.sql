-- Acompanamiento SED · Encuesta de Clima de Aula (2026)
-- Aplicativo independiente: personal de la SED se apunta a acompanar las visitas.
-- Tablas propias con prefijo sed_. No toca las tablas clima_* ni arc_*.
--
-- RLS activo sin politicas: la anon key NO puede leer las tablas.
-- Todo pasa por sed_get / sed_post, que son SECURITY DEFINER.

create table if not exists public.sed_config (
  clave text primary key,
  valor text not null
);
insert into public.sed_config (clave, valor) values
  ('cupo_por_visita', '1'),
  ('dominios_permitidos', '.gov.co')
on conflict (clave) do nothing;

create table if not exists public.sed_personas (
  email       text primary key,
  nombre      text not null,
  dependencia text,
  equipo      text,
  telefono    text,
  localidades text[] not null default '{}',
  creado_at   timestamptz not null default now(),
  visto_at    timestamptz not null default now()
);

alter table public.sed_personas add column if not exists equipo text;

create table if not exists public.sed_acompanamientos (
  id           bigserial primary key,
  visita_id    text not null,
  fecha        date not null,
  hora         text not null,
  colegio      text,
  sede         text,
  localidad    text,
  jornada      text,
  clase        text,
  dane         text,
  email        text not null references public.sed_personas(email) on delete cascade,
  estado       text not null default 'confirmado' check (estado in ('confirmado','cancelado')),
  creado_at    timestamptz not null default now(),
  cancelado_at timestamptz
);

create unique index if not exists sed_acomp_unico
  on public.sed_acompanamientos (visita_id, email) where estado = 'confirmado';
create index if not exists sed_acomp_visita
  on public.sed_acompanamientos (visita_id) where estado = 'confirmado';
create index if not exists sed_acomp_email
  on public.sed_acompanamientos (email);

create table if not exists public.sed_log (
  id        bigserial primary key,
  ts        timestamptz not null default now(),
  accion    text not null,
  email     text,
  visita_id text,
  detalle   jsonb
);

alter table public.sed_config          enable row level security;
alter table public.sed_personas        enable row level security;
alter table public.sed_acompanamientos enable row level security;
alter table public.sed_log             enable row level security;

-- ---------------------------------------------------------------- lectura

create or replace function public.sed_get(p_email text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_email text := lower(trim(coalesce(p_email, '')));
  v_cupo  int  := coalesce((select valor::int from sed_config where clave = 'cupo_por_visita'), 2);
  v_apuntados jsonb;
  v_yo jsonb;
begin
  -- Quien acompana cada visita. Se devuelve el nombre y la dependencia,
  -- nunca el correo ni el telefono de otra persona.
  select coalesce(jsonb_object_agg(visita_id, gente), '{}'::jsonb) into v_apuntados
  from (
    select visita_id,
           jsonb_agg(jsonb_build_object(
             'nombre', p.nombre,
             'dependencia', p.dependencia,
             'equipo', p.equipo,
             'mio', (a.email = v_email and v_email <> '')
           ) order by a.creado_at) as gente
    from sed_acompanamientos a join sed_personas p on p.email = a.email
    where a.estado = 'confirmado'
    group by visita_id
  ) t;

  if v_email <> '' then
    -- Sin UPDATE aqui: sed_get se llama por GET y PostgREST abre la
    -- transaccion en solo lectura. visto_at se actualiza en 'registrar'.
    select to_jsonb(p) - 'creado_at' - 'visto_at' into v_yo
    from sed_personas p where p.email = v_email;
  end if;

  return jsonb_build_object(
    'ok', true,
    'cupo', v_cupo,
    'apuntados', v_apuntados,
    'yo', v_yo,
    'total_personas', (select count(*) from sed_personas),
    'total_cupos', (select count(*) from sed_acompanamientos where estado = 'confirmado')
  );
end $$;

-- ---------------------------------------------------------------- escritura

create or replace function public.sed_post(body jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_accion text := body->>'accion';
  v_email  text := lower(trim(coalesce(body->>'email', '')));
  v_nombre text := trim(coalesce(body->>'nombre', ''));
  v_visita text := trim(coalesce(body->>'visita_id', ''));
  v_dom    text := coalesce((select valor from sed_config where clave = 'dominios_permitidos'), '.gov.co');
  v_cupo   int  := coalesce((select valor::int from sed_config where clave = 'cupo_por_visita'), 2);
  v_fecha  date;
  v_hora   text;
  v_n      int;
  v_choque text;
begin
  if v_email = '' or position('@' in v_email) = 0 then
    return jsonb_build_object('ok', false, 'error', 'Falta el correo.');
  end if;
  if right(v_email, length(v_dom)) <> v_dom then
    return jsonb_build_object('ok', false,
      'error', 'Use su correo institucional (terminado en ' || v_dom || ').');
  end if;

  ------------------------------------------------------------------ registrar
  if v_accion = 'registrar' then
    if v_nombre = '' then
      return jsonb_build_object('ok', false, 'error', 'Falta el nombre.');
    end if;
    insert into sed_personas (email, nombre, dependencia, equipo, telefono, localidades)
    values (v_email, v_nombre, nullif(trim(coalesce(body->>'dependencia','')), ''),
            nullif(trim(coalesce(body->>'equipo','')), ''),
            nullif(trim(coalesce(body->>'telefono','')), ''),
            coalesce((select array_agg(x) from jsonb_array_elements_text(
                       coalesce(body->'localidades', '[]'::jsonb)) x), '{}'))
    on conflict (email) do update
      set nombre = excluded.nombre,
          dependencia = coalesce(excluded.dependencia, sed_personas.dependencia),
          equipo = coalesce(excluded.equipo, sed_personas.equipo),
          telefono = coalesce(excluded.telefono, sed_personas.telefono),
          localidades = excluded.localidades,
          visto_at = now();
    insert into sed_log (accion, email, detalle) values ('registrar', v_email, body);
    return jsonb_build_object('ok', true);
  end if;

  ------------------------------------------------------------------- apuntar
  if v_accion = 'apuntar' then
    if not exists (select 1 from sed_personas where email = v_email) then
      return jsonb_build_object('ok', false, 'error', 'Regístrese primero.');
    end if;
    if v_visita = '' then
      return jsonb_build_object('ok', false, 'error', 'Falta la visita.');
    end if;
    v_fecha := (body->>'fecha')::date;
    v_hora  := body->>'hora';

    perform pg_advisory_xact_lock(hashtext('sed_' || v_visita));

    select count(*) into v_n
    from sed_acompanamientos where visita_id = v_visita and estado = 'confirmado';
    if v_n >= v_cupo then
      return jsonb_build_object('ok', false, 'error',
        case when v_cupo = 1 then 'Esa visita ya tiene acompañante.'
             else 'Esa visita ya tiene sus acompañantes.' end);
    end if;

    -- una persona no puede estar en dos visitas a la misma hora
    select colegio into v_choque
    from sed_acompanamientos
    where email = v_email and estado = 'confirmado'
      and fecha = v_fecha and hora = v_hora and visita_id <> v_visita
    limit 1;
    if v_choque is not null then
      return jsonb_build_object('ok', false,
        'error', 'Ya está apuntado a esa misma hora en ' || v_choque || '.');
    end if;

    insert into sed_acompanamientos
      (visita_id, fecha, hora, colegio, sede, localidad, jornada, clase, dane, email)
    values (v_visita, v_fecha, v_hora, body->>'colegio', body->>'sede', body->>'localidad',
            body->>'jornada', body->>'clase', body->>'dane', v_email)
    on conflict do nothing;

    -- si habia una cancelada, se reactiva
    update sed_acompanamientos
      set estado = 'confirmado', cancelado_at = null, creado_at = now()
      where visita_id = v_visita and email = v_email and estado = 'cancelado'
        and not exists (select 1 from sed_acompanamientos b
                        where b.visita_id = v_visita and b.email = v_email
                          and b.estado = 'confirmado');

    insert into sed_log (accion, email, visita_id, detalle) values ('apuntar', v_email, v_visita, body);
    return jsonb_build_object('ok', true);
  end if;

  ------------------------------------------------------------------ cancelar
  if v_accion = 'cancelar' then
    update sed_acompanamientos
      set estado = 'cancelado', cancelado_at = now()
      where visita_id = v_visita and email = v_email and estado = 'confirmado';
    insert into sed_log (accion, email, visita_id, detalle) values ('cancelar', v_email, v_visita, body);
    return jsonb_build_object('ok', true);
  end if;

  return jsonb_build_object('ok', false, 'error', 'Acción desconocida.');
end $$;

revoke all on function public.sed_get(text)    from public;
revoke all on function public.sed_post(jsonb)  from public;
grant execute on function public.sed_get(text)   to anon, authenticated;
grant execute on function public.sed_post(jsonb) to anon, authenticated;
