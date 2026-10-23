-- 03 esquema del módulo B: Venta, bloqueo de asientos, pago y boletos
-- Dueño de la rama/módulo: Juan José Morales Montero (rama Mod_ventas)
-- Se arma por partes: cada tabla es un commit
-- Requiere: database/ddl/01_catalogo.sql (funcion, asiento, tipo_entrada, usuario)
--                   =============================================================
-- Reglas que este script garantiza con restricciones (no con código de la aplicación):
--   RN-03/RN-05  un asiento no puede estar BLOQUEADO o VENDIDO dos veces para la misma función
--   RN-09        no existe ninguna columna para número de tarjeta ni CVV
--   RN-11/RN-12  el boleto (QR) es único y queda ligado de forma unívoca a función + asiento
--   RN-14        el boleto solo puede estar USADO si tiene la hora de uso (la validación atómica va en la función)
-- Los índices de rendimiento NO están aquí: van en 08_venta_indices.sql para poder medir con EXPLAIN ANALYZE
-- antes y después. Aquí solo están los índices que implementan una restricción de integridad.
 
-- ----------------------
-- Métodos de pago (el pago se SIMULA; no hay pasarela real)
-- ----------------------
create table metodo_pago (
    id bigint generated always as identity primary key,
    codigo varchar(30) not null unique,
    nombre varchar(60) not null,
    activo boolean not null default true
);
-- ----------------------
-- Orden: una compra de un usuario para UNA función. Mientras está PENDIENTE sus asientos están bloqueados.
-- ----------------------
create table orden (
    id bigint generated always as identity primary key,
    usuario_id bigint not null references usuario(id) on delete restrict,
    funcion_id bigint not null references funcion(id) on delete restrict,
    estado varchar(20) not null default 'PENDIENTE',
    subtotal numeric(12,2) not null default 0,
    descuento numeric(12,2) not null default 0,
    cargo_servicio numeric(12,2) not null default 0,
    total numeric(12,2) not null default 0,
    creada_en timestamptz not null default now(),
    pagada_en timestamptz,
    constraint ck_orden_estado check (estado in ('PENDIENTE', 'PAGADA', 'CANCELADA', 'EXPIRADA', 'REEMBOLSADA')),
    constraint ck_orden_montos check (subtotal >= 0 and descuento >= 0 and cargo_servicio >= 0 and total >= 0),
    -- RN-08: el total es exactamente la suma de tarifas, menos descuentos, más cargos por servicio
    constraint ck_orden_total check (total = subtotal - descuento + cargo_servicio),
    -- tiene fecha de pago si y solo si fue pagada (una reembolsada conserva la fecha en que se pagó)
    constraint ck_orden_pagada check ((estado in ('PAGADA', 'REEMBOLSADA')) = (pagada_en is not null)),
    -- permite que reserva_asiento apunte a (orden, función) y así nunca contradiga la función de su orden
    constraint uq_orden_id_funcion unique (id, funcion_id)
);
 