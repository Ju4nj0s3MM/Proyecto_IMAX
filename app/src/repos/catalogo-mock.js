// MÓDULO A · Catálogo — versión en memoria (MOCK=true) con la MISMA interfaz que catalogo-sql.js.
// Imita las restricciones del DDL (unique, FK, check) para que la GUI muestre los mismos errores sin BD.
// Los datos se reinician cada vez que se reinicia el servidor.

let seq = 100;
const ahora = () => new Date().toISOString();
const err = (status, message) => Object.assign(new Error(message), { status });

const db = {
  cine: [
    { id: 1, nombre: 'IMAX Los Ángeles', direccion: '6801 Hollywood Blvd', ciudad: 'Los Ángeles', pais: 'Estados Unidos', latitud: 34.1022, longitud: -118.3405, activo: true, creado_en: ahora() },
    { id: 2, nombre: 'IMAX San José', direccion: 'Lincoln Plaza, Moravia', ciudad: 'San José', pais: 'Costa Rica', latitud: 9.9612, longitud: -84.0496, activo: true, creado_en: ahora() }
  ],
  sala: [
    { id: 1, cine_id: 1, nombre: 'Sala 1 IMAX Laser', capacidad: 80, minutos_limpieza: 20, activa: true, creado_en: ahora() },
    { id: 2, cine_id: 2, nombre: 'Sala 2', capacidad: 48, minutos_limpieza: 15, activa: true, creado_en: ahora() }
  ],
  zona_asiento: [
    { id: 1, nombre: 'General', descripcion: 'Butaca estándar' },
    { id: 2, nombre: 'VIP', descripcion: 'Butaca reclinable, zona central' },
    { id: 3, nombre: 'Accesible', descripcion: 'Espacio para silla de ruedas' }
  ],
  asiento: [],
  clasificacion: [
    { id: 1, codigo: 'G', descripcion: 'Todo público', edad_minima: 0 },
    { id: 2, codigo: 'PG-13', descripcion: 'Mayores de 13 años', edad_minima: 13 },
    { id: 3, codigo: 'R', descripcion: 'Mayores de 17 años', edad_minima: 17 }
  ],
  genero: [
    { id: 1, nombre: 'Ciencia ficción' }, { id: 2, nombre: 'Documental' }, { id: 3, nombre: 'Acción' }, { id: 4, nombre: 'Animación' }
  ],
  pelicula: [
    { id: 1, titulo: 'Dune: Parte Tres', sinopsis: 'La saga continúa en Arrakis.', duracion_min: 165, poster_url: null, clasificacion_id: 2, fecha_estreno: '2026-12-18', activa: true, creado_en: ahora() },
    { id: 2, titulo: 'Océano Profundo', sinopsis: 'Documental inmersivo filmado con cámaras IMAX.', duracion_min: 45, poster_url: null, clasificacion_id: 1, fecha_estreno: null, activa: true, creado_en: ahora() }
  ],
  pelicula_genero: [{ pelicula_id: 1, genero_id: 1 }, { pelicula_id: 1, genero_id: 3 }, { pelicula_id: 2, genero_id: 2 }],
  funcion: [],
  tipo_entrada: [
    { id: 1, nombre: 'Adulto', descripcion: 'Tarifa general', requiere_documento: false },
    { id: 2, nombre: 'Niño', descripcion: 'Menores de 12 años', requiere_documento: true },
    { id: 3, nombre: 'Adulto mayor', descripcion: 'Ciudadano de oro (65+)', requiere_documento: true },
    { id: 4, nombre: 'Estudiante', descripcion: 'Con carné vigente', requiere_documento: true }
  ],
  tarifa: [],
  promocion: [
    { id: 1, nombre: '2x1 los miércoles', tipo: '2X1', dia_semana: 3, requiere_cantidad_par: true, tipo_entrada_id: null, fecha_desde: null, fecha_hasta: null, activa: true },
    { id: 2, nombre: '2x1 estudiantes', tipo: '2X1', dia_semana: null, requiere_cantidad_par: true, tipo_entrada_id: 4, fecha_desde: null, fecha_hasta: null, activa: true }
  ]
};

