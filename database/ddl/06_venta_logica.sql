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