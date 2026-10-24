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


-- Prueba de la bitácora de asientos
 
-- Prueba 1: una fila de octubre cae en la partición de octubre
-- Resultado esperado: FUNCIONA
insert into asiento_auditoria_log (funcion_id, asiento_id, estado_nuevo, fecha)
values (1, 1, 'BLOQUEADO', '2026-10-22 10:00');
 
-- Prueba 2: una fila de noviembre cae en la partición de noviembre
-- Resultado esperado: FUNCIONA
insert into asiento_auditoria_log (funcion_id, asiento_id, estado_nuevo, fecha)
values (1, 1, 'VENDIDO', '2026-11-05 15:30');
 
-- Prueba 3: una fecha sin partición creada (marzo de 2027)
-- Resultado esperado: ERROR (no partition found for row)
insert into asiento_auditoria_log (funcion_id, asiento_id, estado_nuevo, fecha)
values (1, 1, 'BLOQUEADO', '2027-03-01 09:00');
 
-- Prueba 4: ver en qué partición quedó cada fila
-- Resultado esperado: tableoid = asiento_auditoria_log_2026_10 y asiento_auditoria_log_2026_11
select tableoid::regclass as particion, estado_nuevo, fecha
from asiento_auditoria_log
order by fecha;

-- Prueba de la bitácora de transacciones
 
-- Prueba 1: registrar un pago aprobado
-- Resultado esperado: FUNCIONA
insert into transaccion_log (orden_id, usuario_id, tipo, monto, resultado, fecha)
values (1, 1, 'PAGO', 17.00, 'APROBADO', '2026-10-22 11:00');
 
-- Prueba 2: tipo de transacción que no existe
-- Resultado esperado: ERROR (check de tipo)
insert into transaccion_log (orden_id, usuario_id, tipo, fecha)
values (1, 1, 'REGALO', '2026-10-22 11:05');
 
-- Prueba 3: fecha sin partición (abril de 2027)
-- Resultado esperado: ERROR (no partition found for row)
insert into transaccion_log (orden_id, usuario_id, tipo, fecha)
values (1, 1, 'BLOQUEO', '2027-04-01 08:00');
 
-- Prueba 4: ver en qué partición quedó la fila
-- Resultado esperado: transaccion_log_2026_10
select tableoid::regclass as particion, tipo, monto, resultado, fecha
from transaccion_log;

-- Prueba del bloqueo de UPDATE y DELETE en las bitácoras
 
-- Prueba 1: agregar filas sigue funcionando
-- Resultado esperado: FUNCIONA
insert into asiento_auditoria_log (funcion_id, asiento_id, estado_nuevo, fecha)
values (1, 1, 'BLOQUEADO', '2026-10-22 10:00');
insert into transaccion_log (orden_id, usuario_id, tipo, fecha)
values (1, 1, 'BLOQUEO', '2026-10-22 10:00');
 
-- Prueba 2: modificar una fila de la bitácora de asientos
-- Resultado esperado: ERROR (la bitácora no permite UPDATE)
update asiento_auditoria_log set estado_nuevo = 'VENDIDO' where asiento_id = 1;
 
-- Prueba 3: borrar una fila de la bitácora de asientos
-- Resultado esperado: ERROR (la bitácora no permite DELETE)
delete from asiento_auditoria_log where asiento_id = 1;
 
-- Prueba 4: modificar una fila de la bitácora de transacciones
-- Resultado esperado: ERROR
update transaccion_log set tipo = 'PAGO' where orden_id = 1;
 
-- Prueba 5: borrar una fila de la bitácora de transacciones
-- Resultado esperado: ERROR
delete from transaccion_log where orden_id = 1;
 
-- Prueba 6: intentar saltarse el bloqueo escribiendo directo en la partición
-- Resultado esperado: ERROR
delete from asiento_auditoria_log_2026_10;
 
-- Prueba 7: las filas siguen intactas
-- Resultado esperado: 1 y 1
select (select count(*) from asiento_auditoria_log) as asientos,
       (select count(*) from transaccion_log) as transacciones;

-- Prueba de la creación de particiones mensuales

-- Prueba 1: antes de crear la partición, una fecha de marzo de 2027 falla
-- Resultado esperado: ERROR (no partition found for row)
insert into transaccion_log (orden_id, usuario_id, tipo, fecha)
values (1, 1, 'BLOQUEO', '2027-03-10 09:00');

-- Prueba 2: crear las particiones de marzo de 2027
-- Resultado esperado: FUNCIONA
select fn_crear_particiones_mes('2027-03-15');

-- Prueba 3: ahora la misma fila entra en la partición de marzo
-- Resultado esperado: FUNCIONA
insert into transaccion_log (orden_id, usuario_id, tipo, fecha)
values (1, 1, 'BLOQUEO', '2027-03-10 09:00');

