// MÓDULO C — Usuarios, RBAC, check-in, reembolsos y auditoría · DUEÑO: Brandon
const router = require('express').Router();
const { call } = require('../db');
const { requireLogin, requireRole, wrap, isMock } = require('../auth');
const mock = require('../mock');

const ROLES = ['cliente', 'taquillero', 'operador_sala', 'contador', 'administrador'];

router.get('/config', (req, res) => res.json({
  devBypass: process.env.AUTH_DEV_BYPASS === 'true', mock: isMock(), roles: ROLES
}));

// Contrato propuesto: fn_autenticar(email, password) -> usuario_id, nombre, roles text[]  (contraseña verificada con hash, p.ej. pgcrypto crypt)
router.post('/login', wrap(async (req, res) => {
  const { email, password, rol } = req.body;
  if (process.env.AUTH_DEV_BYPASS === 'true' && rol) {
    if (!ROLES.includes(rol)) return res.status(400).json({ error: 'Rol inválido' });
    req.session.user = { id: rol === 'cliente' ? 100 : 1, nombre: `Dev (${rol})`, roles: [rol] };
    return res.json(req.session.user);
  }
  const rows = await call('SELECT * FROM fn_autenticar($1,$2)', [email, password]);
  if (!rows.length) return res.status(401).json({ error: 'Credenciales inválidas' });
  const r = rows[0];
  req.session.user = { id: r.usuario_id, nombre: r.nombre, roles: r.roles };
  res.json(req.session.user);
}));

router.post('/logout', (req, res) => req.session.destroy(() => res.json({ ok: true })));
router.get('/me', (req, res) => req.session.user ? res.json(req.session.user) : res.status(401).json({ error: 'Sin sesión' }));

// RN-14, RN-15, RN-16. Contrato: fn_validar_entrada(codigo_qr, puerta) -> ok boolean, mensaje text
router.post('/checkin', requireRole('operador_sala', 'administrador'), wrap(async (req, res) => {
  const { codigo_qr, puerta_id } = req.body;
  if (isMock()) return res.json(mock.checkin(codigo_qr));
  const rows = await call('SELECT * FROM fn_validar_entrada($1,$2)', [codigo_qr, puerta_id]);
  res.json(rows[0] || {});
}));

// RN-19, RN-20. Contrato: fn_reembolsar(boleto, admin, motivo). El admin sale de la SESIÓN.
router.post('/reembolsos', requireRole('administrador'), wrap(async (req, res) => {
  const { boleto_id, motivo } = req.body;
  if (isMock()) return res.json({ ok: true, mensaje: 'Reembolso registrado (mock)' });
  res.json(await call('SELECT * FROM fn_reembolsar($1,$2,$3)', [boleto_id, req.session.user.id, motivo]));
}));

// TODO (Brandon): consulta #4 (auditoría del último mes agrupada por admin) y visor de bitácora
router.get('/auditoria', requireRole('administrador'), wrap(async (req, res) => {
  if (isMock()) return res.json(mock.auditoria);
  res.status(501).json({ error: 'TODO Brandon: consulta de admin_operacion_audit' });
}));

// TODO (Brandon, opcional): ejecutar cada request con el rol de PostgreSQL del usuario (SET ROLE rol_x) para que el RBAC también lo aplique la BD.

module.exports = router;
