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