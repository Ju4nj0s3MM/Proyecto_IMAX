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