\encoding UTF8
-- 04 Pruebas del proyecto
-- Cada grupo de pruebas se corre en una base nueva, copiada de imax_base (DDL + seed del catálogo),
-- porque las pruebas usan ids fijos y no se pueden mezclar entre sí.
-- Ejecutar con psql conectado a la base postgres (o cualquier otra) con un usuario que pueda crear bases:
--   psql -U postgres -d postgres -f 04_tests.sql
-- Las líneas "Resultado esperado" dicen qué debe pasar en cada prueba. Al final se borran las bases temporales.

\set ON_ERROR_STOP off
\pset pager off

\c postgres
\encoding UTF8
drop database if exists imax_prueba;
drop database if exists imax_base;
create database imax_base;
\c imax_base
\encoding UTF8

-- 01 DDL completo: tablas, funciones, triggers, roles e índices
-- Unión de los scripts de database/ en el orden de ejecución. Los archivos originales siguen en sus carpetas.


-- =====================================================================
-- database/ddl/01_catalogo.sql
-- =====================================================================
-- 01 esquema del catalogo en sql ... Módulo A : Catalogo, salas, programación y tatifas 
-- Además se le agregan las tablas de usuarios y roles para que los demás miembros trabajen con estas tablas
-- Dueño de la rama/módulo: Matias Esquivel Lizano 
-- Fecha de creación domingo 18 de octubre del 2026 / Hora: 22:22
--                  =============================================================

create extension if not exists btree_gist; 
create extension if not exists pgcrypto;   -- crypt()/gen_salt() para guardar password_hash (bcrypt) dentro de la BD


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

create unique index uq_usuario_email on usuario(lower(email)); 

create table usuario_rol (
    usuario_id bigint not null references usuario(id) on delete cascade,
    rol_id bigint not null references rol(id) on delete restrict,
    asignado_en timestamptz not null default now(),
    asignado_por bigint references usuario(id) on delete set null,
    primary key (usuario_id, rol_id)
); 






-- =====================================================================
-- database/ddl/02_seguridad_usuarios.sql
-- =====================================================================
create extension if not exists pgcrypto;

alter table usuario
    add column intentos_fallidos integer not null default 0,
    add column bloqueado_hasta timestamptz,
    add column ultimo_login timestamptz;

alter table usuario
    add constraint ck_usuario_intentos check (intentos_fallidos >= 0),
    -- Exigir formato bcrypt
    add constraint ck_usuario_hash check (password_hash ~ '^\$2[aby]\$[0-9]{2}\$.{53}$');

-- =====================================================================
-- database/ddl/03_venta.sql
-- =====================================================================
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


-- =====================================================================
-- database/ddl/03_venta_logs.sql
-- =====================================================================
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


-- Crea la partición del mes de la fecha indicada en las dos bitácoras (si ya existe, no hace nada)
create function fn_crear_particiones_mes(p_fecha date) returns void
language plpgsql as $$
declare
    v_inicio date := date_trunc('month', p_fecha)::date;
    v_fin date := (date_trunc('month', p_fecha) + interval '1 month')::date;
    v_sufijo text := to_char(v_inicio, 'YYYY_MM');
    v_tabla text;
begin
    foreach v_tabla in array array['asiento_auditoria_log', 'transaccion_log'] loop
        execute format(
            'create table if not exists %I partition of %I for values from (%L) to (%L)',
            v_tabla || '_' || v_sufijo, v_tabla, v_inicio, v_fin);
    end loop;
end $$;

-- =====================================================================
-- database/ddl/04_seguridad_acceso.sql
-- =====================================================================
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

-- =====================================================================
-- database/ddl/05_catalogo_logica.sql
-- =====================================================================
-- Creación de la cartelera, cálculos de los totales y demás reglas de negocio del módulo A
-- Matías Esquivel Lizano
-- Se ejecuta después de 03_venta.sql: el trigger RN-18 consulta reserva_asiento y boleto



--- ----------------
-- cartelera
-- -----------------

create or replace function fn_listar_cartelera(p_cine text, p_fecha date, p_genero text)
returns table (
    funcion_id bigint,
    titulo varchar,
    sinopsis text,
    clasificacion varchar,
    genero text, 
    duracion_min integer,
    poster_url varchar,
    cine varchar,
    ubicacion text,
    sala varchar,
    inicio timestamptz,
    fin timestamptz
)
language sql stable as $$
    select f.id, p.titulo, p.sinopsis, c.codigo,
           (select string_agg(g.nombre, ', ' order by g.nombre)
              from pelicula_genero pg join genero g on g.id = pg.genero_id
             where pg.pelicula_id = p.id),
           p.duracion_min, p.poster_url, ci.nombre,
           ci.direccion || ', ' || ci.ciudad || ', ' || ci.pais,
           s.nombre, f.inicio, f.fin
      from funcion f
      join pelicula p on p.id = f.pelicula_id
      join clasificacion c on c.id = p.clasificacion_id
      join sala s on s.id = f.sala_id
      join cine ci on ci.id = s.cine_id
     where f.estado = 'Activa'
       and f.inicio > now()
       and p.activa and s.activa and ci.activo
       -- rango de fechas escrito así para que se pueda usar el índice de inicio
       and f.inicio >= coalesce(p_fecha::timestamp at time zone 'America/Costa_Rica', now())
       and f.inicio <  coalesce((p_fecha + 1)::timestamp at time zone 'America/Costa_Rica', now() + interval '7 days')
       and (p_cine is null or ci.nombre ilike '%' || p_cine || '%' or ci.ciudad ilike '%' || p_cine || '%')
       and (p_genero is null or exists (
               select 1 from pelicula_genero pg join genero g on g.id = pg.genero_id
                where pg.pelicula_id = p.id and g.nombre ilike '%' || p_genero || '%'))
     order by f.inicio, p.titulo;
$$;

-- ----------------------
-- cálculo de total de las compras 
-- ----------------------
create or replace function fn_calcular_total(p_funcion_id bigint, p_asientos bigint[], p_tipos bigint[])
returns table (
    subtotal numeric(12,2),
    descuento numeric(12,2),
    cargo_servicio numeric(12,2),
    total numeric(12,2),
    detalle jsonb
)
language plpgsql stable as $$
declare
    v_sala bigint;
    v_local timestamp;   -- inicio de la función en hora local
    v_dia smallint;      -- 1 = lunes ... 7 = domingo
    v_malos integer;
begin
    if p_asientos is null or cardinality(p_asientos) = 0 then
        raise exception 'Debe seleccionar al menos un asiento';
    end if;
    if cardinality(p_asientos) <> coalesce(cardinality(p_tipos), 0) then
        raise exception 'Cada asiento debe tener un tipo de entrada';
    end if;
    if cardinality(p_asientos) <> (select count(distinct x) from unnest(p_asientos) x) then
        raise exception 'Hay asientos repetidos en la compra';
    end if;

    select f.sala_id, f.inicio at time zone 'America/Costa_Rica'
      into v_sala, v_local
      from funcion f where f.id = p_funcion_id;
    if not found then
        raise exception 'La función % no existe', p_funcion_id;
    end if;
    v_dia := extract(isodow from v_local);

    -- todos los asientos deben ser de la sala de la función y estar activos
    select count(*) into v_malos
      from unnest(p_asientos) x(id)
      left join asiento a on a.id = x.id and a.sala_id = v_sala and a.activo
     where a.id is null;
    if v_malos > 0 then
        raise exception 'Hay asientos que no pertenecen a la sala de la función';
    end if;

    -- cada asiento debe tener una tarifa para su tipo de entrada, zona, día y hora
    select count(*) into v_malos
      from unnest(p_asientos, p_tipos) x(asiento_id, tipo_id)
      join asiento a on a.id = x.asiento_id
     where not exists (
            select 1 from tarifa t
             where t.tipo_entrada_id = x.tipo_id and t.zona_asiento_id = a.zona_asiento_id and t.activa
               and (t.dia_semana is null or t.dia_semana = v_dia)
               and v_local::time between t.hora_desde and t.hora_hasta);
    if v_malos > 0 then
        raise exception 'No hay tarifa definida para alguno de los asientos seleccionados';
    end if;

    return query
    with linea as (
        select x.orden, x.asiento_id, x.tipo_id, a.fila, a.numero,
               te.nombre as tipo, z.nombre as zona, t.precio, t.cargo_servicio as cargo
          from unnest(p_asientos, p_tipos) with ordinality x(asiento_id, tipo_id, orden)
          join asiento a on a.id = x.asiento_id
          join zona_asiento z on z.id = a.zona_asiento_id
          join tipo_entrada te on te.id = x.tipo_id
          cross join lateral (
                select t.precio, t.cargo_servicio from tarifa t
                 where t.tipo_entrada_id = x.tipo_id and t.zona_asiento_id = a.zona_asiento_id and t.activa
                   and (t.dia_semana is null or t.dia_semana = v_dia)
                   and v_local::time between t.hora_desde and t.hora_hasta
                 order by (t.dia_semana is null), (t.hora_hasta - t.hora_desde), t.precio
                 limit 1) t
    ),
    grupo as (   -- cuántas entradas hay de cada tipo y qué promoción les aplica
        select l.tipo_id, count(*) as cantidad,
               (select pr.nombre from promocion pr
                 where pr.activa and pr.tipo = '2X1'
                   and (pr.tipo_entrada_id is null or pr.tipo_entrada_id = l.tipo_id)
                   and (pr.dia_semana is null or pr.dia_semana = v_dia)
                   and (pr.fecha_desde is null or v_local::date >= pr.fecha_desde)
                   and (pr.fecha_hasta is null or v_local::date <= pr.fecha_hasta)
                 order by pr.id limit 1) as promocion
          from linea l
         group by l.tipo_id
    ),
    calculo as (
        select l.*, g.promocion,
               case when g.promocion is not null
                     and row_number() over (partition by l.tipo_id order by l.precio, l.orden) <= g.cantidad / 2
                    then l.precio else 0 end as rebaja
          from linea l join grupo g on g.tipo_id = l.tipo_id
    )
    select sum(c.precio)::numeric(12,2),
           sum(c.rebaja)::numeric(12,2),
           sum(c.cargo)::numeric(12,2),
           (sum(c.precio) - sum(c.rebaja) + sum(c.cargo))::numeric(12,2),
           jsonb_agg(jsonb_build_object(
               'asiento_id', c.asiento_id, 'asiento', c.fila || c.numero, 'zona', c.zona,
               'tipo_entrada', c.tipo, 'precio', c.precio, 'descuento', c.rebaja,
               'cargo_servicio', c.cargo, 'promocion', c.promocion) order by c.orden)
      from calculo c;
end $$;

-- ----------------------
-- no cambiar la distribución de una sala con ventas activas
-- ----------------------

-- true si la sala tiene asientos vendidos o bloqueados (bloqueo vigente) en funciones que no han terminado
create or replace function fn_sala_tiene_ventas(p_sala_id bigint) returns boolean
language sql stable as $$
    select exists (
        select 1 from reserva_asiento ra
          join funcion f on f.id = ra.funcion_id
         where f.sala_id = p_sala_id and f.estado = 'Activa' and f.fin > now()
           and (ra.estado = 'VENDIDO' or (ra.estado = 'BLOQUEADO' and ra.bloqueado_hasta > now())))
        or exists (
        select 1 from boleto b
          join funcion f on f.id = b.funcion_id
         where f.sala_id = p_sala_id and f.estado = 'Activa' and f.fin > now()
           and b.estado = 'EMITIDO');
$$;

create or replace function trg_asiento_rn18() returns trigger
language plpgsql as $$
begin
    if tg_op in ('UPDATE', 'DELETE') and fn_sala_tiene_ventas(old.sala_id) then
        raise exception 'RN-18: la sala % tiene entradas vendidas o reservadas para funciones programadas, no se puede modificar su mapa de asientos', old.sala_id;
    end if;
    if tg_op in ('INSERT', 'UPDATE') and fn_sala_tiene_ventas(new.sala_id) then
        raise exception 'RN-18: la sala % tiene entradas vendidas o reservadas para funciones programadas, no se puede modificar su mapa de asientos', new.sala_id;
    end if;
    if tg_op = 'DELETE' then
        return old;
    end if;
    return new;
end $$;

create trigger trg_asiento_rn18
    before insert or update of sala_id, zona_asiento_id, fila, numero, activo or delete on asiento
    for each row execute function trg_asiento_rn18();

create or replace function trg_sala_rn18() returns trigger
language plpgsql as $$
begin
    if fn_sala_tiene_ventas(old.id) then
        raise exception 'RN-18: la sala % tiene entradas vendidas o reservadas para funciones programadas, no se puede modificar ni eliminar', old.id;
    end if;
    if tg_op = 'DELETE' then
        return old;
    end if;
    return new;
end $$;

create trigger trg_sala_rn18
    before update of cine_id, capacidad, activa or delete on sala
    for each row execute function trg_sala_rn18();



-- =====================================================================
-- database/ddl/06_venta_logica.sql
-- =====================================================================
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

