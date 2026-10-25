-- 05 EXPLAIN ANALYZE de las consultas (correr después de 04_seeds_masivos.sql)
-- Unión de los scripts de database/ en el orden de ejecución. Los archivos originales siguen en sus carpetas.


-- =====================================================================
-- database/explain/01_explain_catalogo.sql
-- =====================================================================
-- Planes de ejecución de las consultas pesadas del Módulo A
-- Se corre dos veces: antes y después de 10_catalogo_indices.sql, sobre los datos masivos.
--   psql -d imax -f database/explain/01_explain_catalogo.sql > database/explain/antes.txt
-- La función fn_listar_cartelera es SQL simple, así que PostgreSQL la "abre" y el plan muestra la consulta de adentro.

\pset pager off
\timing on

\echo '===== 1. Cartelera sin filtros (próximos 7 días)'
explain (analyze, costs, buffers)
select * from fn_listar_cartelera(null, null, null);

\echo '===== 2. Cartelera por ciudad y fecha'
explain (analyze, costs, buffers)
select * from fn_listar_cartelera('Tokio', current_date + 3, null);

\echo '===== 3. Cartelera por género'
explain (analyze, costs, buffers)
select * from fn_listar_cartelera(null, null, 'Drama');

\echo '===== 4. Top 5 de la última semana'
explain (analyze, costs, buffers)
select p.id as pelicula_id,
       p.titulo,
       count(*) as boletos_vendidos,
       count(distinct b.funcion_id) as funciones,
       round(100.0 * count(*) / sum(count(*)) over (), 2) as porcentaje_semana
  from boleto b
  join funcion f on f.id = b.funcion_id
  join pelicula p on p.id = f.pelicula_id
 where b.emitido_en >= now() - interval '7 days'
   and b.estado <> 'ANULADO'
 group by p.id, p.titulo
 order by boletos_vendidos desc, p.titulo
 limit 5;


-- =====================================================================
-- database/explain/02_explain_venta.sql
-- =====================================================================
-- Planes de ejecución de las consultas de venta
-- Se corre dos veces sobre los datos masivos: antes y después de 09_venta_indices.sql
--   psql -d imax -f database/explain/02_explain_venta.sql > database/explain/venta_antes.txt
--   psql -d imax -f database/explain/02_explain_venta.sql > database/explain/venta_despues.txt
-- La función 500001 tiene ventas en los datos masivos; cambiar el número si se usan otros datos.

-- 1. Ocupación y recaudación de una función (consulta 1)
explain (analyze, buffers)
select f.id as funcion_id, p.titulo, s.capacidad,
       (select count(*) from boleto b where b.funcion_id = f.id and b.estado <> 'ANULADO') as asientos_vendidos,
       coalesce((select sum(o.total) from orden o where o.funcion_id = f.id and o.estado = 'PAGADA'), 0) as recaudado
  from funcion f
  join pelicula p on p.id = f.pelicula_id
  join sala s on s.id = f.sala_id
 where f.id = 500001;

-- 2. Métodos de pago más usados (consulta 3)
explain (analyze, buffers)
select m.nombre, count(p.id) as pagos,
       round(100.0 * count(p.id) / nullif(sum(count(p.id)) over (), 0), 2) as porcentaje_uso
  from metodo_pago m
  left join pago p on p.metodo_pago_id = m.id and p.resultado = 'APROBADO'
 group by m.id, m.nombre
 order by pagos desc;

-- 3. Mapa de asientos de una función
explain (analyze, buffers)
select * from fn_mapa_asientos(500001);

-- 4. Liberación de bloqueos vencidos
explain (analyze, buffers)
select id from reserva_asiento where estado = 'BLOQUEADO' and bloqueado_hasta < now();

-- =====================================================================
-- database/explain/04_explain_auditoria.sql
-- =====================================================================
-- Planes de ejecución de la auditoría administrativa (Módulo C)
--   psql -d imax -f database/explain/04_explain_auditoria.sql
-- Genera datos masivos dentro de una transacción y la revierte al final, así que no deja nada en la base.

\pset pager off
\timing on
begin;

-- 50 administradores de prueba y 300 000 operaciones repartidas entre ellos
insert into usuario (nombre, apellido, email, password_hash)
select 'Admin', 'Prueba ' || g, 'admin-prueba-' || g || '@test.local', (select crypt('x', gen_salt('bf', 4)))
  from generate_series(1, 50) g;

insert into usuario_rol (usuario_id, rol_id)
select u.id, r.id from usuario u, rol r
 where u.email like 'admin-prueba-%' and r.nombre = 'administrador';

insert into admin_operacion_audit (creado_en, usuario_id, rol_id, ip, accion)
select now() - (random() * interval '24 days'),
       u.id,
       (select id from rol where nombre = 'administrador'),
       '10.0.0.1',
       (array['cortesia', 'reembolso_forzado', 'cambio_asiento', 'cambio_precio', 'otro'])[1 + floor(random() * 5)::int]
  from generate_series(1, 300000) g
  join lateral (select id from usuario where email = 'admin-prueba-' || (1 + g % 50) || '@test.local') u on true;

analyze admin_operacion_audit;
select (select id from usuario where email = 'admin-prueba-7@test.local') as admin_prueba \gset

\echo '===== 1. Operaciones de UN administrador en la última semana, SIN índice por usuario'
drop index idx_admin_audit_usuario;
explain (analyze, costs, buffers)
select accion, count(*) from admin_operacion_audit
 where usuario_id = :admin_prueba and creado_en >= now() - interval '7 days'
 group by accion;

\echo '===== 2. La misma consulta CON el índice (usuario_id, creado_en)'
create index idx_admin_audit_usuario on admin_operacion_audit (usuario_id, creado_en);
analyze admin_operacion_audit;
explain (analyze, costs, buffers)
select accion, count(*) from admin_operacion_audit
 where usuario_id = :admin_prueba and creado_en >= now() - interval '7 days'
 group by accion;

\echo '===== 3. Consulta analítica #4 (último mes por administrador)'
explain (analyze, costs, buffers)
select a.usuario_id,
       u.nombre || ' ' || u.apellido as administrador,
       count(*) as total_operaciones,
       count(*) filter (where a.accion = 'cortesia') as cortesias,
       count(*) filter (where a.accion = 'reembolso_forzado') as reembolsos_forzados,
       count(*) filter (where a.accion not in ('cortesia', 'reembolso_forzado')) as otras_modificaciones,
       max(a.creado_en) as ultima_operacion
  from admin_operacion_audit a
  join usuario u on u.id = a.usuario_id
  join rol r on r.id = a.rol_id
 where r.nombre = 'administrador'
   and a.creado_en >= now() - interval '1 month'
 group by a.usuario_id, u.nombre, u.apellido
 order by total_operaciones desc, a.usuario_id;

rollback;