// Tarifas de ejemplo: precio base por tipo × zona (todos los días), más martes de descuento para Adulto/General
[[1, 8.5], [2, 6], [3, 5.5], [4, 6.5]].forEach(([tipo, base]) => [[1, 0], [2, 4], [3, 0]].forEach(([zona, extra]) =>
  db.tarifa.push({ id: ++seq, tipo_entrada_id: tipo, zona_asiento_id: zona, dia_semana: null, hora_desde: '00:00:00', hora_hasta: '23:59:59',
                   precio: base + extra, cargo_servicio: 0.75, activa: true })));
db.tarifa.push({ id: ++seq, tipo_entrada_id: 1, zona_asiento_id: 1, dia_semana: 2, hora_desde: '00:00:00', hora_hasta: '23:59:59', precio: 6, cargo_servicio: 0.75, activa: true });

// Asientos de ejemplo: sala 1 = 8×10 (A-C VIP), sala 2 = 6×8
function generar(salaId, filas, porFila, zonas) {
  let n = 0;
  for (let f = 1; f <= filas; f++) for (let c = 1; c <= porFila; c++) {
    db.asiento.push({ id: ++seq, sala_id: salaId, zona_asiento_id: zonas[f - 1], fila: String.fromCharCode(64 + f), numero: c, activo: true });
    n++;
  }
  return n;
}
generar(1, 8, 10, [2, 2, 2, 1, 1, 1, 1, 3]);
generar(2, 6, 8, [1, 1, 1, 1, 2, 2]);

// Imita trg_funcion_calcular_fin: fin = inicio + duración; fin_limpieza = fin + minutos de limpieza de la sala
function calcularFin(f) {
  const p = db.pelicula.find(x => x.id === Number(f.pelicula_id));
  const s = db.sala.find(x => x.id === Number(f.sala_id));
  if (!p || !s) throw Object.assign(err(400, `Película ${f.pelicula_id} o sala ${f.sala_id} inexistente`), { code: 'P0001' });
  const ini = new Date(f.inicio);
  if (isNaN(ini)) throw Object.assign(err(400, 'Fecha inválida'), { code: '22007' });
  f.inicio = ini.toISOString();
  f.fin = new Date(ini.getTime() + p.duracion_min * 60000).toISOString();
  f.fin_limpieza = new Date(ini.getTime() + (p.duracion_min + s.minutos_limpieza) * 60000).toISOString();
}
// Funciones de ejemplo: mañana y pasado mañana
{
  const d = new Date(); d.setDate(d.getDate() + 1); d.setHours(15, 0, 0, 0);
  [[1, 1, 0], [2, 1, 4], [2, 2, 1], [1, 2, 5], [2, 1, 24 + 2]].forEach(([peli, sala, horas]) => {
    const f = { id: ++seq, pelicula_id: peli, sala_id: sala, inicio: new Date(d.getTime() + horas * 3600000).toISOString(), estado: 'Activa', creado_en: ahora() };
    calcularFin(f);
    db.funcion.push(f);
  });
}
const DIA_OK = d => d == null || (d >= 1 && d <= 7);
const hora = h => (h == null ? h : String(h).length === 5 ? h + ':00' : String(h));

