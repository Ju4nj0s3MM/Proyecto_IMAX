-- 14 Datos masivos de venta para las pruebas de rendimiento (EXPLAIN ANALYZE)
-- Requiere los DDL de venta, 10_metodos_pago.sql y 12_masivo_catalogo.sql (de ahí salen las funciones).
-- No usar junto con explain/00_datos_venta_prueba.sql.
-- Para cada función ya finalizada de los últimos 90 días crea una orden pagada con 1 a 5 asientos,
-- su pago (reparto de métodos 50/30/20) y sus boletos. Además deja pagos rechazados (unos 8 %) sin boletos.

begin;

-- asientos que se venden en cada función (los primeros 1 a 5 de la sala)
create temp table venta_tmp on commit drop as
select f.id as funcion_id, f.inicio, a.id as asiento_id,
       row_number() over (partition by f.id order by a.id) as n
  from funcion f
  join lateral (select id from asiento
                 where sala_id = f.sala_id and activo
                 order by id
                 limit 1 + (f.id % 5)) a on true
 where f.estado = 'Finalizada'
   and f.inicio >= now() - interval '90 days';

-- una orden pagada por función
with nuevas as (
    insert into orden (usuario_id, funcion_id, estado, subtotal, descuento, cargo_servicio, total, creada_en, pagada_en)
    select 1, v.funcion_id, 'PAGADA',
           count(*) * 8.50, 0, count(*) * 0.50, count(*) * 9.00,
           min(v.inicio) - interval '2 days', min(v.inicio) - interval '2 days'
      from venta_tmp v
     group by v.funcion_id
    returning id, funcion_id, total, pagada_en
),
pagos as (
    insert into pago (orden_id, metodo_pago_id, monto, resultado, referencia, creado_en)
    select n.id,
           (select id from metodo_pago
             order by codigo
             offset case when n.id % 10 < 5 then 2 when n.id % 10 < 8 then 1 else 0 end limit 1),
           n.total, 'APROBADO', 'MASIVO-' || n.id, n.pagada_en
      from nuevas n
    returning orden_id
),
reservas as (
    insert into reserva_asiento (orden_id, funcion_id, asiento_id, estado, bloqueado_hasta, precio, cargo_servicio, creada_en)
    select n.id, v.funcion_id, v.asiento_id, 'VENDIDO', n.pagada_en, 8.50, 0.50, n.pagada_en
      from venta_tmp v join nuevas n on n.funcion_id = v.funcion_id
    returning id, orden_id, funcion_id, asiento_id, creada_en
)
insert into boleto (orden_id, reserva_asiento_id, funcion_id, asiento_id, codigo_qr, estado, emitido_en)
select r.orden_id, r.id, r.funcion_id, r.asiento_id, md5('qr-' || r.id), 'USADO', r.creada_en
  from reservas r;

-- pagos rechazados: órdenes canceladas, una de cada 12 funciones
with canceladas as (
    insert into orden (usuario_id, funcion_id, estado, subtotal, descuento, cargo_servicio, total, creada_en)
    select 1, f.id, 'CANCELADA', 8.50, 0, 0.50, 9.00, f.inicio - interval '2 days'
      from funcion f
     where f.estado = 'Finalizada' and f.inicio >= now() - interval '90 days' and f.id % 12 = 0
    returning id, creada_en
)
insert into pago (orden_id, metodo_pago_id, monto, resultado, referencia, creado_en)
select c.id, (select id from metodo_pago order by codigo limit 1), 9.00, 'RECHAZADO', 'MASIVO-R' || c.id, c.creada_en
  from canceladas c;

commit;

analyze orden, reserva_asiento, boleto, pago;