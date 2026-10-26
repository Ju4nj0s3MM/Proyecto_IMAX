-- Datos para mostrar el check-in en la demo
-- Una función en la Sala 1 de San José que empieza en 20 minutos (la puerta abre 30 minutos antes)
-- y dos entradas del cliente con los QR IMAX-DEMO-1 e IMAX-DEMO-2 (asientos A1 y A2).
-- Las entradas sirven hasta 15 minutos después del inicio. Si ya pasó la hora, volver a correr este archivo:
-- mueve la función a 20 minutos desde ahora y deja otra vez sin usar las entradas que ya se escanearon.
-- Va después de 11_seed_venta.sql, que usa ids de orden fijos.

select exists (select 1 from boleto where codigo_qr = 'IMAX-DEMO-1') as demo_creada \gset

\if :demo_creada
update funcion set inicio = now() + interval '20 minutes'
 where id = (select funcion_id from boleto where codigo_qr = 'IMAX-DEMO-1');
update boleto set estado = 'EMITIDO' where codigo_qr in ('IMAX-DEMO-1', 'IMAX-DEMO-2') and estado = 'USADO';
\else
insert into funcion (pelicula_id, sala_id, inicio)
select (select id from pelicula where titulo = 'La Noche Eterna'), s.id, now() + interval '20 minutes'
  from sala s join cine c on c.id = s.cine_id
 where c.nombre = 'IMAX San José' and s.nombre = 'Sala 1'
returning id as funcion_demo, sala_id as sala_demo \gset

select array_agg(id order by numero) as asientos_demo
  from asiento where sala_id = :sala_demo and fila = 'A' and numero in (1, 2) \gset

-- La compra pasa por las mismas funciones que la aplicación
select reserva_id as orden_demo from fn_bloquear_asientos(1, :funcion_demo, :'asientos_demo') \gset
select total from fn_asignar_tipos(:orden_demo, 1, :'asientos_demo', array[1, 1]);
select resultado_pago from fn_confirmar_pago(:orden_demo, 1, 'TARJETA_SIMULADA', 'APROBADO');

-- QR cortos para escribirlos a mano en la pantalla de check-in
update boleto b set codigo_qr = 'IMAX-DEMO-' || a.numero
  from asiento a where a.id = b.asiento_id and b.orden_id = :orden_demo;
\endif
