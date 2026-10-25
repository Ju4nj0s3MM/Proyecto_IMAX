-- Consulta analítica: ocupación y recaudación por función
-- Porcentaje de asientos vendidos frente a la capacidad de la sala e ingresos de la función.
-- Cuenta los boletos que no están anulados y suma solo las órdenes pagadas (las reembolsadas no cuentan).
-- Para ver todas las funciones basta quitar el where.
-- Índices que usa: idx_boleto_funcion e idx_orden_funcion_estado (09_venta_indices.sql)

select f.id as funcion_id,
       p.titulo,
       s.nombre as sala,
       f.inicio,
       s.capacidad,
       (select count(*) from boleto b
         where b.funcion_id = f.id and b.estado <> 'ANULADO') as asientos_vendidos,
       round(100.0 * (select count(*) from boleto b
                       where b.funcion_id = f.id and b.estado <> 'ANULADO') / s.capacidad, 2) as porcentaje_ocupacion,
       coalesce((select sum(o.total) from orden o
                  where o.funcion_id = f.id and o.estado = 'PAGADA'), 0) as recaudado
  from funcion f
  join pelicula p on p.id = f.pelicula_id
  join sala s on s.id = f.sala_id
 where f.id = 1;  -- la función 1 es la que tiene las ventas del seed