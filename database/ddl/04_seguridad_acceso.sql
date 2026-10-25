create table puerta (
    id bigint generated always as identity primary key,
    sala_id bigint not null references sala(id) on delete restrict,
    nombre varchar(60) not null,
    activa boolean not null default true,
    creado_en timestamptz not null default now(),
    constraint uq_puerta_sala_nombre unique (sala_id, nombre)
);

-- Indexar la llave foránea
create index idx_puerta_sala on puerta (sala_id);

create table admin_operacion_audit (
    id bigint generated always as identity,
    creado_en timestamptz not null default now(),
    usuario_id bigint not null references usuario(id) on delete restrict,
    rol_id bigint not null references rol(id) on delete restrict,
    ip inet not null,
    accion varchar(40) not null,
    tabla_afectada varchar(60),
    registro_id bigint,
    motivo varchar(300),
    detalle jsonb,
    constraint pk_admin_operacion_audit primary key (id, creado_en),
    constraint ck_admin_audit_accion check (accion in
        ('cortesia', 'cambio_asiento', 'reembolso_forzado', 'anulacion_venta',
         'cambio_precio', 'cambio_sala', 'cambio_rol', 'otro'))
) partition by range (creado_en);

create index idx_admin_audit_usuario on admin_operacion_audit (usuario_id, creado_en);
create index idx_admin_audit_fecha on admin_operacion_audit (creado_en);

-- Crear la partición mensual que contiene la fecha dada
create or replace function fn_crear_particion_admin_audit(p_mes date)
returns void
language plpgsql
as $$
declare
    v_desde date := date_trunc('month', p_mes)::date;
    v_hasta date := (date_trunc('month', p_mes) + interval '1 month')::date;
begin
    execute format(
        'create table if not exists %I partition of admin_operacion_audit
         for values from (%L) to (%L)',
        'admin_operacion_audit_' || to_char(v_desde, 'YYYYMM'), v_desde, v_hasta);
end;
$$;

select fn_crear_particion_admin_audit(m::date)
  from generate_series('2026-10-01'::date, '2027-12-01'::date, interval '1 month') m;

create table admin_operacion_audit_default partition of admin_operacion_audit default;

-- Bitácora inalterable: prohibir modificar o borrar filas
create or replace function trg_audit_inmutable() returns trigger
language plpgsql as $$
begin
    raise exception 'La bitácora de auditoría no permite % de registros', tg_op
        using errcode = '42501';
end;
$$;

create trigger trg_admin_audit_inmutable
    before update or delete on admin_operacion_audit
    for each row execute function trg_audit_inmutable();

    create table acceso_puerta_log (
    id bigint generated always as identity,
    fecha timestamptz not null default now(),
    boleto_id bigint,
    codigo_qr varchar(64) not null,
    puerta_id bigint,
    resultado varchar(10) not null,
    motivo varchar(60) not null,
    constraint pk_acceso_puerta_log primary key (id, fecha),
    constraint ck_acceso_resultado check (resultado in ('EXITOSO', 'RECHAZADO'))
) partition by range (fecha);

create index idx_acceso_log_boleto on acceso_puerta_log (boleto_id, fecha);
create index idx_acceso_log_puerta on acceso_puerta_log (puerta_id, fecha);

-- Una partición por mes, de octubre de 2026 a diciembre de 2027
do $$
declare
    v_mes date;
begin
    for v_mes in select generate_series('2026-10-01'::date, '2027-12-01'::date, interval '1 month')::date
    loop
        execute format(
            'create table %I partition of acceso_puerta_log for values from (%L) to (%L)',
            'acceso_puerta_log_' || to_char(v_mes, 'YYYYMM'), v_mes, (v_mes + interval '1 month')::date);
    end loop;
end;
$$;

create table acceso_puerta_log_default partition of acceso_puerta_log default;

create trigger trg_acceso_log_inmutable
    before update or delete on acceso_puerta_log
    for each row execute function trg_audit_inmutable();

create table reembolso (
    id bigint generated always as identity primary key,
    boleto_id bigint not null references boleto(id) on delete restrict,
    orden_id bigint not null references orden(id) on delete restrict,
    admin_id bigint not null references usuario(id) on delete restrict,
    monto numeric(12,2) not null,
    forzado boolean not null default false,
    motivo varchar(300) not null,
    creado_en timestamptz not null default now(),
    constraint uq_reembolso_boleto unique (boleto_id),
    constraint ck_reembolso_monto check (monto >= 0)
);

create index idx_reembolso_orden on reembolso (orden_id);
create index idx_reembolso_admin on reembolso (admin_id, creado_en);