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

-- Asientos: filas A..H × 10 (A-C VIP, H accesible) para la sala de Los Ángeles; el resto todo General.
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

commit;
