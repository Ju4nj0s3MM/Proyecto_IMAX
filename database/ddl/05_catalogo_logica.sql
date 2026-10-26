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

