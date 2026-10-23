// MÓDULO C · Usuarios y roles — acceso a PostgreSQL para el panel de administración de usuarios.
// Tablas: rol, usuario, usuario_rol (database/ddl/01_catalogo.sql).
// La contraseña se convierte en hash DENTRO de la BD con pgcrypto: crypt(password, gen_salt('bf')).
// password_hash nunca se devuelve al navegador.
const { pool } = require('../db');

const COLS_USUARIO = ['nombre', 'apellido', 'email', 'telefono', 'activo'];

function noEncontrado() { const e = new Error('Registro no encontrado'); e.status = 404; return e; }
function limpiar(body, cols) {
  const out = {};
  for (const c of cols) if (body[c] !== undefined) out[c] = typeof body[c] === 'string' ? (body[c].trim() || null) : body[c];
  return out;
}

async function enTransaccion(fn) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const r = await fn(client);
    await client.query('COMMIT');
    return r;
  } catch (e) {
    await client.query('ROLLBACK');
    throw e;
  } finally {
    client.release();
  }
}

// Deja al usuario exactamente con los roles indicados. Los que ya tenía conservan su asignado_en / asignado_por.
async function guardarRoles(db, usuarioId, roles, asignadoPor) {
  if (!Array.isArray(roles)) return;
  await db.query('delete from usuario_rol where usuario_id = $1 and rol_id <> all($2::bigint[])', [usuarioId, roles]);
  await db.query(`
    insert into usuario_rol (usuario_id, rol_id, asignado_por)
    select $1, unnest($2::bigint[]), (select id from usuario where id = $3)
    on conflict (usuario_id, rol_id) do nothing`, [usuarioId, roles, asignadoPor]);
}

const SELECT_USUARIOS = `
  select u.id, u.nombre, u.apellido, u.email, u.telefono, u.activo, u.creado_en,
         coalesce(array_agg(r.id order by r.nombre) filter (where r.id is not null), '{}')::int[] as roles_ids,
         coalesce(array_agg(r.nombre order by r.nombre) filter (where r.id is not null), '{}') as roles
    from usuario u
    left join usuario_rol ur on ur.usuario_id = u.id
    left join rol r on r.id = ur.rol_id
   %WHERE%
   group by u.id
   order by u.activo desc, u.apellido, u.nombre`;

module.exports = {
  // ---- Usuarios ----
  async listarUsuarios() {
    return (await pool.query(SELECT_USUARIOS.replace('%WHERE%', ''))).rows;
  },
  async obtenerUsuario(id) {
    const { rows } = await pool.query(SELECT_USUARIOS.replace('%WHERE%', 'where u.id = $1'), [id]);
    if (!rows[0]) throw noEncontrado();
    return rows[0];
  },
  async crearUsuario(body, asignadoPor) {
    return enTransaccion(async db => {
      const d = limpiar(body, COLS_USUARIO);
      const k = Object.keys(d);
      const { rows } = await db.query(
        `insert into usuario (${k.join(', ')}, password_hash)
         values (${k.map((_, i) => '$' + (i + 1)).join(', ')}, crypt($${k.length + 1}, gen_salt('bf')))
         returning id`,
        [...Object.values(d), body.password]);
      await guardarRoles(db, rows[0].id, body.roles, asignadoPor);
      return rows[0];
    });
  },
  async editarUsuario(id, body, asignadoPor) {
    return enTransaccion(async db => {
      const d = limpiar(body, COLS_USUARIO);
      const sets = Object.keys(d).map((c, i) => `${c} = $${i + 1}`);
      const params = Object.values(d);
      if (body.password) { params.push(body.password); sets.push(`password_hash = crypt($${params.length}, gen_salt('bf'))`); }
      if (sets.length) {
        params.push(id);
        const { rowCount } = await db.query(`update usuario set ${sets.join(', ')} where id = $${params.length}`, params);
        if (!rowCount) throw noEncontrado();
      } else {
        const { rowCount } = await db.query('select 1 from usuario where id = $1', [id]);
        if (!rowCount) throw noEncontrado();
      }
      await guardarRoles(db, id, body.roles, asignadoPor);
      return { id: Number(id) };
    });
  },
  async borrarUsuario(id) {
    const { rowCount } = await pool.query('delete from usuario where id = $1', [id]);   // usuario_rol cae en cascada
    if (!rowCount) throw noEncontrado();
  },

  // ---- Roles ----
  async listarRoles() {
    const { rows } = await pool.query(`
      select r.*, (select count(*) from usuario_rol ur where ur.rol_id = r.id)::int as usuarios
        from rol r order by r.id`);
    return rows;
  },
  async obtenerRol(id) {
    const { rows } = await pool.query('select * from rol where id = $1', [id]);
    if (!rows[0]) throw noEncontrado();
    return rows[0];
  },
  async crearRol(body) {
    const d = limpiar(body, ['nombre', 'descripcion']);
    const { rows } = await pool.query('insert into rol (nombre, descripcion) values ($1, $2) returning *', [d.nombre ?? null, d.descripcion ?? null]);
    return rows[0];
  },
  async editarRol(id, body) {
    const d = limpiar(body, ['nombre', 'descripcion']);
    const k = Object.keys(d);
    if (!k.length) return this.obtenerRol(id);
    const { rows } = await pool.query(
      `update rol set ${k.map((c, i) => `${c} = $${i + 1}`).join(', ')} where id = $${k.length + 1} returning *`, [...Object.values(d), id]);
    if (!rows[0]) throw noEncontrado();
    return rows[0];
  },
  async borrarRol(id) {
    const { rowCount } = await pool.query('delete from rol where id = $1', [id]);
    if (!rowCount) throw noEncontrado();
  },

  // Para el modo AUTH_DEV_BYPASS con BD real: primer usuario activo que tenga ese rol
  async usuarioDemoPorRol(rol) {
    const { rows } = await pool.query(`
      select u.id, u.nombre || ' ' || u.apellido as nombre
        from usuario u join usuario_rol ur on ur.usuario_id = u.id join rol r on r.id = ur.rol_id
       where r.nombre = $1 and u.activo order by u.id limit 1`, [rol]);
    return rows[0] || null;
  }
};