-- Bloquea asientos de una función por 2 minutos para un usuario.
-- Crea la orden PENDIENTE y devuelve su id (reserva_id) y la hora en que vence el bloqueo.
-- Es atómica: si un asiento falla, no queda ninguno bloqueado ni orden creada.
create function fn_bloquear_asientos(p_usuario_id bigint, p_funcion_id bigint, p_asientos bigint[])
returns table (reserva_id bigint, expira_en timestamptz)
language plpgsql as $$
declare
    v_max constant integer := 6;            -- máximo de asientos por compra (RN-04)
    v_cantidad integer;
    v_validos integer;
    v_expira timestamptz := now() + interval '2 minutes';
    v_orden bigint;
    v_asiento bigint;
begin
    if p_asientos is null or cardinality(p_asientos) = 0 then
        raise exception 'Debe elegir al menos un asiento';
    end if;
    if cardinality(p_asientos) > v_max then
        raise exception 'Máximo % asientos por compra', v_max;
    end if;

    select count(distinct x) into v_cantidad from unnest(p_asientos) x;
    if v_cantidad <> cardinality(p_asientos) then
        raise exception 'Hay asientos repetidos en la selección';
    end if;

    -- la función debe estar activa y no haber empezado
    if not exists (select 1 from funcion where id = p_funcion_id and estado = 'Activa' and inicio > now()) then
        raise exception 'La función no está disponible para la venta';
    end if;

    -- todos los asientos deben ser de la sala de la función y estar activos
    select count(*) into v_validos
    from asiento a join funcion f on f.sala_id = a.sala_id
    where f.id = p_funcion_id and a.activo and a.id = any(p_asientos);
    if v_validos <> v_cantidad then
        raise exception 'Algún asiento no pertenece a la sala de la función';
    end if;

    -- libera lo vencido antes de intentar bloquear
    perform fn_liberar_expirados();

    insert into orden (usuario_id, funcion_id) values (p_usuario_id, p_funcion_id)
    returning id into v_orden;

    begin
        foreach v_asiento in array p_asientos loop
            insert into reserva_asiento (orden_id, funcion_id, asiento_id, bloqueado_hasta)
            values (v_orden, p_funcion_id, v_asiento, v_expira);
        end loop;
    exception when unique_violation then
        -- otro usuario tomó el asiento primero: se deshace todo
        raise exception 'Asiento no disponible: otro usuario lo tiene bloqueado o comprado';
    end;

    insert into asiento_auditoria_log (funcion_id, asiento_id, orden_id, usuario_id, estado_anterior, estado_nuevo)
    select p_funcion_id, x, v_orden, p_usuario_id, null, 'BLOQUEADO' from unnest(p_asientos) x;

    insert into transaccion_log (orden_id, usuario_id, tipo, resultado, detalle)
    values (v_orden, p_usuario_id, 'BLOQUEO', 'OK', cardinality(p_asientos) || ' asiento(s)');

    return query select v_orden, v_expira;
end $$;

-- Elige el tipo de entrada de cada asiento bloqueado y calcula los montos de la orden.
-- Usa fn_calcular_total para precios, 2x1 y cargos, y guarda el resultado en la orden y en cada reserva.
create function fn_asignar_tipos(p_orden_id bigint, p_usuario_id bigint, p_asientos bigint[], p_tipos bigint[])
returns table (subtotal numeric, descuento numeric, cargo_servicio numeric, total numeric, detalle jsonb)
language plpgsql as $$
declare
    v_orden orden%rowtype;
    v_calculo record;
begin
    select * into v_orden from orden where id = p_orden_id for update;
    if not found or v_orden.usuario_id <> p_usuario_id then
        raise exception 'La orden no existe o no le pertenece';
    end if;
    if v_orden.estado <> 'PENDIENTE' then
        raise exception 'La orden ya no está pendiente (%)', v_orden.estado;
    end if;

    -- el bloqueo debe seguir vigente
    if not exists (select 1 from reserva_asiento r
                   where r.orden_id = p_orden_id and r.estado = 'BLOQUEADO' and r.bloqueado_hasta > now()) then
        raise exception 'El bloqueo de los asientos ya venció';
    end if;

    -- los asientos recibidos deben ser exactamente los bloqueados de la orden
    if cardinality(p_asientos) <> (select count(*) from reserva_asiento r
                                   where r.orden_id = p_orden_id and r.estado = 'BLOQUEADO')
       or exists (select 1 from unnest(p_asientos) x
                  where x not in (select r.asiento_id from reserva_asiento r
                                  where r.orden_id = p_orden_id and r.estado = 'BLOQUEADO')) then
        raise exception 'Los asientos no coinciden con los bloqueados de la orden';
    end if;

    select * into v_calculo from fn_calcular_total(v_orden.funcion_id, p_asientos, p_tipos);

    -- precio, descuento y cargo de cada asiento
    update reserva_asiento r
    set tipo_entrada_id = t.tipo_id,
        precio = (d.linea ->> 'precio')::numeric,
        descuento = (d.linea ->> 'descuento')::numeric,
        cargo_servicio = (d.linea ->> 'cargo_servicio')::numeric
    from unnest(p_asientos, p_tipos) t(asiento_id, tipo_id)
    join jsonb_array_elements(v_calculo.detalle) d(linea)
      on (d.linea ->> 'asiento_id')::bigint = t.asiento_id
    where r.orden_id = p_orden_id and r.asiento_id = t.asiento_id and r.estado = 'BLOQUEADO';

    -- totales de la orden
    update orden o
    set subtotal = v_calculo.subtotal,
        descuento = v_calculo.descuento,
        cargo_servicio = v_calculo.cargo_servicio,
        total = v_calculo.total
    where o.id = p_orden_id;

    return query select v_calculo.subtotal, v_calculo.descuento, v_calculo.cargo_servicio,
                        v_calculo.total, v_calculo.detalle;
end $$;

-- Confirma el pago (simulado) de una orden.
-- APROBADO: asientos VENDIDO, orden PAGADA y se emiten los boletos con su QR único.
-- RECHAZADO: los asientos se liberan al instante y la orden se cancela.
-- Es atómica: o se hace todo o no se hace nada.
create function fn_confirmar_pago(p_orden_id bigint, p_usuario_id bigint, p_metodo varchar, p_resultado varchar)
returns table (resultado_pago varchar, mensaje varchar, boleto_id bigint, codigo_qr varchar)
language plpgsql as $$
declare
    v_orden orden%rowtype;
    v_metodo bigint;
    v_referencia varchar;
begin
    if p_resultado not in ('APROBADO', 'RECHAZADO') then
        raise exception 'El resultado debe ser APROBADO o RECHAZADO';
    end if;

    select * into v_orden from orden where id = p_orden_id for update;
    if not found or v_orden.usuario_id <> p_usuario_id then
        raise exception 'La orden no existe o no le pertenece';
    end if;
    if v_orden.estado <> 'PENDIENTE' then
        raise exception 'La orden ya no está pendiente (%)', v_orden.estado;
    end if;

    select m.id into v_metodo from metodo_pago m where m.codigo = p_metodo and m.activo;
    if not found then
        raise exception 'Método de pago no válido: %', p_metodo;
    end if;

    -- el bloqueo debe seguir vigente y cada asiento debe tener su tipo de entrada
    if not exists (select 1 from reserva_asiento r where r.orden_id = p_orden_id and r.estado = 'BLOQUEADO')
       or exists (select 1 from reserva_asiento r
                  where r.orden_id = p_orden_id and r.estado = 'BLOQUEADO' and r.bloqueado_hasta <= now()) then
        raise exception 'El bloqueo de los asientos venció; vuelva a seleccionarlos';
    end if;
    if exists (select 1 from reserva_asiento r
               where r.orden_id = p_orden_id and r.estado = 'BLOQUEADO' and r.precio is null) then
        raise exception 'Primero debe elegir el tipo de entrada de cada asiento';
    end if;

    perform fn_crear_particiones_mes(current_date);
    v_referencia := 'SIM-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 12));

    if p_resultado = 'RECHAZADO' then
        insert into pago (orden_id, metodo_pago_id, monto, resultado, referencia)
        values (p_orden_id, v_metodo, v_orden.total, 'RECHAZADO', v_referencia);

        -- RN-10: los asientos se liberan de inmediato
        update reserva_asiento r set estado = 'LIBERADO'
        where r.orden_id = p_orden_id and r.estado = 'BLOQUEADO';
        update orden o set estado = 'CANCELADA' where o.id = p_orden_id;

        insert into asiento_auditoria_log (funcion_id, asiento_id, orden_id, usuario_id, estado_anterior, estado_nuevo)
        select r.funcion_id, r.asiento_id, p_orden_id, p_usuario_id, 'BLOQUEADO', 'LIBERADO'
        from reserva_asiento r where r.orden_id = p_orden_id and r.estado = 'LIBERADO';

        insert into transaccion_log (orden_id, usuario_id, tipo, monto, resultado, detalle)
        values (p_orden_id, p_usuario_id, 'PAGO', v_orden.total, 'RECHAZADO', v_referencia),
               (p_orden_id, p_usuario_id, 'LIBERACION', null, 'OK', 'pago rechazado');

        return query select 'RECHAZADO'::varchar, 'Pago rechazado: los asientos fueron liberados'::varchar,
                            null::bigint, null::varchar;
        return;
    end if;

    -- pago aprobado
    insert into pago (orden_id, metodo_pago_id, monto, resultado, referencia)
    values (p_orden_id, v_metodo, v_orden.total, 'APROBADO', v_referencia);

    update reserva_asiento r set estado = 'VENDIDO'
    where r.orden_id = p_orden_id and r.estado = 'BLOQUEADO';
    update orden o set estado = 'PAGADA', pagada_en = now() where o.id = p_orden_id;

    -- RN-11 y RN-12: los boletos se emiten solo después del pago aprobado, cada uno con un QR único
    insert into boleto (orden_id, reserva_asiento_id, funcion_id, asiento_id, codigo_qr)
    select r.orden_id, r.id, r.funcion_id, r.asiento_id,
           'IMAX-' || upper(replace(gen_random_uuid()::text, '-', ''))
    from reserva_asiento r
    where r.orden_id = p_orden_id and r.estado = 'VENDIDO';

    insert into asiento_auditoria_log (funcion_id, asiento_id, orden_id, usuario_id, estado_anterior, estado_nuevo)
    select r.funcion_id, r.asiento_id, p_orden_id, p_usuario_id, 'BLOQUEADO', 'VENDIDO'
    from reserva_asiento r where r.orden_id = p_orden_id and r.estado = 'VENDIDO';

    insert into transaccion_log (orden_id, usuario_id, tipo, monto, resultado, detalle)
    values (p_orden_id, p_usuario_id, 'PAGO', v_orden.total, 'APROBADO', v_referencia),
           (p_orden_id, p_usuario_id, 'EMISION_BOLETO', null, 'OK',
            (select count(*) from boleto b where b.orden_id = p_orden_id) || ' boleto(s)');

    return query select 'APROBADO'::varchar, 'Pago aprobado'::varchar, b.id, b.codigo_qr
                 from boleto b where b.orden_id = p_orden_id order by b.id;
end $$;

-- Boletos de un usuario, los más próximos primero (RN-13)
create function fn_mis_boletos(p_usuario_id bigint)
returns table (boleto_id bigint, codigo_qr varchar, titulo varchar, inicio timestamptz,
               sala varchar, fila varchar, numero integer, estado varchar)
language sql stable as $$
    select b.id, b.codigo_qr, p.titulo, f.inicio, s.nombre, a.fila, a.numero, b.estado
    from boleto b
    join orden o on o.id = b.orden_id
    join funcion f on f.id = b.funcion_id
    join pelicula p on p.id = f.pelicula_id
    join sala s on s.id = f.sala_id
    join asiento a on a.id = b.asiento_id
    where o.usuario_id = p_usuario_id
    order by f.inicio desc, a.fila, a.numero;
$$;

-- =====================================================================
-- database/ddl/07_seguridad_logica.sql
-- =====================================================================
create or replace function fn_registrar_usuario(
    p_email text,
    p_nombre text,
    p_apellido text,
    p_password text,
    p_rol text default 'cliente'
) returns bigint
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_usuario_id bigint;
    v_rol_id bigint;
begin
    if p_password is null or length(p_password) < 8 then
        raise exception 'La contraseña debe tener al menos 8 caracteres'
            using errcode = '22023';
    end if;

    select id into v_rol_id from rol where nombre = p_rol;
    if v_rol_id is null then
        raise exception 'Rol inexistente: %', p_rol using errcode = '22023';
    end if;

    insert into usuario (email, nombre, apellido, password_hash)
    values (btrim(p_email), btrim(p_nombre), btrim(p_apellido),
            crypt(p_password, gen_salt('bf', 10)))
    returning id into v_usuario_id;

    insert into usuario_rol (usuario_id, rol_id) values (v_usuario_id, v_rol_id);

    return v_usuario_id;
end;
$$;

create or replace function fn_autenticar(
    p_email text,
    p_password text
) returns table (usuario_id bigint, nombre text, roles text[])
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_max_intentos constant integer := 5;
    v_bloqueo constant interval := interval '15 minutes';
    v_u usuario%rowtype;
