-- Consulta analítica: métodos de pago más usados
-- Cuenta solo los pagos aprobados. porcentaje_uso es la parte de los pagos que se hizo con cada método.
-- Los métodos que nadie ha usado salen con cero.

select m.nombre as metodo_pago,
       count(p.id) as pagos,
       round(100.0 * count(p.id) / nullif(sum(count(p.id)) over (), 0), 2) as porcentaje_uso,
       coalesce(sum(p.monto), 0) as monto_total
  from metodo_pago m
  left join pago p on p.metodo_pago_id = m.id and p.resultado = 'APROBADO'
 group by m.id, m.nombre
 order by pagos desc, m.nombre;