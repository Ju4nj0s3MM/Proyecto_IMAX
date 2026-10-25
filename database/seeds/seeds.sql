\encoding UTF8
-- 02 Datos de demostración (catálogo, seguridad, métodos de pago y ventas)
-- Unión de los scripts de database/ en el orden de ejecución. Los archivos originales siguen en sus carpetas.


-- =====================================================================
-- database/seeds/01_catalogo_demo.sql
-- =====================================================================
-- Datos de DEMOSTRACIÓN para probar el panel de administración del catálogo (Módulo A).
-- Requiere: database/ddl/01_catalogo.sql. Se puede correr sobre una BD vacía:
--   psql -d imax -f database/ddl/01_catalogo.sql -f database/seeds/01_catalogo_demo.sql
-- No es la semilla final del proyecto: es solo para ir probando la GUI.

begin;

insert into zona_asiento (nombre, descripcion) values
  ('General',   'Butaca estándar'),
  ('VIP',       'Butaca reclinable en la zona central'),
  ('Accesible', 'Espacio para silla de ruedas y acompañante');

insert into clasificacion (codigo, descripcion, edad_minima) values
  ('G',     'Todo público', 0),
  ('PG',    'Se sugiere guía de los padres', 0),
  ('PG-13', 'Mayores de 13 años', 13),
  ('R',     'Mayores de 17 años o acompañados', 17);

insert into genero (nombre) values
  ('Acción'), ('Animación'), ('Ciencia ficción'), ('Documental'), ('Drama'), ('Terror');

insert into cine (nombre, direccion, ciudad, pais, latitud, longitud) values
  ('IMAX Los Ángeles', '6801 Hollywood Blvd',        'Los Ángeles', 'Estados Unidos', 34.102200, -118.340500),
  ('IMAX San José',    'Lincoln Plaza, Moravia',     'San José',    'Costa Rica',       9.961200,  -84.049600),
  ('IMAX Ciudad de México', 'Av. Insurgentes Sur 1235', 'Ciudad de México', 'México', 19.372800, -99.178300);

insert into sala (cine_id, nombre, capacidad, minutos_limpieza)
select c.id, s.nombre, s.capacidad, s.limpieza
  from (values ('IMAX Los Ángeles', 'Sala 1 IMAX Laser', 80, 25),
               ('IMAX San José',    'Sala 1',            48, 20),
               ('IMAX San José',    'Sala 2',            60, 20),
               ('IMAX Ciudad de México', 'Sala Premium', 40, 30)) s(cine, nombre, capacidad, limpieza)
  join cine c on c.nombre = s.cine;

-- Asientos: filas A..H × 10 (A-C VIP, H accesible) para la sala de Los Ángeles; Sala Premium todo VIP y el resto General.
insert into asiento (sala_id, zona_asiento_id, fila, numero)
select s.id,
       (select id from zona_asiento where nombre = case when f <= 3 then 'VIP' when f = 8 then 'Accesible' else 'General' end),
       chr(64 + f), n
  from sala s, generate_series(1, 8) f, generate_series(1, 10) n
 where s.nombre = 'Sala 1 IMAX Laser';

insert into asiento (sala_id, zona_asiento_id, fila, numero)
select s.id, (select id from zona_asiento where nombre = 'General'), chr(64 + f), n
  from sala s join cine c on c.id = s.cine_id, generate_series(1, 6) f, generate_series(1, 8) n
 where c.nombre = 'IMAX San José' and s.nombre = 'Sala 1';

insert into asiento (sala_id, zona_asiento_id, fila, numero)
select s.id, (select id from zona_asiento where nombre = 'General'), chr(64 + f), n
  from sala s join cine c on c.id = s.cine_id, generate_series(1, 6) f, generate_series(1, 10) n
 where c.nombre = 'IMAX San José' and s.nombre = 'Sala 2';

insert into asiento (sala_id, zona_asiento_id, fila, numero)
select s.id, (select id from zona_asiento where nombre = 'VIP'), chr(64 + f), n
  from sala s, generate_series(1, 4) f, generate_series(1, 10) n
 where s.nombre = 'Sala Premium';