begin
    select * into v_u from usuario
     where lower(email) = lower(btrim(p_email)) for update;

    if not found then
        -- Igualar el tiempo de respuesta si el correo no existe
        perform crypt(coalesce(p_password, ''), gen_salt('bf', 10));
        return;
    end if;

    if not v_u.activo then
        return;
    end if;

    -- Rechazar cuenta bloqueada
    if v_u.bloqueado_hasta is not null and v_u.bloqueado_hasta > now() then
        return;
    end if;

    if v_u.password_hash = crypt(coalesce(p_password, ''), v_u.password_hash) then
        update usuario
           set intentos_fallidos = 0,
               bloqueado_hasta = null,
               ultimo_login = now()
         where id = v_u.id;

        return query
        select v_u.id,
               (v_u.nombre || ' ' || v_u.apellido)::text,
               coalesce(array_agg(r.nombre::text order by r.nombre), array[]::text[])
          from usuario_rol ur
          join rol r on r.id = ur.rol_id
         where ur.usuario_id = v_u.id;
    else
        -- Contar el fallo y bloquear al llegar al máximo
        update usuario
           set intentos_fallidos = intentos_fallidos + 1,
               bloqueado_hasta = case when intentos_fallidos + 1 >= v_max_intentos
                                      then now() + v_bloqueo end
         where id = v_u.id;
    end if;
end;
$$;

create or replace function fn_registrar_auditoria(
    p_usuario_id bigint,
    p_ip inet,
    p_accion text,
    p_tabla text default null,
    p_registro_id bigint default null,
    p_motivo text default null,
    p_detalle jsonb default null
) returns bigint
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_rol_id bigint;
    v_id bigint;
begin
    -- Tomar el rol del usuario, con preferencia por administrador
    select ur.rol_id into v_rol_id
      from usuario_rol ur
      join rol r on r.id = ur.rol_id
     where ur.usuario_id = p_usuario_id
     order by (r.nombre = 'administrador') desc, ur.asignado_en
     limit 1;

    if v_rol_id is null then
        raise exception 'El usuario % no tiene rol asignado', p_usuario_id
            using errcode = '22023';
    end if;

    insert into admin_operacion_audit
        (usuario_id, rol_id, ip, accion, tabla_afectada, registro_id, motivo, detalle)
    values
        (p_usuario_id, v_rol_id, p_ip, p_accion, p_tabla, p_registro_id, p_motivo, p_detalle)
    returning id into v_id;

    return v_id;
end;
$$;

create or replace function fn_validar_entrada(p_codigo_qr text, p_puerta_id bigint)
returns table (ok boolean, mensaje text)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_antes constant interval := interval '30 minutes';
    v_despues constant interval := interval '15 minutes';
    v_puerta puerta%rowtype;
    v_boleto boleto%rowtype;
    v_inicio timestamptz;
    v_estado_funcion varchar;
    v_sala bigint;
    v_motivo text;
begin
    select * into v_puerta from puerta where id = p_puerta_id and activa;
    if not found then
        v_motivo := 'Puerta no válida';
    else
        -- Bloquear el boleto para que dos lecturas simultáneas se atiendan en orden
        select * into v_boleto from boleto where codigo_qr = p_codigo_qr for update;
        if not found then
            v_motivo := 'Entrada no reconocida';
        else
            select f.inicio, f.estado, f.sala_id into v_inicio, v_estado_funcion, v_sala
              from funcion f where f.id = v_boleto.funcion_id;

            if v_boleto.estado = 'USADO' then
                v_motivo := 'Entrada ya utilizada';
            elsif v_boleto.estado = 'ANULADO' then
                v_motivo := 'Entrada anulada';
            elsif v_estado_funcion <> 'Activa' then
                v_motivo := 'Función cancelada';
            elsif v_sala <> v_puerta.sala_id then
                v_motivo := 'Entrada de otra sala';
            elsif now() < v_inicio - v_antes then
                v_motivo := 'Ingreso aún no habilitado';
            elsif now() > v_inicio + v_despues then
                v_motivo := 'Ingreso cerrado: fuera del tiempo de tolerancia';
            end if;
        end if;
    end if;

    if v_motivo is null then
        update boleto set estado = 'USADO', usado_en = now() where id = v_boleto.id;
    end if;

    insert into acceso_puerta_log (boleto_id, codigo_qr, puerta_id, resultado, motivo)
    values (v_boleto.id, left(coalesce(p_codigo_qr, ''), 64), p_puerta_id,
            case when v_motivo is null then 'EXITOSO' else 'RECHAZADO' end,
            coalesce(v_motivo, 'Ingreso permitido'));

    return query select v_motivo is null, coalesce(v_motivo, 'Ingreso permitido')::text;
end;
$$;

create or replace function fn_reembolsar(
    p_boleto_id bigint,
    p_admin_id bigint,
    p_motivo text,
    p_ip inet default null
) returns table (ok boolean, mensaje text)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_limite constant interval := interval '2 hours';
    v_boleto boleto%rowtype;
    v_reserva reserva_asiento%rowtype;
    v_inicio timestamptz;
    v_monto numeric(12,2);
    v_forzado boolean;
begin
    if not exists (select 1 from usuario_rol ur join rol r on r.id = ur.rol_id
                    where ur.usuario_id = p_admin_id and r.nombre = 'administrador') then
        return query select false, 'Solo un administrador puede reembolsar'::text;
        return;
    end if;

    if p_motivo is null or length(btrim(p_motivo)) < 5 then
        return query select false, 'Indique el motivo del reembolso (mínimo 5 caracteres)'::text;
        return;
    end if;

    select * into v_boleto from boleto where id = p_boleto_id for update;
    if not found then
        return query select false, 'Boleto inexistente'::text;
        return;
    end if;
    if v_boleto.estado = 'USADO' then
        return query select false, 'La entrada ya fue utilizada, no se puede reembolsar'::text;
        return;
    end if;
    if v_boleto.estado = 'ANULADO' then
        return query select false, 'La entrada ya está anulada'::text;
        return;
    end if;

    select inicio into v_inicio from funcion where id = v_boleto.funcion_id;
    select * into v_reserva from reserva_asiento where id = v_boleto.reserva_asiento_id;

    -- Fuera de la política (hasta 2 horas antes) el reembolso es forzado y queda marcado
    v_forzado := now() > v_inicio - v_limite;
    v_monto := coalesce(v_reserva.precio, 0) - v_reserva.descuento + coalesce(v_reserva.cargo_servicio, 0);

    perform fn_crear_particiones_mes(current_date);

    -- Anular el boleto y liberar el asiento para una nueva venta
    update boleto set estado = 'ANULADO' where id = v_boleto.id;
    update reserva_asiento set estado = 'LIBERADO' where id = v_reserva.id;

    insert into asiento_auditoria_log (funcion_id, asiento_id, orden_id, usuario_id, estado_anterior, estado_nuevo)
    values (v_boleto.funcion_id, v_boleto.asiento_id, v_boleto.orden_id, p_admin_id, 'VENDIDO', 'LIBERADO');

    insert into reembolso (boleto_id, orden_id, admin_id, monto, forzado, motivo)
    values (v_boleto.id, v_boleto.orden_id, p_admin_id, v_monto, v_forzado, left(btrim(p_motivo), 300));

    insert into transaccion_log (orden_id, usuario_id, tipo, monto, resultado, detalle)
    values (v_boleto.orden_id, p_admin_id, 'REEMBOLSO', v_monto, 'OK', left(btrim(p_motivo), 200));

    -- Si todos los boletos de la orden están anulados, la orden queda reembolsada
    update orden set estado = 'REEMBOLSADA'
     where id = v_boleto.orden_id
       and not exists (select 1 from boleto b where b.orden_id = v_boleto.orden_id and b.estado <> 'ANULADO');

    perform fn_registrar_auditoria(
        p_admin_id,
        coalesce(p_ip, inet_client_addr(), '0.0.0.0'::inet),
        case when v_forzado then 'reembolso_forzado' else 'anulacion_venta' end,
        'boleto', v_boleto.id, left(btrim(p_motivo), 300),
        jsonb_build_object('monto', v_monto, 'forzado', v_forzado));

    return query select true, ('Reembolso registrado por ' || v_monto)::text;
end;
$$;

-- =====================================================================
-- database/ddl/08_roles_permisos.sql
-- =====================================================================
-- Crear los roles de PostgreSQL sin inicio de sesión
do $$
declare
    v_rol text;
begin
    foreach v_rol in array array['rol_cliente', 'rol_taquillero', 'rol_operador_sala',
                                 'rol_contador', 'rol_administrador']
    loop
        if not exists (select 1 from pg_roles where rolname = v_rol) then
            execute format('create role %I nologin', v_rol);
        end if;
    end loop;
end;
$$;

-- Quitar los permisos por defecto de PUBLIC
revoke all on all tables in schema public from public;
revoke execute on function fn_registrar_usuario(text, text, text, text, text) from public;
revoke execute on function fn_registrar_auditoria(bigint, inet, text, text, bigint, text, jsonb) from public;
revoke execute on function fn_crear_particion_admin_audit(date) from public;

grant usage on schema public to rol_cliente, rol_taquillero, rol_operador_sala,
    rol_contador, rol_administrador;

-- Lectura de cartelera para cliente, taquillero, operador y contador
grant select on cine, sala, zona_asiento, asiento, clasificacion, genero, pelicula,
    pelicula_genero, funcion, tipo_entrada, tarifa, promocion
    to rol_cliente, rol_taquillero, rol_operador_sala, rol_contador;

-- El operador de sala solo consulta las puertas
grant select on puerta to rol_operador_sala;

-- Administrador: gestión completa del catálogo y las puertas
grant select, insert, update, delete on cine, sala, zona_asiento, asiento, clasificacion,
    genero, pelicula, pelicula_genero, funcion, tipo_entrada, tarifa, promocion, puerta
    to rol_administrador;

-- Administrador: usuarios y roles, sin acceso al hash de la contraseña
grant select on rol to rol_administrador;
grant select, insert, delete on usuario_rol to rol_administrador;
grant select (id, nombre, apellido, email, telefono, activo, creado_en,
              intentos_fallidos, bloqueado_hasta, ultimo_login)
    on usuario to rol_administrador;
grant update (nombre, apellido, telefono, activo, intentos_fallidos, bloqueado_hasta)
    on usuario to rol_administrador;

-- Bitácora: el administrador solo la consulta y registra mediante la función
grant select on admin_operacion_audit to rol_administrador;
grant execute on function fn_registrar_usuario(text, text, text, text, text) to rol_administrador;
grant execute on function fn_registrar_auditoria(bigint, inet, text, text, bigint, text, jsonb)
    to rol_administrador;

-- Check-in y reembolsos
revoke execute on function fn_validar_entrada(text, bigint) from public;
revoke execute on function fn_reembolsar(bigint, bigint, text, inet) from public;

grant execute on function fn_validar_entrada(text, bigint) to rol_operador_sala, rol_administrador;
grant execute on function fn_reembolsar(bigint, bigint, text, inet) to rol_administrador;
grant select on reembolso to rol_administrador, rol_contador;
grant select on acceso_puerta_log to rol_administrador;

-- =====================================================================
-- database/ddl/09_venta_indices.sql
-- =====================================================================
-- Índices del módulo de venta
-- Los índices únicos de 03_venta.sql (uq_asiento_activo, uq_pago_aprobado) ya cubren el mapa de asientos
-- y el control de doble venta; estos son para las consultas de reportes y para "mis boletos".
-- Medidos con explain/02_explain_venta.sql sobre los datos masivos (resultados en explain/resultados/).

-- consulta 1: boletos de una función
create index idx_boleto_funcion on boleto (funcion_id) where estado <> 'ANULADO';

-- consulta 1: órdenes pagadas de una función
create index idx_orden_funcion_estado on orden (funcion_id, estado);

-- La consulta 3 no lleva índice: cuenta casi todos los pagos de la tabla (más del 90 % son aprobados),
-- así que PostgreSQL con razón la resuelve leyendo la tabla completa. Ver explain/resultados/.

-- mis boletos: órdenes de un usuario y boletos de una orden
create index idx_orden_usuario on orden (usuario_id);
create index idx_boleto_orden on boleto (orden_id);

-- fn_liberar_expirados: solo los bloqueos vigentes están en el índice
create index idx_reserva_bloqueo on reserva_asiento (bloqueado_hasta) where estado = 'BLOQUEADO';

analyze boleto, orden, reserva_asiento;

-- =====================================================================
-- database/ddl/10_catalogo_indices.sql
-- =====================================================================
-- Índices del módulo A para la cartelera y el Top 5
-- Matías Esquivel Lizano
-- Se ejecuta después de 03_venta.sql (idx_boleto_emitido es sobre la tabla boleto)
-- Justificación con EXPLAIN ANALYZE en database/explain/README.md

create index idx_funcion_activa_inicio on funcion (inicio) where estado = 'Activa';

create index idx_sala_cine on sala (cine_id);

create index idx_pelicula_genero_genero on pelicula_genero (genero_id);

create index idx_funcion_pelicula on funcion (pelicula_id);

