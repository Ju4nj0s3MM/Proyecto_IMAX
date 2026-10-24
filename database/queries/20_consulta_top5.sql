-- Consulta analítica 2: Top 5 de películas más demandadas en la última semana (nivel global)
-- Dueño: Matias Esquivel Lizano
-- Cuenta los boletos emitidos en los últimos 7 días, sin contar los anulados (reembolsados).
-- porcentaje_semana: parte de todos los boletos de la semana que se llevó cada película.
-- Índice que usa: idx_boleto_emitido (10_catalogo_indices.sql)

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
