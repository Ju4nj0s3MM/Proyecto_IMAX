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