create index idx_boleto_emitido on boleto (emitido_en) include (funcion_id, estado);

analyze funcion, sala, pelicula_genero, boleto;



-- Datos de DEMOSTRACIÓN para probar el panel de administración del catálogo (Módulo A).
-- Requiere: database/ddl/01_catalogo.sql. Se puede correr sobre una BD vacía:
--   psql -d imax -f database/ddl/01_catalogo.sql -f database/seeds/01_catalogo_demo.sql
-- No es la semilla final del proyecto: es solo para ir probando la GUI.

begin;

insert into zona_asiento (nombre, descripcion) values
  ('General',   'Butaca estándar'),
  ('VIP',       'Butaca reclinable en la zona central'),
  ('Accesible', 'Espacio para silla de ruedas y acompañante');

insert into clasificacion (codigo, descripcion, edad_minima) values
  ('G',     'Todo público', 0),
  ('PG',    'Se sugiere guía de los padres', 0),
  ('PG-13', 'Mayores de 13 años', 13),
  ('R',     'Mayores de 17 años o acompañados', 17);

insert into genero (nombre) values
  ('Acción'), ('Animación'), ('Ciencia ficción'), ('Documental'), ('Drama'), ('Terror');

insert into cine (nombre, direccion, ciudad, pais, latitud, longitud) values
  ('IMAX Los Ángeles', '6801 Hollywood Blvd',        'Los Ángeles', 'Estados Unidos', 34.102200, -118.340500),
  ('IMAX San José',    'Lincoln Plaza, Moravia',     'San José',    'Costa Rica',       9.961200,  -84.049600),
  ('IMAX Ciudad de México', 'Av. Insurgentes Sur 1235', 'Ciudad de México', 'México', 19.372800, -99.178300);

insert into sala (cine_id, nombre, capacidad, minutos_limpieza)
select c.id, s.nombre, s.capacidad, s.limpieza
  from (values ('IMAX Los Ángeles', 'Sala 1 IMAX Laser', 80, 25),
               ('IMAX San José',    'Sala 1',            48, 20),
               ('IMAX San José',    'Sala 2',            60, 20),
               ('IMAX Ciudad de México', 'Sala Premium', 40, 30)) s(cine, nombre, capacidad, limpieza)
  join cine c on c.nombre = s.cine;

-- Asientos: filas A..H × 10 (A-C VIP, H accesible) para la sala de Los Ángeles; el resto todo General.
insert into asiento (sala_id, zona_asiento_id, fila, numero)
select s.id,
       (select id from zona_asiento where nombre = case when f <= 3 then 'VIP' when f = 8 then 'Accesible' else 'General' end),
       chr(64 + f), n
  from sala s, generate_series(1, 8) f, generate_series(1, 10) n
 where s.nombre = 'Sala 1 IMAX Laser';

insert into asiento (sala_id, zona_asiento_id, fila, numero)
select s.id, (select id from zona_asiento where nombre = 'General'), chr(64 + f), n
  from sala s join cine c on c.id = s.cine_id, generate_series(1, 6) f, generate_series(1, 8) n
 where c.nombre = 'IMAX San José' and s.nombre = 'Sala 1';

insert into pelicula (titulo, sinopsis, duracion_min, clasificacion_id, fecha_estreno)
select p.titulo, p.sinopsis, p.duracion, c.id, p.estreno::date
  from (values ('Dune: Parte Tres', 'Paul Atreides enfrenta las consecuencias de la guerra santa que desató en el universo conocido.', 165, 'PG-13', '2026-12-18'),
               ('Océano Profundo', 'Documental inmersivo filmado con cámaras IMAX en las fosas más profundas del Pacífico.', 45, 'G', '2026-11-05'),
               ('La Noche Eterna', 'Un pueblo aislado descubre que el sol no volverá a salir.', 112, 'R', '2026-10-30')) p(titulo, sinopsis, duracion, clasif, estreno)
  join clasificacion c on c.codigo = p.clasif;

insert into pelicula_genero (pelicula_id, genero_id)
select p.id, g.id
  from (values ('Dune: Parte Tres', 'Ciencia ficción'), ('Dune: Parte Tres', 'Acción'),
               ('Océano Profundo', 'Documental'),
               ('La Noche Eterna', 'Terror'), ('La Noche Eterna', 'Drama')) x(titulo, genero)
  join pelicula p on p.titulo = x.titulo
  join genero g on g.nombre = x.genero;

-- Tipos de entrada (RN-06: los que requieren documento se validan en puerta)
insert into tipo_entrada (nombre, descripcion, requiere_documento) values
  ('Adulto',       'Tarifa general', false),
  ('Niño',         'Menores de 12 años', true),
  ('Adulto mayor', 'Ciudadano de oro (65+)', true),
  ('Estudiante',   'Con carné vigente', true);

-- Tarifas base (todos los días, todo el día) por tipo × zona; VIP cuesta 4.00 más
insert into tarifa (tipo_entrada_id, zona_asiento_id, precio, cargo_servicio)
select t.id, z.id, b.precio + case z.nombre when 'VIP' then 4 else 0 end, 0.75
  from (values ('Adulto', 8.50), ('Niño', 6.00), ('Adulto mayor', 5.50), ('Estudiante', 6.50)) b(tipo, precio)
  join tipo_entrada t on t.nombre = b.tipo
  cross join zona_asiento z;

-- Martes de descuento para Adulto en zona General, y matiné (10:00 a 14:59) para Adulto en General
insert into tarifa (tipo_entrada_id, zona_asiento_id, dia_semana, precio, cargo_servicio)
select t.id, z.id, 2, 6.00, 0.75 from tipo_entrada t, zona_asiento z where t.nombre = 'Adulto' and z.nombre = 'General';
insert into tarifa (tipo_entrada_id, zona_asiento_id, hora_desde, hora_hasta, precio, cargo_servicio)
select t.id, z.id, '10:00', '14:59:59', 7.00, 0.75 from tipo_entrada t, zona_asiento z where t.nombre = 'Adulto' and z.nombre = 'General';

-- Promociones 2x1 (RN-07)
insert into promocion (nombre, dia_semana, requiere_cantidad_par, tipo_entrada_id) values
  ('2x1 los miércoles', 3, true, null);
insert into promocion (nombre, requiere_cantidad_par, tipo_entrada_id, fecha_desde, fecha_hasta)
select '2x1 estudiantes', true, id, current_date, current_date + 60 from tipo_entrada where nombre = 'Estudiante';

-- Funciones de los próximos dos días (hora de Costa Rica). fin y fin_limpieza los calcula el trigger.
insert into funcion (pelicula_id, sala_id, inicio)
select p.id, s.id, ((current_date + x.dias) + x.hora) at time zone 'America/Costa_Rica'
  from (values ('Dune: Parte Tres', 'Sala 1 IMAX Laser', 1, time '14:00'),
               ('Dune: Parte Tres', 'Sala 1 IMAX Laser', 1, time '17:30'),
               ('Océano Profundo',  'Sala 1 IMAX Laser', 1, time '21:00'),
               ('Océano Profundo',  'Sala 1',            1, time '15:00'),
               ('La Noche Eterna',  'Sala 1',            1, time '20:00'),
               ('La Noche Eterna',  'Sala Premium',      1, time '19:00'),
               ('Dune: Parte Tres', 'Sala 1 IMAX Laser', 2, time '18:00'),
               ('Océano Profundo',  'Sala 2',            2, time '16:00')) x(titulo, sala, dias, hora)
  join pelicula p on p.titulo = x.titulo
  join sala s on s.nombre = x.sala
 order by s.id, x.dias, x.hora;   -- así los ids de las funciones siempre salen en el mismo orden

commit;

INSERT INTO rol (nombre, descripcion) VALUES
    ('cliente',       'Espectador: cartelera, compra y consulta de sus propias entradas'),
    ('taquillero',    'Venta presencial y corte de caja propio'),
    ('operador_sala', 'Validación de entradas (QR) en puerta'),
    ('contador',      'Lectura y exportación de información financiera'),
    ('administrador', 'Configuración de cartelera, salas y precios; reembolsos; auditoría');

-- Usuarios de DEMOSTRACIÓN, uno por rol. Contraseña de todos: Imax2026!  (solo para pruebas locales)
-- La contraseña se guarda como hash bcrypt con pgcrypto; nunca en texto plano.
insert into usuario (nombre, apellido, email, password_hash, telefono)
values ('Ana',    'Cliente',  'cliente@imax.test',    crypt('Imax2026!', gen_salt('bf')), '8888-0001'),
       ('Tomás',  'Taquilla', 'taquilla@imax.test',   crypt('Imax2026!', gen_salt('bf')), '8888-0002'),
       ('Olga',   'Operadora','operador@imax.test',   crypt('Imax2026!', gen_salt('bf')), null),
       ('Carlos', 'Contador', 'contador@imax.test',   crypt('Imax2026!', gen_salt('bf')), null),
       ('Admin',  'IMAX',     'admin@imax.test',      crypt('Imax2026!', gen_salt('bf')), null);

insert into usuario_rol (usuario_id, rol_id)
select u.id, r.id
  from (values ('cliente@imax.test', 'cliente'), ('taquilla@imax.test', 'taquillero'), ('operador@imax.test', 'operador_sala'),
               ('contador@imax.test', 'contador'), ('admin@imax.test', 'administrador')) x(email, rol)
  join usuario u on u.email = x.email
  join rol r on r.nombre = x.rol;


\c postgres
\encoding UTF8
drop database if exists imax_prueba;
create database imax_prueba template imax_base;
\c imax_prueba
\encoding UTF8
\echo
\echo '################ Pruebas: restricciones del módulo de venta ################'

-- Pruebas de las restricciones del módulo de venta
-- Se corren sobre una base recién creada con 01_catalogo.sql, 03_venta.sql y el seed del catálogo.
-- Cada prueba dice qué se espera: FUNCIONA o ERROR.

-- Datos base: un método de pago y dos órdenes del usuario 1 para la función 1
insert into metodo_pago (id, codigo, nombre) values (1, 'TARJETA', 'Tarjeta simulada');
insert into orden (id, usuario_id, funcion_id) values (1, 1, 1);
insert into orden (id, usuario_id, funcion_id) values (2, 1, 1);


-- Prueba 1: bloquear el asiento 1 para la función 1
-- Resultado esperado: FUNCIONA
insert into reserva_asiento (id, orden_id, funcion_id, asiento_id, bloqueado_hasta)
values (1, 1, 1, 1, now() + interval '2 minutes');

-- Prueba 2: otra orden intenta bloquear el mismo asiento en la misma función
-- Resultado esperado: ERROR (duplicate key, uq_asiento_activo)
insert into reserva_asiento (id, orden_id, funcion_id, asiento_id, bloqueado_hasta)
values (2, 2, 1, 1, now() + interval '2 minutes');

-- Prueba 3: la primera reserva expira y la otra orden ya puede tomar el asiento
-- Resultado esperado: FUNCIONA
update reserva_asiento set estado = 'EXPIRADO' where id = 1;
insert into reserva_asiento (id, orden_id, funcion_id, asiento_id, bloqueado_hasta)
values (2, 2, 1, 1, now() + interval '2 minutes');

-- Prueba 4: estado de reserva que no existe
-- Resultado esperado: ERROR (check de estado)
update reserva_asiento set estado = 'COMPRADO' where id = 2;


-- Prueba 5: orden con total que no cuadra (10 - 2 + 1 debería ser 9, no 99)
-- Resultado esperado: ERROR (check del total)
insert into orden (id, usuario_id, funcion_id, subtotal, descuento, cargo_servicio, total)
values (3, 1, 1, 10, 2, 1, 99);

-- Prueba 6: la misma orden con el total correcto
-- Resultado esperado: FUNCIONA
insert into orden (id, usuario_id, funcion_id, subtotal, descuento, cargo_servicio, total)
values (3, 1, 1, 10, 2, 1, 9);

-- Prueba 7: estado de orden que no existe
-- Resultado esperado: ERROR (check de estado)
update orden set estado = 'LISTA' where id = 1;


-- Prueba 8: un pago aprobado para la orden 1
-- Resultado esperado: FUNCIONA
insert into pago (id, orden_id, metodo_pago_id, monto, resultado)
values (1, 1, 1, 0, 'APROBADO');

-- Prueba 9: un segundo pago aprobado para la misma orden
-- Resultado esperado: ERROR (duplicate key, uq_pago_aprobado)
insert into pago (id, orden_id, metodo_pago_id, monto, resultado)
values (2, 1, 1, 0, 'APROBADO');

-- Prueba 10: varios pagos rechazados para la orden 2
-- Resultado esperado: FUNCIONA
insert into pago (id, orden_id, metodo_pago_id, monto, resultado)
values (3, 2, 1, 0, 'RECHAZADO');
insert into pago (id, orden_id, metodo_pago_id, monto, resultado)
values (4, 2, 1, 0, 'RECHAZADO');


-- Prueba 11: crear el boleto de la reserva 2 con su código QR
-- Resultado esperado: FUNCIONA
insert into boleto (id, orden_id, reserva_asiento_id, funcion_id, asiento_id, codigo_qr)
values (1, 2, 2, 1, 1, 'QR-0001');

