-- Datos de venta SOLO para medir el Top 5 con EXPLAIN ANALYZE mientras no exista 14_masivo_venta.sql (Juanjo)
-- Requiere 03_venta.sql y 12_masivo_catalogo.sql. No usar junto con 14_masivo_venta.sql.
-- Vende de 1 a 5 asientos por función en los últimos 90 días (unos 2 millones de boletos).
-- La cantidad por función depende del id de la película, y 5 películas venden más para que el Top 5 no salga empatado.

begin;

insert into metodo_pago (codigo, nombre)
values ('TARJETA', 'Tarjeta simulada')
on conflict (codigo) do nothing;

-- una orden pagada por función, a nombre del cliente de prueba
create temp table venta_tmp on commit drop as
select f.id as funcion_id, f.inicio, a.id as asiento_id
  from funcion f
  join lateral (
        select id from asiento
         where sala_id = f.sala_id and activo
         order by id
         limit 1 + (f.pelicula_id % 5) + coalesce(
                 (select e.extra
                    from (values ('Película 007', 12), ('Película 123', 9), ('Película 250', 5),
                                 ('Película 333', 5), ('Película 499', 3)) e(titulo, extra)
                    join pelicula p on p.titulo = e.titulo
                   where p.id = f.pelicula_id), 0)) a on true
 where f.estado = 'Finalizada'
   and f.inicio >= now() - interval '90 days';

with nuevas as (
    insert into orden (usuario_id, funcion_id, estado, creada_en, pagada_en)
    select (select id from usuario where email = 'cliente@imax.test'), funcion_id, 'PAGADA',
           min(inicio) - interval '2 days', min(inicio) - interval '2 days'
      from venta_tmp
     group by funcion_id
    returning id, funcion_id
),
reservas as (
    insert into reserva_asiento (orden_id, funcion_id, asiento_id, estado, bloqueado_hasta, creada_en)
    select n.id, v.funcion_id, v.asiento_id, 'VENDIDO', v.inicio - interval '2 days', v.inicio - interval '2 days'
      from venta_tmp v join nuevas n on n.funcion_id = v.funcion_id
    returning id, orden_id, funcion_id, asiento_id, creada_en
)
insert into boleto (orden_id, reserva_asiento_id, funcion_id, asiento_id, codigo_qr, estado, emitido_en)
select r.orden_id, r.id, r.funcion_id, r.asiento_id, md5('qr-' || r.id), 'USADO', r.creada_en
  from reservas r;

commit;

analyze orden, reserva_asiento, boleto;
