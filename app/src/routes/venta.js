// MÓDULO B — Venta, bloqueo de asientos, pago y boletos · DUEÑO: Juanjo
const router = require('express').Router();
const { call } = require('../db');
const { requireLogin, requireRole, wrap, isMock } = require('../auth');
const mock = require('../mock');

// RN-03. Contrato: fn_mapa_asientos(funcion) -> asiento_id, fila, numero, zona, estado
router.get('/funciones/:id/asientos', wrap(async (req, res) => {
  if (isMock()) return res.json(mock.mapa(req.params.id));
  res.json(await call('SELECT * FROM fn_mapa_asientos($1)', [req.params.id]));
}));

// RN-04, RN-05. Contrato: fn_bloquear_asientos(usuario, funcion, asientos[]) -> reserva_id, expira_en
// El usuario sale de la SESIÓN, nunca del body.
router.post('/reservas', requireLogin, wrap(async (req, res) => {
  if (isMock()) return res.json(mock.reserva());
  const { funcion_id, asientos = [] } = req.body;
  const rows = await call('SELECT * FROM fn_bloquear_asientos($1,$2,$3::bigint[])',
    [req.session.user.id, funcion_id, asientos]);
  res.json(rows[0] || {});
}));

// RN-09, RN-10, RN-11. fn_confirmar_pago(orden, usuario, metodo, resultado)  resultado = APROBADO | RECHAZADO (simulado)
router.post('/pagos', requireLogin, wrap(async (req, res) => {
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

// TODO (Juanjo): consultas analíticas #1 (ocupación y recaudación por función) y #3 (métodos de pago %)
router.get('/reportes/ocupacion', requireRole('administrador', 'contador'), (req, res) => res.status(501).json({ error: 'TODO Juanjo: ocupación y recaudación' }));
router.get('/reportes/metodos-pago', requireRole('administrador', 'contador'), (req, res) => res.status(501).json({ error: 'TODO Juanjo: métodos de pago' }));

module.exports = router;
