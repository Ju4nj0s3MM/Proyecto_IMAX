-- 01 esquema del catalogo en sql ... Módulo A : Catalogo, salas, programación y tatifas 
-- Además se le agregan las tablas de usuarios y roles para que los demás miembros trabajen con estas tablas
-- Dueño de la rama/módulo: Matias Esquivel Lizano 
-- Fecha de creación domingo 18 de octubre del 2026 / Hora: 22:22
--                  =============================================================

create extension if not exists btree_gist; 


-- --------------
-- Primeras tablas: Cines, salas, zonas y asientos 
-- --------------

create table cine (
    id bigint generated always as identity primary key,
    nombre varchar(100) not null,
    direccion varchar(250) not null,
    ciudad varchar(100) not null,
    pais varchar(50) not null default 'Costa Rica',
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
    nombre varchar(60) not null,
    capacidad integer not null,
    minutos_limpieza integer not null default 20, 
    activa boolean not null default true,
    creado_en timestamptz not null default now(),
    constraint uq_sala_cine_nombre unique (cine_id, nombre),
    constraint ck_sala_capacidad check (capacidad > 0),
    constraint ck_sala_limpieza check (minutos_limpieza >= 0)
); 

create table zona_asiento (
    id bigint generated always as identity primary key,
    nombre varchar(40) not null unique, 
    descripcion varchar(200)
); 

create table asiento ( 
    id bigint generated always as identity primary key,
    sala_id bigint not null references sala(id) on delete restrict,
    zona_asiento_id bigint not null references zona_asiento(id) on delete restrict,
    fila varchar(5) not null, 
    numero integer not null,
    activo boolean not null default true,
    constraint uq_asiento_sala_fila_numero unique (sala_id, fila, numero),
    constraint ck_asiento_numero check (numero > 0)
); 

-- ----------------------
-- Películas, clasificacion y géneros
-- ----------------------

create table clasificacion (
    id bigint generated always as identity primary key, 
    codigo varchar(10) not null unique, 
    descripcion varchar(200) not null,
    edad_minima integer not null default 0,
    constraint ck_clasificacion_edad check (edad_minima >= 0)
); 

create table genero (
    id bigint generated always as identity primary key, 
    nombre varchar(50)not null unique
); 

create table pelicula (
    id bigint generated always as identity primary key, 
    titulo varchar(200) not null, 
    sinopsis text not null,
    duracion_min integer not null,
    porter_url varchar(250),
    clasificacion_id bigint not null references clasificacion(id) on delete restrict, 
    fecha_estreno date,
    activa boolean not null default true,
    creado_en timestamptz not null default now(),
    constraint ck_pelicula_duracion check (duracion_min > 0)
); 