-- El identificador de la visita deja de llevar la fecha adentro.
--
-- Antes: visita_id = '<slot>|<dane>|<clase>'  →  '2026-09-28 07:00|11100110787501|704'
-- Ahora: visita_id = '<dane>|<JORNADA>|<clase sin ceros>'  →  '11100110787501|TARDE|704'
--
-- Por qué: al reprogramar, `clima_reprogramar` solo cambia `slot` (dane/jornada/clase se
-- quedan igual), así que el identificador viejo cambiaba y el apuntado de la persona de la
-- SED quedaba huérfano: la fecha nueva salía «nadie apuntado» y quien se había apuntado
-- seguía viendo una fecha que ya nadie iba a hacer, sin que nadie le avisara.
-- Caso real el 28-sep-2026: Ciudadela Educativa de Bosa se movió del 28-sep al 13-oct y
-- Tania V se quedó colgada del 28-sep.
--
-- Efecto: el apuntado sigue al aula a donde sea que la muevan.
-- Además, fecha y hora se leen SIEMPRE en vivo de clima_reservas; lo guardado en
-- sed_acompanamientos queda solo como registro de cómo estaba al apuntarse.

-- Misma normalización que `llaveAula()` de index.html. El DANE se deja tal cual viene de
-- clima_reservas (el aplicativo manda unas veces 12 y otras 14, pero la reserva conserva
-- el suyo al reprogramar, así que la llave es estable).
create or replace function public.sed_llave_aula(p_dane text, p_jornada text, p_clase text)
returns text language sql immutable as $$
  select btrim(coalesce(p_dane, '')) || '|'
      || upper(btrim(coalesce(p_jornada, ''))) || '|'
      || coalesce(nullif(ltrim(btrim(coalesce(p_clase, '')), '0'), ''), '0')
$$;

-- Fecha y hora vivas de un aula, desde el aplicativo de reservas.
create or replace function public.sed_slot_vivo(p_dane text, p_jornada text, p_clase text)
returns text language sql stable as $$
  select min(slot) from clima_reservas
  where sed_llave_aula(dane, jornada, clase) = sed_llave_aula(p_dane, p_jornada, p_clase)
$$;

-- ---------------------------------------------------------------- reescribir lo que existe
do $$
declare v_dup int;
begin
  -- Si alguien se apuntó dos veces a la misma aula en slots distintos, el índice único
  -- (visita_id, lower(nombre)) chocaría. Se deja la más reciente y la otra se cancela.
  select count(*) into v_dup from (
    select sed_llave_aula(dane, jornada, clase) k, lower(nombre) n, count(*) c
    from sed_acompanamientos where estado = 'confirmado'
    group by 1, 2 having count(*) > 1) t;
  if v_dup > 0 then
    update sed_acompanamientos a set estado = 'cancelado', cancelado_at = now()
    where a.estado = 'confirmado' and exists (
      select 1 from sed_acompanamientos b
      where b.estado = 'confirmado'
        and sed_llave_aula(b.dane, b.jornada, b.clase) = sed_llave_aula(a.dane, a.jornada, a.clase)
        and lower(b.nombre) = lower(a.nombre) and b.creado_at > a.creado_at);
    raise notice 'se cancelaron apuntados repetidos en % aula(s)', v_dup;
  end if;
end $$;

update sed_acompanamientos
   set visita_id = sed_llave_aula(dane, jornada, clase)
 where dane is not null and btrim(dane) <> ''
   and visita_id <> sed_llave_aula(dane, jornada, clase);