-- Prueba 4: llamar la función otra vez para el mismo mes no da error
-- Resultado esperado: FUNCIONA
select fn_crear_particiones_mes('2027-03-01');

-- Prueba 5: ver las particiones que existen (deben salir las de octubre 2026 a marzo 2027, en las dos bitácoras)
select inhparent::regclass as bitacora, inhrelid::regclass as particion
from pg_inherits
where inhparent in ('asiento_auditoria_log'::regclass, 'transaccion_log'::regclass)
order by 1, 2;

-- Pruebas de fn_liberar_expirados
-- Se corre sobre una base nueva con los DDL y el seed del catálogo.

-- Datos base: 3 órdenes del usuario 1 para la función 1
insert into metodo_pago (id, codigo, nombre) values (1, 'TARJETA', 'Tarjeta simulada');
insert into orden (id, usuario_id, funcion_id) values (1, 1, 1);
insert into orden (id, usuario_id, funcion_id) values (2, 1, 1);
insert into orden (id, usuario_id, funcion_id) values (3, 1, 1);

-- Orden 1: asiento 1 con el bloqueo ya vencido (hace 1 minuto)
insert into reserva_asiento (id, orden_id, funcion_id, asiento_id, bloqueado_hasta)
values (1, 1, 1, 1, now() - interval '1 minute');
-- Orden 2: asiento 2 con el bloqueo todavía vigente (2 minutos más)
insert into reserva_asiento (id, orden_id, funcion_id, asiento_id, bloqueado_hasta)
values (2, 2, 1, 2, now() + interval '2 minutes');
-- Orden 3: asiento 3 ya vendido (con fecha vieja, no se debe tocar)
insert into reserva_asiento (id, orden_id, funcion_id, asiento_id, estado, bloqueado_hasta, precio)
values (3, 3, 1, 3, 'VENDIDO', now() - interval '10 minutes', 8.50);


-- Prueba 1: liberar los vencidos
-- Resultado esperado: 1 (solo el asiento 1)
select fn_liberar_expirados();

-- Prueba 2: estado de cada reserva
-- Resultado esperado: 1 = EXPIRADO, 2 = BLOQUEADO, 3 = VENDIDO
select id, asiento_id, estado from reserva_asiento order by id;

-- Prueba 3: estado de cada orden
-- Resultado esperado: 1 = EXPIRADA, 2 = PENDIENTE, 3 = PENDIENTE
select id, estado from orden order by id;

-- Prueba 4: el cambio quedó en las bitácoras
-- Resultado esperado: 1 fila en asiento_auditoria_log (BLOQUEADO -> EXPIRADO) y 1 en transaccion_log (EXPIRACION)
select asiento_id, estado_anterior, estado_nuevo from asiento_auditoria_log;
select orden_id, tipo, resultado from transaccion_log;

-- Prueba 5: el asiento 1 ya se puede bloquear otra vez con otra orden
-- Resultado esperado: FUNCIONA
insert into reserva_asiento (id, orden_id, funcion_id, asiento_id, bloqueado_hasta)
values (4, 2, 1, 1, now() + interval '2 minutes');

-- Prueba 6: el asiento 2 (bloqueo vigente) sigue sin poder tomarse
-- Resultado esperado: ERROR (duplicate key, uq_asiento_activo)
insert into reserva_asiento (id, orden_id, funcion_id, asiento_id, bloqueado_hasta)
values (5, 1, 1, 2, now() + interval '2 minutes');

-- Prueba 7: volver a correr la función cuando no hay nada vencido
-- Resultado esperado: 0
select fn_liberar_expirados();

-- Pruebas de fn_mapa_asientos 
-- Se corre sobre una base nueva con los DDL y el seed del catálogo.
-- La función 1 es de la sala "Sala 1 IMAX Laser" (80 asientos, filas A a H).

insert into orden (id, usuario_id, funcion_id) values (1, 1, 1);
insert into orden (id, usuario_id, funcion_id) values (2, 1, 1);
insert into orden (id, usuario_id, funcion_id) values (3, 1, 1);

-- Prueba 1: función sin ventas, todos los asientos disponibles
-- Resultado esperado: 80 asientos, todos DISPONIBLE
select estado, count(*) from fn_mapa_asientos(1) group by estado;

-- Asiento 1 bloqueado, asiento 2 vendido, asiento 3 con bloqueo vencido
insert into reserva_asiento (id, orden_id, funcion_id, asiento_id, bloqueado_hasta)
values (1, 1, 1, 1, now() + interval '2 minutes');
insert into reserva_asiento (id, orden_id, funcion_id, asiento_id, estado, bloqueado_hasta, precio)
values (2, 2, 1, 2, 'VENDIDO', now() - interval '10 minutes', 8.50);
insert into reserva_asiento (id, orden_id, funcion_id, asiento_id, bloqueado_hasta)
values (3, 3, 1, 3, now() - interval '1 minute');

