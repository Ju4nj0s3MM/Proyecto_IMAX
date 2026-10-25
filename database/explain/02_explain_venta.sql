-- Planes de ejecución de las consultas de venta
-- Se corre dos veces sobre los datos masivos: antes y después de 09_venta_indices.sql
--   psql -d imax -f database/explain/02_explain_venta.sql > database/explain/venta_antes.txt
--   psql -d imax -f database/explain/02_explain_venta.sql > database/explain/venta_despues.txt
-- La función 500001 tiene ventas en los datos masivos; cambiar el número si se usan otros datos.

-- 1. Ocupación y recaudación de una función (consulta 1)
explain (analyze, buffers)
select f.id as funcion_id, p.titulo, s.capacidad,
       (select count(*) from boleto b where b.funcion_id = f.id and b.estado <> 'ANULADO') as asientos_vendidos,
       coalesce((select sum(o.total) from orden o where o.funcion_id = f.id and o.estado = 'PAGADA'), 0) as recaudado
  from funcion f
  join pelicula p on p.id = f.pelicula_id
  join sala s on s.id = f.sala_id
 where f.id = 500001;

-- 2. Métodos de pago más usados (consulta 3)
explain (analyze, buffers)
select m.nombre, count(p.id) as pagos,
       round(100.0 * count(p.id) / nullif(sum(count(p.id)) over (), 0), 2) as porcentaje_uso
  from metodo_pago m
  left join pago p on p.metodo_pago_id = m.id and p.resultado = 'APROBADO'
 group by m.id, m.nombre
 order by pagos desc;

-- 3. Mapa de asientos de una función
explain (analyze, buffers)
select * from fn_mapa_asientos(500001);

-- 4. Liberación de bloqueos vencidos
explain (analyze, buffers)
select id from reserva_asiento where estado = 'BLOQUEADO' and bloqueado_hasta < now();