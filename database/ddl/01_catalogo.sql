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
    poster_url varchar(250),
    clasificacion_id bigint not null references clasificacion(id) on delete restrict, 
    fecha_estreno date,
    activa boolean not null default true,
    creado_en timestamptz not null default now(),
    constraint ck_pelicula_duracion check (duracion_min > 0)
); 

create table pelicula_genero (
    pelicula_id bigint not null references pelicula(id) on delete cascade,
    genero_id bigint not null references genero(id) on delete restrict,
    primary key (pelicula_id, genero_id)
);

-- ----------------------
-- Funciones (con no translape por sala)
-- ---------------------
create table funcion (
    id bigint generated always as identity primary key,
    pelicula_id bigint not null references pelicula(id) on delete restrict,
    sala_id bigint not null references sala(id) on delete restrict,
    inicio timestamptz not null,
    fin timestamptz not null,
    fin_limpieza timestamptz not null,
    estado varchar(20) not null default 'Activa',
    creado_en timestamptz not null default now(),
    constraint ck_funcion_estado check (estado in ('Activa', 'Cancelada', 'Finalizada')),
    constraint ck_funcion_fin check (fin >= inicio),
    constraint ck_funcion_fin_limpieza check (fin_limpieza >= fin), 
    constraint ex_funcion_sin_traslape 
        exclude using gist (sala_id with =, tstzrange(inicio, fin_limpieza) with &&)
        where (estado <> 'Cancelada')
);


-- ocupamos antes de seguir con otras funciones un trigger para que funcione la tabla anterior

create function trg_funcion_calcular_fin() returns trigger 
language plpgsql as $$
declare
    v_duracion integer;
    v_limpieza integer;
begin 
    select duracion_min into v_duracion from pelicula where id = new.pelicula_id;
    select minutos_limpieza into v_limpieza from sala where id = new.sala_id;
    if v_duracion is null or v_limpieza is null then 
        raise exception 'Película % o sala % inexistente',
            new.pelicula_id, new.sala_id;
    end if;
    new.fin := new.inicio + make_interval(mins => v_duracion);
    new.fin_limpieza := new.fin + make_interval(mins => v_limpieza);
    return new;
end $$; 

create trigger trg_funcion_calcular_fin
    before insert or update of pelicula_id, sala_id, inicio on funcion
    for each row execute function trg_funcion_calcular_fin();

-- ----------------------
-- tipos de entradas promociones tarifas entre otros precios
-- ----------------------

create table tipo_entrada(
    id bigint generated always as identity primary key,
    nombre varchar(50) not null unique,
    descripcion varchar(200),
    requiere_documento boolean not null default false
);

create table tarifa (
    id bigint generated always as identity primary key,
    tipo_entrada_id bigint not null references tipo_entrada(id) on delete restrict,
    zona_asiento_id bigint not null references zona_asiento(id) on delete restrict,
    dia_semana smallint, 
    hora_desde time not null default '00:00:00',
    hora_hasta time not null default '23:59:59',
    precio numeric(12,2) not null,
    cargo_servicio numeric(12,2) not null default 0,
    activa boolean not null default true,
    constraint ck_tarifa_dia check (dia_semana is null or dia_semana between 1 and 7),
    constraint ck_tarifa_horas check (hora_hasta > hora_desde),
    constraint ck_tarifa_precio check (precio >= 0),
    constraint ck_tarifa_cargo check (cargo_servicio >= 0)
);

create unique index uq_tarifa_combinacion  
    on tarifa (tipo_entrada_id, zona_asiento_id, coalesce(dia_semana, 0), hora_desde); 

create table promocion (
    id bigint generated always as identity primary key,
    nombre varchar(100) not null, 
    tipo varchar(10) not null default '2X1',
    dia_semana smallint,
    requiere_cantidad_par boolean not null default true,
    tipo_entrada_id bigint references tipo_entrada(id) on delete restrict,
    fecha_desde date,
    fecha_hasta date,
    activa boolean not null default true,
    constraint ck_promocion_tipo check (tipo in ('2X1')),
    constraint ck_promocion_dia check (dia_semana is null or dia_semana between 1 and 7),
    constraint ck_promocion_fechas check (fecha_hasta is null or fecha_desde is null or fecha_hasta >= fecha_desde),
    constraint ck_promocion_condicion check (dia_semana is not null or requiere_cantidad_par)
); 

-- ----------------------
-- usuarios y roles 
-- ---------------------- 

create table rol (
    id bigint generated always as identity primary key,
    nombre varchar(50) not null unique,
    descripcion varchar(200)
);

create table usuario (
    id bigint generated always as identity primary key,
    nombre varchar(100) not null,
    apellido varchar(100) not null,
    email varchar(150) not null,
    password_hash varchar(200) not null,
    telefono varchar(20),
    activo boolean not null default true,
    creado_en timestamptz not null default now(),
    constraint ck_usuario_email check (email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$')
);




