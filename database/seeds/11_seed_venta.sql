-- Datos de venta para la demo
-- Requiere todos los DDL, 01_catalogo_demo.sql y el seed de métodos de pago.
-- Usa las mismas funciones que la aplicación, así que los datos quedan como los de una compra real.

-- Orden 1: el cliente compra 2 asientos de la función 1 y paga (aprobado)
select * from fn_bloquear_asientos(1, 1, array[1, 2]);
select total from fn_asignar_tipos(1, 1, array[1, 2], array[1, 4]);
select resultado_pago from fn_confirmar_pago(1, 1, 'TARJETA_SIMULADA', 'APROBADO');

-- Orden 2: otra compra de 3 asientos en la función 1 pagada con PayPal
select * from fn_bloquear_asientos(1, 1, array[10, 11, 12]);
select total from fn_asignar_tipos(2, 1, array[10, 11, 12], array[1, 1, 2]);
select resultado_pago from fn_confirmar_pago(2, 1, 'PAYPAL_SIMULADO', 'APROBADO');

-- Orden 3: un pago rechazado (los asientos quedan libres)
select * from fn_bloquear_asientos(1, 1, array[20, 21]);
select total from fn_asignar_tipos(3, 1, array[20, 21], array[1, 1]);
select resultado_pago from fn_confirmar_pago(3, 1, 'BILLETERA_SIMULADA', 'RECHAZADO');

-- Orden 4: una compra en la función 2 con billetera
select * from fn_bloquear_asientos(1, 2, array[50]);
select total from fn_asignar_tipos(4, 1, array[50], array[1]);
select resultado_pago from fn_confirmar_pago(4, 1, 'BILLETERA_SIMULADA', 'APROBADO');

-- Orden 5: un bloqueo que se venció sin pagar
select * from fn_bloquear_asientos(1, 1, array[30, 31]);
update reserva_asiento set bloqueado_hasta = now() - interval '5 minutes' where orden_id = 5;
select fn_liberar_expirados();

-- Orden 6: un bloqueo vigente (el cliente sigue eligiendo)
select * from fn_bloquear_asientos(1, 1, array[40]);