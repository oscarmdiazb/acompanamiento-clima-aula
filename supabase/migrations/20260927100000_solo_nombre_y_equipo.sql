-- Simplificación (27-sep-2026): la página ya no pide registro previo.
-- Se entra directo al calendario, se escoge la cita y solo entonces se piden
-- DOS datos: nombre completo y equipo.
--
-- Se va el correo, y con él la tabla sed_personas. Quien se apunta queda
-- identificado por su nombre; para poder cancelar, el navegador guarda un
-- token propio que viaja con cada acción.
--
-- La base estaba vacía cuando se aplicó esto, así que se rehace limpia.

drop function if exists public.sed_get(text);
drop function if exists public.sed_post(jsonb);
drop table   if exists public.sed_acompanamientos;
drop table   if exists public.sed_personas;

create table public.sed_acompanamientos (
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
  nombre       text not null,
  equipo       text not null,
  token        text not null,          -- identifica el navegador, para cancelar
  estado       text not null default 'confirmado' check (estado in ('confirmado','cancelado')),
  creado_at    timestamptz not null default now(),
  cancelado_at timestamptz
);

-- la misma persona no puede quedar dos veces en la misma visita
create unique index sed_acomp_unico
  on public.sed_acompanamientos (visita_id, lower(nombre)) where estado = 'confirmado';
create index sed_acomp_visita on public.sed_acompanamientos (visita_id) where estado = 'confirmado';
create index sed_acomp_token  on public.sed_acompanamientos (token);

alter table public.sed_acompanamientos enable row level security;

-- ---------------------------------------------------------------- lectura

create or replace function public.sed_get(p_token text default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_tok  text := trim(coalesce(p_token, ''));
  v_cupo int  := coalesce((select valor::int from sed_config where clave = 'cupo_por_visita'), 1);
  v_ap   jsonb;
begin
  -- Quien acompaña cada visita: nombre y equipo. El token nunca sale.
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

  return jsonb_build_object(
    'ok', true,
    'cupo', v_cupo,
    'apuntados', v_ap,
    'total_cupos', (select count(*) from sed_acompanamientos where estado = 'confirmado')
  );
end $$;

-- ---------------------------------------------------------------- escritura

create or replace function public.sed_post(body jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_accion text := body->>'accion';
  v_visita text := trim(coalesce(body->>'visita_id', ''));
  v_nombre text := trim(coalesce(body->>'nombre', ''));
  v_equipo text := trim(coalesce(body->>'equipo', ''));
  v_token  text := trim(coalesce(body->>'token', ''));
  v_cupo   int  := coalesce((select valor::int from sed_config where clave = 'cupo_por_visita'), 1);
  v_fecha  date;
  v_hora   text;
  v_n      int;
  v_choque text;
begin
  if v_token = '' then
    return jsonb_build_object('ok', false, 'error', 'Recargue la página e intente de nuevo.');
  end if;

  ------------------------------------------------------------------- apuntar
  if v_accion = 'apuntar' then
    if v_visita = '' then
      return jsonb_build_object('ok', false, 'error', 'Falta la visita.');
    end if;
    if length(v_nombre) < 5 or position(' ' in v_nombre) = 0 then
      return jsonb_build_object('ok', false, 'error', 'Escriba su nombre y su apellido.');
    end if;
    if v_equipo = '' then
      return jsonb_build_object('ok', false, 'error', 'Falta el equipo.');
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

    -- nadie puede estar en dos visitas a la misma hora
    select colegio into v_choque
    from sed_acompanamientos
    where estado = 'confirmado' and fecha = v_fecha and hora = v_hora
      and visita_id <> v_visita
      and (token = v_token or lower(nombre) = lower(v_nombre))
    limit 1;
    if v_choque is not null then
      return jsonb_build_object('ok', false,
        'error', 'Ya está apuntado a esa misma hora en ' || v_choque || '.');
    end if;

    insert into sed_acompanamientos
      (visita_id, fecha, hora, colegio, sede, localidad, jornada, clase, dane,
       nombre, equipo, token)
    values (v_visita, v_fecha, v_hora, body->>'colegio', body->>'sede', body->>'localidad',
            body->>'jornada', body->>'clase', body->>'dane', v_nombre, v_equipo, v_token)
    on conflict do nothing;

    insert into sed_log (accion, email, visita_id, detalle)
      values ('apuntar', v_nombre, v_visita, body - 'token');
    return jsonb_build_object('ok', true);
  end if;

  ------------------------------------------------------------------ cancelar
  -- Cancela quien se apuntó desde este navegador, o quien escriba el mismo
  -- nombre (por si cambió de equipo o de teléfono).
  if v_accion = 'cancelar' then
    update sed_acompanamientos
      set estado = 'cancelado', cancelado_at = now()
      where visita_id = v_visita and estado = 'confirmado'
        and (token = v_token or (v_nombre <> '' and lower(nombre) = lower(v_nombre)));
    if not found then
      return jsonb_build_object('ok', false,
        'error', 'Esa visita la tomó otra persona. Solo quien se apuntó puede cancelar.');
    end if;
    insert into sed_log (accion, email, visita_id, detalle)
      values ('cancelar', v_nombre, v_visita, body - 'token');
    return jsonb_build_object('ok', true);
  end if;

  return jsonb_build_object('ok', false, 'error', 'Acción desconocida.');
end $$;

revoke all on function public.sed_get(text)   from public;
revoke all on function public.sed_post(jsonb) from public;
grant execute on function public.sed_get(text)   to anon, authenticated;
grant execute on function public.sed_post(jsonb) to anon, authenticated;