-- Prueba 12: otro boleto con el mismo código QR
-- Resultado esperado: ERROR (duplicate key, codigo_qr)
insert into boleto (id, orden_id, reserva_asiento_id, funcion_id, asiento_id, codigo_qr)
values (2, 1, 1, 1, 1, 'QR-0001');

-- Prueba 13: otro boleto para la misma reserva, con QR distinto
-- Resultado esperado: ERROR (duplicate key, reserva_asiento_id)
insert into boleto (id, orden_id, reserva_asiento_id, funcion_id, asiento_id, codigo_qr)
values (3, 2, 2, 1, 1, 'QR-0002');


-- Prueba 14: las tablas no guardan datos de tarjeta (ni número ni CVV)
-- Resultado esperado: 0 filas
select table_name, column_name
from information_schema.columns
where table_name in ('pago', 'orden', 'boleto')
  and (column_name like '%cvv%' or column_name like '%numero_tarjeta%');


-- Prueba de la bitácora de asientos
 
-- Prueba 1: una fila de octubre cae en la partición de octubre
-- Resultado esperado: FUNCIONA
insert into asiento_auditoria_log (funcion_id, asiento_id, estado_nuevo, fecha)
values (1, 1, 'BLOQUEADO', '2026-10-22 10:00');
 
-- Prueba 2: una fila de noviembre cae en la partición de noviembre
-- Resultado esperado: FUNCIONA
insert into asiento_auditoria_log (funcion_id, asiento_id, estado_nuevo, fecha)
values (1, 1, 'VENDIDO', '2026-11-05 15:30');
 
-- Prueba 3: una fecha sin partición creada (marzo de 2027)
-- Resultado esperado: ERROR (no partition found for row)
insert into asiento_auditoria_log (funcion_id, asiento_id, estado_nuevo, fecha)
values (1, 1, 'BLOQUEADO', '2027-03-01 09:00');
 
-- Prueba 4: ver en qué partición quedó cada fila
-- Resultado esperado: tableoid = asiento_auditoria_log_2026_10 y asiento_auditoria_log_2026_11
select tableoid::regclass as particion, estado_nuevo, fecha
from asiento_auditoria_log
order by fecha;

-- Prueba de la bitácora de transacciones
 
-- Prueba 1: registrar un pago aprobado
-- Resultado esperado: FUNCIONA
insert into transaccion_log (orden_id, usuario_id, tipo, monto, resultado, fecha)
values (1, 1, 'PAGO', 17.00, 'APROBADO', '2026-10-22 11:00');
 
-- Prueba 2: tipo de transacción que no existe
-- Resultado esperado: ERROR (check de tipo)
insert into transaccion_log (orden_id, usuario_id, tipo, fecha)
values (1, 1, 'REGALO', '2026-10-22 11:05');
 
-- Prueba 3: fecha sin partición (abril de 2027)
-- Resultado esperado: ERROR (no partition found for row)
insert into transaccion_log (orden_id, usuario_id, tipo, fecha)
values (1, 1, 'BLOQUEO', '2027-04-01 08:00');
 
-- Prueba 4: ver en qué partición quedó la fila
-- Resultado esperado: transaccion_log_2026_10
select tableoid::regclass as particion, tipo, monto, resultado, fecha
from transaccion_log;

-- Prueba del bloqueo de UPDATE y DELETE en las bitácoras
 
-- Prueba 1: agregar filas sigue funcionando
-- Resultado esperado: FUNCIONA
insert into asiento_auditoria_log (funcion_id, asiento_id, estado_nuevo, fecha)
values (1, 1, 'BLOQUEADO', '2026-10-22 10:00');
insert into transaccion_log (orden_id, usuario_id, tipo, fecha)
values (1, 1, 'BLOQUEO', '2026-10-22 10:00');
 
-- Prueba 2: modificar una fila de la bitácora de asientos
-- Resultado esperado: ERROR (la bitácora no permite UPDATE)
update asiento_auditoria_log set estado_nuevo = 'VENDIDO' where asiento_id = 1;
 
-- Prueba 3: borrar una fila de la bitácora de asientos
-- Resultado esperado: ERROR (la bitácora no permite DELETE)
delete from asiento_auditoria_log where asiento_id = 1;
 
-- Prueba 4: modificar una fila de la bitácora de transacciones
-- Resultado esperado: ERROR
update transaccion_log set tipo = 'PAGO' where orden_id = 1;
 
-- Prueba 5: borrar una fila de la bitácora de transacciones
-- Resultado esperado: ERROR
delete from transaccion_log where orden_id = 1;
 
-- Prueba 6: intentar saltarse el bloqueo escribiendo directo en la partición
-- Resultado esperado: ERROR
delete from asiento_auditoria_log_2026_10;
 
-- Prueba 7: las filas siguen intactas
-- Resultado esperado: 1 y 1
select (select count(*) from asiento_auditoria_log) as asientos,
       (select count(*) from transaccion_log) as transacciones;

-- Prueba de la creación de particiones mensuales

-- Prueba 1: antes de crear la partición, una fecha de marzo de 2027 falla
-- Resultado esperado: ERROR (no partition found for row)
insert into transaccion_log (orden_id, usuario_id, tipo, fecha)
values (1, 1, 'BLOQUEO', '2027-03-10 09:00');

-- Prueba 2: crear las particiones de marzo de 2027
-- Resultado esperado: FUNCIONA
select fn_crear_particiones_mes('2027-03-15');

-- Prueba 3: ahora la misma fila entra en la partición de marzo
-- Resultado esperado: FUNCIONA
insert into transaccion_log (orden_id, usuario_id, tipo, fecha)
values (1, 1, 'BLOQUEO', '2027-03-10 09:00');

-- Prueba 4: llamar la función otra vez para el mismo mes no da error
-- Resultado esperado: FUNCIONA
select fn_crear_particiones_mes('2027-03-01');

-- Prueba 5: ver las particiones que existen (deben salir las de octubre 2026 a marzo 2027, en las dos bitácoras)
select inhparent::regclass as bitacora, inhrelid::regclass as particion
from pg_inherits
where inhparent in ('asiento_auditoria_log'::regclass, 'transaccion_log'::regclass)
order by 1, 2;


\c postgres
\encoding UTF8
drop database if exists imax_prueba;
create database imax_prueba template imax_base;
\c imax_prueba
\encoding UTF8
\echo
\echo '################ Pruebas: fn_liberar_expirados ################'

-- Pruebas de fn_liberar_expirados
-- Se corre sobre una base nueva con los DDL y el seed del catálogo.

-- Datos base: 3 órdenes del usuario 1 para la función 1
insert into metodo_pago (id, codigo, nombre) values (1, 'TARJETA', 'Tarjeta simulada');
insert into orden (id, usuario_id, funcion_id) values (1, 1, 1);
insert into orden (id, usuario_id, funcion_id) values (2, 1, 1);
insert into orden (id, usuario_id, funcion_id) values (3, 1, 1);

-- Orden 1: asiento 1 con el bloqueo ya vencido (hace 1 minuto)
insert into reserva_asiento (id, orden_id, funcion_id, asiento_id, bloqueado_hasta)
values (1, 1, 1, 1, now() - interval '1 minute');
-- Orden 2: asiento 2 con el bloqueo todavía vigente (2 minutos más)
insert into reserva_asiento (id, orden_id, funcion_id, asiento_id, bloqueado_hasta)
values (2, 2, 1, 2, now() + interval '2 minutes');
-- Orden 3: asiento 3 ya vendido (con fecha vieja, no se debe tocar)
insert into reserva_asiento (id, orden_id, funcion_id, asiento_id, estado, bloqueado_hasta, precio)
values (3, 3, 1, 3, 'VENDIDO', now() - interval '10 minutes', 8.50);


-- Prueba 1: liberar los vencidos
-- Resultado esperado: 1 (solo el asiento 1)
select fn_liberar_expirados();

-- Prueba 2: estado de cada reserva
-- Resultado esperado: 1 = EXPIRADO, 2 = BLOQUEADO, 3 = VENDIDO
select id, asiento_id, estado from reserva_asiento order by id;

-- Prueba 3: estado de cada orden
-- Resultado esperado: 1 = EXPIRADA, 2 = PENDIENTE, 3 = PENDIENTE
select id, estado from orden order by id;

-- Prueba 4: el cambio quedó en las bitácoras
-- Resultado esperado: 1 fila en asiento_auditoria_log (BLOQUEADO -> EXPIRADO) y 1 en transaccion_log (EXPIRACION)
select asiento_id, estado_anterior, estado_nuevo from asiento_auditoria_log;
select orden_id, tipo, resultado from transaccion_log;

-- Prueba 5: el asiento 1 ya se puede bloquear otra vez con otra orden
-- Resultado esperado: FUNCIONA
insert into reserva_asiento (id, orden_id, funcion_id, asiento_id, bloqueado_hasta)
values (4, 2, 1, 1, now() + interval '2 minutes');

-- Prueba 6: el asiento 2 (bloqueo vigente) sigue sin poder tomarse
-- Resultado esperado: ERROR (duplicate key, uq_asiento_activo)
insert into reserva_asiento (id, orden_id, funcion_id, asiento_id, bloqueado_hasta)
values (5, 1, 1, 2, now() + interval '2 minutes');

-- Prueba 7: volver a correr la función cuando no hay nada vencido
-- Resultado esperado: 0
select fn_liberar_expirados();


\c postgres
\encoding UTF8
drop database if exists imax_prueba;
create database imax_prueba template imax_base;
\c imax_prueba
\encoding UTF8
\echo
\echo '################ Pruebas: fn_mapa_asientos ################'

-- Pruebas de fn_mapa_asientos 
-- Se corre sobre una base nueva con los DDL y el seed del catálogo.
-- La función 1 es de la sala "Sala 1 IMAX Laser" (80 asientos, filas A a H).

insert into orden (id, usuario_id, funcion_id) values (1, 1, 1);
insert into orden (id, usuario_id, funcion_id) values (2, 1, 1);
insert into orden (id, usuario_id, funcion_id) values (3, 1, 1);

-- Prueba 1: función sin ventas, todos los asientos disponibles
-- Resultado esperado: 80 asientos, todos DISPONIBLE
select estado, count(*) from fn_mapa_asientos(1) group by estado;

-- Asiento 1 bloqueado, asiento 2 vendido, asiento 3 con bloqueo vencido
insert into reserva_asiento (id, orden_id, funcion_id, asiento_id, bloqueado_hasta)
values (1, 1, 1, 1, now() + interval '2 minutes');
insert into reserva_asiento (id, orden_id, funcion_id, asiento_id, estado, bloqueado_hasta, precio)
values (2, 2, 1, 2, 'VENDIDO', now() - interval '10 minutes', 8.50);
insert into reserva_asiento (id, orden_id, funcion_id, asiento_id, bloqueado_hasta)
values (3, 3, 1, 3, now() - interval '1 minute');

-- Prueba 2: estado de los 3 primeros asientos
-- Resultado esperado: asiento 1 (A1) BLOQUEADO, asiento 2 (B1) VENDIDO, asiento 3 (C1) DISPONIBLE (el bloqueo ya venció)
select asiento_id, fila, numero, zona, estado
from fn_mapa_asientos(1) where asiento_id in (1, 2, 3) order by asiento_id;

-- Prueba 3: conteo por estado
-- Resultado esperado: BLOQUEADO 1, VENDIDO 1, DISPONIBLE 78
select estado, count(*) from fn_mapa_asientos(1) group by estado order by estado;

-- Prueba 4: un asiento desactivado ya no aparece en el mapa
-- Resultado esperado: 79 asientos
update asiento set activo = false where id = 80;
select count(*) from fn_mapa_asientos(1);

-- Prueba 5: función que no existe
-- Resultado esperado: 0 filas
select count(*) from fn_mapa_asientos(9999);

-- Prueba 6: las ventas de una función no afectan el mapa de otra de la misma sala
-- Resultado esperado: función 2 (misma sala), todos los asientos DISPONIBLE
select f.id as funcion, count(*) filter (where m.estado <> 'DISPONIBLE') as ocupados
from funcion f, lateral fn_mapa_asientos(f.id) m
where f.id = 2 and f.sala_id = (select sala_id from funcion where id = 1)
group by f.id;


\c postgres
\encoding UTF8
drop database if exists imax_prueba;
create database imax_prueba template imax_base;
\c imax_prueba
\encoding UTF8
\echo
\echo '################ Pruebas: fn_bloquear_asientos ################'

-- Pruebas de fn_bloquear_asientos 
-- Se corre sobre una base nueva con los DDL y el seed del catálogo.
-- Función 1: sala "Sala 1 IMAX Laser" (asientos 1 a 80). Usuarios 1 y 2. Función 5: otra sala (asientos desde el 81).

-- Prueba 1: el usuario 1 bloquea los asientos 1 y 2
-- Resultado esperado: FUNCIONA, devuelve el reserva_id y una hora de vencimiento unos 2 minutos adelante
select * from fn_bloquear_asientos(1, 1, array[1, 2]);

