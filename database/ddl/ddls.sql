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
       -- una sala sin asientos activos no tiene nada que vender
       and exists (select 1 from asiento a where a.sala_id = s.id and a.activo)
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