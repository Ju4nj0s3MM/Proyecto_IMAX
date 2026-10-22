// MÓDULO C · Usuarios y roles — versión en memoria (MOCK=true) con la MISMA interfaz que seguridad-sql.js.
// Imita las restricciones del DDL (email único sin importar mayúsculas, formato de email, FK de usuario_rol).
// Las contraseñas NO se guardan: en modo mock solo se marca que existe una.

let seq = 500;
const ahora = () => new Date().toISOString();
const err = (status, message, extra = {}) => Object.assign(new Error(message), { status }, extra);
const EMAIL_OK = e => /^[^@\s]+@[^@\s]+\.[^@\s]+$/i.test(e || '');

const db = {
  rol: [
    { id: 1, nombre: 'cliente',       descripcion: 'Espectador: cartelera, compra y consulta de sus propias entradas' },
    { id: 2, nombre: 'taquillero',    descripcion: 'Venta presencial y corte de caja propio' },
    { id: 3, nombre: 'operador_sala', descripcion: 'Validación de entradas (QR) en puerta' },
    { id: 4, nombre: 'contador',      descripcion: 'Lectura y exportación de información financiera' },
    { id: 5, nombre: 'administrador', descripcion: 'Configuración de cartelera, salas y precios; reembolsos; auditoría' }
  ],
  usuario: [
    { id: 1, nombre: 'Ana',    apellido: 'Cliente',   email: 'cliente@imax.test',  telefono: '8888-0001', activo: true },
    { id: 2, nombre: 'Tomás',  apellido: 'Taquilla',  email: 'taquilla@imax.test', telefono: '8888-0002', activo: true },
    { id: 3, nombre: 'Olga',   apellido: 'Operadora', email: 'operador@imax.test', telefono: null, activo: true },
    { id: 4, nombre: 'Carlos', apellido: 'Contador',  email: 'contador@imax.test', telefono: null, activo: true },
    { id: 5, nombre: 'Admin',  apellido: 'IMAX',      email: 'admin@imax.test',    telefono: null, activo: true }
  ].map(u => ({ ...u, creado_en: ahora() })),
  usuario_rol: [1, 2, 3, 4, 5].map(i => ({ usuario_id: i, rol_id: i, asignado_en: ahora(), asignado_por: null }))
};

function noEncontrado() { return err(404, 'Registro no encontrado'); }
function limpio(v) { return typeof v === 'string' ? (v.trim() || null) : v; }

function validarUsuario(u, id) {
  for (const c of ['nombre', 'apellido', 'email']) if (!u[c]) throw err(400, 'x', { code: '23502', column: c });
  if (!EMAIL_OK(u.email)) throw err(400, 'x', { code: '23514', constraint: 'ck_usuario_email' });
  if (db.usuario.some(x => x.id !== id && x.email.toLowerCase() === u.email.toLowerCase())) throw err(409, 'x', { code: '23505', constraint: 'uq_usuario_email' });
}

function guardarRoles(usuarioId, roles, asignadoPor) {
  if (!Array.isArray(roles)) return;
  const ids = [...new Set(roles.map(Number))];
  if (ids.some(r => !db.rol.some(x => x.id === r))) throw err(409, 'x', { code: '23503' });
  db.usuario_rol = db.usuario_rol.filter(x => x.usuario_id !== usuarioId || ids.includes(x.rol_id));
  const por = db.usuario.some(u => u.id === asignadoPor) ? asignadoPor : null;
  ids.forEach(r => {
    if (!db.usuario_rol.some(x => x.usuario_id === usuarioId && x.rol_id === r)) {
      db.usuario_rol.push({ usuario_id: usuarioId, rol_id: r, asignado_en: ahora(), asignado_por: por });
    }
  });
}

function vistaUsuario(u) {
  const rs = db.usuario_rol.filter(x => x.usuario_id === u.id).map(x => db.rol.find(r => r.id === x.rol_id)).filter(Boolean)
    .sort((a, b) => a.nombre.localeCompare(b.nombre));
  return { ...u, roles_ids: rs.map(r => r.id), roles: rs.map(r => r.nombre) };
}

