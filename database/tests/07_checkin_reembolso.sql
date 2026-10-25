\set ON_ERROR_STOP off
begin;

-- Datos de prueba: puertas, asientos y funciones respecto a la hora actual
insert into puerta (sala_id, nombre)
select id, 'Tótem 1' from sala where nombre in ('Sala 1', 'Sala 2', 'Sala Premium');

insert into asiento (sala_id, zona_asiento_id, fila, numero)
select s.id, (select id from zona_asiento where nombre = 'General'), 'A', n
  from sala s, generate_series(1, 6) n
 where s.nombre = 'Sala 2';

create function pg_temp.crear_funcion(p_sala text, p_cine text, p_inicio timestamptz, p_estado text default 'Activa')
returns bigint language sql as $f$
    insert into funcion (pelicula_id, sala_id, inicio, estado)
    select (select min(id) from pelicula), s.id, p_inicio, p_estado
      from sala s join cine c on c.id = s.cine_id
     where s.nombre = p_sala and c.nombre = p_cine
    returning id;
$f$;

create function pg_temp.crear_boleto(p_funcion bigint, p_numero integer, p_qr text, p_estado text default 'EMITIDO')
returns bigint language plpgsql as $f$
declare v_orden bigint; v_reserva bigint; v_asiento bigint; v_boleto bigint;
begin
    select a.id into v_asiento from asiento a join funcion f on f.sala_id = a.sala_id
     where f.id = p_funcion and a.numero = p_numero order by a.fila limit 1;
    insert into orden (usuario_id, funcion_id, estado, subtotal, descuento, cargo_servicio, total, pagada_en)
    values ((select id from usuario where email = 'cliente@imax.test'), p_funcion, 'PAGADA', 8.50, 0, 0.75, 9.25, now())
    returning id into v_orden;
    insert into reserva_asiento (orden_id, funcion_id, asiento_id, estado, bloqueado_hasta, precio, cargo_servicio)
    values (v_orden, p_funcion, v_asiento, 'VENDIDO', now(), 8.50, 0.75) returning id into v_reserva;
    insert into boleto (orden_id, reserva_asiento_id, funcion_id, asiento_id, codigo_qr, estado)
    values (v_orden, v_reserva, p_funcion, v_asiento, p_qr, p_estado) returning id into v_boleto;
    return v_boleto;
end $f$;

-- F1: empieza en 10 min (dentro de la ventana). F2: en 6 horas. F3: empezó hace 30 min. F4: cancelada.
select pg_temp.crear_funcion('Sala 1', 'IMAX San José', now() + interval '10 minutes') as f1 \gset
select pg_temp.crear_funcion('Sala 1', 'IMAX San José', now() + interval '6 hours') as f2 \gset
select pg_temp.crear_funcion('Sala 2', 'IMAX San José', now() - interval '30 minutes') as f3 \gset
select pg_temp.crear_funcion('Sala 2', 'IMAX San José', now() + interval '2 hours', 'Cancelada') as f4 \gset

select pg_temp.crear_boleto(:f1, 1, 'QR-OK-1') as b_ok \gset
select pg_temp.crear_boleto(:f1, 2, 'QR-FORZADO') as b_forzado \gset
select pg_temp.crear_boleto(:f1, 3, 'QR-USADO', 'USADO') as b_usado \gset
select pg_temp.crear_boleto(:f1, 4, 'QR-ANULADO', 'ANULADO') as b_anulado \gset
select pg_temp.crear_boleto(:f2, 1, 'QR-TEMPRANO') as b_temprano \gset
select pg_temp.crear_boleto(:f3, 1, 'QR-TARDE') as b_tarde \gset
select pg_temp.crear_boleto(:f4, 1, 'QR-CANCELADA') as b_cancelada \gset

select p.id as p_sj1 from puerta p join sala s on s.id = p.sala_id join cine c on c.id = s.cine_id where s.nombre = 'Sala 1' and c.nombre = 'IMAX San José' \gset
select p.id as p_sj2 from puerta p join sala s on s.id = p.sala_id where s.nombre = 'Sala 2' \gset
select p.id as p_prem from puerta p join sala s on s.id = p.sala_id where s.nombre = 'Sala Premium' \gset
select id as admin from usuario where email = 'admin@imax.test' \gset
select id as taq from usuario where email = 'taquilla@imax.test' \gset