// ---- Restricciones del DDL ----
const RESTRICCIONES = {
  cine: {
    req: ['nombre', 'direccion', 'ciudad'],
    unique: [['nombre', 'ciudad']], uqName: ['uq_cine_nombre_ciudad'],
    check: r => (r.latitud != null && (r.latitud < -90 || r.latitud > 90) && 'ck_cine_latitud') ||
                (r.longitud != null && (r.longitud < -180 || r.longitud > 180) && 'ck_cine_longitud'),
    defaults: { pais: 'Costa Rica', activo: true }
  },
  sala: {
    req: ['cine_id', 'nombre', 'capacidad'], fk: { cine_id: 'cine' },
    unique: [['cine_id', 'nombre']], uqName: ['uq_sala_cine_nombre'],
    check: r => (!(r.capacidad > 0) && 'ck_sala_capacidad') || (!(r.minutos_limpieza >= 0) && 'ck_sala_limpieza'),
    defaults: { minutos_limpieza: 20, activa: true }
  },
  zona_asiento: { req: ['nombre'], unique: [['nombre']], uqName: ['zona_asiento_nombre_key'], defaults: {} },
  clasificacion: {
    req: ['codigo', 'descripcion'], unique: [['codigo']], uqName: ['clasificacion_codigo_key'],
    check: r => !(r.edad_minima >= 0) && 'ck_clasificacion_edad', defaults: { edad_minima: 0 }
  },
  genero: { req: ['nombre'], unique: [['nombre']], uqName: ['genero_nombre_key'], defaults: {} },
  pelicula: {
    req: ['titulo', 'sinopsis', 'duracion_min', 'clasificacion_id'], fk: { clasificacion_id: 'clasificacion' },
    check: r => !(r.duracion_min > 0) && 'ck_pelicula_duracion', defaults: { activa: true }
  },
  asiento: { req: ['zona_asiento_id'], fk: { zona_asiento_id: 'zona_asiento' }, defaults: {} },
  funcion: {
    antes: calcularFin,   // el trigger corre antes de los NOT NULL
    req: ['pelicula_id', 'sala_id', 'inicio', 'fin', 'fin_limpieza', 'estado'], fk: { pelicula_id: 'pelicula', sala_id: 'sala' },
    check: r => !['Activa', 'Cancelada', 'Finalizada'].includes(r.estado) && 'ck_funcion_estado',
    // ex_funcion_sin_traslape: misma sala, rangos [inicio, fin_limpieza) que se cruzan, ignorando canceladas
    excl: (r, id) => r.estado !== 'Cancelada' && db.funcion.some(x => x.id !== id && x.sala_id === r.sala_id && x.estado !== 'Cancelada' &&
            new Date(x.inicio) < new Date(r.fin_limpieza) && new Date(r.inicio) < new Date(x.fin_limpieza)) && 'ex_funcion_sin_traslape',
    defaults: { estado: 'Activa' }
  },
  tipo_entrada: { req: ['nombre'], unique: [['nombre']], uqName: ['tipo_entrada_nombre_key'], defaults: { requiere_documento: false } },
  tarifa: {
    antes: r => { r.hora_desde = hora(r.hora_desde); r.hora_hasta = hora(r.hora_hasta); },
    req: ['tipo_entrada_id', 'zona_asiento_id', 'hora_desde', 'hora_hasta', 'precio', 'cargo_servicio'],
    fk: { tipo_entrada_id: 'tipo_entrada', zona_asiento_id: 'zona_asiento' },
    unique: [['tipo_entrada_id', 'zona_asiento_id', 'dia_semana', 'hora_desde']], uqName: ['uq_tarifa_combinacion'],
    check: r => (!DIA_OK(r.dia_semana) && 'ck_tarifa_dia') || (!(r.hora_hasta > r.hora_desde) && 'ck_tarifa_horas') ||
                (!(r.precio >= 0) && 'ck_tarifa_precio') || (!(r.cargo_servicio >= 0) && 'ck_tarifa_cargo'),
    defaults: { hora_desde: '00:00:00', hora_hasta: '23:59:59', cargo_servicio: 0, activa: true }
  },
  promocion: {
    req: ['nombre', 'tipo', 'requiere_cantidad_par'], fk: { tipo_entrada_id: 'tipo_entrada' }, fkOpcional: true,
    check: r => (r.tipo !== '2X1' && 'ck_promocion_tipo') || (!DIA_OK(r.dia_semana) && 'ck_promocion_dia') ||
                (r.fecha_desde && r.fecha_hasta && r.fecha_hasta < r.fecha_desde && 'ck_promocion_fechas') ||
                (r.dia_semana == null && !r.requiere_cantidad_par && 'ck_promocion_condicion'),
    defaults: { tipo: '2X1', requiere_cantidad_par: true, activa: true }
  }
};

