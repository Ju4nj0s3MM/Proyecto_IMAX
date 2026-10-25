-- Índices del módulo de venta
-- Los índices únicos de 03_venta.sql (uq_asiento_activo, uq_pago_aprobado) ya cubren el mapa de asientos
-- y el control de doble venta; estos son para las consultas de reportes y para "mis boletos".
-- Medidos con explain/02_explain_venta.sql sobre los datos masivos (resultados en explain/resultados/).

-- consulta 1: boletos de una función
create index idx_boleto_funcion on boleto (funcion_id) where estado <> 'ANULADO';

-- consulta 1: órdenes pagadas de una función
create index idx_orden_funcion_estado on orden (funcion_id, estado);

-- La consulta 3 no lleva índice: cuenta casi todos los pagos de la tabla (más del 90 % son aprobados),
-- así que PostgreSQL con razón la resuelve leyendo la tabla completa. Ver explain/resultados/.

-- mis boletos: órdenes de un usuario y boletos de una orden
create index idx_orden_usuario on orden (usuario_id);
create index idx_boleto_orden on boleto (orden_id);

-- fn_liberar_expirados: solo los bloqueos vigentes están en el índice
create index idx_reserva_bloqueo on reserva_asiento (bloqueado_hasta) where estado = 'BLOQUEADO';

analyze boleto, orden, reserva_asiento;