// MÓDULO A · Catálogo — API del panel de administración (/api/catalogo/admin/...) · DUEÑO: Mati
// Solo rol administrador (RN-17, aplicado en el backend). Con MOCK=true usa datos en memoria con la misma forma.
//
//   GET/POST          /admin/{cines|salas|zonas|clasificaciones|generos|funciones|tipos|tarifas|promociones}
//   PUT/DELETE        /admin/{...}/:id
//   GET/POST          /admin/peliculas              (body.generos = [ids])
//   PUT/DELETE        /admin/peliculas/:id
//   GET               /admin/salas/:id/asientos
//   POST              /admin/salas/:id/asientos/generar   { filas, por_fila, zonas:[id por fila], reemplazar }
//   PUT               /admin/asientos/:id                 { zona_asiento_id?, activo? }
//   PUT               /admin/asientos                     { ids:[...], zona_asiento_id?, activo? }
const router = require('express').Router();
const { requireRole, wrap, isMock } = require('../auth');

const repo = () => (isMock() ? require('../repos/catalogo-mock') : require('../repos/catalogo-sql'));
const recurso = (req, res, next) => (repo().RECURSOS[req.params.recurso] ? next() : next('route'));

router.use(requireRole('administrador'));

// ---- Películas ----
router.get('/peliculas', wrap(async (req, res) => res.json(await repo().listarPeliculas())));
router.post('/peliculas', wrap(async (req, res) => res.status(201).json(await repo().crearPelicula(req.body))));
router.put('/peliculas/:id', wrap(async (req, res) => res.json(await repo().editarPelicula(req.params.id, req.body))));
router.delete('/peliculas/:id', wrap(async (req, res) => { await repo().borrarPelicula(req.params.id); res.status(204).end(); }));

// ---- Asientos de una sala ----
router.get('/salas/:id/asientos', wrap(async (req, res) => res.json(await repo().asientos(req.params.id))));
router.post('/salas/:id/asientos/generar', wrap(async (req, res) => {
  const filas = parseInt(req.body.filas, 10), por_fila = parseInt(req.body.por_fila, 10);
  const zonas = Array.isArray(req.body.zonas) ? req.body.zonas : [];
  if (!(filas >= 1 && filas <= 26)) return res.status(400).json({ error: 'Las filas deben estar entre 1 y 26 (A-Z)' });
  if (!(por_fila >= 1 && por_fila <= 60)) return res.status(400).json({ error: 'Los asientos por fila deben estar entre 1 y 60' });
  if (zonas.length !== filas) return res.status(400).json({ error: 'Debe indicarse una zona para cada fila' });
  res.status(201).json(await repo().generarAsientos(req.params.id, { filas, por_fila, zonas, reemplazar: !!req.body.reemplazar }));
}));
router.put('/asientos/:id', wrap(async (req, res) => res.json(await repo().editarAsiento(req.params.id, req.body))));
router.put('/asientos', wrap(async (req, res) => {
  const ids = Array.isArray(req.body.ids) ? req.body.ids : [];
  res.json(await repo().editarAsientos(ids, req.body));
}));

// ---- CRUD genérico ----
router.get('/:recurso', recurso, wrap(async (req, res) => res.json(await repo().listar(req.params.recurso))));
router.post('/:recurso', recurso, wrap(async (req, res) => res.status(201).json(await repo().crear(req.params.recurso, req.body))));
router.put('/:recurso/:id', recurso, wrap(async (req, res) => res.json(await repo().editar(req.params.recurso, req.params.id, req.body))));
router.delete('/:recurso/:id', recurso, wrap(async (req, res) => { await repo().borrar(req.params.recurso, req.params.id); res.status(204).end(); }));

