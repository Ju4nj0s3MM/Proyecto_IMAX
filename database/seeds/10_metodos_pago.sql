-- Métodos de pago simulados (no se guarda ningún dato de tarjeta)
-- Los códigos son los que usa el combo de app/public/venta/pago.html
insert into metodo_pago (codigo, nombre) values
    ('TARJETA_SIMULADA', 'Tarjeta simulada'),
    ('PAYPAL_SIMULADO', 'PayPal simulado'),
    ('BILLETERA_SIMULADA', 'Billetera digital simulada')
on conflict (codigo) do nothing;