-- Cambiar a la persona que acompaña una visita (16-oct-2026).
-- Nueva acción 'cambiar' en sed_post: cancela la fila de quien estaba e inserta la
-- de quien va, en la misma transacción y con el mismo candado de la visita.

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
  v_viejo  text := trim(coalesce(body->>'nombre_actual', ''));
  v_tok2   text := trim(coalesce(body->>'token_nuevo', ''));
  v_fila   bigint;
  v_antes  text;
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

  -- Cambiar a la persona que acompaña (16-oct-2026). Quien se apuntó no puede ir y
  -- otra persona va en su lugar. Lo puede hacer quien se apuntó (mismo navegador) o
  -- quien escriba el nombre de quien estaba, igual que para cancelar. La visita
  -- nunca queda libre en el medio, así que nadie más la toma mientras tanto.
  if v_accion = 'cambiar' then
    if v_visita = '' then
      return jsonb_build_object('ok', false, 'error', 'Falta la visita.');
    end if;
    if length(v_nombre) < 5 or position(' ' in v_nombre) = 0 then
      return jsonb_build_object('ok', false, 'error', 'Escriba el nombre y el apellido de quien va a ir.');
    end if;
    if not (v_lista ? v_equipo) then
      return jsonb_build_object('ok', false, 'error', 'Escoja el equipo de la lista.');
    end if;
    if length(regexp_replace(v_tel, '\D', '', 'g')) < 7 then
      return jsonb_build_object('ok', false, 'error', 'Escriba un número de contacto.');
    end if;

    perform pg_advisory_xact_lock(hashtext('sed_' || v_visita));

    select id, nombre, fecha, hora into v_fila, v_antes, v_fecha, v_hora
    from sed_acompanamientos
    where visita_id = v_visita and estado = 'confirmado'
      and (token = v_token or (v_viejo <> '' and lower(trim(nombre)) = lower(v_viejo)))
    order by (token = v_token) desc, creado_at
    limit 1;
    if v_fila is null then
      return jsonb_build_object('ok', false, 'error',
        'Ese no es el nombre de quien está apuntado. Escríbalo tal como aparece en la visita.');
    end if;
    if lower(v_antes) = lower(v_nombre) then
      return jsonb_build_object('ok', false, 'error', 'Esa persona ya es quien acompaña.');
    end if;

    select colegio into v_choque
    from sed_acompanamientos
    where estado = 'confirmado' and fecha = v_fecha and hora = v_hora
      and visita_id <> v_visita and lower(nombre) = lower(v_nombre)
    limit 1;
    if v_choque is not null then
      return jsonb_build_object('ok', false,
        'error', v_nombre || ' ya está apuntado a esa misma hora en ' || v_choque || '.');
    end if;

    update sed_acompanamientos
      set estado = 'cancelado', cancelado_at = now()
      where id = v_fila;
    insert into sed_acompanamientos
      (visita_id, fecha, hora, colegio, sede, localidad, jornada, clase, dane,
       nombre, equipo, equipo_raw, telefono, token)
    select visita_id, fecha, hora, colegio, sede, localidad, jornada, clase, dane,
           v_nombre, v_equipo, v_equipo, v_tel,
           case when v_tok2 <> '' then v_tok2 else v_token end
    from sed_acompanamientos where id = v_fila;

    insert into sed_log (accion, email, visita_id, detalle)
      values ('cambiar', v_nombre, v_visita,
              (body - 'token' - 'token_nuevo' - 'telefono') || jsonb_build_object('antes', v_antes));
    return jsonb_build_object('ok', true, 'antes', v_antes);
  end if;

  return jsonb_build_object('ok', false, 'error', 'Acción desconocida.');
end $$;

revoke all on function public.sed_post(jsonb) from public;
grant execute on function public.sed_post(jsonb) to anon, authenticated;