// Qué tablas apuntan a cuál (para simular ON DELETE RESTRICT)
const REFERENCIAS = {
  cine: [['sala', 'cine_id']],
  sala: [['asiento', 'sala_id'], ['funcion', 'sala_id']],
  pelicula: [['funcion', 'pelicula_id']],
  zona_asiento: [['asiento', 'zona_asiento_id'], ['tarifa', 'zona_asiento_id']],
  tipo_entrada: [['tarifa', 'tipo_entrada_id'], ['promocion', 'tipo_entrada_id']],
  clasificacion: [['pelicula', 'clasificacion_id']],
  genero: [['pelicula_genero', 'genero_id']]
};

const NUM = ['latitud', 'longitud', 'capacidad', 'minutos_limpieza', 'edad_minima', 'duracion_min', 'cine_id', 'clasificacion_id', 'zona_asiento_id',
             'pelicula_id', 'sala_id', 'tipo_entrada_id', 'dia_semana', 'precio', 'cargo_servicio'];
function normalizar(data) {
  for (const k of Object.keys(data)) {
    if (data[k] === '') data[k] = null;
    if (NUM.includes(k) && data[k] != null) data[k] = Number(data[k]);
  }
  return data;
}

function validar(tabla, fila, id) {
  const R = RESTRICCIONES[tabla];
  if (R.antes) R.antes(fila);
  for (const c of R.req) if (fila[c] == null || fila[c] === '') throw Object.assign(err(400, `Falta el campo obligatorio: ${c}`), { code: '23502', column: c });
  for (const [c, ref] of Object.entries(R.fk || {})) {
    if (fila[c] == null && R.fkOpcional) continue;
    if (!db[ref].some(x => x.id === Number(fila[c]))) throw Object.assign(err(409, 'Referencia inexistente'), { code: '23503' });
  }
  (R.unique || []).forEach((cols, i) => {
    const dup = db[tabla].some(x => x.id !== id && cols.every(c => String(x[c]).toLowerCase() === String(fila[c]).toLowerCase()));
    if (dup) throw Object.assign(err(409, 'Duplicado'), { code: '23505', constraint: R.uqName[i] });
  });
  const ck = R.check && R.check(fila);
  if (ck) throw Object.assign(err(400, 'Check'), { code: '23514', constraint: ck });
  const ex = R.excl && R.excl(fila, id);
  if (ex) throw Object.assign(err(409, 'Traslape'), { code: '23P01', constraint: ex });
}

function pick(body, cols) {
  const out = {};
  for (const c of cols) if (body[c] !== undefined) out[c] = body[c];
  return normalizar(out);
}

function insertar(tabla, cols, body) {
  const fila = { ...RESTRICCIONES[tabla].defaults, ...pick(body, cols) };
  validar(tabla, fila, null);
  const nueva = { id: ++seq, ...fila };
  if (['cine', 'sala', 'pelicula', 'funcion'].includes(tabla)) nueva.creado_en = ahora();
  db[tabla].push(nueva);
  return nueva;
}

function actualizar(tabla, cols, id, body) {
  const actual = db[tabla].find(x => x.id === Number(id));
  if (!actual) throw err(404, 'Registro no encontrado');
  const fila = { ...actual, ...pick(body, cols) };
  validar(tabla, fila, actual.id);
  Object.assign(actual, fila);
  return actual;
}

function borrar(tabla, id) {
  id = Number(id);
  const i = db[tabla].findIndex(x => x.id === id);
  if (i < 0) throw err(404, 'Registro no encontrado');
  for (const [t, col] of REFERENCIAS[tabla] || []) {
    if (db[t].some(x => x[col] === id)) throw Object.assign(err(409, 'Referenciado'), { code: '23503', detail: `Key is still referenced from table "${t}".` });
  }
  db[tabla].splice(i, 1);
}

