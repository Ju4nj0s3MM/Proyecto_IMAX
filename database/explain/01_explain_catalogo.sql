-- Planes de ejecución de las consultas pesadas del Módulo A
-- Se corre dos veces: antes y después de 10_catalogo_indices.sql, sobre los datos masivos.
--   psql -d imax -f database/explain/01_explain_catalogo.sql > database/explain/antes.txt
-- La función fn_listar_cartelera es SQL simple, así que PostgreSQL la "abre" y el plan muestra la consulta de adentro.

\pset pager off
\timing on

\echo '===== 1. Cartelera sin filtros (próximos 7 días)'
explain (analyze, costs, buffers)
select * from fn_listar_cartelera(null, null, null);

\echo '===== 2. Cartelera por ciudad y fecha'
explain (analyze, costs, buffers)
select * from fn_listar_cartelera('Tokio', current_date + 3, null);

\echo '===== 3. Cartelera por género'
explain (analyze, costs, buffers)
select * from fn_listar_cartelera(null, null, 'Drama');

\echo '===== 4. Top 5 de la última semana'
explain (analyze, costs, buffers)
select p.id as pelicula_id,
       p.titulo,
       count(*) as boletos_vendidos,
       count(distinct b.funcion_id) as funciones,
       round(100.0 * count(*) / sum(count(*)) over (), 2) as porcentaje_semana
  from boleto b
  join funcion f on f.id = b.funcion_id
  join pelicula p on p.id = f.pelicula_id
 where b.emitido_en >= now() - interval '7 days'
   and b.estado <> 'ANULADO'
 group by p.id, p.titulo
 order by boletos_vendidos desc, p.titulo
 limit 5;
