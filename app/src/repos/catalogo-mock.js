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
  pelicula_genero: [{ pelicula_id: 1, genero_id: 1 }, { pelicula_id: 1, genero_id: 3 }, { pelicula_id: 2, genero_id: 2 }]
};

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
  asiento: { req: ['zona_asiento_id'], fk: { zona_asiento_id: 'zona_asiento' }, defaults: {} }
};

// Qué tablas apuntan a cuál (para simular ON DELETE RESTRICT)
const REFERENCIAS = {
  cine: [['sala', 'cine_id']],
  sala: [['asiento', 'sala_id']],
  zona_asiento: [['asiento', 'zona_asiento_id']],
  clasificacion: [['pelicula', 'clasificacion_id']],
  genero: [['pelicula_genero', 'genero_id']]
};

const NUM = ['latitud', 'longitud', 'capacidad', 'minutos_limpieza', 'edad_minima', 'duracion_min', 'cine_id', 'clasificacion_id', 'zona_asiento_id'];
function normalizar(data) {
  for (const k of Object.keys(data)) {
    if (data[k] === '') data[k] = null;
    if (NUM.includes(k) && data[k] != null) data[k] = Number(data[k]);
  }
  return data;
}

function validar(tabla, fila, id) {
  const R = RESTRICCIONES[tabla];
  for (const c of R.req) if (fila[c] == null || fila[c] === '') throw Object.assign(err(400, `Falta el campo obligatorio: ${c}`), { code: '23502', column: c });
  for (const [c, ref] of Object.entries(R.fk || {})) {
    if (!db[ref].some(x => x.id === Number(fila[c]))) throw Object.assign(err(409, 'Referencia inexistente'), { code: '23503' });
  }
  (R.unique || []).forEach((cols, i) => {
    const dup = db[tabla].some(x => x.id !== id && cols.every(c => String(x[c]).toLowerCase() === String(fila[c]).toLowerCase()));
    if (dup) throw Object.assign(err(409, 'Duplicado'), { code: '23505', constraint: R.uqName[i] });
  });
  const ck = R.check && R.check(fila);
  if (ck) throw Object.assign(err(400, 'Check'), { code: '23514', constraint: ck });
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
  if (['cine', 'sala', 'pelicula'].includes(tabla)) nueva.creado_en = ahora();
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
  generos: { tabla: 'genero', cols: ['nombre'] }
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
    .sort((a, b) => a.nombre.localeCompare(b.nombre))
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
