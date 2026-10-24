-- 12 Datos masivos del catálogo para las pruebas de rendimiento (EXPLAIN ANALYZE)
-- Dueño: Matias Esquivel Lizano
-- Requiere 01_catalogo.sql, 05_catalogo_logica.sql y el seed 01_catalogo_demo.sql (zonas, clasificaciones, géneros)
-- Genera 300 cines, 1 500 salas, 270 000 asientos, 500 películas y unas 900 000 funciones
-- (90 días hacia atrás y 30 hacia adelante, 5 funciones por sala al día). Tarda unos minutos.

begin;

-- 300 cines en 10 ciudades
insert into cine (nombre, direccion, ciudad, pais)
select 'IMAX Masivo ' || lpad(i::text, 3, '0'),
       'Calle ' || i,
       (array['Nueva York','Chicago','Toronto','Londres','París','Tokio','Sídney','Ciudad de México','Bogotá','Madrid'])[1 + i % 10],
       (array['Estados Unidos','Estados Unidos','Canadá','Reino Unido','Francia','Japón','Australia','México','Colombia','España'])[1 + i % 10]
  from generate_series(1, 300) i;

-- 5 salas por cine (1 500 salas) con 20 a 30 minutos de limpieza
insert into sala (cine_id, nombre, capacidad, minutos_limpieza)
select c.id, 'Sala ' || s, 180, 20 + (s % 3) * 5
  from cine c, generate_series(1, 5) s
 where c.nombre like 'IMAX Masivo %';

-- 12 filas x 15 asientos por sala; filas A-C son VIP
insert into asiento (sala_id, zona_asiento_id, fila, numero)
select s.id,
       case when f <= 3 then (select id from zona_asiento where nombre = 'VIP')
            else (select id from zona_asiento where nombre = 'General') end,
       chr(64 + f), n
  from sala s join cine c on c.id = s.cine_id,
       generate_series(1, 12) f, generate_series(1, 15) n
 where c.nombre like 'IMAX Masivo %';

-- 500 películas de 80 a 180 minutos
insert into pelicula (titulo, sinopsis, duracion_min, clasificacion_id, fecha_estreno)
select 'Película ' || lpad(i::text, 3, '0'),
       'Sinopsis de prueba de la película ' || i || '.',
       80 + (i * 37) % 101,
       (select id from clasificacion order by id offset (i % 4) limit 1),
       current_date - (i % 120)
  from generate_series(1, 500) i;

-- uno o dos géneros por película
insert into pelicula_genero (pelicula_id, genero_id)
select p.id, g.id
  from pelicula p
  join lateral (select id from genero order by id offset (p.id % 6) limit 1 + (p.id % 2)) g on true
 where p.titulo like 'Película %';

-- funciones: 5 horarios separados al menos 3,5 h (la película más larga + limpieza ocupa 3,5 h, así no hay traslape);
-- la de las 00:00 es la trasnoche que sigue a la de las 20:30 del día anterior
-- el trigger calcula fin y fin_limpieza
insert into funcion (pelicula_id, sala_id, inicio, estado)
select pel.ids[1 + (s.id * 7 + (d + 90) * 3 + h) % 500],
       s.id,
       ((current_date + d) + hora) at time zone 'America/Costa_Rica',
       case when d < 0 then 'Finalizada'
            when (s.id + d + h) % 50 = 0 then 'Cancelada'
            else 'Activa' end
  from sala s
  join cine c on c.id = s.cine_id
  cross join generate_series(-90, 30) d
  cross join lateral (values (0, time '10:00'), (1, time '13:30'), (2, time '17:00'), (3, time '20:30'), (4, time '00:00')) x(h, hora)
  cross join (select array_agg(id order by id) as ids from pelicula where titulo like 'Película %') pel
 where c.nombre like 'IMAX Masivo %';

commit;

analyze cine, sala, asiento, pelicula, pelicula_genero, funcion;