module.exports = {
  async listarUsuarios() {
    return db.usuario.map(vistaUsuario)
      .sort((a, b) => (b.activo - a.activo) || (a.apellido + a.nombre).localeCompare(b.apellido + b.nombre));
  },
  async obtenerUsuario(id) {
    const u = db.usuario.find(x => x.id === Number(id));
    if (!u) throw noEncontrado();
    return vistaUsuario(u);
  },
  async crearUsuario(body, asignadoPor) {
    const u = { nombre: limpio(body.nombre), apellido: limpio(body.apellido), email: limpio(body.email), telefono: limpio(body.telefono),
                activo: body.activo ?? true };
    validarUsuario(u, null);
    if (Array.isArray(body.roles) && body.roles.some(r => !db.rol.some(x => x.id === Number(r)))) throw err(409, 'x', { code: '23503' });
    const nuevo = { id: ++seq, ...u, creado_en: ahora() };
    db.usuario.push(nuevo);
    guardarRoles(nuevo.id, body.roles, asignadoPor);
    return { id: nuevo.id };
  },
  async editarUsuario(id, body, asignadoPor) {
    const u = db.usuario.find(x => x.id === Number(id));
    if (!u) throw noEncontrado();
    const nuevo = { ...u };
    for (const c of ['nombre', 'apellido', 'email', 'telefono', 'activo']) if (body[c] !== undefined) nuevo[c] = limpio(body[c]);
    validarUsuario(nuevo, u.id);
    if (Array.isArray(body.roles) && body.roles.some(r => !db.rol.some(x => x.id === Number(r)))) throw err(409, 'x', { code: '23503' });
    Object.assign(u, nuevo);
    guardarRoles(u.id, body.roles, asignadoPor);
    return { id: u.id };
  },
  async borrarUsuario(id) {
    id = Number(id);
    const i = db.usuario.findIndex(x => x.id === id);
    if (i < 0) throw noEncontrado();
    db.usuario.splice(i, 1);
    db.usuario_rol = db.usuario_rol.filter(x => x.usuario_id !== id);                                    // on delete cascade
    db.usuario_rol.forEach(x => { if (x.asignado_por === id) x.asignado_por = null; });                // on delete set null
  },

  async listarRoles() {
    return db.rol.map(r => ({ ...r, usuarios: db.usuario_rol.filter(x => x.rol_id === r.id).length })).sort((a, b) => a.id - b.id);
  },
  async obtenerRol(id) {
    const r = db.rol.find(x => x.id === Number(id));
    if (!r) throw noEncontrado();
    return r;
  },
  async crearRol(body) {
    const r = { nombre: limpio(body.nombre), descripcion: limpio(body.descripcion) ?? null };
    if (!r.nombre) throw err(400, 'x', { code: '23502', column: 'nombre' });
    if (db.rol.some(x => x.nombre === r.nombre)) throw err(409, 'x', { code: '23505', constraint: 'rol_nombre_key' });
    const nuevo = { id: ++seq, ...r };
    db.rol.push(nuevo);
    return nuevo;
  },
  async editarRol(id, body) {
    const r = db.rol.find(x => x.id === Number(id));
    if (!r) throw noEncontrado();
    const nuevo = { ...r };
    if (body.nombre !== undefined) nuevo.nombre = limpio(body.nombre);
    if (body.descripcion !== undefined) nuevo.descripcion = limpio(body.descripcion);
    if (!nuevo.nombre) throw err(400, 'x', { code: '23502', column: 'nombre' });
    if (db.rol.some(x => x.id !== r.id && x.nombre === nuevo.nombre)) throw err(409, 'x', { code: '23505', constraint: 'rol_nombre_key' });
    return Object.assign(r, nuevo);
  },
  async borrarRol(id) {
    id = Number(id);
    const i = db.rol.findIndex(x => x.id === id);
    if (i < 0) throw noEncontrado();
    if (db.usuario_rol.some(x => x.rol_id === id)) throw err(409, 'x', { code: '23503', detail: 'Key is still referenced from table "usuario_rol".' });
    db.rol.splice(i, 1);
  },

  async usuarioDemoPorRol(rol) {
    const r = db.rol.find(x => x.nombre === rol);
    const ur = r && db.usuario_rol.find(x => x.rol_id === r.id && db.usuario.find(u => u.id === x.usuario_id && u.activo));
    const u = ur && db.usuario.find(x => x.id === ur.usuario_id);
    return u ? { id: u.id, nombre: `${u.nombre} ${u.apellido}` } : null;
  }
};
