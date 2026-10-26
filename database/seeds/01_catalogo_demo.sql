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