\echo '=== CHECK-IN (RN-14, RN-15, RN-16) ==='
\echo '1. Primer escaneo valido (debe entrar)'
select * from fn_validar_entrada('QR-OK-1', :p_sj1);
\echo '2. Segundo escaneo del mismo QR (debe decir Entrada ya utilizada)'
select * from fn_validar_entrada('QR-OK-1', :p_sj1);
\echo '3. QR que no existe'
select * from fn_validar_entrada('QR-INVENTADO', :p_sj1);
\echo '4. Entrada de Sala 1 escaneada en otra sala'
select * from fn_validar_entrada('QR-FORZADO', :p_prem);
\echo '5. Funcion que empieza en 6 horas (antes de la ventana)'
select * from fn_validar_entrada('QR-TEMPRANO', :p_sj1);
\echo '6. Funcion que empezo hace 30 min (fuera de tolerancia)'
select * from fn_validar_entrada('QR-TARDE', :p_sj2);
\echo '7. Funcion cancelada'
select * from fn_validar_entrada('QR-CANCELADA', :p_sj2);
\echo '8. Entrada anulada'
select * from fn_validar_entrada('QR-ANULADO', :p_sj1);
\echo '9. Puerta inexistente'
select * from fn_validar_entrada('QR-FORZADO', 99999);

\echo '--- Bitacora de accesos'
select resultado, motivo, count(*) from acceso_puerta_log group by 1, 2 order by 1, 2;
\echo '--- El boleto de la prueba 1 quedo USADO'
select codigo_qr, estado, usado_en is not null as con_fecha_de_uso from boleto where codigo_qr = 'QR-OK-1';

\echo '=== REEMBOLSOS (RN-19, RN-20) ==='
\echo '10. Reembolso dentro de la politica (funcion en 6 horas)'
select * from fn_reembolsar(:b_temprano, :admin, 'Cliente no puede asistir');
\echo '    boleto anulado, asiento liberado, orden reembolsada'
select b.estado as boleto, r.estado as reserva, o.estado as orden
  from boleto b join reserva_asiento r on r.id = b.reserva_asiento_id join orden o on o.id = b.orden_id where b.id = :b_temprano;
\echo '    el QR reembolsado ya no entra'
select * from fn_validar_entrada('QR-TEMPRANO', :p_sj1);
\echo '11. Reembolso fuera de politica (funcion en 10 min): forzado'
select * from fn_reembolsar(:b_forzado, :admin, 'Falla tecnica en la sala');
\echo '12. Boleto ya usado (debe rechazar)'
select * from fn_reembolsar(:b_ok, :admin, 'Intento sobre boleto usado');
\echo '13. Quien no es administrador (debe rechazar)'
select * from fn_reembolsar(:b_tarde, :taq, 'Taquillero intenta reembolsar');
\echo '14. Sin motivo (debe rechazar)'
select * from fn_reembolsar(:b_tarde, :admin, '');
\echo '15. Segundo reembolso del mismo boleto (debe rechazar)'
select * from fn_reembolsar(:b_temprano, :admin, 'Repetido');

\echo '--- Tabla reembolso'
select boleto_id, monto, forzado, motivo from reembolso order by id;
\echo '--- Auditoria administrativa (RN-20): usuario, rol, accion, ip'
select a.accion, u.email, r.nombre as rol, a.ip, a.motivo, a.detalle
  from admin_operacion_audit a join usuario u on u.id = a.usuario_id join rol r on r.id = a.rol_id order by a.id;
\echo '--- Bitacora de transacciones'
select tipo, monto, resultado from transaccion_log where tipo = 'REEMBOLSO' order by id;
\echo '--- Bitacora inalterable (ambos deben fallar)'
savepoint prueba_update;
update acceso_puerta_log set resultado = 'EXITOSO';
rollback to prueba_update;
delete from acceso_puerta_log;

rollback;