-- Prueba 2: la orden y las reservas quedaron creadas
-- Resultado esperado: orden 1 PENDIENTE; asientos 1 y 2 BLOQUEADO
select id, usuario_id, estado from orden;
select orden_id, asiento_id, estado from reserva_asiento order by asiento_id;

-- Prueba 3: el mapa ya muestra esos asientos como bloqueados
-- Resultado esperado: BLOQUEADO 2
select estado, count(*) from fn_mapa_asientos(1) where estado = 'BLOQUEADO' group by estado;

-- Prueba 4: el usuario 2 intenta bloquear el asiento 2 (ya bloqueado) junto con el 3
-- Resultado esperado: ERROR (Asiento no disponible)
select * from fn_bloquear_asientos(2, 1, array[3, 2]);

-- Prueba 5: no quedó nada a medias (el asiento 3 no se bloqueó y no se creó una orden)
-- Resultado esperado: 1 orden y 2 reservas
select (select count(*) from orden) as ordenes, (select count(*) from reserva_asiento) as reservas;

-- Prueba 6: más de 6 asientos
-- Resultado esperado: ERROR (Máximo 6 asientos por compra)
select * from fn_bloquear_asientos(2, 1, array[10, 11, 12, 13, 14, 15, 16]);

-- Prueba 7: exactamente 6 asientos
-- Resultado esperado: FUNCIONA
select * from fn_bloquear_asientos(2, 1, array[10, 11, 12, 13, 14, 15]);

-- Prueba 8: lista vacía y asientos repetidos
-- Resultado esperado: ERROR en los dos
select * from fn_bloquear_asientos(2, 1, array[]::bigint[]);
select * from fn_bloquear_asientos(2, 1, array[20, 20]);

-- Prueba 9: un asiento de otra sala (el 81 es de la sala de la función 5)
-- Resultado esperado: ERROR (no pertenece a la sala)
select * from fn_bloquear_asientos(2, 1, array[81]);

-- Prueba 10: función cancelada
-- Resultado esperado: ERROR (la función no está disponible)
update funcion set estado = 'Cancelada' where id = 2;
select * from fn_bloquear_asientos(2, 2, array[1]);

-- Prueba 11: el bloqueo del asiento 1 vence y otro usuario puede tomarlo
-- Resultado esperado: FUNCIONA
update reserva_asiento set bloqueado_hasta = now() - interval '1 minute' where asiento_id = 1;
select * from fn_bloquear_asientos(2, 1, array[1]);

-- Prueba 12: quedó registro en las bitácoras
-- Resultado esperado: filas de BLOQUEADO y de EXPIRADO para el asiento 1; transacciones de tipo BLOQUEO
select asiento_id, estado_anterior, estado_nuevo from asiento_auditoria_log where asiento_id = 1 order by id;
select tipo, resultado, detalle from transaccion_log order by id;


\c postgres
\encoding UTF8
drop database if exists imax_prueba;
create database imax_prueba template imax_base;
\c imax_prueba
\encoding UTF8
\echo
\echo '################ Pruebas: fn_asignar_tipos ################'

-- Pruebas de fn_asignar_tipos 
-- Se corre sobre una base nueva con todos los DDL (incluida la lógica de catálogo de Mati) y el seed.
-- Tipos de entrada: 1 Adulto, 2 Niño, 3 Adulto mayor, 4 Estudiante. Usuarios 1 y 2. Función 1, asientos 1 a 80.
-- Los precios del seed dependen del día y la hora de la función, por eso se comparan contra fn_calcular_total.

select * from fn_bloquear_asientos(1, 1, array[1, 2]);

-- Prueba 1: elegir tipo Adulto para los dos asientos
-- Resultado esperado: FUNCIONA, devuelve subtotal, descuento, cargo, total y el detalle por asiento
select subtotal, descuento, cargo_servicio, total from fn_asignar_tipos(1, 1, array[1, 2], array[1, 1]);

-- Prueba 2: la orden guardó los mismos montos que calcula fn_calcular_total
-- Resultado esperado: coincide = true
select o.total = c.total and o.subtotal = c.subtotal as coincide
from orden o, fn_calcular_total(1, array[1, 2], array[1, 1]) c
where o.id = 1;

-- Prueba 3: cada reserva guardó su tipo de entrada y su precio
-- Resultado esperado: 2 filas con tipo_entrada_id = 1 y precio mayor que 0
select asiento_id, tipo_entrada_id, precio, cargo_servicio from reserva_asiento where orden_id = 1 order by asiento_id;

-- Prueba 4: otro usuario intenta asignar tipos a esa orden
-- Resultado esperado: ERROR (la orden no le pertenece)
select * from fn_asignar_tipos(1, 2, array[1, 2], array[1, 1]);

-- Prueba 5: asientos que no son los bloqueados
-- Resultado esperado: ERROR (no coinciden con los bloqueados)
select * from fn_asignar_tipos(1, 1, array[1, 3], array[1, 1]);

-- Prueba 6: faltan asientos de la orden
-- Resultado esperado: ERROR (no coinciden con los bloqueados)
select * from fn_asignar_tipos(1, 1, array[1], array[1]);

-- Prueba 7: dos entradas de estudiante activan el 2x1 de estudiantes
-- Resultado esperado: descuento mayor que 0
select * from fn_bloquear_asientos(2, 1, array[10, 11]);
select descuento > 0 as hay_descuento_2x1 from fn_asignar_tipos(2, 2, array[10, 11], array[4, 4]);

-- Prueba 8: el bloqueo ya venció
-- Resultado esperado: ERROR (el bloqueo ya venció)
update reserva_asiento set bloqueado_hasta = now() - interval '1 minute' where orden_id = 1;
select * from fn_asignar_tipos(1, 1, array[1, 2], array[1, 1]);

-- Prueba 9: la orden ya no está pendiente
-- Resultado esperado: ERROR (la orden ya no está pendiente)
update orden set estado = 'CANCELADA' where id = 1;
select * from fn_asignar_tipos(1, 1, array[1, 2], array[1, 1]);


\c postgres
\encoding UTF8
drop database if exists imax_prueba;
create database imax_prueba template imax_base;
\c imax_prueba
\encoding UTF8
\echo
\echo '################ Pruebas: fn_confirmar_pago ################'

-- Pruebas de fn_confirmar_pago
-- Se corre sobre una base nueva con todos los DDL y el seed del catálogo.
-- Función 1, asientos 1 a 80. Usuarios 1 y 2. Tipo de entrada 1 = Adulto.

insert into metodo_pago (codigo, nombre) values ('TARJETA_SIMULADA', 'Tarjeta simulada');

-- Orden 1: usuario 1 bloquea los asientos 1 y 2 y elige tipo Adulto
select * from fn_bloquear_asientos(1, 1, array[1, 2]);
select total from fn_asignar_tipos(1, 1, array[1, 2], array[1, 1]);

-- Prueba 1: pago aprobado
-- Resultado esperado: 2 filas APROBADO, cada una con su boleto y su código QR
select resultado_pago, boleto_id, codigo_qr from fn_confirmar_pago(1, 1, 'TARJETA_SIMULADA', 'APROBADO');

-- Prueba 2: estado después del pago
-- Resultado esperado: orden PAGADA con fecha de pago; reservas VENDIDO; 1 pago APROBADO por el total de la orden
select estado, pagada_en is not null as tiene_fecha from orden where id = 1;
select asiento_id, estado from reserva_asiento where orden_id = 1 order by asiento_id;
select p.resultado, p.monto = o.total as monto_correcto from pago p join orden o on o.id = p.orden_id where o.id = 1;

-- Prueba 3: los códigos QR son distintos entre sí
-- Resultado esperado: 2 boletos y 2 códigos distintos
select count(*) as boletos, count(distinct codigo_qr) as codigos_distintos from boleto;

-- Prueba 4: volver a pagar la misma orden
-- Resultado esperado: ERROR (la orden ya no está pendiente)
select * from fn_confirmar_pago(1, 1, 'TARJETA_SIMULADA', 'APROBADO');

-- Orden 2: usuario 1 bloquea los asientos 10 y 11 y elige tipo Adulto
select * from fn_bloquear_asientos(1, 1, array[10, 11]);
select total from fn_asignar_tipos(2, 1, array[10, 11], array[1, 1]);

-- Prueba 5: pago rechazado
-- Resultado esperado: RECHAZADO, sin boleto ni código QR
select * from fn_confirmar_pago(2, 1, 'TARJETA_SIMULADA', 'RECHAZADO');

-- Prueba 6: los asientos se liberaron al instante, no se emitió ningún boleto
-- Resultado esperado: orden CANCELADA; reservas LIBERADO; asientos 10 y 11 DISPONIBLE; sigue habiendo solo 2 boletos
select estado from orden where id = 2;
select asiento_id, estado from reserva_asiento where orden_id = 2 order by asiento_id;
select asiento_id, estado from fn_mapa_asientos(1) where asiento_id in (1, 2, 10, 11) order by asiento_id;
select count(*) as boletos from boleto;

-- Prueba 7: otro usuario ya puede tomar el asiento 10 apenas se rechazó el pago
-- Resultado esperado: FUNCIONA
select * from fn_bloquear_asientos(2, 1, array[10]);

-- Prueba 8: otro usuario intenta pagar una orden ajena (la orden 3 es del usuario 2)
-- Resultado esperado: ERROR (la orden no le pertenece)
select * from fn_confirmar_pago(3, 1, 'TARJETA_SIMULADA', 'APROBADO');

-- Prueba 9: pagar sin haber elegido el tipo de entrada
-- Resultado esperado: ERROR (primero debe elegir el tipo de entrada)
select * from fn_confirmar_pago(3, 2, 'TARJETA_SIMULADA', 'APROBADO');

-- Prueba 10: método de pago que no existe, y resultado inválido
-- Resultado esperado: ERROR en los dos
select * from fn_confirmar_pago(3, 2, 'BITCOIN', 'APROBADO');
select * from fn_confirmar_pago(3, 2, 'TARJETA_SIMULADA', 'TAL_VEZ');

-- Prueba 11: el bloqueo venció antes de pagar
-- Resultado esperado: ERROR (el bloqueo venció)
select total from fn_asignar_tipos(3, 2, array[10], array[1]);
update reserva_asiento set bloqueado_hasta = now() - interval '1 minute' where orden_id = 3;
select * from fn_confirmar_pago(3, 2, 'TARJETA_SIMULADA', 'APROBADO');

-- Prueba 12: quedó todo en las bitácoras
-- Resultado esperado: VENDIDO x2, LIBERADO x2 en asientos; PAGO APROBADO, EMISION_BOLETO, PAGO RECHAZADO y LIBERACION en transacciones
select estado_nuevo, count(*) from asiento_auditoria_log where estado_nuevo in ('VENDIDO', 'LIBERADO') group by estado_nuevo order by 1;
select tipo, resultado from transaccion_log where tipo in ('PAGO', 'EMISION_BOLETO', 'LIBERACION') order by id;


\c postgres
\encoding UTF8
drop database if exists imax_prueba;
create database imax_prueba template imax_base;
\c imax_prueba
\encoding UTF8
\echo
\echo '################ Pruebas: seed de venta y consultas analíticas ################'

-- Métodos de pago simulados (no se guarda ningún dato de tarjeta)
-- Los códigos son los que usa el combo de app/public/venta/pago.html
insert into metodo_pago (codigo, nombre) values
    ('TARJETA_SIMULADA', 'Tarjeta simulada'),
    ('PAYPAL_SIMULADO', 'PayPal simulado'),
    ('BILLETERA_SIMULADA', 'Billetera digital simulada')
on conflict (codigo) do nothing;
-- Datos de venta para la demo
-- Las compras son en funciones de "Sala 1 IMAX Laser" (80 asientos, ids 1 a 80); la última compra va en otra función de esa sala.
-- Requiere todos los DDL, 01_catalogo_demo.sql y el seed de métodos de pago.
-- Usa las mismas funciones que la aplicación, así que los datos quedan como los de una compra real.

-- Orden 1: el cliente compra 2 asientos de la primera función de la sala y paga (aprobado)
select * from fn_bloquear_asientos(1, (select min(id) from funcion where sala_id = 1), array[1, 2]);
select total from fn_asignar_tipos(1, 1, array[1, 2], array[1, 4]);
select resultado_pago from fn_confirmar_pago(1, 1, 'TARJETA_SIMULADA', 'APROBADO');

-- Orden 2: otra compra de 3 asientos en la misma función pagada con PayPal
select * from fn_bloquear_asientos(1, (select min(id) from funcion where sala_id = 1), array[10, 11, 12]);
select total from fn_asignar_tipos(2, 1, array[10, 11, 12], array[1, 1, 2]);
select resultado_pago from fn_confirmar_pago(2, 1, 'PAYPAL_SIMULADO', 'APROBADO');

-- Orden 3: un pago rechazado (los asientos quedan libres)
select * from fn_bloquear_asientos(1, (select min(id) from funcion where sala_id = 1), array[20, 21]);
select total from fn_asignar_tipos(3, 1, array[20, 21], array[1, 1]);
select resultado_pago from fn_confirmar_pago(3, 1, 'BILLETERA_SIMULADA', 'RECHAZADO');

