// MÓDULO B — Venta, bloqueo de asientos, pago y boletos · DUEÑO: Juanjo
const router = require('express').Router();
const { call } = require('../db');
const { requireLogin, requireRole, wrap, isMock } = require('../auth');
const mock = require('../mock');

// Comprar: cliente, taquillero y admin. Operador de sala y contador no venden (matriz RBAC)
const compra = requireRole('cliente', 'taquillero', 'administrador');

// RN-03. Contrato: fn_mapa_asientos(funcion) -> asiento_id, fila, numero, zona, estado
router.get('/funciones/:id/asientos', wrap(async (req, res) => {
  if (isMock()) return res.json(mock.mapa(req.params.id));
  res.json(await call('SELECT * FROM fn_mapa_asientos($1)', [req.params.id]));
}));

// RN-04, RN-05. Contrato: fn_bloquear_asientos(usuario, funcion, asientos[]) -> reserva_id, expira_en
// El usuario sale de la SESIÓN, nunca del body.
router.post('/reservas', compra, wrap(async (req, res) => {
  if (isMock()) return res.json(mock.reserva());
  const { funcion_id, asientos = [] } = req.body;
  const rows = await call('SELECT * FROM fn_bloquear_asientos($1,$2,$3::bigint[])',
    [req.session.user.id, funcion_id, asientos]);
  res.json(rows[0] || {});
}));

// RN-09, RN-10, RN-11. fn_confirmar_pago(orden, usuario, metodo, resultado)  resultado = APROBADO | RECHAZADO (simulado)
router.post('/pagos', compra, wrap(async (req, res) => {
  // RN-09: jamás aceptar datos de tarjeta
  const prohibidos = ['numero_tarjeta', 'tarjeta', 'cvv', 'cvc', 'card_number'];
  if (prohibidos.some(k => k in req.body)) {
    return res.status(400).json({ error: 'No se permite enviar datos de tarjeta (RN-09). El pago es simulado.' });
  }
  const { reserva_id, metodo = 'TARJETA_SIMULADA', resultado } = req.body;
  if (!['APROBADO', 'RECHAZADO'].includes(resultado)) return res.status(400).json({ error: 'resultado debe ser APROBADO o RECHAZADO' });
  if (isMock()) return res.json(mock.pago({ resultado }));
  // el usuario sale de la sesión, nunca del body
  const rows = await call('SELECT * FROM fn_confirmar_pago($1,$2,$3,$4)',
    [reserva_id, req.session.user.id, metodo, resultado]);
  // la función devuelve una fila por boleto; se agrupan para que quede igual que el mock
  res.json({
    resultado: rows[0].resultado_pago,
    mensaje: rows[0].mensaje,
    boletos: rows.filter(r => r.boleto_id).map(r => ({ boleto_id: r.boleto_id, codigo_qr: r.codigo_qr }))
  });
}));

// RN-13. Contrato: fn_mis_boletos(usuario)
router.get('/mis-boletos', requireLogin, wrap(async (req, res) => {
  if (isMock()) return res.json(mock.boletos);
  res.json(await call('SELECT * FROM fn_mis_boletos($1)', [req.session.user.id]));
}));

// Tipos de entrada para el combo de la pantalla de pago
router.get('/tipos-entrada', requireLogin, wrap(async (req, res) => {
  if (isMock()) return res.json([{ id: 1, nombre: 'Adulto' }, { id: 2, nombre: 'Niño' }]);
  res.json(await call('SELECT id, nombre FROM tipo_entrada ORDER BY id'));
}));

// Resumen de una orden pendiente: película, función y asientos. Solo el dueño puede verla.
router.get('/ordenes/:id', compra, wrap(async (req, res) => {
  if (isMock()) return res.json(mock.orden());
  const rows = await call(
    `SELECT o.id AS orden_id, o.estado, o.total, p.titulo, s.nombre AS sala, f.inicio,
            min(r.bloqueado_hasta) AS expira_en,
            json_agg(json_build_object('asiento_id', a.id, 'fila', a.fila, 'numero', a.numero,
                                       'precio', r.precio) ORDER BY a.fila, a.numero) AS asientos
       FROM orden o
       JOIN funcion f ON f.id = o.funcion_id
       JOIN pelicula p ON p.id = f.pelicula_id
       JOIN sala s ON s.id = f.sala_id
       JOIN reserva_asiento r ON r.orden_id = o.id AND r.estado = 'BLOQUEADO'
       JOIN asiento a ON a.id = r.asiento_id
      WHERE o.id = $1 AND o.usuario_id = $2
      GROUP BY o.id, p.titulo, s.nombre, f.inicio`,
    [req.params.id, req.session.user.id]);
  if (!rows.length) return res.status(404).json({ error: 'No hay una orden pendiente con asientos bloqueados' });
  res.json(rows[0]);
}));

