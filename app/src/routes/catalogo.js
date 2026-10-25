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

// RN-07, RN-08. Contrato: fn_calcular_total(funcion_id, asientos[], tipos_entrada[])
// La función es necesaria para saber el día y la hora (tarifas por día/horario y 2x1 por día).
router.post('/total', wrap(async (req, res) => {
  if (isMock()) return res.json({ subtotal: 20, descuento: 10, cargo_servicio: 1, total: 11, detalle: [] });
  const { funcion_id, asientos = [], tipos = [] } = req.body;
  const filas = await call('SELECT * FROM fn_calcular_total($1::bigint, $2::bigint[], $3::bigint[])', [funcion_id, asientos, tipos]);
  res.json(filas[0]);
}));

// Consulta analítica #2: Top 5 de películas más vendidas en la última semana (database/queries/20_consulta_top5.sql)
router.get('/reportes/top5', requireRole('administrador', 'contador'), wrap(async (req, res) => {
  if (isMock()) return res.json([{ pelicula_id: 1, titulo: 'Dune: Parte Tres', boletos_vendidos: 120, funciones: 6, porcentaje_semana: 60 }]);
  res.json(await call(`
    SELECT p.id AS pelicula_id, p.titulo, count(*) AS boletos_vendidos,
           count(DISTINCT b.funcion_id) AS funciones,
           round(100.0 * count(*) / sum(count(*)) OVER (), 2) AS porcentaje_semana
      FROM boleto b
      JOIN funcion f ON f.id = b.funcion_id
      JOIN pelicula p ON p.id = f.pelicula_id
     WHERE b.emitido_en >= now() - interval '7 days'
       AND b.estado <> 'ANULADO'
     GROUP BY p.id, p.titulo
     ORDER BY boletos_vendidos DESC, p.titulo
     LIMIT 5`));
}));

// Dashboard: indicadores del catálogo y próximas funciones (lo de venta viene de /venta/reportes/*)
router.get('/reportes/resumen', requireRole('administrador', 'contador'), wrap(async (req, res) => {
  if (isMock()) {
    return res.json({
      indicadores: { cines: 3, salas: 4, peliculas_activas: 3, funciones_24h: 6, funciones_7d: 8 },
      proximas: mock.cartelera.map(f => ({ funcion_id: f.funcion_id, titulo: f.titulo, cine: f.cine, sala: f.sala, inicio: f.inicio, capacidad: 80 }))
    });
  }
  const [indicadores] = await call(`
    SELECT (SELECT count(*) FROM cine WHERE activo) AS cines,
           (SELECT count(*) FROM sala WHERE activa) AS salas,
           (SELECT count(*) FROM pelicula WHERE activa) AS peliculas_activas,
           (SELECT count(*) FROM funcion WHERE estado = 'Activa' AND inicio > now() AND inicio < now() + interval '1 day') AS funciones_24h,
           (SELECT count(*) FROM funcion WHERE estado = 'Activa' AND inicio > now() AND inicio < now() + interval '7 days') AS funciones_7d`);
  const proximas = await call(`
    SELECT f.id AS funcion_id, p.titulo, c.nombre AS cine, s.nombre AS sala, f.inicio, s.capacidad
      FROM funcion f
      JOIN pelicula p ON p.id = f.pelicula_id
      JOIN sala s ON s.id = f.sala_id
      JOIN cine c ON c.id = s.cine_id
     WHERE f.estado = 'Activa' AND f.inicio > now()
     ORDER BY f.inicio
     LIMIT 10`);
  res.json({ indicadores, proximas });
}));

// CRUD de cines, salas, asientos, zonas, clasificaciones, géneros, películas, funciones, tipos de entrada,
// tarifas y promociones (tablas de 01_catalogo.sql). Ver src/routes/catalogo-admin.js
router.use('/admin', require('./catalogo-admin'));

module.exports = router;
