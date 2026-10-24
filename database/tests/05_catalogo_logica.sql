-- Pruebas del Módulo A (catálogo, programación, total y RN-18)
-- Se corren sobre una base recién creada con 01 a 07 y el seed 01_catalogo_demo.sql:
--   psql -d imax -f database/tests/05_catalogo_logica.sql
-- Cada prueba dice qué se espera. Las que modifican datos terminan en rollback, así se puede repetir.

\pset pager off
\set sj1 '(select id from sala where nombre = ''Sala 1'')'
\set la '(select id from sala where nombre = ''Sala 1 IMAX Laser'')'
\set adulto '(select id from tipo_entrada where nombre = ''Adulto'')'
\set estudiante '(select id from tipo_entrada where nombre = ''Estudiante'')'
\set mayor '(select id from tipo_entrada where nombre = ''Adulto mayor'')'


\echo '===== Prueba 1: traslape en la misma sala. Esperado: ERROR ex_funcion_sin_traslape'
insert into funcion (pelicula_id, sala_id, inicio)
select (select id from pelicula where titulo = 'Océano Profundo'), :la,
       ((current_date + 1) + time '16:00') at time zone 'America/Costa_Rica';

\echo '===== Prueba 2: reprogramar sobre una función cancelada. Esperado: UPDATE 1 e INSERT 0 1'
begin;
update funcion set estado = 'Cancelada'
 where sala_id = :la and inicio = ((current_date + 1) + time '21:00') at time zone 'America/Costa_Rica';
insert into funcion (pelicula_id, sala_id, inicio)
select (select id from pelicula where titulo = 'La Noche Eterna'), :la,
       ((current_date + 1) + time '21:00') at time zone 'America/Costa_Rica';
rollback;

\echo '===== Prueba 3: fin y fin_limpieza calculados por el trigger. Esperado: duración y limpieza correctas'
select p.titulo, s.nombre as sala, f.fin - f.inicio as duracion, f.fin_limpieza - f.fin as limpieza
  from funcion f join pelicula p on p.id = f.pelicula_id join sala s on s.id = f.sala_id
 order by f.inicio;

\echo '===== Prueba 4: asiento repetido en la sala. Esperado: ERROR uq_asiento_sala_fila_numero'
insert into asiento (sala_id, zona_asiento_id, fila, numero)
values (:la, (select id from zona_asiento where nombre = 'General'), 'A', 1);

\echo '===== Prueba 5: tarifa repetida. Esperado: ERROR uq_tarifa_combinacion'
insert into tarifa (tipo_entrada_id, zona_asiento_id, precio)
values (:adulto, (select id from zona_asiento where nombre = 'General'), 9.00);

\echo '===== Prueba 6: promoción sin condición. Esperado: ERROR ck_promocion_condicion'
insert into promocion (nombre, requiere_cantidad_par) values ('2x1 sin condición', false);


\echo '===== Prueba 7: cartelera (RN-01, RN-02)'
begin;
-- una función de ayer y la de Sala Premium cancelada: ninguna debe salir
insert into funcion (pelicula_id, sala_id, inicio, estado)
select (select id from pelicula where titulo = 'Océano Profundo'), (select id from sala where nombre = 'Sala 2'),
       now() - interval '1 day', 'Finalizada';
update funcion set estado = 'Cancelada' where sala_id = (select id from sala where nombre = 'Sala Premium');
\echo '7a. Sin filtros. Esperado: 7 funciones, todas futuras'
select titulo, clasificacion, genero, cine, sala, inicio > now() as futura from fn_listar_cartelera(null, null, null);
\echo '7b. Ciudad San José. Esperado: 3 funciones, todas de IMAX San José'
select titulo, cine, sala from fn_listar_cartelera('San José', null, null);
\echo '7c. Género Terror. Esperado: solo La Noche Eterna en San José'
select titulo, genero, cine from fn_listar_cartelera(null, null, 'Terror');
\echo '7d. Fecha de pasado mañana. Esperado: 2 funciones'
select titulo, cine, inicio from fn_listar_cartelera(null, current_date + 2, null);
rollback;


\echo '===== Prueba 8: total de la compra (RN-07, RN-08)'
begin;
-- funciones en fechas fijas para no depender del día en que se corre la prueba
-- 2026-11-07 sábado, 2026-11-03 martes, 2026-11-04 miércoles
insert into funcion (pelicula_id, sala_id, inicio)
select (select id from pelicula where titulo = 'Océano Profundo'), :sj1, x.t at time zone 'America/Costa_Rica'
  from (values (timestamp '2026-11-07 16:00'), (timestamp '2026-11-03 11:00'), (timestamp '2026-11-04 16:00')) x(t);

