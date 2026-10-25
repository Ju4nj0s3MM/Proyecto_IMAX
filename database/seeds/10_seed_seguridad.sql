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