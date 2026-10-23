-- 03_venta_logs.sql: bitácoras del módulo de venta (particionadas por mes)
-- Una bitácora nunca se modifica ni se borra, solo se agregan filas.

-- Registra cada cambio de estado de un asiento (bloqueado, vendido, liberado, expirado)
create table asiento_auditoria_log (
    id bigserial,
    funcion_id bigint not null,
    asiento_id bigint not null,
    orden_id bigint,
    usuario_id bigint,
    estado_anterior varchar(20),
    estado_nuevo varchar(20) not null,
    fecha timestamptz not null default now(),
    primary key (id, fecha)
) partition by range (fecha);

-- Una partición por mes
create table asiento_auditoria_log_2026_10 partition of asiento_auditoria_log
    for values from ('2026-10-01') to ('2026-11-01');
create table asiento_auditoria_log_2026_11 partition of asiento_auditoria_log
    for values from ('2026-11-01') to ('2026-12-01');
create table asiento_auditoria_log_2026_12 partition of asiento_auditoria_log
    for values from ('2026-12-01') to ('2027-01-01');

    -- Registra cada operación de dinero o de compra (bloqueo, pago, boleto, etc.)
create table transaccion_log (
    id bigserial,
    orden_id bigint,
    usuario_id bigint,
    tipo varchar(30) not null,
    monto numeric(12,2),
    resultado varchar(20),
    detalle varchar(200),
    fecha timestamptz not null default now(),
    primary key (id, fecha),
    check (tipo in ('BLOQUEO', 'PAGO', 'LIBERACION', 'EXPIRACION', 'EMISION_BOLETO', 'REEMBOLSO'))
) partition by range (fecha);
 
create table transaccion_log_2026_10 partition of transaccion_log
    for values from ('2026-10-01') to ('2026-11-01');
create table transaccion_log_2026_11 partition of transaccion_log
    for values from ('2026-11-01') to ('2026-12-01');
create table transaccion_log_2026_12 partition of transaccion_log
    for values from ('2026-12-01') to ('2027-01-01');


-- Las bitácoras solo se pueden agregar, no se modifican ni se borran
create function fn_bloquear_cambios_bitacora() returns trigger
language plpgsql as $$
begin
    raise exception 'La bitácora % no permite % (solo INSERT)', tg_table_name, tg_op;
end $$;
 
create trigger trg_asiento_auditoria_log_solo_insert
    before update or delete on asiento_auditoria_log
    for each row execute function fn_bloquear_cambios_bitacora();
 
create trigger trg_transaccion_log_solo_insert
    before update or delete on transaccion_log
    for each row execute function fn_bloquear_cambios_bitacora();