const RECURSOS = {
  cines: { tabla: 'cine', cols: ['nombre', 'direccion', 'ciudad', 'pais', 'latitud', 'longitud', 'activo'] },
  salas: { tabla: 'sala', cols: ['cine_id', 'nombre', 'capacidad', 'minutos_limpieza', 'activa'] },
  zonas: { tabla: 'zona_asiento', cols: ['nombre', 'descripcion'] },
  clasificaciones: { tabla: 'clasificacion', cols: ['codigo', 'descripcion', 'edad_minima'] },
  generos: { tabla: 'genero', cols: ['nombre'] },
  funciones: { tabla: 'funcion', cols: ['pelicula_id', 'sala_id', 'inicio', 'estado'] },
  tipos: { tabla: 'tipo_entrada', cols: ['nombre', 'descripcion', 'requiere_documento'] },
  tarifas: { tabla: 'tarifa', cols: ['tipo_entrada_id', 'zona_asiento_id', 'dia_semana', 'hora_desde', 'hora_hasta', 'precio', 'cargo_servicio', 'activa'] },
  promociones: { tabla: 'promocion', cols: ['nombre', 'tipo', 'dia_semana', 'requiere_cantidad_par', 'tipo_entrada_id', 'fecha_desde', 'fecha_hasta', 'activa'] }
};
const PELICULA_COLS = ['titulo', 'sinopsis', 'duracion_min', 'poster_url', 'clasificacion_id', 'fecha_estreno', 'activa'];

const VISTAS = {
  cines: () => db.cine.map(c => ({ ...c, salas: db.sala.filter(s => s.cine_id === c.id).length }))
    .sort((a, b) => (a.pais + a.ciudad + a.nombre).localeCompare(b.pais + b.ciudad + b.nombre)),
  salas: () => db.sala.map(s => {
    const c = db.cine.find(x => x.id === s.cine_id) || {};
    const as = db.asiento.filter(a => a.sala_id === s.id);
    return { ...s, cine: c.nombre, ciudad: c.ciudad, asientos_activos: as.filter(a => a.activo).length, asientos_total: as.length };
  }).sort((a, b) => (a.cine + a.nombre).localeCompare(b.cine + b.nombre)),
  zonas: () => db.zona_asiento.map(z => ({ ...z, asientos: db.asiento.filter(a => a.zona_asiento_id === z.id).length }))
    .sort((a, b) => a.nombre.localeCompare(b.nombre)),
  clasificaciones: () => [...db.clasificacion].sort((a, b) => a.edad_minima - b.edad_minima || a.codigo.localeCompare(b.codigo)),
  generos: () => db.genero.map(g => ({ ...g, peliculas: db.pelicula_genero.filter(x => x.genero_id === g.id).length }))
    .sort((a, b) => a.nombre.localeCompare(b.nombre)),
  funciones: () => db.funcion.map(f => {
    const p = db.pelicula.find(x => x.id === f.pelicula_id) || {};
    const s = db.sala.find(x => x.id === f.sala_id) || {};
    const c = db.cine.find(x => x.id === s.cine_id) || {};
    return { ...f, titulo: p.titulo, duracion_min: p.duracion_min, sala: s.nombre, minutos_limpieza: s.minutos_limpieza, cine: c.nombre, ciudad: c.ciudad };
  }).sort((a, b) => b.inicio.localeCompare(a.inicio)),
  tipos: () => db.tipo_entrada.map(t => ({ ...t, tarifas: db.tarifa.filter(x => x.tipo_entrada_id === t.id).length }))
    .sort((a, b) => a.nombre.localeCompare(b.nombre)),
  tarifas: () => db.tarifa.map(t => ({ ...t, tipo_entrada: (db.tipo_entrada.find(x => x.id === t.tipo_entrada_id) || {}).nombre,
                                       zona: (db.zona_asiento.find(x => x.id === t.zona_asiento_id) || {}).nombre }))
    .sort((a, b) => (a.tipo_entrada + a.zona).localeCompare(b.tipo_entrada + b.zona) || (a.dia_semana || 0) - (b.dia_semana || 0) || a.hora_desde.localeCompare(b.hora_desde)),
  promociones: () => db.promocion.map(p => ({ ...p, tipo_entrada: p.tipo_entrada_id ? (db.tipo_entrada.find(x => x.id === p.tipo_entrada_id) || {}).nombre : null }))
    .sort((a, b) => (b.activa - a.activa) || a.nombre.localeCompare(b.nombre))
};

