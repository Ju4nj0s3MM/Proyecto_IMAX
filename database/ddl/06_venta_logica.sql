-- 06 Lógica del módulo de venta: funciones transaccionales
-- Módulo B - Juan José Morales Montero
-- Requiere: 03_venta.sql y 03_venta_logs.sql

-- Libera los asientos cuyo bloqueo de 2 minutos ya venció.
-- Devuelve cuántos asientos se liberaron.
create function fn_liberar_expirados() returns integer
language plpgsql as $$
declare
    v_total integer;
begin
    -- por si el mes actual todavía no tiene partición en las bitácoras
    perform fn_crear_particiones_mes(current_date);

    -- bloqueos vencidos pasan a EXPIRADO y se anotan en la bitácora de asientos
    with vencidas as (
        update reserva_asiento
        set estado = 'EXPIRADO'
        where estado = 'BLOQUEADO' and bloqueado_hasta < now()
        returning orden_id, funcion_id, asiento_id
    )
    insert into asiento_auditoria_log (funcion_id, asiento_id, orden_id, estado_anterior, estado_nuevo)
    select funcion_id, asiento_id, orden_id, 'BLOQUEADO', 'EXPIRADO'
    from vencidas;
    get diagnostics v_total = row_count;

    -- las órdenes pendientes que se quedaron sin asientos pasan a EXPIRADA
    with ordenes as (
        update orden o
        set estado = 'EXPIRADA'
        where o.estado = 'PENDIENTE'
          and exists (select 1 from reserva_asiento r where r.orden_id = o.id and r.estado = 'EXPIRADO')
          and not exists (select 1 from reserva_asiento r where r.orden_id = o.id and r.estado in ('BLOQUEADO', 'VENDIDO'))
        returning o.id, o.usuario_id
    )
    insert into transaccion_log (orden_id, usuario_id, tipo, resultado)
    select id, usuario_id, 'EXPIRACION', 'EXPIRADA'
    from ordenes;

    return v_total;
end $$;

-- Mapa de la sala de una función: estado de cada asiento (DISPONIBLE, BLOQUEADO o VENDIDO).
-- Un bloqueo vencido se muestra como DISPONIBLE, aunque todavía no se haya liberado.
create function fn_mapa_asientos(p_funcion_id bigint)
returns table (asiento_id bigint, fila varchar, numero integer, zona varchar, estado varchar)
language sql stable as $$
    select a.id,
           a.fila,
           a.numero,
           z.nombre,
           case
               when r.estado = 'VENDIDO' then 'VENDIDO'
               when r.estado = 'BLOQUEADO' and r.bloqueado_hasta > now() then 'BLOQUEADO'
               else 'DISPONIBLE'
           end::varchar
    from funcion f
    join asiento a on a.sala_id = f.sala_id and a.activo
    join zona_asiento z on z.id = a.zona_asiento_id
    left join reserva_asiento r on r.funcion_id = f.id
                               and r.asiento_id = a.id
                               and r.estado in ('BLOQUEADO', 'VENDIDO')
    where f.id = p_funcion_id
    order by a.fila, a.numero;
$$;

-- Bloquea asientos de una función por 2 minutos para un usuario.
-- Crea la orden PENDIENTE y devuelve su id (reserva_id) y la hora en que vence el bloqueo.
-- Es atómica: si un asiento falla, no queda ninguno bloqueado ni orden creada.
create function fn_bloquear_asientos(p_usuario_id bigint, p_funcion_id bigint, p_asientos bigint[])
returns table (reserva_id bigint, expira_en timestamptz)
language plpgsql as $$
declare
    v_max constant integer := 6;            -- máximo de asientos por compra (RN-04)
    v_cantidad integer;
    v_validos integer;
    v_expira timestamptz := now() + interval '2 minutes';
    v_orden bigint;
    v_asiento bigint;
begin
    if p_asientos is null or cardinality(p_asientos) = 0 then
        raise exception 'Debe elegir al menos un asiento';
    end if;
    if cardinality(p_asientos) > v_max then
        raise exception 'Máximo % asientos por compra', v_max;
    end if;

    select count(distinct x) into v_cantidad from unnest(p_asientos) x;
    if v_cantidad <> cardinality(p_asientos) then
        raise exception 'Hay asientos repetidos en la selección';
    end if;

    -- la función debe estar activa y no haber empezado
    if not exists (select 1 from funcion where id = p_funcion_id and estado = 'Activa' and inicio > now()) then
        raise exception 'La función no está disponible para la venta';
    end if;

    -- todos los asientos deben ser de la sala de la función y estar activos
    select count(*) into v_validos
    from asiento a join funcion f on f.sala_id = a.sala_id
    where f.id = p_funcion_id and a.activo and a.id = any(p_asientos);
    if v_validos <> v_cantidad then
        raise exception 'Algún asiento no pertenece a la sala de la función';
    end if;

    -- libera lo vencido antes de intentar bloquear
    perform fn_liberar_expirados();

    insert into orden (usuario_id, funcion_id) values (p_usuario_id, p_funcion_id)
    returning id into v_orden;

    begin
        foreach v_asiento in array p_asientos loop
            insert into reserva_asiento (orden_id, funcion_id, asiento_id, bloqueado_hasta)
            values (v_orden, p_funcion_id, v_asiento, v_expira);
        end loop;
    exception when unique_violation then
        -- otro usuario tomó el asiento primero: se deshace todo
        raise exception 'Asiento no disponible: otro usuario lo tiene bloqueado o comprado';
    end;

    insert into asiento_auditoria_log (funcion_id, asiento_id, orden_id, usuario_id, estado_anterior, estado_nuevo)
    select p_funcion_id, x, v_orden, p_usuario_id, null, 'BLOQUEADO' from unnest(p_asientos) x;

    insert into transaccion_log (orden_id, usuario_id, tipo, resultado, detalle)
    values (v_orden, p_usuario_id, 'BLOQUEO', 'OK', cardinality(p_asientos) || ' asiento(s)');

    return query select v_orden, v_expira;
end $$;