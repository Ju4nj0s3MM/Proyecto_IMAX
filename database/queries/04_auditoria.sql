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