-- ---------------------------------------------------------------- escritura
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

  -- El identificador SIEMPRE se deriva del aula, nunca se confía en el que mande la página:
  -- así una pestaña vieja en el celular de alguien tampoco puede volver a escribir un id
  -- con la fecha adentro.
  if coalesce(btrim(body->>'dane'), '') <> '' then
    v_visita := sed_llave_aula(body->>'dane', body->>'jornada', body->>'clase');
  elsif v_visita ~ '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}\|' then
    -- Compatibilidad: cancelar desde una pestaña vieja manda solo el id viejo, sin jornada.
    select visita_id into v_visita from sed_acompanamientos
     where dane = split_part(v_visita, '|', 2)
       and coalesce(nullif(ltrim(clase, '0'), ''), '0')
           = coalesce(nullif(ltrim(split_part(v_visita, '|', 3), '0'), ''), '0')
     order by creado_at desc limit 1;
    if v_visita is null then
      return jsonb_build_object('ok', false, 'error', 'Recargue la página e intente de nuevo.');
    end if;
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

    -- la hora que vale es la del aplicativo de reservas, no la que traiga la página
    v_hora  := coalesce(nullif(split_part(sed_slot_vivo(body->>'dane', body->>'jornada', body->>'clase'), ' ', 2), ''),
                        body->>'hora');
    v_fecha := coalesce(nullif(split_part(sed_slot_vivo(body->>'dane', body->>'jornada', body->>'clase'), ' ', 1), '')::date,
                        (body->>'fecha')::date);

    perform pg_advisory_xact_lock(hashtext('sed_' || v_visita));

    select count(*) into v_n
    from sed_acompanamientos where visita_id = v_visita and estado = 'confirmado';
    if v_n >= v_cupo then
      return jsonb_build_object('ok', false, 'error',
        case when v_cupo = 1 then 'Esa visita ya tiene acompañante.'
             else 'Esa visita ya tiene sus acompañantes.' end);
    end if;

    -- nadie puede estar en dos visitas a la misma hora; se compara contra el slot VIVO de
    -- cada una, porque el guardado se queda viejo en cuanto el colegio reprograma
    select colegio into v_choque
    from sed_acompanamientos
    where estado = 'confirmado'
      and visita_id <> v_visita
      and (token = v_token or lower(nombre) = lower(v_nombre))
      and coalesce(sed_slot_vivo(dane, jornada, clase), to_char(fecha, 'YYYY-MM-DD') || ' ' || hora)
          = to_char(v_fecha, 'YYYY-MM-DD') || ' ' || v_hora
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

-- ---------------------------------------------------------------- agenda (consola)
-- Devuelve la fecha y la hora VIVAS del aplicativo de reservas. Lo guardado en la fila queda
-- como `fecha_apuntada`: sirve para ver que la visita se movió después de que alguien se apuntó.
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
        'visita_id', a.visita_id,
        'fecha', coalesce(nullif(split_part(sed_slot_vivo(a.dane, a.jornada, a.clase), ' ', 1), ''),
                          to_char(a.fecha, 'YYYY-MM-DD')),
        'hora',  coalesce(nullif(split_part(sed_slot_vivo(a.dane, a.jornada, a.clase), ' ', 2), ''), a.hora),
        'fecha_apuntada', to_char(a.fecha, 'YYYY-MM-DD'),
        'sin_reserva', (sed_slot_vivo(a.dane, a.jornada, a.clase) is null),
        'dane', a.dane, 'jornada', a.jornada, 'clase', a.clase, 'colegio', a.colegio,
        'nombre', a.nombre, 'equipo', a.equipo, 'telefono', a.telefono,
        'creado_at', a.creado_at) order by a.fecha, a.hora)
      from sed_acompanamientos a where a.estado = 'confirmado'), '[]'::jsonb),
    'coordinadoras', coalesce((
      select jsonb_object_agg(nombre, coalesce(telefono, ''))
      from sed_coordinadoras), '{}'::jsonb)
  );
end $$;

revoke all on function public.sed_llave_aula(text, text, text) from public;
revoke all on function public.sed_slot_vivo(text, text, text) from public;
revoke all on function public.sed_post(jsonb) from public;
revoke all on function public.sed_agenda(text) from public;
grant execute on function public.sed_post(jsonb) to anon, authenticated;
grant execute on function public.sed_agenda(text) to anon, authenticated;