// ---- Errores de PostgreSQL → mensajes legibles para la GUI ----
const MENSAJES = {
  uq_cine_nombre_ciudad: 'Ya existe un cine con ese nombre en esa ciudad.',
  uq_sala_cine_nombre: 'Ese cine ya tiene una sala con ese nombre.',
  uq_puerta_sala_nombre: 'Esa sala ya tiene una puerta con ese nombre.',
  uq_asiento_sala_fila_numero: 'La sala ya tiene asientos. Marca "reemplazar" para regenerar el mapa.',
  zona_asiento_nombre_key: 'Ya existe una zona con ese nombre.',
  clasificacion_codigo_key: 'Ya existe una clasificación con ese código.',
  genero_nombre_key: 'Ya existe un género con ese nombre.',
  ck_cine_latitud: 'La latitud debe estar entre -90 y 90.',
  ck_cine_longitud: 'La longitud debe estar entre -180 y 180.',
  ck_sala_capacidad: 'La capacidad debe ser mayor que 0.',
  ck_sala_limpieza: 'Los minutos de limpieza no pueden ser negativos.',
  ck_clasificacion_edad: 'La edad mínima no puede ser negativa.',
  ck_pelicula_duracion: 'La duración debe ser mayor que 0 minutos.',
  ck_asiento_numero: 'El número de asiento debe ser mayor que 0.',
  ex_funcion_sin_traslape: 'La sala ya tiene otra función en ese horario (contando el tiempo de limpieza). Elige otra hora o sala.',
  ck_funcion_estado: 'El estado debe ser Activa, Cancelada o Finalizada.',
  ck_funcion_fin: 'La hora de fin no puede ser anterior al inicio.',
  ck_funcion_fin_limpieza: 'El fin de limpieza no puede ser anterior al fin de la función.',
  tipo_entrada_nombre_key: 'Ya existe un tipo de entrada con ese nombre.',
  uq_tarifa_combinacion: 'Ya existe una tarifa para ese tipo de entrada, zona, día y hora de inicio.',
  ck_tarifa_dia: 'El día de la semana debe estar entre 1 (lunes) y 7 (domingo).',
  ck_tarifa_horas: 'La hora "hasta" debe ser mayor que la hora "desde".',
  ck_tarifa_precio: 'El precio no puede ser negativo.',
  ck_tarifa_cargo: 'El cargo por servicio no puede ser negativo.',
  ck_promocion_tipo: 'El único tipo de promoción permitido es 2X1.',
  ck_promocion_dia: 'El día de la semana debe estar entre 1 (lunes) y 7 (domingo).',
  ck_promocion_fechas: 'La fecha "hasta" no puede ser anterior a la fecha "desde".',
  ck_promocion_condicion: 'La promoción necesita una condición: un día de la semana o exigir cantidad par de entradas.'
};
const TABLAS = { sala: 'salas', asiento: 'asientos', pelicula: 'películas', pelicula_genero: 'películas', funcion: 'funciones',
                 tarifa: 'tarifas', promocion: 'promociones', boleto: 'boletos', puerta: 'puertas',
                 acceso_puerta_log: 'lecturas de check-in', reserva_asiento: 'reservas', orden: 'órdenes' };

router.use((err, req, res, next) => {
  const porConstraint = MENSAJES[err.constraint];
  switch (err.code) {
    case '23P01': return res.status(409).json({ error: porConstraint || 'El registro choca con otro existente.' });
    case '23505': return res.status(409).json({ error: porConstraint || 'Ya existe un registro con esos datos.' });
    case '23514': return res.status(400).json({ error: porConstraint || 'Algún valor no cumple las reglas de la tabla.' });
    case '23502': return res.status(400).json({ error: `Falta el campo obligatorio: ${err.column}.` });
    case '23001':   // on delete restrict
    case '23503': {
      const t = /table "(\w+)"/.exec(err.detail || '');
      if (t && /referenced from/.test(err.detail)) {
        return res.status(409).json({ error: `No se puede eliminar: todavía hay ${TABLAS[t[1]] || t[1]} que lo usan. Desactívalo en su lugar.` });
      }
      return res.status(409).json({ error: 'Hace referencia a un registro que no existe.' });
    }
    case '22P02': case '22007': case '22008': return res.status(400).json({ error: 'Formato inválido en algún campo (número o fecha).' });
    case '22001': return res.status(400).json({ error: 'Algún texto excede el largo permitido.' });
    case '22003': return res.status(400).json({ error: 'Algún número está fuera de rango.' });
  }
  next(err);   // el resto (RAISE de triggers RN-18, 403, 500) lo maneja server.js
});

module.exports = router;
