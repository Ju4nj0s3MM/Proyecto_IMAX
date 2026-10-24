\set ON_ERROR_STOP off

\echo '=== CLIENTE ==='
set role rol_cliente;
select count(*) as peliculas_visibles from pelicula;
\echo '-- cliente lee usuario (debe fallar)'
select * from usuario;
\echo '-- cliente modifica tarifa (debe fallar)'
update tarifa set precio = 0;
\echo '-- cliente se registra como admin (debe fallar)'
select fn_registrar_usuario('x@x.com', 'X', 'Y', 'Clave12345', 'administrador');
reset role;

\echo '=== TAQUILLERO ==='
set role rol_taquillero;
select count(*) as tarifas_visibles from tarifa;
\echo '-- taquillero modifica precio (debe fallar)'
update tarifa set precio = 1;
\echo '-- taquillero crea sala (debe fallar)'
insert into sala (cine_id, nombre, capacidad) values (1, 'Hack', 10);
\echo '-- taquillero lee bitácora (debe fallar)'
select * from admin_operacion_audit;
reset role;

\echo '=== OPERADOR DE SALA ==='
set role rol_operador_sala;
select count(*) as puertas_visibles from puerta;
\echo '-- operador crea puerta (debe fallar)'
insert into puerta (sala_id, nombre) values (1, 'Falsa');
\echo '-- operador modifica funcion (debe fallar)'
update funcion set estado = 'Cancelada';
reset role;

\echo '=== CONTADOR ==='
set role rol_contador;
select count(*) as funciones_visibles from funcion;
\echo '-- contador modifica programación (debe fallar)'
delete from funcion;
reset role;

\echo '=== ADMINISTRADOR ==='
set role rol_administrador;
insert into genero (nombre) values ('Musical');
select count(*) as usuarios_visibles from usuario;
\echo '-- administrador lee el hash (debe fallar)'
select password_hash from usuario;
\echo '-- administrador altera bitácora (debe fallar)'
update admin_operacion_audit set motivo = 'x';
delete from admin_operacion_audit;
\echo '-- administrador crea partición (debe fallar)'
select fn_crear_particion_admin_audit(current_date);
reset role;
