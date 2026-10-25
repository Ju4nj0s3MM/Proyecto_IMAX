// MÓDULO C — Usuarios, RBAC, check-in, reembolsos y auditoría · DUEÑO: Brandon
const router = require('express').Router();
const { call } = require('../db');
const { requireLogin, requireRole, wrap, isMock } = require('../auth');
const mock = require('../mock');
const acceso = () => isMock() ? require('../repos/acceso-mock') : require('../repos/acceso-sql');

const ROLES = ['cliente', 'taquillero', 'operador_sala', 'contador', 'administrador'];

router.get('/config', (req, res) => res.json({
  devBypass: process.env.AUTH_DEV_BYPASS === 'true', mock: isMock(), roles: ROLES
}));

// Contrato propuesto: fn_autenticar(email, password) -> usuario_id, nombre, roles text[]  (contraseña verificada con hash, p.ej. pgcrypto crypt)
router.post('/login', wrap(async (req, res) => {
  const { email, password, rol } = req.body;
  if (process.env.AUTH_DEV_BYPASS === 'true' && rol) {
    if (!ROLES.includes(rol)) return res.status(400).json({ error: 'Rol inválido' });
    // Usa un usuario REAL con ese rol (seed demo) para que las FK a usuario funcionen; si no hay, cae al id ficticio.
    const repo = isMock() ? require('../repos/seguridad-mock') : require('../repos/seguridad-sql');
    const u = await repo.usuarioDemoPorRol(rol).catch(() => null);
    req.session.user = u ? { id: Number(u.id), nombre: `${u.nombre} (dev)`, roles: [rol] }
                         : { id: rol === 'cliente' ? 100 : 1, nombre: `Dev (${rol})`, roles: [rol] };
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
  if (!codigo_qr || !Number.isInteger(Number(puerta_id))) {
    return res.status(400).json({ error: 'Indique el código QR y la puerta' });
  }
  if (isMock()) {
    const r = mock.checkin(codigo_qr);
    acceso().registrarLectura(codigo_qr, puerta_id, r);
    return res.json(r);
  }
  const rows = await call('SELECT * FROM fn_validar_entrada($1,$2)', [codigo_qr, Number(puerta_id)]);
  res.json(rows[0] || {});
}));

router.get('/puertas', requireRole('operador_sala', 'administrador'), wrap(async (req, res) => {
  res.json(await acceso().puertas());
}));

router.get('/accesos', requireRole('operador_sala', 'administrador'), wrap(async (req, res) => {
  res.json(await acceso().accesosRecientes(15));
}));

// RN-19, RN-20. Contrato: fn_reembolsar(boleto, admin, motivo, ip). El admin sale de la SESIÓN.
router.get('/boletos', requireRole('administrador'), wrap(async (req, res) => {
  const q = String(req.query.q || '').trim();
  if (!q) return res.status(400).json({ error: 'Indique el código QR o el ID del boleto' });
  const b = await acceso().buscarBoleto(q);
  if (!b) return res.status(404).json({ error: 'Boleto no encontrado' });
  res.json(b);
}));

router.post('/reembolsos', requireRole('administrador'), wrap(async (req, res) => {
  const { boleto_id, motivo } = req.body;
  if (!Number.isInteger(Number(boleto_id))) return res.status(400).json({ error: 'Boleto inválido' });
  res.json(await acceso().reembolsar(Number(boleto_id), req.session.user.id, motivo, req.ip));
}));

// Bitácora de operaciones administrativas (admin_operacion_audit)
router.get('/auditoria', requireRole('administrador'), wrap(async (req, res) => {
  res.json(await acceso().auditoria(100));
}));

// Consulta analítica #4: operaciones del último mes agrupadas por administrador
router.get('/auditoria/resumen', requireRole('administrador'), wrap(async (req, res) => {
  res.json(await acceso().resumenAuditoria());
}));

// Administración de usuarios, roles y usuario_rol (tablas de 01_catalogo.sql). Ver src/routes/seguridad-admin.js
router.use('/admin', require('./seguridad-admin'));

module.exports = router;