function setGeneros(peliculaId, generos) {
  if (!Array.isArray(generos)) return;
  const ids = [...new Set(generos.map(Number))];
  if (ids.some(g => !db.genero.some(x => x.id === g))) throw Object.assign(err(409, 'Género inexistente'), { code: '23503' });
  db.pelicula_genero = db.pelicula_genero.filter(x => x.pelicula_id !== peliculaId);
  ids.forEach(g => db.pelicula_genero.push({ pelicula_id: peliculaId, genero_id: g }));
}

module.exports = {
  RECURSOS,
  async listar(nombre) { return VISTAS[nombre](); },
  async crear(nombre, body) { const r = RECURSOS[nombre]; return insertar(r.tabla, r.cols, body); },
  async editar(nombre, id, body) { const r = RECURSOS[nombre]; return actualizar(r.tabla, r.cols, id, body); },
  async borrar(nombre, id) { borrar(RECURSOS[nombre].tabla, id); },

  async listarPeliculas() {
    return db.pelicula.map(p => {
      const gs = db.pelicula_genero.filter(x => x.pelicula_id === p.id).map(x => db.genero.find(g => g.id === x.genero_id))
        .filter(Boolean).sort((a, b) => a.nombre.localeCompare(b.nombre));
      return { ...p, clasificacion: (db.clasificacion.find(c => c.id === p.clasificacion_id) || {}).codigo,
               generos_ids: gs.map(g => g.id), generos: gs.map(g => g.nombre).join(', ') };
    }).sort((a, b) => (b.activa - a.activa) || a.titulo.localeCompare(b.titulo));
  },
  async crearPelicula(body) {
    if (Array.isArray(body.generos) && body.generos.some(g => !db.genero.some(x => x.id === Number(g)))) throw Object.assign(err(409, 'x'), { code: '23503' });
    const p = insertar('pelicula', PELICULA_COLS, body);
    setGeneros(p.id, body.generos);
    return p;
  },
  async editarPelicula(id, body) {
    const p = actualizar('pelicula', PELICULA_COLS, id, body);
    setGeneros(p.id, body.generos);
    return p;
  },
  async borrarPelicula(id) {
    borrar('pelicula', id);
    db.pelicula_genero = db.pelicula_genero.filter(x => x.pelicula_id !== Number(id));   // ON DELETE CASCADE
  },

  async asientos(salaId) {
    return db.asiento.filter(a => a.sala_id === Number(salaId))
      .map(a => ({ id: a.id, fila: a.fila, numero: a.numero, activo: a.activo, zona_asiento_id: a.zona_asiento_id,
                   zona: (db.zona_asiento.find(z => z.id === a.zona_asiento_id) || {}).nombre }))
      .sort((a, b) => a.fila.length - b.fila.length || a.fila.localeCompare(b.fila) || a.numero - b.numero);
  },
  async generarAsientos(salaId, { filas, por_fila, zonas, reemplazar }) {
    salaId = Number(salaId);
    if (!db.sala.some(s => s.id === salaId)) throw err(404, 'Registro no encontrado');
    if (zonas.some(z => !db.zona_asiento.some(x => x.id === Number(z)))) throw Object.assign(err(409, 'x'), { code: '23503' });
    if (reemplazar) db.asiento = db.asiento.filter(a => a.sala_id !== salaId);
    else if (db.asiento.some(a => a.sala_id === salaId)) throw Object.assign(err(409, 'x'), { code: '23505', constraint: 'uq_asiento_sala_fila_numero' });
    return { insertados: generar(salaId, filas, por_fila, zonas.map(Number)) };
  },
  async editarAsiento(id, body) { return actualizar('asiento', ['zona_asiento_id', 'activo'], id, body); },
  async editarAsientos(ids, body) {
    const set = new Set(ids.map(Number));
    const data = pick(body, ['zona_asiento_id', 'activo']);
    if (data.zona_asiento_id != null && !db.zona_asiento.some(z => z.id === data.zona_asiento_id)) throw Object.assign(err(409, 'x'), { code: '23503' });
    let n = 0;
    db.asiento.forEach(a => { if (set.has(a.id)) { Object.assign(a, data); n++; } });
    return { actualizados: n };
  }
};