insert into pelicula (titulo, sinopsis, duracion_min, clasificacion_id, fecha_estreno)
select p.titulo, p.sinopsis, p.duracion, c.id, p.estreno::date
  from (values ('Dune: Parte Tres', 'Paul Atreides enfrenta las consecuencias de la guerra santa que desató en el universo conocido.', 165, 'PG-13', '2026-12-18'),
               ('Océano Profundo', 'Documental inmersivo filmado con cámaras IMAX en las fosas más profundas del Pacífico.', 45, 'G', '2026-11-05'),
               ('La Noche Eterna', 'Un pueblo aislado descubre que el sol no volverá a salir.', 112, 'R', '2026-10-30')) p(titulo, sinopsis, duracion, clasif, estreno)
  join clasificacion c on c.codigo = p.clasif;

insert into pelicula_genero (pelicula_id, genero_id)
select p.id, g.id
  from (values ('Dune: Parte Tres', 'Ciencia ficción'), ('Dune: Parte Tres', 'Acción'),
               ('Océano Profundo', 'Documental'),
               ('La Noche Eterna', 'Terror'), ('La Noche Eterna', 'Drama')) x(titulo, genero)
  join pelicula p on p.titulo = x.titulo
  join genero g on g.nombre = x.genero;

-- Tipos de entrada (RN-06: los que requieren documento se validan en puerta)
insert into tipo_entrada (nombre, descripcion, requiere_documento) values
  ('Adulto',       'Tarifa general', false),
  ('Niño',         'Menores de 12 años', true),
  ('Adulto mayor', 'Ciudadano de oro (65+)', true),
  ('Estudiante',   'Con carné vigente', true);

-- Tarifas base (todos los días, todo el día) por tipo × zona; VIP cuesta 4.00 más
insert into tarifa (tipo_entrada_id, zona_asiento_id, precio, cargo_servicio)
select t.id, z.id, b.precio + case z.nombre when 'VIP' then 4 else 0 end, 0.75
  from (values ('Adulto', 8.50), ('Niño', 6.00), ('Adulto mayor', 5.50), ('Estudiante', 6.50)) b(tipo, precio)
  join tipo_entrada t on t.nombre = b.tipo
  cross join zona_asiento z;

-- Martes de descuento para Adulto en zona General, y matiné (10:00 a 14:59) para Adulto en General
insert into tarifa (tipo_entrada_id, zona_asiento_id, dia_semana, precio, cargo_servicio)
select t.id, z.id, 2, 6.00, 0.75 from tipo_entrada t, zona_asiento z where t.nombre = 'Adulto' and z.nombre = 'General';
insert into tarifa (tipo_entrada_id, zona_asiento_id, hora_desde, hora_hasta, precio, cargo_servicio)
select t.id, z.id, '10:00', '14:59:59', 7.00, 0.75 from tipo_entrada t, zona_asiento z where t.nombre = 'Adulto' and z.nombre = 'General';

-- Promociones 2x1 (RN-07)
insert into promocion (nombre, dia_semana, requiere_cantidad_par, tipo_entrada_id) values
  ('2x1 los miércoles', 3, true, null);
insert into promocion (nombre, requiere_cantidad_par, tipo_entrada_id, fecha_desde, fecha_hasta)
select '2x1 estudiantes', true, id, current_date, current_date + 60 from tipo_entrada where nombre = 'Estudiante';

-- Funciones de los próximos dos días (hora de Costa Rica). fin y fin_limpieza los calcula el trigger.
insert into funcion (pelicula_id, sala_id, inicio)
select p.id, s.id, ((current_date + x.dias) + x.hora) at time zone 'America/Costa_Rica'
  from (values ('Dune: Parte Tres', 'Sala 1 IMAX Laser', 1, time '14:00'),
               ('Dune: Parte Tres', 'Sala 1 IMAX Laser', 1, time '17:30'),
               ('Océano Profundo',  'Sala 1 IMAX Laser', 1, time '21:00'),
               ('Océano Profundo',  'Sala 1',            1, time '15:00'),
               ('La Noche Eterna',  'Sala 1',            1, time '20:00'),
               ('La Noche Eterna',  'Sala Premium',      1, time '19:00'),
               ('Dune: Parte Tres', 'Sala 1 IMAX Laser', 2, time '18:00'),
               ('Océano Profundo',  'Sala 2',            2, time '16:00')) x(titulo, sala, dias, hora)
  join pelicula p on p.titulo = x.titulo
  join sala s on s.nombre = x.sala
 order by s.id, x.dias, x.hora;   -- así los ids de las funciones siempre salen en el mismo orden