-- Prueba 2: estado de los 3 primeros asientos
-- Resultado esperado: asiento 1 (A1) BLOQUEADO, asiento 2 (B1) VENDIDO, asiento 3 (C1) DISPONIBLE (el bloqueo ya venció)
select asiento_id, fila, numero, zona, estado
from fn_mapa_asientos(1) where asiento_id in (1, 2, 3) order by asiento_id;

-- Prueba 3: conteo por estado
-- Resultado esperado: BLOQUEADO 1, VENDIDO 1, DISPONIBLE 78
select estado, count(*) from fn_mapa_asientos(1) group by estado order by estado;

-- Prueba 4: un asiento desactivado ya no aparece en el mapa
-- Resultado esperado: 79 asientos
update asiento set activo = false where id = 80;
select count(*) from fn_mapa_asientos(1);

-- Prueba 5: función que no existe
-- Resultado esperado: 0 filas
select count(*) from fn_mapa_asientos(9999);

-- Prueba 6: las ventas de una función no afectan el mapa de otra de la misma sala
-- Resultado esperado: función 2 (misma sala), todos los asientos DISPONIBLE
select f.id as funcion, count(*) filter (where m.estado <> 'DISPONIBLE') as ocupados
from funcion f, lateral fn_mapa_asientos(f.id) m
where f.id = 2 and f.sala_id = (select sala_id from funcion where id = 1)
group by f.id;

-- Pruebas de fn_bloquear_asientos 
-- Se corre sobre una base nueva con los DDL y el seed del catálogo.
-- Función 1: sala "Sala 1 IMAX Laser" (asientos 1 a 80). Usuarios 1 y 2. Función 5: otra sala (asientos desde el 81).

-- Prueba 1: el usuario 1 bloquea los asientos 1 y 2
-- Resultado esperado: FUNCIONA, devuelve el reserva_id y una hora de vencimiento unos 2 minutos adelante
select * from fn_bloquear_asientos(1, 1, array[1, 2]);

-- Prueba 2: la orden y las reservas quedaron creadas
-- Resultado esperado: orden 1 PENDIENTE; asientos 1 y 2 BLOQUEADO
select id, usuario_id, estado from orden;
select orden_id, asiento_id, estado from reserva_asiento order by asiento_id;

-- Prueba 3: el mapa ya muestra esos asientos como bloqueados
-- Resultado esperado: BLOQUEADO 2
select estado, count(*) from fn_mapa_asientos(1) where estado = 'BLOQUEADO' group by estado;

-- Prueba 4: el usuario 2 intenta bloquear el asiento 2 (ya bloqueado) junto con el 3
-- Resultado esperado: ERROR (Asiento no disponible)
select * from fn_bloquear_asientos(2, 1, array[3, 2]);

-- Prueba 5: no quedó nada a medias (el asiento 3 no se bloqueó y no se creó una orden)
-- Resultado esperado: 1 orden y 2 reservas
select (select count(*) from orden) as ordenes, (select count(*) from reserva_asiento) as reservas;

-- Prueba 6: más de 6 asientos
-- Resultado esperado: ERROR (Máximo 6 asientos por compra)
select * from fn_bloquear_asientos(2, 1, array[10, 11, 12, 13, 14, 15, 16]);

-- Prueba 7: exactamente 6 asientos
-- Resultado esperado: FUNCIONA
select * from fn_bloquear_asientos(2, 1, array[10, 11, 12, 13, 14, 15]);

-- Prueba 8: lista vacía y asientos repetidos
-- Resultado esperado: ERROR en los dos
select * from fn_bloquear_asientos(2, 1, array[]::bigint[]);
select * from fn_bloquear_asientos(2, 1, array[20, 20]);

-- Prueba 9: un asiento de otra sala (el 81 es de la sala de la función 5)
-- Resultado esperado: ERROR (no pertenece a la sala)
select * from fn_bloquear_asientos(2, 1, array[81]);

-- Prueba 10: función cancelada
-- Resultado esperado: ERROR (la función no está disponible)
update funcion set estado = 'Cancelada' where id = 2;
select * from fn_bloquear_asientos(2, 2, array[1]);

-- Prueba 11: el bloqueo del asiento 1 vence y otro usuario puede tomarlo
-- Resultado esperado: FUNCIONA
update reserva_asiento set bloqueado_hasta = now() - interval '1 minute' where asiento_id = 1;
select * from fn_bloquear_asientos(2, 1, array[1]);

-- Prueba 12: quedó registro en las bitácoras
-- Resultado esperado: filas de BLOQUEADO y de EXPIRADO para el asiento 1; transacciones de tipo BLOQUEO
select asiento_id, estado_anterior, estado_nuevo from asiento_auditoria_log where asiento_id = 1 order by id;
select tipo, resultado, detalle from transaccion_log order by id;