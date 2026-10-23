-- Pruebas de las restricciones del módulo de venta
-- Se corren sobre una base recién creada con 01_catalogo.sql, 03_venta.sql y el seed del catálogo.
-- Cada prueba dice qué se espera: FUNCIONA o ERROR.

-- Datos base: un método de pago y dos órdenes del usuario 1 para la función 1
insert into metodo_pago (id, codigo, nombre) values (1, 'TARJETA', 'Tarjeta simulada');
insert into orden (id, usuario_id, funcion_id) values (1, 1, 1);
insert into orden (id, usuario_id, funcion_id) values (2, 1, 1);


-- Prueba 1: bloquear el asiento 1 para la función 1
-- Resultado esperado: FUNCIONA
insert into reserva_asiento (id, orden_id, funcion_id, asiento_id, bloqueado_hasta)
values (1, 1, 1, 1, now() + interval '2 minutes');

-- Prueba 2: otra orden intenta bloquear el mismo asiento en la misma función
-- Resultado esperado: ERROR (duplicate key, uq_asiento_activo)
insert into reserva_asiento (id, orden_id, funcion_id, asiento_id, bloqueado_hasta)
values (2, 2, 1, 1, now() + interval '2 minutes');

-- Prueba 3: la primera reserva expira y la otra orden ya puede tomar el asiento
-- Resultado esperado: FUNCIONA
update reserva_asiento set estado = 'EXPIRADO' where id = 1;
insert into reserva_asiento (id, orden_id, funcion_id, asiento_id, bloqueado_hasta)
values (2, 2, 1, 1, now() + interval '2 minutes');

-- Prueba 4: estado de reserva que no existe
-- Resultado esperado: ERROR (check de estado)
update reserva_asiento set estado = 'COMPRADO' where id = 2;


-- Prueba 5: orden con total que no cuadra (10 - 2 + 1 debería ser 9, no 99)
-- Resultado esperado: ERROR (check del total)
insert into orden (id, usuario_id, funcion_id, subtotal, descuento, cargo_servicio, total)
values (3, 1, 1, 10, 2, 1, 99);

-- Prueba 6: la misma orden con el total correcto
-- Resultado esperado: FUNCIONA
insert into orden (id, usuario_id, funcion_id, subtotal, descuento, cargo_servicio, total)
values (3, 1, 1, 10, 2, 1, 9);

-- Prueba 7: estado de orden que no existe
-- Resultado esperado: ERROR (check de estado)
update orden set estado = 'LISTA' where id = 1;


-- Prueba 8: un pago aprobado para la orden 1
-- Resultado esperado: FUNCIONA
insert into pago (id, orden_id, metodo_pago_id, monto, resultado)
values (1, 1, 1, 0, 'APROBADO');

-- Prueba 9: un segundo pago aprobado para la misma orden
-- Resultado esperado: ERROR (duplicate key, uq_pago_aprobado)
insert into pago (id, orden_id, metodo_pago_id, monto, resultado)
values (2, 1, 1, 0, 'APROBADO');

-- Prueba 10: varios pagos rechazados para la orden 2
-- Resultado esperado: FUNCIONA
insert into pago (id, orden_id, metodo_pago_id, monto, resultado)
values (3, 2, 1, 0, 'RECHAZADO');
insert into pago (id, orden_id, metodo_pago_id, monto, resultado)
values (4, 2, 1, 0, 'RECHAZADO');


-- Prueba 11: crear el boleto de la reserva 2 con su código QR
-- Resultado esperado: FUNCIONA
insert into boleto (id, orden_id, reserva_asiento_id, funcion_id, asiento_id, codigo_qr)
values (1, 2, 2, 1, 1, 'QR-0001');

-- Prueba 12: otro boleto con el mismo código QR
-- Resultado esperado: ERROR (duplicate key, codigo_qr)
insert into boleto (id, orden_id, reserva_asiento_id, funcion_id, asiento_id, codigo_qr)
values (2, 1, 1, 1, 1, 'QR-0001');

-- Prueba 13: otro boleto para la misma reserva, con QR distinto
-- Resultado esperado: ERROR (duplicate key, reserva_asiento_id)
insert into boleto (id, orden_id, reserva_asiento_id, funcion_id, asiento_id, codigo_qr)
values (3, 2, 2, 1, 1, 'QR-0002');


-- Prueba 14: las tablas no guardan datos de tarjeta (ni número ni CVV)
-- Resultado esperado: 0 filas
select table_name, column_name
from information_schema.columns
where table_name in ('pago', 'orden', 'boleto')
  and (column_name like '%cvv%' or column_name like '%numero_tarjeta%');