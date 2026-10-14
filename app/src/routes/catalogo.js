// MÓDULO A — Catálogo, salas, programación y tarifas · DUEÑO: Mati
const router = require('express').Router();
const { call } = require('../db');
const { requireRole, wrap, isMock } = require('../auth');
const mock = require('../mock');

// RN-01, RN-02. Contrato: fn_listar_cartelera(cine, fecha, genero)
router.get('/cartelera', wrap(async (req, res) => {
  if (isMock()) return res.json(mock.cartelera);
  const { cine = null, fecha = null, genero = null } = req.query;
  res.json(await call('SELECT * FROM fn_listar_cartelera($1,$2,$3)', [cine || null, fecha || null, genero || null]));
}));

// RN-07, RN-08. Contrato: fn_calcular_total(asientos[], tipos_entrada[])
router.post('/total', wrap(async (req, res) => {
  if (isMock()) return res.json({ subtotal: 20, descuento: 10, cargo_servicio: 1, total: 11 });
  const { asientos = [], tipos = [] } = req.body;
  res.json(await call('SELECT * FROM fn_calcular_total($1::bigint[], $2::bigint[])', [asientos, tipos]));
}));

// TODO (Mati): CRUD de administración. Debe llamar a INSERT/UPDATE o funciones SQL (los triggers RN-18 y RN-20 los dispara la BD).
router.get('/admin/peliculas',  requireRole('administrador'), (req, res) => res.status(501).json({ error: 'TODO Mati: listar películas' }));
router.post('/admin/peliculas', requireRole('administrador'), (req, res) => res.status(501).json({ error: 'TODO Mati: alta de película (con póster)' }));
router.post('/admin/salas',     requireRole('administrador'), (req, res) => res.status(501).json({ error: 'TODO Mati: configuración de sala y asientos' }));
router.post('/admin/funciones', requireRole('administrador'), (req, res) => res.status(501).json({ error: 'TODO Mati: programar función (sin traslapes)' }));
router.post('/admin/tarifas',   requireRole('administrador'), (req, res) => res.status(501).json({ error: 'TODO Mati: matriz de precios y promociones' }));

// TODO (Mati): consulta analítica #2 (Top 5 de la semana) y datos del dashboard
router.get('/reportes/top5', requireRole('administrador', 'contador'), (req, res) => res.status(501).json({ error: 'TODO Mati: top 5 última semana' }));

module.exports = router;
