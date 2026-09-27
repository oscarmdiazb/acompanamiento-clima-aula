-- Tercer dato al apuntarse: el celular de quien acompaña, para que la
-- coordinación lo tenga a la mano si hay un cambio de última hora.
--
-- NO se muestra en la página: es pública y un celular personal no puede quedar
-- a la vista de cualquiera con el enlace. Sale solo por exportar.sh.
--
-- Las filas anteriores a este cambio quedan con telefono nulo, a propósito.

alter table public.sed_acompanamientos add column if not exists telefono text;

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
       nombre, equipo, telefono, token)
    values (v_visita, v_fecha, v_hora, body->>'colegio', body->>'sede', body->>'localidad',
            body->>'jornada', body->>'clase', body->>'dane', v_nombre, v_equipo, v_tel, v_token)
    on conflict do nothing;

    -- el telefono nunca entra al log: no hace falta repetirlo ahi
    insert into sed_log (accion, email, visita_id, detalle)
      values ('apuntar', v_nombre, v_visita, body - 'token' - 'telefono');
    return jsonb_build_object('ok', true);
  end if;

  ------------------------------------------------------------------ cancelar
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

revoke all on function public.sed_post(jsonb) from public;
grant execute on function public.sed_post(jsonb) to anon, authenticated;
