\encoding UTF8
-- 03 Consultas analíticas del negocio
-- Unión de los scripts de database/ en el orden de ejecución. Los archivos originales siguen en sus carpetas.


-- =====================================================================
-- database/queries/19_consulta_ocupacion.sql
-- =====================================================================
-- Consulta analítica: ocupación y recaudación por función
-- Porcentaje de asientos vendidos frente a la capacidad de la sala e ingresos de la función.
-- Cuenta los boletos que no están anulados y suma solo las órdenes pagadas (las reembolsadas no cuentan).
-- Para ver todas las funciones basta quitar el where.
-- Índices que usa: idx_boleto_funcion e idx_orden_funcion_estado (09_venta_indices.sql)

select f.id as funcion_id,
       p.titulo,
       s.nombre as sala,
       f.inicio,
       s.capacidad,
       (select count(*) from boleto b
         where b.funcion_id = f.id and b.estado <> 'ANULADO') as asientos_vendidos,
       round(100.0 * (select count(*) from boleto b
                       where b.funcion_id = f.id and b.estado <> 'ANULADO') / s.capacidad, 2) as porcentaje_ocupacion,
       coalesce((select sum(o.total) from orden o
                  where o.funcion_id = f.id and o.estado = 'PAGADA'), 0) as recaudado
  from funcion f
  join pelicula p on p.id = f.pelicula_id
  join sala s on s.id = f.sala_id
 where f.id = 3;  -- la función 3 es la que tiene las ventas del seed

-- =====================================================================
-- database/queries/20_consulta_top5.sql
-- =====================================================================
-- Consulta analítica 2: Top 5 de películas más demandadas en la última semana (nivel global)
-- Dueño: Matias Esquivel Lizano
-- Cuenta los boletos emitidos en los últimos 7 días, sin contar los anulados (reembolsados).
-- porcentaje_semana: parte de todos los boletos de la semana que se llevó cada película.
-- Índice que usa: idx_boleto_emitido (10_catalogo_indices.sql)

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
-- database/queries/21_consulta_metodos_pago.sql
-- =====================================================================
-- Consulta analítica: métodos de pago más usados
-- Cuenta solo los pagos aprobados. porcentaje_uso es la parte de los pagos que se hizo con cada método.
-- Los métodos que nadie ha usado salen con cero.

select m.nombre as metodo_pago,
       count(p.id) as pagos,
       round(100.0 * count(p.id) / nullif(sum(count(p.id)) over (), 0), 2) as porcentaje_uso,
       coalesce(sum(p.monto), 0) as monto_total
  from metodo_pago m
  left join pago p on p.metodo_pago_id = m.id and p.resultado = 'APROBADO'
 group by m.id, m.nombre
 order by pagos desc, m.nombre;

-- =====================================================================
-- database/queries/04_auditoria.sql
-- =====================================================================
-- Operaciones manuales de administradores en el último mes, por administrador
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