-- La lista de equipos viaja a la página y el servidor la exige (29-sep-2026).

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
             'nombre', nombre, 'equipo', equipo,
             'mio', (token = v_tok and v_tok <> '')
           ) order by creado_at) as gente
    from sed_acompanamientos where estado = 'confirmado'
    group by visita_id
  ) t;

  select coalesce(jsonb_object_agg(nombre, telefono), '{}'::jsonb) into v_co
  from sed_coordinadoras where rol = 'coordinadora' and coalesce(telefono, '') <> '';

  select to_jsonb(x) into v_re from (
    select nombre, telefono, coalesce(nota, 'Coordinador de campo') as nota
    from sed_coordinadoras where rol = 'campo' and coalesce(telefono, '') <> ''
    order by nombre limit 1) x;

  return jsonb_build_object(
    'ok', true,
    'cupo', v_cupo,
    'apuntados', v_ap,
    'coordinadoras', v_co,
    'respaldo', v_re,
    'equipos', coalesce((select valor::jsonb from sed_config where clave = 'equipos'), '[]'::jsonb),
    'total_cupos', (select count(*) from sed_acompanamientos where estado = 'confirmado')
  );
end $$;

create or replace function public.sed_post(body jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_accion text := body->>'accion';
  v_visita text := trim(coalesce(body->>'visita_id', ''));
  v_nombre text := trim(coalesce(body->>'nombre', ''));
  v_equipo text := trim(coalesce(body->>'equipo', ''));
  v_tel    text := trim(coalesce(body->>'telefono', ''));
  v_token  text := trim(coalesce(body->>'token', ''));
  v_cupo   int  := coalesce((select valor::int from sed_config where clave = 'cupo_por_visita'), 1);
  v_lista  jsonb := coalesce((select valor::jsonb from sed_config where clave = 'equipos'), '[]'::jsonb);
  v_fecha  date;
  v_hora   text;
  v_n      int;
  v_choque text;
begin
  if v_token = '' then
    return jsonb_build_object('ok', false, 'error', 'Recargue la página e intente de nuevo.');
  end if;

  if v_accion = 'apuntar' then
    if v_visita = '' then
      return jsonb_build_object('ok', false, 'error', 'Falta la visita.');
    end if;
    if length(v_nombre) < 5 or position(' ' in v_nombre) = 0 then
      return jsonb_build_object('ok', false, 'error', 'Escriba su nombre y su apellido.');
    end if;
    -- el equipo tiene que ser uno de la lista: si no, no se puede agrupar nada
    if not (v_lista ? v_equipo) then
      return jsonb_build_object('ok', false, 'error', 'Escoja su equipo de la lista.');
    end if;
    if length(regexp_replace(v_tel, '\D', '', 'g')) < 7 then
      return jsonb_build_object('ok', false, 'error', 'Escriba un número de contacto.');
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
       nombre, equipo, equipo_raw, telefono, token)
    values (v_visita, v_fecha, v_hora, body->>'colegio', body->>'sede', body->>'localidad',
            body->>'jornada', body->>'clase', body->>'dane', v_nombre, v_equipo, v_equipo,
            v_tel, v_token)
    on conflict do nothing;

    insert into sed_log (accion, email, visita_id, detalle)
      values ('apuntar', v_nombre, v_visita, body - 'token' - 'telefono');
    return jsonb_build_object('ok', true);
  end if;

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
      values ('cancelar', v_nombre, v_visita, body - 'token' - 'telefono');
    return jsonb_build_object('ok', true);
  end if;

  return jsonb_build_object('ok', false, 'error', 'Acción desconocida.');
end $$;

revoke all on function public.sed_get(text)   from public;
revoke all on function public.sed_post(jsonb) from public;
grant execute on function public.sed_get(text)   to anon, authenticated;
grant execute on function public.sed_post(jsonb) to anon, authenticated;