-- Orden 4: una compra en otra función de la sala con billetera
select * from fn_bloquear_asientos(1, (select max(id) from funcion where sala_id = 1), array[50]);
select total from fn_asignar_tipos(4, 1, array[50], array[1]);
select resultado_pago from fn_confirmar_pago(4, 1, 'BILLETERA_SIMULADA', 'APROBADO');

-- Orden 5: un bloqueo que se venció sin pagar
select * from fn_bloquear_asientos(1, (select min(id) from funcion where sala_id = 1), array[30, 31]);
update reserva_asiento set bloqueado_hasta = now() - interval '5 minutes' where orden_id = 5;
select fn_liberar_expirados();

-- Orden 6: un bloqueo vigente (el cliente sigue eligiendo)
select * from fn_bloquear_asientos(1, (select min(id) from funcion where sala_id = 1), array[40]);
-- Revisión del seed de venta
-- Resultado esperado: PAGADA x3, CANCELADA x1, EXPIRADA x1, PENDIENTE x1
select estado, count(*) from orden group by estado order by estado;

-- Resultado esperado: 6 boletos EMITIDO (2 + 3 + 1) y todos con QR distinto
select count(*) as boletos, count(distinct codigo_qr) as qr_distintos from boleto where estado = 'EMITIDO';

-- Resultado esperado: APROBADO x3 y RECHAZADO x1
select resultado, count(*) from pago group by resultado order by resultado;

-- Resultado esperado: asientos 1, 2, 10, 11, 12 VENDIDO; 20, 21, 30, 31 DISPONIBLE; 40 BLOQUEADO
select asiento_id, estado from fn_mapa_asientos(1)
where asiento_id in (1, 2, 10, 11, 12, 20, 21, 30, 31, 40) order by asiento_id;

-- Resultado esperado: asiento 50 VENDIDO en la función 2 y DISPONIBLE en la función 1
select 2 as funcion, estado from fn_mapa_asientos(2) where asiento_id = 50
union all
select 1, estado from fn_mapa_asientos(1) where asiento_id = 50;

-- Pruebas de las consultas sobre el seed de venta (10_metodos_pago.sql y 11_seed_venta.sql)

-- Prueba 1 (consulta 1, función 1): ocupación y recaudación
-- Resultado esperado: 5 asientos vendidos de 80, 6.25 % de ocupación y 57.75 recaudado (órdenes 1 y 2)
select (select count(*) from boleto b where b.funcion_id = 1 and b.estado <> 'ANULADO') as vendidos,
       (select sum(total) from orden where funcion_id = 1 and estado = 'PAGADA') as recaudado;

-- Prueba 2: una función sin ventas
-- Resultado esperado: 0 vendidos, 0.00 % y recaudado 0
select f.id,
       (select count(*) from boleto b where b.funcion_id = f.id and b.estado <> 'ANULADO') as vendidos,
       coalesce((select sum(o.total) from orden o where o.funcion_id = f.id and o.estado = 'PAGADA'), 0) as recaudado
  from funcion f where f.id = 3;

-- Prueba 3: un boleto anulado deja de contar en la ocupación
-- Resultado esperado: baja de 5 a 4 vendidos
update boleto set estado = 'ANULADO' where id = 1;
select count(*) as vendidos from boleto where funcion_id = 1 and estado <> 'ANULADO';
update boleto set estado = 'EMITIDO' where id = 1;

-- Prueba 4 (consulta 3): los pagos rechazados no cuentan
-- Resultado esperado: 3 pagos aprobados en total, 33.33 % cada método
select count(*) as aprobados from pago where resultado = 'APROBADO';

-- Prueba 5: un método que nadie ha usado sale con cero pagos
-- Resultado esperado: el método nuevo aparece con 0 pagos y 0.00 %; los demás siguen en 33.33 %
-- (después de insertar, correr de nuevo 21_consulta_metodos_pago.sql)
insert into metodo_pago (codigo, nombre) values ('PRUEBA', 'Método de prueba');


\c postgres
\encoding UTF8
drop database if exists imax_prueba;
create database imax_prueba template imax_base;
\c imax_prueba
\encoding UTF8
\echo
\echo '################ Pruebas: fn_mis_boletos ################'

-- Pruebas de fn_mis_boletos 
-- Se corre sobre una base nueva con todos los DDL y el seed del catálogo.

insert into metodo_pago (codigo, nombre) values ('TARJETA_SIMULADA', 'Tarjeta simulada');

-- Prueba 1: antes de comprar no hay boletos
-- Resultado esperado: 0 filas
select count(*) from fn_mis_boletos(1);

-- El usuario 1 compra 2 asientos; el usuario 2 compra 1
select * from fn_bloquear_asientos(1, 1, array[1, 2]);
select total from fn_asignar_tipos(1, 1, array[1, 2], array[1, 1]);
select resultado_pago from fn_confirmar_pago(1, 1, 'TARJETA_SIMULADA', 'APROBADO');
select * from fn_bloquear_asientos(2, 1, array[20]);
select total from fn_asignar_tipos(2, 2, array[20], array[1]);
select resultado_pago from fn_confirmar_pago(2, 2, 'TARJETA_SIMULADA', 'APROBADO');

-- Prueba 2: el usuario 1 ve sus 2 boletos con película, sala, asiento y estado
-- Resultado esperado: 2 filas EMITIDO (asientos 1 y 2 de la sala, ver fila y número)
select boleto_id, codigo_qr, titulo, sala, fila, numero, estado from fn_mis_boletos(1);

-- Prueba 3: el usuario 2 solo ve el suyo
-- Resultado esperado: 1 fila
select count(*) from fn_mis_boletos(2);

-- Prueba 4: un usuario sin compras
-- Resultado esperado: 0 filas
select count(*) from fn_mis_boletos(3);

-- Prueba 5: un boleto pagado y otro de un pago rechazado
-- Resultado esperado: el rechazado no genera boleto (el usuario 1 sigue con 2)
select * from fn_bloquear_asientos(1, 1, array[30]);
select total from fn_asignar_tipos(3, 1, array[30], array[1]);
select resultado_pago from fn_confirmar_pago(3, 1, 'TARJETA_SIMULADA', 'RECHAZADO');
select count(*) from fn_mis_boletos(1);

\c postgres
\encoding UTF8
drop database if exists imax_prueba;
create database imax_prueba template imax_base;
\c imax_prueba
\encoding UTF8
\echo
\echo '################ Pruebas: catálogo, total y RN-18 ################'

-- Pruebas del Módulo A (catálogo, programación, total y RN-18)
-- Se corren sobre una base recién creada con 01 a 07 y el seed 01_catalogo_demo.sql:
--   psql -d imax -f database/tests/05_catalogo_logica.sql
-- Cada prueba dice qué se espera. Las que modifican datos terminan en rollback, así se puede repetir.

\pset pager off
\set sj1 '(select id from sala where nombre = ''Sala 1'')'
\set la '(select id from sala where nombre = ''Sala 1 IMAX Laser'')'
\set adulto '(select id from tipo_entrada where nombre = ''Adulto'')'
\set estudiante '(select id from tipo_entrada where nombre = ''Estudiante'')'
\set mayor '(select id from tipo_entrada where nombre = ''Adulto mayor'')'


\echo '===== Prueba 1: traslape en la misma sala. Esperado: ERROR ex_funcion_sin_traslape'
insert into funcion (pelicula_id, sala_id, inicio)
select (select id from pelicula where titulo = 'Océano Profundo'), :la,
       ((current_date + 1) + time '16:00') at time zone 'America/Costa_Rica';

\echo '===== Prueba 2: reprogramar sobre una función cancelada. Esperado: UPDATE 1 e INSERT 0 1'
begin;
update funcion set estado = 'Cancelada'
 where sala_id = :la and inicio = ((current_date + 1) + time '21:00') at time zone 'America/Costa_Rica';
insert into funcion (pelicula_id, sala_id, inicio)
select (select id from pelicula where titulo = 'La Noche Eterna'), :la,
       ((current_date + 1) + time '21:00') at time zone 'America/Costa_Rica';
rollback;

\echo '===== Prueba 3: fin y fin_limpieza calculados por el trigger. Esperado: duración y limpieza correctas'
select p.titulo, s.nombre as sala, f.fin - f.inicio as duracion, f.fin_limpieza - f.fin as limpieza
  from funcion f join pelicula p on p.id = f.pelicula_id join sala s on s.id = f.sala_id
 order by f.inicio;

\echo '===== Prueba 4: asiento repetido en la sala. Esperado: ERROR uq_asiento_sala_fila_numero'
insert into asiento (sala_id, zona_asiento_id, fila, numero)
values (:la, (select id from zona_asiento where nombre = 'General'), 'A', 1);

\echo '===== Prueba 5: tarifa repetida. Esperado: ERROR uq_tarifa_combinacion'
insert into tarifa (tipo_entrada_id, zona_asiento_id, precio)
values (:adulto, (select id from zona_asiento where nombre = 'General'), 9.00);

\echo '===== Prueba 6: promoción sin condición. Esperado: ERROR ck_promocion_condicion'
insert into promocion (nombre, requiere_cantidad_par) values ('2x1 sin condición', false);


\echo '===== Prueba 7: cartelera (RN-01, RN-02)'
begin;
-- una función de ayer y la de Sala Premium cancelada: ninguna debe salir
insert into funcion (pelicula_id, sala_id, inicio, estado)
select (select id from pelicula where titulo = 'Océano Profundo'), (select id from sala where nombre = 'Sala 2'),
       now() - interval '1 day', 'Finalizada';
update funcion set estado = 'Cancelada' where sala_id = (select id from sala where nombre = 'Sala Premium');
\echo '7a. Sin filtros. Esperado: 7 funciones, todas futuras'
select titulo, clasificacion, genero, cine, sala, inicio > now() as futura from fn_listar_cartelera(null, null, null);
\echo '7b. Ciudad San José. Esperado: 3 funciones, todas de IMAX San José'
select titulo, cine, sala from fn_listar_cartelera('San José', null, null);
\echo '7c. Género Terror. Esperado: solo La Noche Eterna en San José'
select titulo, genero, cine from fn_listar_cartelera(null, null, 'Terror');
\echo '7d. Fecha de pasado mañana. Esperado: 2 funciones'
select titulo, cine, inicio from fn_listar_cartelera(null, current_date + 2, null);
rollback;


\echo '===== Prueba 8: total de la compra (RN-07, RN-08)'
begin;
-- funciones en fechas fijas para no depender del día en que se corre la prueba
-- 2026-11-07 sábado, 2026-11-03 martes, 2026-11-04 miércoles
insert into funcion (pelicula_id, sala_id, inicio)
select (select id from pelicula where titulo = 'Océano Profundo'), :sj1, x.t at time zone 'America/Costa_Rica'
  from (values (timestamp '2026-11-07 16:00'), (timestamp '2026-11-03 11:00'), (timestamp '2026-11-04 16:00')) x(t);

\echo '8a. 2 estudiantes en General, sábado. Esperado: 13.00 - 6.50 + 1.50 = 8.00'
select subtotal, descuento, cargo_servicio, total
  from fn_calcular_total(
        (select id from funcion where inicio = timestamp '2026-11-07 16:00' at time zone 'America/Costa_Rica'),
        array(select id from asiento where sala_id = :sj1 and fila = 'A' and numero in (1, 2) order by numero),
        array[:estudiante, :estudiante]);

\echo '8b. 3 adultos en General, sábado (sin promoción). Esperado: 25.50 - 0 + 2.25 = 27.75'
select subtotal, descuento, cargo_servicio, total
  from fn_calcular_total(
        (select id from funcion where inicio = timestamp '2026-11-07 16:00' at time zone 'America/Costa_Rica'),
        array(select id from asiento where sala_id = :sj1 and fila = 'A' and numero in (1, 2, 3) order by numero),
        array[:adulto, :adulto, :adulto]);

\echo '8c. 1 adulto martes 11:00: gana la tarifa del martes (6.00) sobre la matiné (7.00). Esperado: 6.75'
select subtotal, descuento, cargo_servicio, total
  from fn_calcular_total(
        (select id from funcion where inicio = timestamp '2026-11-03 11:00' at time zone 'America/Costa_Rica'),
        array(select id from asiento where sala_id = :sj1 and fila = 'B' and numero = 1),
        array[:adulto]);

\echo '8d. Miércoles 2x1: 2 adultos y 1 adulto mayor. Esperado: 22.50 - 8.50 + 2.25 = 16.25'
select subtotal, descuento, cargo_servicio, total, jsonb_array_length(detalle) as lineas
  from fn_calcular_total(
        (select id from funcion where inicio = timestamp '2026-11-04 16:00' at time zone 'America/Costa_Rica'),
        array(select id from asiento where sala_id = :sj1 and fila = 'B' and numero in (1, 2, 3) order by numero),
        array[:adulto, :adulto, :mayor]);