commit;

INSERT INTO rol (nombre, descripcion) VALUES
    ('cliente',       'Espectador: cartelera, compra y consulta de sus propias entradas'),
    ('taquillero',    'Venta presencial y corte de caja propio'),
    ('operador_sala', 'Validación de entradas (QR) en puerta'),
    ('contador',      'Lectura y exportación de información financiera'),
    ('administrador', 'Configuración de cartelera, salas y precios; reembolsos; auditoría');

-- Usuarios de DEMOSTRACIÓN, uno por rol. Contraseña de todos: Imax2026!  (solo para pruebas locales)
-- La contraseña se guarda como hash bcrypt con pgcrypto; nunca en texto plano.
insert into usuario (nombre, apellido, email, password_hash, telefono)
values ('Ana',    'Cliente',  'cliente@imax.test',    crypt('Imax2026!', gen_salt('bf')), '8888-0001'),
       ('Tomás',  'Taquilla', 'taquilla@imax.test',   crypt('Imax2026!', gen_salt('bf')), '8888-0002'),
       ('Olga',   'Operadora','operador@imax.test',   crypt('Imax2026!', gen_salt('bf')), null),
       ('Carlos', 'Contador', 'contador@imax.test',   crypt('Imax2026!', gen_salt('bf')), null),
       ('Admin',  'IMAX',     'admin@imax.test',      crypt('Imax2026!', gen_salt('bf')), null);

insert into usuario_rol (usuario_id, rol_id)
select u.id, r.id
  from (values ('cliente@imax.test', 'cliente'), ('taquilla@imax.test', 'taquillero'), ('operador@imax.test', 'operador_sala'),
               ('contador@imax.test', 'contador'), ('admin@imax.test', 'administrador')) x(email, rol)
  join usuario u on u.email = x.email
  join rol r on r.nombre = x.rol;


-- =====================================================================
-- database/seeds/10_metodos_pago.sql
-- =====================================================================
-- Métodos de pago simulados (no se guarda ningún dato de tarjeta)
-- Los códigos son los que usa el combo de app/public/venta/pago.html
insert into metodo_pago (codigo, nombre) values
    ('TARJETA_SIMULADA', 'Tarjeta simulada'),
    ('PAYPAL_SIMULADO', 'PayPal simulado'),
    ('BILLETERA_SIMULADA', 'Billetera digital simulada')
on conflict (codigo) do nothing;

-- =====================================================================
-- database/seeds/10_seed_seguridad.sql
-- =====================================================================
-- Datos de demostración del módulo de seguridad: puertas y operaciones de auditoría.
-- Requiere: DDL completo y seeds/01_catalogo_demo.sql (usuarios y salas).

insert into puerta (sala_id, nombre)
select s.id, p.nombre
  from sala s
  cross join (values ('Tótem 1'), ('Tótem 2')) p(nombre)
 where s.nombre = 'Sala 1 IMAX Laser' or (p.nombre = 'Tótem 1' and s.nombre <> 'Sala 1 IMAX Laser')
on conflict (sala_id, nombre) do nothing;

