-- Creación de la cartelera, cálculos de los totales y demás reglas de negocio del módulo A
-- Matías Esquivel Lizano



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