// RN-06, RN-07, RN-08. Guarda el tipo de entrada de cada asiento y devuelve el desglose.
// Contrato: fn_asignar_tipos(orden, usuario, asientos[], tipos[])
router.post('/ordenes/:id/tipos', compra, wrap(async (req, res) => {
  const { asientos = [], tipos = [] } = req.body;
  if (isMock()) return res.json({ subtotal: 20, descuento: 0, cargo_servicio: 1, total: 21, detalle: [] });
  const rows = await call('SELECT * FROM fn_asignar_tipos($1,$2,$3::bigint[],$4::bigint[])',
    [req.params.id, req.session.user.id, asientos, tipos]);
  res.json(rows[0]);
}));

// Consulta analítica 1: ocupación y recaudación de una función (database/queries/19_consulta_ocupacion.sql)
// Con funcion_id devuelve esa función (pantalla de reportes). Sin él, las funciones activas que no han terminado (dashboard).
router.get('/reportes/ocupacion', requireRole('administrador', 'contador'), wrap(async (req, res) => {
  const id = req.query.funcion_id ? Number(req.query.funcion_id) : null;
  if (id !== null && !(Number.isInteger(id) && id > 0)) return res.status(400).json({ error: 'funcion_id no es válido' });
  if (isMock()) {
    const fila = { funcion_id: id || 1, titulo: 'Dune: Parte Tres', capacidad: 80, asientos_vendidos: 5, porcentaje_ocupacion: 6.25, recaudado: 57.75 };
    return res.json(id ? fila : [fila]);
  }
  const rows = await call(
    `SELECT f.id AS funcion_id, p.titulo, s.nombre AS sala, f.inicio, s.capacidad,
            (SELECT count(*) FROM boleto b WHERE b.funcion_id = f.id AND b.estado <> 'ANULADO') AS asientos_vendidos,
            round(100.0 * (SELECT count(*) FROM boleto b WHERE b.funcion_id = f.id AND b.estado <> 'ANULADO') / s.capacidad, 2) AS porcentaje_ocupacion,
            coalesce((SELECT sum(o.total) FROM orden o WHERE o.funcion_id = f.id AND o.estado = 'PAGADA'), 0) AS recaudado
       FROM funcion f
       JOIN pelicula p ON p.id = f.pelicula_id
       JOIN sala s ON s.id = f.sala_id
      WHERE ($1::bigint IS NOT NULL AND f.id = $1)
         OR ($1::bigint IS NULL AND f.estado = 'Activa' AND f.fin >= now())
      ORDER BY f.inicio`, [id]);
  if (!id) return res.json(rows);
  if (!rows.length) return res.status(404).json({ error: 'La función no existe' });
  res.json(rows[0]);
}));

// Consulta analítica 3: métodos de pago más usados (database/queries/21_consulta_metodos_pago.sql)
router.get('/reportes/metodos-pago', requireRole('administrador', 'contador'), wrap(async (req, res) => {
  if (isMock()) return res.json([{ metodo_pago: 'Tarjeta simulada', pagos: 3, porcentaje_uso: 100, monto_total: 70 }]);
  res.json(await call(
    `SELECT m.nombre AS metodo_pago, count(p.id) AS pagos,
            round(100.0 * count(p.id) / nullif(sum(count(p.id)) OVER (), 0), 2) AS porcentaje_uso,
            coalesce(sum(p.monto), 0) AS monto_total
       FROM metodo_pago m
       LEFT JOIN pago p ON p.metodo_pago_id = m.id AND p.resultado = 'APROBADO'
      GROUP BY m.id, m.nombre
      ORDER BY pagos DESC, m.nombre`));
}));

module.exports = router;