\echo '8a. 2 estudiantes en General, sábado. Esperado: 13.00 - 6.50 + 1.50 = 8.00'
select subtotal, descuento, cargo_servicio, total
  from fn_calcular_total(
        (select id from funcion where inicio = timestamp '2026-11-07 16:00' at time zone 'America/Costa_Rica'),
        array(select id from asiento where sala_id = :sj1 and fila = 'A' and numero in (1, 2) order by numero),
        array[:estudiante, :estudiante]);

\echo '8b. 3 adultos en General, sábado (sin promoción). Esperado: 25.50 - 0 + 2.25 = 27.75'
select subtotal, descuento, cargo_servicio, total
  from fn_calcular_total(
        (select id from funcion where inicio = timestamp '2026-11-07 16:00' at time zone 'America/Costa_Rica'),
        array(select id from asiento where sala_id = :sj1 and fila = 'A' and numero in (1, 2, 3) order by numero),
        array[:adulto, :adulto, :adulto]);

\echo '8c. 1 adulto martes 11:00: gana la tarifa del martes (6.00) sobre la matiné (7.00). Esperado: 6.75'
select subtotal, descuento, cargo_servicio, total
  from fn_calcular_total(
        (select id from funcion where inicio = timestamp '2026-11-03 11:00' at time zone 'America/Costa_Rica'),
        array(select id from asiento where sala_id = :sj1 and fila = 'B' and numero = 1),
        array[:adulto]);

\echo '8d. Miércoles 2x1: 2 adultos y 1 adulto mayor. Esperado: 22.50 - 8.50 + 2.25 = 16.25'
select subtotal, descuento, cargo_servicio, total, jsonb_array_length(detalle) as lineas
  from fn_calcular_total(
        (select id from funcion where inicio = timestamp '2026-11-04 16:00' at time zone 'America/Costa_Rica'),
        array(select id from asiento where sala_id = :sj1 and fila = 'B' and numero in (1, 2, 3) order by numero),
        array[:adulto, :adulto, :mayor]);

\echo '8e. Asiento de otra sala. Esperado: ERROR Hay asientos que no pertenecen a la sala de la función'
select * from fn_calcular_total(
        (select id from funcion where inicio = timestamp '2026-11-07 16:00' at time zone 'America/Costa_Rica'),
        array(select id from asiento where sala_id = :la and fila = 'A' and numero = 1),
        array[:adulto]);
rollback;


\echo '===== Prueba 9: RN-18, no modificar una sala con ventas activas'
begin;
-- se vende el asiento A1 de la primera función de mañana en Los Ángeles
insert into metodo_pago (codigo, nombre) values ('TARJETA', 'Tarjeta simulada') on conflict (codigo) do nothing;
insert into orden (usuario_id, funcion_id, estado)
values ((select id from usuario where email = 'cliente@imax.test'),
        (select min(id) from funcion where sala_id = :la), 'PAGADA');
insert into reserva_asiento (orden_id, funcion_id, asiento_id, estado, bloqueado_hasta)
values ((select max(id) from orden), (select min(id) from funcion where sala_id = :la),
        (select id from asiento where sala_id = :la and fila = 'A' and numero = 1), 'VENDIDO', now());

\echo '9a. Cambiar la zona de una fila. Esperado: ERROR RN-18'
savepoint s;
update asiento set zona_asiento_id = (select id from zona_asiento where nombre = 'General') where sala_id = :la and fila = 'A';
rollback to s;
\echo '9b. Borrar una fila. Esperado: ERROR RN-18'
delete from asiento where sala_id = :la and fila = 'H';
rollback to s;
\echo '9c. Agregar un asiento. Esperado: ERROR RN-18'
insert into asiento (sala_id, zona_asiento_id, fila, numero) values (:la, (select id from zona_asiento where nombre = 'General'), 'I', 1);
rollback to s;
\echo '9d. Cambiar la capacidad de la sala. Esperado: ERROR RN-18'
update sala set capacidad = 100 where id = :la;
rollback to s;
\echo '9e. Cambiar solo el nombre de la sala (no es la distribución). Esperado: UPDATE 1'
update sala set nombre = 'Sala 1 IMAX Laser (renovada)' where id = :la;
rollback to s;
\echo '9f. Misma operación en la Sala 1 de San José, sin ventas. Esperado: UPDATE 8'
update asiento set zona_asiento_id = (select id from zona_asiento where nombre = 'VIP') where sala_id = :sj1 and fila = 'F';
rollback to s;
\echo '9g. Si el bloqueo venció, ya no cuenta como reserva. Esperado: UPDATE 1'
update reserva_asiento set estado = 'BLOQUEADO', bloqueado_hasta = now() - interval '1 minute';
update asiento set activo = false where sala_id = :la and fila = 'H' and numero = 10;
rollback;
