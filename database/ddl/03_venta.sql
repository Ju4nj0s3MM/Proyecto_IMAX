-- 03 Módulo de venta: órdenes, asientos bloqueados, pagos y boletos
-- Módulo B - Juan José Morales Montero
-- Requiere 01_catalogo.sql (funcion, asiento, tipo_entrada, usuario)
-- Los índices para mejorar rendimiento van aparte, en 08_venta_indices.sql
 
-- Métodos de pago (el pago es simulado, no hay pasarela real)
create table metodo_pago (
    id bigserial primary key,
    codigo varchar(30) not null unique,
    nombre varchar(60) not null,
    activo boolean not null default true
);
 
-- Una compra de un usuario para una función.
-- Mientras está PENDIENTE sus asientos están bloqueados.
create table orden (
    id bigserial primary key,
    usuario_id bigint not null references usuario(id),
    funcion_id bigint not null references funcion(id),
    estado varchar(20) not null default 'PENDIENTE',
    subtotal numeric(12,2) not null default 0,
    descuento numeric(12,2) not null default 0,
    cargo_servicio numeric(12,2) not null default 0,
    total numeric(12,2) not null default 0,
    creada_en timestamptz not null default now(),
    pagada_en timestamptz,
    check (estado in ('PENDIENTE', 'PAGADA', 'CANCELADA', 'EXPIRADA', 'REEMBOLSADA')),
    check (total = subtotal - descuento + cargo_servicio)
);
 
-- Un asiento tomado por una orden
create table reserva_asiento (
    id bigserial primary key,
    orden_id bigint not null references orden(id),
    funcion_id bigint not null references funcion(id),
    asiento_id bigint not null references asiento(id),
    tipo_entrada_id bigint references tipo_entrada(id),
    estado varchar(20) not null default 'BLOQUEADO',
    bloqueado_hasta timestamptz not null,
    precio numeric(12,2),
    cargo_servicio numeric(12,2),
    descuento numeric(12,2) not null default 0,
    creada_en timestamptz not null default now(),
    check (estado in ('BLOQUEADO', 'VENDIDO', 'LIBERADO', 'EXPIRADO'))
);
 
-- Evita la doble venta: un asiento no puede estar BLOQUEADO o VENDIDO
-- dos veces en la misma función. Si está LIBERADO o EXPIRADO se puede volver a tomar.
create unique index uq_asiento_activo
    on reserva_asiento (funcion_id, asiento_id)
    where estado in ('BLOQUEADO', 'VENDIDO');
 
-- Pago simulado. No se guarda número de tarjeta ni CVV, solo los últimos 4 dígitos.
create table pago (
    id bigserial primary key,
    orden_id bigint not null references orden(id),
    metodo_pago_id bigint not null references metodo_pago(id),
    monto numeric(12,2) not null,
    resultado varchar(10) not null,
    referencia varchar(60),
    ultimos4 char(4),
    creado_en timestamptz not null default now(),
    check (resultado in ('APROBADO', 'RECHAZADO'))
);
 
-- Una orden solo puede tener un pago aprobado (los rechazados pueden ser varios)
create unique index uq_pago_aprobado
    on pago (orden_id)
    where resultado = 'APROBADO';
 
-- Boleto: solo se crea después de un pago aprobado
create table boleto (
    id bigserial primary key,
    orden_id bigint not null references orden(id),
    reserva_asiento_id bigint not null unique references reserva_asiento(id),
    funcion_id bigint not null references funcion(id),
    asiento_id bigint not null references asiento(id),
    codigo_qr varchar(64) not null unique,
    estado varchar(10) not null default 'EMITIDO',
    emitido_en timestamptz not null default now(),
    usado_en timestamptz,
    check (estado in ('EMITIDO', 'USADO', 'ANULADO'))
);