-- Operaciones manuales de ejemplo para la bitácora y la consulta #4
insert into admin_operacion_audit (creado_en, usuario_id, rol_id, ip, accion, tabla_afectada, registro_id, motivo, detalle)
select now() - x.hace, u.id, r.id, x.ip::inet, x.accion, x.tabla, x.registro, x.motivo, x.detalle::jsonb
  from (values
    (interval '1 day',   '190.113.20.15', 'cortesia',          'boleto', 101, 'Cortesía para prensa del estreno', '{"cantidad": 2}'),
    (interval '3 days',  '190.113.20.15', 'cortesia',          'boleto', 102, 'Cortesía para influencer invitado', '{"cantidad": 1}'),
    (interval '6 days',  '190.113.20.15', 'cortesia',          'boleto', 103, 'Cortesía por reclamo de servicio', '{"cantidad": 2}'),
    (interval '9 days',  '190.113.20.15', 'reembolso_forzado', 'boleto', 104, 'Función cancelada por falla técnica', '{"monto": 9.25, "forzado": true}'),
    (interval '12 days', '190.113.20.15', 'reembolso_forzado', 'boleto', 105, 'Cliente atendido por incidencia en sala', '{"monto": 14.50, "forzado": true}'),
    (interval '15 days', '190.113.20.15', 'cambio_asiento',    'boleto', 106, 'Asiento dañado, se reubica al cliente', '{"de": "B4", "a": "C4"}'),
    (interval '20 days', '190.113.20.15', 'cambio_precio',     'tarifa', 3,   'Ajuste de precio del martes de descuento', '{"anterior": 6.00, "nuevo": 6.50}')
  ) x(hace, ip, accion, tabla, registro, motivo, detalle)
  join usuario u on u.email = 'admin@imax.test'
  join rol r on r.nombre = 'administrador'
 where not exists (select 1 from admin_operacion_audit where ip = '190.113.20.15'::inet);

-- =====================================================================
-- database/seeds/11_seed_venta.sql
-- =====================================================================
-- Datos de venta para la demo
-- Las compras son en funciones de "Sala 1 IMAX Laser" (80 asientos, ids 1 a 80); la última compra va en otra función de esa sala.
-- Requiere todos los DDL, 01_catalogo_demo.sql y el seed de métodos de pago.
-- Usa las mismas funciones que la aplicación, así que los datos quedan como los de una compra real.

-- Orden 1: el cliente compra 2 asientos de la primera función de la sala y paga (aprobado)
select * from fn_bloquear_asientos(1, (select min(id) from funcion where sala_id = 1), array[1, 2]);
select total from fn_asignar_tipos(1, 1, array[1, 2], array[1, 4]);
select resultado_pago from fn_confirmar_pago(1, 1, 'TARJETA_SIMULADA', 'APROBADO');

-- Orden 2: otra compra de 3 asientos en la misma función pagada con PayPal
select * from fn_bloquear_asientos(1, (select min(id) from funcion where sala_id = 1), array[10, 11, 12]);
select total from fn_asignar_tipos(2, 1, array[10, 11, 12], array[1, 1, 2]);
select resultado_pago from fn_confirmar_pago(2, 1, 'PAYPAL_SIMULADO', 'APROBADO');

-- Orden 3: un pago rechazado (los asientos quedan libres)
select * from fn_bloquear_asientos(1, (select min(id) from funcion where sala_id = 1), array[20, 21]);
select total from fn_asignar_tipos(3, 1, array[20, 21], array[1, 1]);
select resultado_pago from fn_confirmar_pago(3, 1, 'BILLETERA_SIMULADA', 'RECHAZADO');

-- Orden 4: una compra en otra función de la sala con billetera
select * from fn_bloquear_asientos(1, (select max(id) from funcion where sala_id = 1), array[50]);
select total from fn_asignar_tipos(4, 1, array[50], array[1]);
select resultado_pago from fn_confirmar_pago(4, 1, 'BILLETERA_SIMULADA', 'APROBADO');

-- Orden 5: un bloqueo que se venció sin pagar
select * from fn_bloquear_asientos(1, (select min(id) from funcion where sala_id = 1), array[30, 31]);
update reserva_asiento set bloqueado_hasta = now() - interval '5 minutes' where orden_id = 5;
select fn_liberar_expirados();

-- Orden 6: un bloqueo vigente (el cliente sigue eligiendo)
select * from fn_bloquear_asientos(1, (select min(id) from funcion where sala_id = 1), array[40]);


-- =====================================================================
-- database/seeds/13_demo_checkin.sql
-- =====================================================================
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
