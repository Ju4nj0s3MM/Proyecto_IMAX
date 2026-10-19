-- 01 esquema del catalogo en sql ... Módulo A : Catalogo, salas, programación y tatifas 
-- Además se le agregan las tablas de usuarios y roles para que los demás miembros trabajen con estas tablas
-- Dueño de la rama/módulo: Matias Esquivel Lizano 
-- Fecha de creación domingo 18 de octubre del 2026 / Hora: 22:22
--                  =============================================================

create extension if not eexists btree_gist; 


-- --------------
-- Primeras tablas: Cines, salas, zonas y asientos 
-- --------------

create table cine (
    id bigint generated always as identity primary key,
    nombre varchar(100) not null,
    direccion varchar(250) not null,
    ciudad varchar(100) not null,
    pais varchat(50) not null default 'Costa Rica',
    latitud numeric(9,6),
    longitud numeric(9,6), 
    activo boolean not null default true,
    creado_en timestamptz not null default now(),
    constraint uq_cine_nombre_ciudad unique (nombre, ciudad),
    constraint ck_cine_latitud check (latitud is null or latitud between -90 and 90),
    constraint ck_cine_longitud check (longitud is null or longitud between -180 and 180)
);

create table sala (
    id bigint generated always as identity primary key, 
    cine_id bigint not null references cine(id) on delete restrict,
    nombre varchat(60) not null,
    capacidad integer not null,
    minutos_limpieza integer not null default 20, 
    activa boolean not null default true,
    creado_en timestamptz not null default now(),
    constraint uq_sala_cine_nombre unique (cine_id, nombre),
    constraint ck_sala_capacidad check (capacidad > 0),
    constraint ck_sala_limpieza check (minutos_limpieza >= 0)
); 
