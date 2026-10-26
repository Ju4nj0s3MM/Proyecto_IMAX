// MÓDULO C · Usuarios y roles — API del panel de administración (/api/seguridad/admin/...)
// Solo rol administrador (RN-17, aplicado en el backend). Con MOCK=true usa datos en memoria con la misma forma.
//
//   GET/POST     /admin/usuarios          body: { nombre, apellido, email, telefono, activo, password, roles:[ids] }
//   PUT/DELETE   /admin/usuarios/:id      (password opcional al editar: vacío = no cambia)
//   GET/POST     /admin/roles             body: { nombre, descripcion }
//   PUT/DELETE   /admin/roles/:id
const router = require('express').Router();
const { requireRole, wrap, isMock } = require('../auth');

const repo = () => (isMock() ? require('../repos/seguridad-mock') : require('../repos/seguridad-sql'));

// Roles que la app usa por NOMBRE para el control de acceso (nav.js, requireRole). Renombrarlos o borrarlos dejaría a todos sin acceso.
// Mantener igual que ROLES en src/routes/seguridad.js.
const ROLES_SISTEMA = ['cliente', 'taquillero', 'operador_sala', 'contador', 'administrador'];

const malo = (status, error) => Object.assign(new Error(error), { status });
const yo = req => Number(req.session.user.id);

function validarPassword(pw, obligatoria) {
  if (!pw) { if (obligatoria) throw malo(400, 'La contraseña es obligatoria al crear un usuario.'); return; }
  if (typeof pw !== 'string' || pw.length < 8) throw malo(400, 'La contraseña debe tener al menos 8 caracteres.');
  if (pw.length > 72) throw malo(400, 'La contraseña no puede pasar de 72 caracteres.');   // límite de bcrypt
}

router.use(requireRole('administrador'));

// ---- Usuarios ----
router.get('/usuarios', wrap(async (req, res) => res.json(await repo().listarUsuarios())));

router.post('/usuarios', wrap(async (req, res) => {
  validarPassword(req.body.password, true);
  const { id } = await repo().crearUsuario(req.body, yo(req));
  res.status(201).json(await repo().obtenerUsuario(id));
}));

router.put('/usuarios/:id', wrap(async (req, res) => {
  const id = Number(req.params.id);
  validarPassword(req.body.password, false);
  if (id === yo(req)) {
    if (req.body.activo === false) throw malo(400, 'No puedes desactivar tu propio usuario.');
    if (Array.isArray(req.body.roles)) {
      const roles = await repo().listarRoles();
      const admin = roles.find(r => r.nombre === 'administrador');
      if (admin && !req.body.roles.map(Number).includes(admin.id)) throw malo(400, 'No puedes quitarte a ti mismo el rol administrador.');
    }
  }
  await repo().editarUsuario(id, req.body, yo(req));
  res.json(await repo().obtenerUsuario(id));
}));

router.delete('/usuarios/:id', wrap(async (req, res) => {
  if (Number(req.params.id) === yo(req)) throw malo(400, 'No puedes eliminar tu propio usuario.');
  await repo().borrarUsuario(req.params.id);
  res.status(204).end();
}));

// ---- Roles ----
router.get('/roles', wrap(async (req, res) => {
  const roles = await repo().listarRoles();
  res.json(roles.map(r => ({ ...r, sistema: ROLES_SISTEMA.includes(r.nombre) })));
}));

router.post('/roles', wrap(async (req, res) => res.status(201).json(await repo().crearRol(req.body))));

router.put('/roles/:id', wrap(async (req, res) => {
  const actual = await repo().obtenerRol(req.params.id);
  if (ROLES_SISTEMA.includes(actual.nombre) && req.body.nombre !== undefined && req.body.nombre !== actual.nombre) {
    throw malo(400, `"${actual.nombre}" es un rol del sistema: la app lo usa por nombre, así que no se puede renombrar. Sí puedes cambiar su descripción.`);
  }
  res.json(await repo().editarRol(req.params.id, req.body));
}));

router.delete('/roles/:id', wrap(async (req, res) => {
  const actual = await repo().obtenerRol(req.params.id);
  if (ROLES_SISTEMA.includes(actual.nombre)) throw malo(400, `"${actual.nombre}" es un rol del sistema y no se puede eliminar.`);
  await repo().borrarRol(req.params.id);
  res.status(204).end();
}));

// ---- Errores de PostgreSQL → mensajes legibles para la GUI ----
const MENSAJES = {
  uq_usuario_email: 'Ya existe un usuario con ese correo (sin importar mayúsculas).',
  ck_usuario_email: 'El correo no tiene un formato válido (ej. nombre@dominio.com).',
  rol_nombre_key: 'Ya existe un rol con ese nombre.'
};
const TABLAS = { usuario_rol: 'usuarios con ese rol', reserva: 'reservas', orden: 'órdenes', boleto: 'boletos', reembolso: 'reembolsos' };

router.use((err, req, res, next) => {
  const m = MENSAJES[err.constraint];
  switch (err.code) {
    case '23505': return res.status(409).json({ error: m || 'Ya existe un registro con esos datos.' });
    case '23514': return res.status(400).json({ error: m || 'Algún valor no cumple las reglas de la tabla.' });
    case '23502': return res.status(400).json({ error: `Falta el campo obligatorio: ${err.column}.` });
    case '23001':   // on delete restrict
    case '23503': {
      const t = /table "(\w+)"/.exec(err.detail || '');
      if (t && /referenced from/.test(err.detail)) {
        return res.status(409).json({ error: `No se puede eliminar: todavía hay ${TABLAS[t[1]] || t[1]}. Quítalo de ellos primero o desactívalo.` });
      }
      return res.status(409).json({ error: 'Hace referencia a un registro que no existe.' });
    }
    case '22001': return res.status(400).json({ error: 'Algún texto excede el largo permitido.' });
  }
  next(err);
});

module.exports = router;