\echo '8e. Asiento de otra sala. Esperado: ERROR Hay asientos que no pertenecen a la sala de la función'
select * from fn_calcular_total(
        (select id from funcion where inicio = timestamp '2026-11-07 16:00' at time zone 'America/Costa_Rica'),
        array(select id from asiento where sala_id = :la and fila = 'A' and numero = 1),
        array[:adulto]);
rollback;


\echo '===== Prueba 9: RN-18, no modificar una sala con ventas activas'
begin;
-- se vende el asiento A1 de la primera función de mañana en Los Ángeles
insert into metodo_pago (codigo, nombre) values ('TARJETA', 'Tarjeta simulada') on conflict (codigo) do nothing;
insert into orden (usuario_id, funcion_id, estado)
values ((select id from usuario where email = 'cliente@imax.test'),
        (select min(id) from funcion where sala_id = :la), 'PAGADA');
insert into reserva_asiento (orden_id, funcion_id, asiento_id, estado, bloqueado_hasta)
values ((select max(id) from orden), (select min(id) from funcion where sala_id = :la),
        (select id from asiento where sala_id = :la and fila = 'A' and numero = 1), 'VENDIDO', now());

\echo '9a. Cambiar la zona de una fila. Esperado: ERROR RN-18'
savepoint s;
update asiento set zona_asiento_id = (select id from zona_asiento where nombre = 'General') where sala_id = :la and fila = 'A';
rollback to s;
\echo '9b. Borrar una fila. Esperado: ERROR RN-18'
delete from asiento where sala_id = :la and fila = 'H';
rollback to s;
\echo '9c. Agregar un asiento. Esperado: ERROR RN-18'
insert into asiento (sala_id, zona_asiento_id, fila, numero) values (:la, (select id from zona_asiento where nombre = 'General'), 'I', 1);
rollback to s;
\echo '9d. Cambiar la capacidad de la sala. Esperado: ERROR RN-18'
update sala set capacidad = 100 where id = :la;
rollback to s;
\echo '9e. Cambiar solo el nombre de la sala (no es la distribución). Esperado: UPDATE 1'
update sala set nombre = 'Sala 1 IMAX Laser (renovada)' where id = :la;
rollback to s;
\echo '9f. Misma operación en la Sala 1 de San José, sin ventas. Esperado: UPDATE 8'
update asiento set zona_asiento_id = (select id from zona_asiento where nombre = 'VIP') where sala_id = :sj1 and fila = 'F';
rollback to s;
\echo '9g. Si el bloqueo venció, ya no cuenta como reserva. Esperado: UPDATE 1'
update reserva_asiento set estado = 'BLOQUEADO', bloqueado_hasta = now() - interval '1 minute';
update asiento set activo = false where sala_id = :la and fila = 'H' and numero = 10;
rollback;


\c postgres
\encoding UTF8
drop database if exists imax_prueba;
create database imax_prueba template imax_base;
\c imax_prueba
\encoding UTF8
\echo
\echo '################ Pruebas: check-in y reembolsos ################'

\set ON_ERROR_STOP off
begin;

-- Datos de prueba: puertas, asientos y funciones respecto a la hora actual
insert into puerta (sala_id, nombre)
select id, 'Tótem 1' from sala where nombre in ('Sala 1', 'Sala 2', 'Sala Premium');

insert into asiento (sala_id, zona_asiento_id, fila, numero)
select s.id, (select id from zona_asiento where nombre = 'General'), 'A', n
  from sala s, generate_series(1, 6) n
 where s.nombre = 'Sala 2';

create function pg_temp.crear_funcion(p_sala text, p_cine text, p_inicio timestamptz, p_estado text default 'Activa')
returns bigint language sql as $f$
    insert into funcion (pelicula_id, sala_id, inicio, estado)
    select (select min(id) from pelicula), s.id, p_inicio, p_estado
      from sala s join cine c on c.id = s.cine_id
     where s.nombre = p_sala and c.nombre = p_cine
    returning id;
$f$;

create function pg_temp.crear_boleto(p_funcion bigint, p_numero integer, p_qr text, p_estado text default 'EMITIDO')
returns bigint language plpgsql as $f$
declare v_orden bigint; v_reserva bigint; v_asiento bigint; v_boleto bigint;
begin
    select a.id into v_asiento from asiento a join funcion f on f.sala_id = a.sala_id
     where f.id = p_funcion and a.numero = p_numero order by a.fila limit 1;
    insert into orden (usuario_id, funcion_id, estado, subtotal, descuento, cargo_servicio, total, pagada_en)
    values ((select id from usuario where email = 'cliente@imax.test'), p_funcion, 'PAGADA', 8.50, 0, 0.75, 9.25, now())
    returning id into v_orden;
    insert into reserva_asiento (orden_id, funcion_id, asiento_id, estado, bloqueado_hasta, precio, cargo_servicio)
    values (v_orden, p_funcion, v_asiento, 'VENDIDO', now(), 8.50, 0.75) returning id into v_reserva;
    insert into boleto (orden_id, reserva_asiento_id, funcion_id, asiento_id, codigo_qr, estado)
    values (v_orden, v_reserva, p_funcion, v_asiento, p_qr, p_estado) returning id into v_boleto;
    return v_boleto;
end $f$;

-- F1: empieza en 10 min (dentro de la ventana). F2: en 6 horas. F3: empezó hace 30 min. F4: cancelada.
select pg_temp.crear_funcion('Sala 1', 'IMAX San José', now() + interval '10 minutes') as f1 \gset
select pg_temp.crear_funcion('Sala 1', 'IMAX San José', now() + interval '6 hours') as f2 \gset
select pg_temp.crear_funcion('Sala 2', 'IMAX San José', now() - interval '30 minutes') as f3 \gset
select pg_temp.crear_funcion('Sala 2', 'IMAX San José', now() + interval '2 hours', 'Cancelada') as f4 \gset

select pg_temp.crear_boleto(:f1, 1, 'QR-OK-1') as b_ok \gset
select pg_temp.crear_boleto(:f1, 2, 'QR-FORZADO') as b_forzado \gset
select pg_temp.crear_boleto(:f1, 3, 'QR-USADO', 'USADO') as b_usado \gset
select pg_temp.crear_boleto(:f1, 4, 'QR-ANULADO', 'ANULADO') as b_anulado \gset
select pg_temp.crear_boleto(:f2, 1, 'QR-TEMPRANO') as b_temprano \gset
select pg_temp.crear_boleto(:f3, 1, 'QR-TARDE') as b_tarde \gset
select pg_temp.crear_boleto(:f4, 1, 'QR-CANCELADA') as b_cancelada \gset

select p.id as p_sj1 from puerta p join sala s on s.id = p.sala_id join cine c on c.id = s.cine_id where s.nombre = 'Sala 1' and c.nombre = 'IMAX San José' \gset
select p.id as p_sj2 from puerta p join sala s on s.id = p.sala_id where s.nombre = 'Sala 2' \gset
select p.id as p_prem from puerta p join sala s on s.id = p.sala_id where s.nombre = 'Sala Premium' \gset
select id as admin from usuario where email = 'admin@imax.test' \gset
select id as taq from usuario where email = 'taquilla@imax.test' \gset

\echo '=== CHECK-IN (RN-14, RN-15, RN-16) ==='
\echo '1. Primer escaneo valido (debe entrar)'
select * from fn_validar_entrada('QR-OK-1', :p_sj1);
\echo '2. Segundo escaneo del mismo QR (debe decir Entrada ya utilizada)'
select * from fn_validar_entrada('QR-OK-1', :p_sj1);
\echo '3. QR que no existe'
select * from fn_validar_entrada('QR-INVENTADO', :p_sj1);
\echo '4. Entrada de Sala 1 escaneada en otra sala'
select * from fn_validar_entrada('QR-FORZADO', :p_prem);
\echo '5. Funcion que empieza en 6 horas (antes de la ventana)'
select * from fn_validar_entrada('QR-TEMPRANO', :p_sj1);
\echo '6. Funcion que empezo hace 30 min (fuera de tolerancia)'
select * from fn_validar_entrada('QR-TARDE', :p_sj2);
\echo '7. Funcion cancelada'
select * from fn_validar_entrada('QR-CANCELADA', :p_sj2);
\echo '8. Entrada anulada'
select * from fn_validar_entrada('QR-ANULADO', :p_sj1);
\echo '9. Puerta inexistente'
select * from fn_validar_entrada('QR-FORZADO', 99999);

\echo '--- Bitacora de accesos'
select resultado, motivo, count(*) from acceso_puerta_log group by 1, 2 order by 1, 2;
\echo '--- El boleto de la prueba 1 quedo USADO'
select codigo_qr, estado, usado_en is not null as con_fecha_de_uso from boleto where codigo_qr = 'QR-OK-1';

\echo '=== REEMBOLSOS (RN-19, RN-20) ==='
\echo '10. Reembolso dentro de la politica (funcion en 6 horas)'
select * from fn_reembolsar(:b_temprano, :admin, 'Cliente no puede asistir');
\echo '    boleto anulado, asiento liberado, orden reembolsada'
select b.estado as boleto, r.estado as reserva, o.estado as orden
  from boleto b join reserva_asiento r on r.id = b.reserva_asiento_id join orden o on o.id = b.orden_id where b.id = :b_temprano;
\echo '    el QR reembolsado ya no entra'
select * from fn_validar_entrada('QR-TEMPRANO', :p_sj1);
\echo '11. Reembolso fuera de politica (funcion en 10 min): forzado'
select * from fn_reembolsar(:b_forzado, :admin, 'Falla tecnica en la sala');
\echo '12. Boleto ya usado (debe rechazar)'
select * from fn_reembolsar(:b_ok, :admin, 'Intento sobre boleto usado');
\echo '13. Quien no es administrador (debe rechazar)'
select * from fn_reembolsar(:b_tarde, :taq, 'Taquillero intenta reembolsar');
\echo '14. Sin motivo (debe rechazar)'
select * from fn_reembolsar(:b_tarde, :admin, '');
\echo '15. Segundo reembolso del mismo boleto (debe rechazar)'
select * from fn_reembolsar(:b_temprano, :admin, 'Repetido');

\echo '--- Tabla reembolso'
select boleto_id, monto, forzado, motivo from reembolso order by id;
\echo '--- Auditoria administrativa (RN-20): usuario, rol, accion, ip'
select a.accion, u.email, r.nombre as rol, a.ip, a.motivo, a.detalle
  from admin_operacion_audit a join usuario u on u.id = a.usuario_id join rol r on r.id = a.rol_id order by a.id;
\echo '--- Bitacora de transacciones'
select tipo, monto, resultado from transaccion_log where tipo = 'REEMBOLSO' order by id;
\echo '--- Bitacora inalterable (ambos deben fallar)'
savepoint prueba_update;
update acceso_puerta_log set resultado = 'EXITOSO';
rollback to prueba_update;
delete from acceso_puerta_log;

rollback;

\c postgres
\encoding UTF8
drop database if exists imax_prueba;
create database imax_prueba template imax_base;
\c imax_prueba
\encoding UTF8
\echo
\echo '################ Pruebas: permisos por rol ################'

\set ON_ERROR_STOP off

\echo '=== CLIENTE ==='
set role rol_cliente;
select count(*) as peliculas_visibles from pelicula;
\echo '-- cliente lee usuario (debe fallar)'
select * from usuario;
\echo '-- cliente modifica tarifa (debe fallar)'
update tarifa set precio = 0;
\echo '-- cliente se registra como admin (debe fallar)'
select fn_registrar_usuario('x@x.com', 'X', 'Y', 'Clave12345', 'administrador');
reset role;

\echo '=== TAQUILLERO ==='
set role rol_taquillero;
select count(*) as tarifas_visibles from tarifa;
\echo '-- taquillero modifica precio (debe fallar)'
update tarifa set precio = 1;
\echo '-- taquillero crea sala (debe fallar)'
insert into sala (cine_id, nombre, capacidad) values (1, 'Hack', 10);
\echo '-- taquillero lee bitácora (debe fallar)'
select * from admin_operacion_audit;
reset role;

\echo '=== OPERADOR DE SALA ==='
set role rol_operador_sala;
select count(*) as puertas_visibles from puerta;
\echo '-- operador crea puerta (debe fallar)'
insert into puerta (sala_id, nombre) values (1, 'Falsa');
\echo '-- operador modifica funcion (debe fallar)'
update funcion set estado = 'Cancelada';
reset role;

\echo '=== CONTADOR ==='
set role rol_contador;
select count(*) as funciones_visibles from funcion;
\echo '-- contador modifica programación (debe fallar)'
delete from funcion;
reset role;

\echo '=== ADMINISTRADOR ==='
set role rol_administrador;
insert into genero (nombre) values ('Musical');
select count(*) as usuarios_visibles from usuario;
\echo '-- administrador lee el hash (debe fallar)'
select password_hash from usuario;
\echo '-- administrador altera bitácora (debe fallar)'
update admin_operacion_audit set motivo = 'x';
delete from admin_operacion_audit;
\echo '-- administrador crea partición (debe fallar)'
select fn_crear_particion_admin_audit(current_date);
reset role;


\c postgres
\encoding UTF8
drop database if exists imax_prueba;
drop database if exists imax_base;
\echo
\echo 'Pruebas terminadas'