// MÓDULO C · Check-in, reembolsos y auditoría — acceso a PostgreSQL.
// La lógica de negocio vive en las funciones SQL fn_validar_entrada y fn_reembolsar.
const { pool } = require('../db');

module.exports = {
  async puertas() {
    const { rows } = await pool.query(`
      select p.id, p.nombre, s.nombre as sala, c.nombre as cine
        from puerta p
        join sala s on s.id = p.sala_id
        join cine c on c.id = s.cine_id
       where p.activa
       order by c.nombre, s.nombre, p.nombre`);
    return rows;
  },

  async accesosRecientes(limite = 15) {
    const { rows } = await pool.query(`
      select a.fecha, a.codigo_qr, a.resultado, a.motivo, p.nombre as puerta
        from acceso_puerta_log a
        left join puerta p on p.id = a.puerta_id
       order by a.fecha desc, a.id desc
       limit $1`, [limite]);
    return rows;
  },

  async buscarBoleto(q) {
    const { rows } = await pool.query(`
      select b.id, b.codigo_qr, b.estado, f.inicio, pe.titulo,
             a.fila || a.numero as asiento,
             coalesce(r.precio, 0) - r.descuento + coalesce(r.cargo_servicio, 0) as monto
        from boleto b
        join funcion f on f.id = b.funcion_id
        join pelicula pe on pe.id = f.pelicula_id
        join asiento a on a.id = b.asiento_id
        join reserva_asiento r on r.id = b.reserva_asiento_id
       where b.codigo_qr = $1 or b.id::text = $1
       limit 1`, [q]);
    return rows[0] || null;
  },

  async reembolsar(boletoId, adminId, motivo, ip) {
    const { rows } = await pool.query('select * from fn_reembolsar($1, $2, $3, $4::inet)',
      [boletoId, adminId, motivo, ip || null]);
    return rows[0];
  },

  async auditoria(limite = 100) {
    const { rows } = await pool.query(`
      select a.creado_en as fecha, a.usuario_id, u.nombre || ' ' || u.apellido as usuario,
             r.nombre as rol, a.accion as operacion, host(a.ip) as ip, a.motivo
        from admin_operacion_audit a
        join usuario u on u.id = a.usuario_id
        join rol r on r.id = a.rol_id
       order by a.creado_en desc, a.id desc
       limit $1`, [limite]);
    return rows;
  },

  // Consulta analítica #4: operaciones manuales de administradores en el último mes
  async resumenAuditoria() {
    const { rows } = await pool.query(`
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
       order by total_operaciones desc, a.usuario_id`);
    return rows;
  }
};

