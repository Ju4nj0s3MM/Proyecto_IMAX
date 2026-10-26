// MÓDULO A · Mati — Panel de administración del catálogo.
// CRUD de cines, salas, zonas, clasificaciones, géneros y películas + editor del mapa de asientos.
// Toda validación de datos la hace la BD (constraints del DDL); aquí solo se muestran sus mensajes.

const esc = v => String(v ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const $ = id => document.getElementById(id);
const msg = $('msg');
const ok = t => { mostrarMensaje(msg, t, 'ok'); clearTimeout(ok.t); ok.t = setTimeout(() => (msg.hidden = true), 4000); };
const fallo = e => mostrarMensaje(msg, e.message || e, 'err');
const estado = (v, fem) => v ? `<span class="pill si">Activ${fem ? 'a' : 'o'}</span>` : `<span class="pill no">Inactiv${fem ? 'a' : 'o'}</span>`;

// Datos cargados de la API
const D = { peliculas: [], cines: [], salas: [], puertas: [], zonas: [], clasificaciones: [], generos: [],
            funciones: [], tipos: [], tarifas: [], promociones: [] };

// Días según ISO (1 = lunes … 7 = domingo), igual que extract(isodow from ...) en PostgreSQL
const DIAS = ['', 'Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'];
const OPC_DIAS = DIAS.slice(1).map((d, i) => ({ v: i + 1, t: d }));
const dinero = v => v == null ? '—' : '$' + Number(v).toFixed(2);
const horaCorta = h => String(h ?? '').slice(0, 5);
const fmtHora = iso => new Date(iso).toLocaleTimeString('es-CR', { hour: '2-digit', minute: '2-digit' });
// ISO → valor de <input type="datetime-local"> en hora local
const aLocal = iso => { const d = new Date(iso); return isNaN(d) ? '' : new Date(d - d.getTimezoneOffset() * 60000).toISOString().slice(0, 16); };
const ESTADO_FUNCION = { Activa: 'si', Cancelada: 'cancelada', Finalizada: 'no' };
const editandoReg = () => (editando ? D[tab].find(x => x.id === editando) : null);
const opciones = (lista, txt) => lista.map(x => ({ v: x.id, t: txt(x) }));

// ---------- Definición de cada pestaña CRUD ----------
// Campo: { k: columna, l: etiqueta, type, req, def, opts(), ancho }
const SECCIONES = {
  peliculas: {
    singular: 'película', plural: 'Películas',
    campos: [
      { k: 'titulo', l: 'Título', req: true, max: 200, ancho: 2 },
      { k: 'duracion_min', l: 'Duración (min)', type: 'number', min: 1, req: true },
      { k: 'clasificacion_id', l: 'Clasificación', type: 'select', req: true, opts: () => opciones(D.clasificaciones, c => `${c.codigo} — ${c.descripcion}`) },
      { k: 'fecha_estreno', l: 'Fecha de estreno', type: 'date' },
      { k: 'poster_url', l: 'URL del póster', type: 'url', max: 250, ancho: 2 },
      { k: 'activa', l: 'Activa en cartelera', type: 'checkbox', def: true },
      { k: 'sinopsis', l: 'Sinopsis', type: 'textarea', req: true, ancho: 4 },
      { k: 'generos', l: 'Géneros', type: 'checks', ancho: 4, opts: () => opciones(D.generos, g => g.nombre) }
    ],
    columnas: [
      { t: '', v: p => p.poster_url ? `<img class="poster" src="${esc(p.poster_url)}" alt="" loading="lazy" onerror="this.replaceWith(document.createTextNode('🎞️'))">` : '<span class="poster vacio">🎞️</span>' },
      { t: 'Título', v: p => `<strong>${esc(p.titulo)}</strong><div class="muted corto">${esc(p.sinopsis)}</div>` },
      { t: 'Clasif.', v: p => esc(p.clasificacion) },
      { t: 'Géneros', v: p => esc(p.generos) || '<span class="muted">—</span>' },
      { t: 'Duración', v: p => `${p.duracion_min} min` },
      { t: 'Estreno', v: p => p.fecha_estreno ? '<span class="nowrap">' + esc(String(p.fecha_estreno).slice(0, 10)) + '</span>' : '<span class="muted">—</span>' },
      { t: 'Estado', v: p => estado(p.activa, true) }
    ],
    // generos_ids (de la lista) → generos (lo que espera la API)
    aFormulario: p => ({ ...p, generos: p.generos_ids || [] })
  },
  cines: {
    singular: 'cine', plural: 'Cines',
    campos: [
      { k: 'nombre', l: 'Nombre', req: true, max: 100, ancho: 2 },
      { k: 'ciudad', l: 'Ciudad', req: true, max: 100 },
      { k: 'pais', l: 'País', max: 50, def: 'Costa Rica' },
      { k: 'direccion', l: 'Dirección', req: true, max: 250, ancho: 2 },
      { k: 'latitud', l: 'Latitud', type: 'number', step: 'any', min: -90, max: 90 },
      { k: 'longitud', l: 'Longitud', type: 'number', step: 'any', min: -180, max: 180 },
      { k: 'activo', l: 'Activo', type: 'checkbox', def: true }
    ],
    columnas: [
      { t: 'Nombre', v: c => `<strong>${esc(c.nombre)}</strong><div class="muted">${esc(c.direccion)}</div>` },
      { t: 'Ciudad', v: c => esc(c.ciudad) },
      { t: 'País', v: c => esc(c.pais) },
      { t: 'Coordenadas', v: c => c.latitud != null && c.longitud != null
          ? `<a href="https://www.openstreetmap.org/?mlat=${c.latitud}&mlon=${c.longitud}#map=16/${c.latitud}/${c.longitud}" target="_blank" rel="noopener">${Number(c.latitud).toFixed(4)}, ${Number(c.longitud).toFixed(4)}</a>`
          : '<span class="muted">—</span>' },
      { t: 'Salas', v: c => c.salas ?? 0 },
      { t: 'Estado', v: c => estado(c.activo) }
    ]
  },
  salas: {
    singular: 'sala', plural: 'Salas',
    campos: [
      { k: 'cine_id', l: 'Cine', type: 'select', req: true, ancho: 2, opts: () => opciones(D.cines, c => `${c.nombre} (${c.ciudad})`) },
      { k: 'nombre', l: 'Nombre de la sala', req: true, max: 60 },
      { k: 'capacidad', l: 'Capacidad', type: 'number', min: 1, req: true },
      { k: 'minutos_limpieza', l: 'Minutos de limpieza', type: 'number', min: 0, def: 20 },
      { k: 'activa', l: 'Activa', type: 'checkbox', def: true }
    ],
    columnas: [
      { t: 'Cine', v: s => `${esc(s.cine)}<div class="muted">${esc(s.ciudad)}</div>` },
      { t: 'Sala', v: s => `<strong>${esc(s.nombre)}</strong>` },
      { t: 'Capacidad', v: s => s.capacidad },
      { t: 'Asientos activos', v: s => s.asientos_activos === s.capacidad
          ? `${s.asientos_activos}`
          : `<span class="aviso" title="No coincide con la capacidad declarada">${s.asientos_activos ?? 0} ⚠</span>` },
      { t: 'Puertas', v: s => s.puertas ? `${s.puertas}` : '<span class="aviso" title="Sin puertas no se puede hacer check-in">0 ⚠</span>' },
      { t: 'Limpieza', v: s => `${s.minutos_limpieza} min` },
      { t: 'Estado', v: s => estado(s.activa, true) }
    ],
    extra: s => `<button class="secondary chico" data-asientos="${s.id}">Asientos</button>`
  },
  puertas: {
    singular: 'puerta', plural: 'Puertas de check-in',
    campos: [
      { k: 'sala_id', l: 'Sala', type: 'select', req: true, ancho: 2, opts: () => opciones(D.salas, s => `${s.cine} · ${s.nombre}`) },
      { k: 'nombre', l: 'Nombre', req: true, max: 60, def: 'Tótem 1' },
      { k: 'activa', l: 'Activa', type: 'checkbox', def: true }
    ],
    columnas: [
      { t: 'Cine · Sala', v: p => `${esc(p.cine)}<div class="muted">${esc(p.sala)}</div>` },
      { t: 'Puerta', v: p => `<strong>${esc(p.nombre)}</strong>` },
      { t: 'Estado', v: p => estado(p.activa, true) }
    ]
  },
  zonas: {
    singular: 'zona', plural: 'Zonas de asiento',
    campos: [
      { k: 'nombre', l: 'Nombre', req: true, max: 40 },
      { k: 'descripcion', l: 'Descripción', max: 200, ancho: 3 }
    ],
    columnas: [
      { t: '', v: z => `<i class="punto" style="background:${colorZona(z.id)}"></i>` },
      { t: 'Nombre', v: z => `<strong>${esc(z.nombre)}</strong>` },
      { t: 'Descripción', v: z => esc(z.descripcion) || '<span class="muted">—</span>' },
      { t: 'Asientos', v: z => z.asientos ?? 0 }
    ]
  },
  clasificaciones: {
    singular: 'clasificación', plural: 'Clasificaciones de edad',
    campos: [
      { k: 'codigo', l: 'Código', req: true, max: 10 },
      { k: 'edad_minima', l: 'Edad mínima', type: 'number', min: 0, def: 0 },
      { k: 'descripcion', l: 'Descripción', req: true, max: 200, ancho: 2 }
    ],
    columnas: [
      { t: 'Código', v: c => `<strong>${esc(c.codigo)}</strong>` },
      { t: 'Descripción', v: c => esc(c.descripcion) },
      { t: 'Edad mínima', v: c => `${c.edad_minima}+` }
    ]
  },
  funciones: {
    singular: 'función', plural: 'Funciones',
    campos: [
      { k: 'pelicula_id', l: 'Película', type: 'select', req: true, ancho: 2,
        opts: () => opciones(D.peliculas.filter(p => p.activa || p.id === editandoReg()?.pelicula_id), p => `${p.titulo} (${p.duracion_min} min)`) },
      { k: 'sala_id', l: 'Sala', type: 'select', req: true, ancho: 2,
        opts: () => opciones(D.salas.filter(s => s.activa || s.id === editandoReg()?.sala_id), s => `${s.cine} · ${s.nombre} (limpieza ${s.minutos_limpieza} min)`) },
      { k: 'inicio', l: 'Inicio', type: 'datetime', req: true, ancho: 2 },
      { k: 'estado', l: 'Estado', type: 'select', texto: true, req: true, def: 'Activa', vacio: false,
        opts: () => Object.keys(ESTADO_FUNCION).map(e => ({ v: e, t: e })) },
      { k: '_calculo', type: 'info', ancho: 4 }
    ],
    columnas: [
      { t: 'Película', v: f => `<strong>${esc(f.titulo)}</strong><div class="muted">${f.duracion_min} min</div>` },
      { t: 'Cine · Sala', v: f => `${esc(f.cine)}<div class="muted">${esc(f.sala)}</div>` },
      { t: 'Inicio', v: f => `<span class="nowrap">${esc(fmtFecha(f.inicio))}</span>` },
      { t: 'Fin', v: f => `<span class="nowrap">${esc(fmtHora(f.fin))}</span>` },
      { t: 'Sala libre', v: f => `<span class="nowrap muted" title="Fin + ${f.minutos_limpieza} min de limpieza">${esc(fmtHora(f.fin_limpieza))}</span>` },
      { t: 'Estado', v: f => `<span class="pill ${ESTADO_FUNCION[f.estado] || 'no'}">${esc(f.estado)}</span>` }
    ],
    extra: f => f.estado === 'Activa' ? `<button class="secondary chico" data-cancelar="${f.id}">Cancelar función</button>` : '',
    panel: () => pintarAgenda(),
    alCambiar: calculoFuncion
  },
  tipos: {
    singular: 'tipo de entrada', plural: 'Tipos de entrada', nuevo: 'Nuevo tipo de entrada',
    campos: [
      { k: 'nombre', l: 'Nombre', req: true, max: 50 },
      { k: 'descripcion', l: 'Descripción', max: 200, ancho: 2 },
      { k: 'requiere_documento', l: 'Requiere documento en puerta (RN-06)', type: 'checkbox', def: false }
    ],
    columnas: [
      { t: 'Nombre', v: t => `<strong>${esc(t.nombre)}</strong>` },
      { t: 'Descripción', v: t => esc(t.descripcion) || '<span class="muted">—</span>' },
      { t: 'Documento', v: t => t.requiere_documento ? '<span class="pill alerta">Se valida en puerta</span>' : '<span class="muted">No</span>' },
      { t: 'Tarifas', v: t => t.tarifas ?? 0 }
    ]
  },
  tarifas: {
    singular: 'tarifa', plural: 'Tarifas',
    campos: [
      { k: 'tipo_entrada_id', l: 'Tipo de entrada', type: 'select', req: true, opts: () => opciones(D.tipos, t => t.nombre) },
      { k: 'zona_asiento_id', l: 'Zona', type: 'select', req: true, opts: () => opciones(D.zonas, z => z.nombre) },
      { k: 'dia_semana', l: 'Día', type: 'select', vacio: 'Todos los días', opts: () => OPC_DIAS },
      { k: 'activa', l: 'Activa', type: 'checkbox', def: true },
      { k: 'hora_desde', l: 'Desde', type: 'time', req: true, def: '00:00:00' },
      { k: 'hora_hasta', l: 'Hasta', type: 'time', req: true, def: '23:59:59' },
      { k: 'precio', l: 'Precio', type: 'number', step: '0.01', min: 0, req: true },
      { k: 'cargo_servicio', l: 'Cargo por servicio', type: 'number', step: '0.01', min: 0, def: 0 }
    ],
    columnas: [
      { t: 'Tipo', v: t => `<strong>${esc(t.tipo_entrada)}</strong>` },
      { t: 'Zona', v: t => `<i class="punto" style="background:${colorZona(t.zona_asiento_id)}"></i> ${esc(t.zona)}` },
      { t: 'Día', v: t => t.dia_semana ? DIAS[t.dia_semana] : '<span class="muted">Todos</span>' },
      { t: 'Horario', v: t => `<span class="nowrap">${horaCorta(t.hora_desde)} – ${horaCorta(t.hora_hasta)}</span>` },
      { t: 'Precio', v: t => `<strong>${dinero(t.precio)}</strong>` },
      { t: 'Cargo', v: t => dinero(t.cargo_servicio) },
      { t: 'Estado', v: t => estado(t.activa, true) }
    ],
    panel: () => pintarMatriz()
  },
  promociones: {
    singular: 'promoción', plural: 'Promociones',
    campos: [
      { k: 'nombre', l: 'Nombre', req: true, max: 100, ancho: 2 },
      { k: 'tipo', l: 'Tipo', type: 'select', texto: true, req: true, def: '2X1', vacio: false, opts: () => [{ v: '2X1', t: '2x1' }] },
      { k: 'activa', l: 'Activa', type: 'checkbox', def: true },
      { k: 'dia_semana', l: 'Día de la semana', type: 'select', vacio: 'Cualquier día', opts: () => OPC_DIAS },
      { k: 'tipo_entrada_id', l: 'Aplica a', type: 'select', vacio: 'Todos los tipos de entrada', opts: () => opciones(D.tipos, t => t.nombre) },
      { k: 'requiere_cantidad_par', l: 'Exige cantidad par de entradas', type: 'checkbox', def: true, ancho: 2 },
      { k: 'fecha_desde', l: 'Vigente desde', type: 'date' },
      { k: 'fecha_hasta', l: 'Vigente hasta', type: 'date' },
      { k: '_ayuda', type: 'info', ancho: 2, texto: 'Debe tener al menos una condición: un día de la semana o exigir cantidad par (RN-07).' }
    ],
    columnas: [
      { t: 'Nombre', v: p => `<strong>${esc(p.nombre)}</strong>` },
      { t: 'Tipo', v: p => esc(p.tipo) },
      { t: 'Condición', v: p => [p.dia_semana ? 'Solo ' + DIAS[p.dia_semana].toLowerCase() : '', p.requiere_cantidad_par ? 'cantidad par' : '']
          .filter(Boolean).join(' · ') },
      { t: 'Aplica a', v: p => esc(p.tipo_entrada) || '<span class="muted">Todos</span>' },
      { t: 'Vigencia', v: p => !p.fecha_desde && !p.fecha_hasta ? '<span class="muted">Sin límite</span>'
          : `<span class="nowrap">${esc(String(p.fecha_desde ?? '…').slice(0, 10))} → ${esc(String(p.fecha_hasta ?? '…').slice(0, 10))}</span>` },
      { t: 'Estado', v: p => estado(p.activa, true) }
    ]
  },
  generos: {
    singular: 'género', plural: 'Géneros',
    campos: [{ k: 'nombre', l: 'Nombre', req: true, max: 50, ancho: 2 }],
    columnas: [
      { t: 'Nombre', v: g => `<strong>${esc(g.nombre)}</strong>` },
      { t: 'Películas', v: g => g.peliculas ?? 0 }
    ]
  }
};

// ---------- Carga ----------
async function cargar(...nombres) {
  const lista = nombres.length ? nombres : Object.keys(D);
  const res = await Promise.all(lista.map(n => api('/catalogo/admin/' + n)));
  lista.forEach((n, i) => (D[n] = res[i]));
}

// ---------- Pestañas ----------
let tab = null;
let editando = null;   // id del registro en edición

function irA(nombre) {
  tab = nombre;
  document.querySelectorAll('.tabs button').forEach(b => b.setAttribute('aria-selected', b.dataset.tab === nombre));
  $('crud').hidden = nombre === 'asientos';
  $('asientos').hidden = nombre !== 'asientos';
  msg.hidden = true;
  if (location.hash.slice(1).split('?')[0] !== nombre) history.replaceState(null, '', '#' + nombre);
  if (nombre === 'asientos') return pintarEditorAsientos();
  $('filtro').value = '';
  cancelarEdicion();
  pintarTabla();
}

// ---------- Formulario genérico ----------
function campoHTML(c) {
  const id = 'f-' + c.k;
  const req = c.req ? ' required' : '';
  const span = c.ancho ? ` style="grid-column: span ${c.ancho}"` : '';
  const et = `<span>${esc(c.l)}${c.req ? ' <b class="req">*</b>' : ''}</span>`;
  if (c.type === 'checkbox') return `<label class="check"${span}><input id="${id}" type="checkbox"> ${esc(c.l)}</label>`;
  if (c.type === 'textarea') return `<label${span}>${et}<textarea id="${id}" rows="3"${req}></textarea></label>`;
  if (c.type === 'select') {
    const ops = c.opts();
    const vacio = c.vacio === false ? '' : `<option value="">${esc(c.vacio || '— Seleccionar —')}</option>`;
    return `<label${span}>${et}<select id="${id}"${c.vacio ? '' : req}>${vacio}` +
      ops.map(o => `<option value="${o.v}">${esc(o.t)}</option>`).join('') + '</select>' +
      (ops.length ? '' : `<small class="aviso">Primero crea registros en la pestaña correspondiente.</small>`) + '</label>';
  }
  if (c.type === 'info') return `<div id="${id}" class="info muted"${span}>${esc(c.texto || '')}</div>`;
  if (c.type === 'datetime') return `<label${span}>${et}<input id="${id}" type="datetime-local"${req}></label>`;
  if (c.type === 'time') return `<label${span}>${et}<input id="${id}" type="time" step="1"${req}></label>`;
  if (c.type === 'checks') {
    const ops = c.opts();
    return `<fieldset class="checks"${span}><legend>${esc(c.l)}</legend>` +
      (ops.length ? ops.map(o => `<label class="check"><input type="checkbox" name="${c.k}" value="${o.v}"> ${esc(o.t)}</label>`).join('')
                  : '<span class="muted">No hay géneros. Créalos en la pestaña Géneros.</span>') + '</fieldset>';
  }
  const attrs = [c.type === 'number' && c.step ? `step="${c.step}"` : '', c.min != null ? `min="${c.min}"` : '',
                 c.max != null ? (c.type === 'number' ? `max="${c.max}"` : `maxlength="${c.max}"`) : ''].join(' ');
  const input = `<input id="${id}" type="${c.type || 'text'}" ${attrs}${req}>`;
  if (c.k === 'poster_url') return `<label${span}>${et}<div class="con-preview">${input}<img id="preview-poster" alt="" hidden></div></label>`;
  return `<label${span}>${et}${input}</label>`;
}

function pintarFormulario() {
  const S = SECCIONES[tab];
  $('form').innerHTML = S.campos.map(campoHTML).join('');
  const url = $('f-poster_url');
  if (url) url.oninput = () => {
    const img = $('preview-poster');
    img.hidden = !url.value;
    img.src = url.value;
    img.onerror = () => (img.hidden = true);
  };
  $('form').oninput = $('form').onchange = () => S.alCambiar && S.alCambiar();
}

function llenarFormulario(reg) {
  for (const c of SECCIONES[tab].campos) {
    const v = reg ? reg[c.k] : c.def;
    if (c.type === 'checks') {
      const set = new Set((v || []).map(Number));
      document.querySelectorAll(`#form input[name="${c.k}"]`).forEach(i => (i.checked = set.has(Number(i.value))));
      continue;
    }
    const el = $('f-' + c.k);
    if (c.type === 'checkbox') el.checked = v ?? false;
    else if (c.type === 'info') continue;
    else if (c.type === 'date') el.value = v ? String(v).slice(0, 10) : '';
    else if (c.type === 'datetime') el.value = v ? aLocal(v) : '';
    else el.value = v ?? '';
  }
  const url = $('f-poster_url'); if (url) url.oninput();
  const S = SECCIONES[tab]; if (S.alCambiar) S.alCambiar();
}

function leerFormulario() {
  const out = {};
  for (const c of SECCIONES[tab].campos) {
    if (c.type === 'checks') { out[c.k] = [...document.querySelectorAll(`#form input[name="${c.k}"]:checked`)].map(i => Number(i.value)); continue; }
    const el = $('f-' + c.k);
    if (c.type === 'checkbox') out[c.k] = el.checked;
    else if (c.type === 'info') continue;
    else if (c.type === 'datetime') out[c.k] = el.value ? new Date(el.value).toISOString() : null;
    else if (c.type === 'select' && c.texto) out[c.k] = el.value || null;
    else if (c.type === 'number' || c.type === 'select') out[c.k] = el.value === '' ? null : Number(el.value);
    else out[c.k] = el.value.trim() === '' ? null : el.value.trim();
  }
  return out;
}

function cancelarEdicion() {
  editando = null;
  const S = SECCIONES[tab];
  pintarFormulario();
  llenarFormulario(null);
  $('form-titulo').textContent = S.nuevo || (/^(cine|género)$/.test(S.singular) ? 'Nuevo ' : 'Nueva ') + S.singular;
  $('guardar').textContent = 'Crear';
  $('cancelar').hidden = true;
  document.querySelectorAll('#tabla tr.editando').forEach(tr => tr.classList.remove('editando'));
}

function editar(id) {
  const S = SECCIONES[tab];
  const reg = D[tab].find(x => x.id === id);
  if (!reg) return;
  editando = id;
  pintarFormulario();
  llenarFormulario(S.aFormulario ? S.aFormulario(reg) : reg);
  $('form-titulo').textContent = `Editar ${S.singular} #${id}`;
  $('guardar').textContent = 'Guardar cambios';
  $('cancelar').hidden = false;
  document.querySelectorAll('#tabla tr').forEach(tr => tr.classList.toggle('editando', Number(tr.dataset.id) === id));
  $('form').scrollIntoView({ behavior: 'smooth', block: 'center' });
}

$('form').onsubmit = async ev => {
  ev.preventDefault();
  const S = SECCIONES[tab];
  const body = leerFormulario();
  const btn = $('guardar'); btn.disabled = true;
  try {
    if (editando) {
      await api(`/catalogo/admin/${tab}/${editando}`, { method: 'PUT', body });
      ok('Cambios guardados.');
    } else {
      await api(`/catalogo/admin/${tab}`, { method: 'POST', body });
      ok('Registro creado.');
    }
    await cargar();
    cancelarEdicion();
    pintarTabla();
  } catch (e) { fallo(e); }
  finally { btn.disabled = false; }
};
$('cancelar').onclick = cancelarEdicion;

// ---------- Tabla genérica ----------
function pintarTabla() {
  const S = SECCIONES[tab];
  const f = $('filtro').value.trim().toLowerCase();
  const filas = D[tab].filter(r => !f || JSON.stringify(r).toLowerCase().includes(f));
  $('tabla-titulo').textContent = `${S.plural} (${filas.length})`;
  $('tabla').innerHTML =
    `<thead><tr><th class="id">#</th>${S.columnas.map(c => `<th>${c.t}</th>`).join('')}<th></th></tr></thead><tbody>` +
    (filas.length ? filas.map(r => `<tr data-id="${r.id}"${r.id === editando ? ' class="editando"' : ''}>
        <td class="id muted">${r.id}</td>${S.columnas.map(c => `<td>${c.v(r)}</td>`).join('')}
        <td class="acciones-fila">${S.extra ? S.extra(r) : ''}
          <button class="secondary chico" data-editar="${r.id}">Editar</button>
          <button class="danger chico" data-borrar="${r.id}">Eliminar</button></td></tr>`).join('')
      : `<tr><td colspan="${S.columnas.length + 2}" class="muted vacio-tabla">${f ? 'Sin coincidencias.' : 'Todavía no hay registros. Crea el primero arriba.'}</td></tr>`) +
    '</tbody>';
  $('panel-extra').hidden = !S.panel;
  if (S.panel) S.panel();
}

// ---------- Funciones: cálculo en vivo y agenda por sala ----------
// Solo es una vista previa: el fin real lo calcula el trigger y el traslape lo impide ex_funcion_sin_traslape.
function calculoFuncion() {
  const info = $('f-_calculo'); if (!info) return;
  const p = D.peliculas.find(x => x.id === Number($('f-pelicula_id').value));
  const s = D.salas.find(x => x.id === Number($('f-sala_id').value));
  const v = $('f-inicio').value;
  if (!p || !s || !v) { info.textContent = 'Elige película, sala e inicio para ver a qué hora termina la función y queda libre la sala.'; info.className = 'info muted'; return; }
  const ini = new Date(v);
  const fin = new Date(ini.getTime() + p.duracion_min * 60000);
  const libre = new Date(fin.getTime() + s.minutos_limpieza * 60000);
  const choque = $('f-estado').value !== 'Cancelada' && D.funciones.find(f => f.id !== editando && f.sala_id === s.id && f.estado !== 'Cancelada' &&
    new Date(f.inicio) < libre && ini < new Date(f.fin_limpieza));
  info.innerHTML = `Termina a las <strong>${fmtHora(fin)}</strong> · sala libre a las <strong>${fmtHora(libre)}</strong> ` +
    `(${p.duracion_min} min + ${s.minutos_limpieza} min de limpieza).` +
    (choque ? ` <span class="aviso">⚠ Choca con «${esc(choque.titulo)}» (${fmtHora(choque.inicio)}–${fmtHora(choque.fin_limpieza)}); la base de datos lo va a rechazar.</span>` : '');
  info.className = 'info';
}

let agendaFecha = null;   // 'YYYY-MM-DD' en hora local
const fechaLocal = d => aLocal(d).slice(0, 10);
function pintarAgenda() {
  if (!agendaFecha) {
    const prox = D.funciones.filter(f => f.estado === 'Activa' && new Date(f.inicio) > new Date()).sort((a, b) => a.inicio.localeCompare(b.inicio))[0];
    agendaFecha = fechaLocal(prox ? prox.inicio : new Date());
  }
  const d0 = new Date(agendaFecha + 'T00:00'), d1 = new Date(d0.getTime() + 86400000);
  const delDia = D.funciones.filter(f => new Date(f.inicio) < d1 && new Date(f.fin_limpieza) > d0);
  const salas = D.salas.filter(s => s.activa || delDia.some(f => f.sala_id === s.id));
  // rango visible: de 10:00 a 24:00, ampliado si hay funciones fuera
  let h0 = 10, h1 = 24;
  delDia.forEach(f => {
    h0 = Math.min(h0, Math.max(0, Math.floor((new Date(f.inicio) - d0) / 3600000)));
    h1 = Math.max(h1, Math.min(24, Math.ceil((new Date(f.fin_limpieza) - d0) / 3600000)));
  });
  const pct = t => Math.max(0, Math.min(100, ((t - d0) / 3600000 - h0) / (h1 - h0) * 100));
  const horas = Array.from({ length: h1 - h0 + 1 }, (_, i) => h0 + i);

  $('panel-extra').innerHTML = `<div class="card">
    <div class="row entre"><h2 style="margin:0">Agenda por sala</h2>
      <div class="row"><button class="secondary chico" data-dia="-1">◀</button>
        <input type="date" id="agenda-fecha" value="${agendaFecha}"><button class="secondary chico" data-dia="1">▶</button></div></div>
    <p class="muted">Cada barra es una función; la parte rayada es el tiempo de limpieza. Dos barras de la misma sala nunca pueden cruzarse
      (<code>ex_funcion_sin_traslape</code>). Clic en una función para editarla.</p>
    ${salas.length ? `<div class="agenda">
      <div class="ag-fila ag-horas"><div class="ag-sala"></div><div class="ag-pista">${horas.map(h =>
        `<span style="left:${(h - h0) / (h1 - h0) * 100}%">${String(h).padStart(2, '0')}:00</span>`).join('')}</div></div>
      ${salas.map(s => `<div class="ag-fila"><div class="ag-sala" title="${esc(s.cine)}">${esc(s.nombre)}<small>${esc(s.cine)}</small></div>
        <div class="ag-pista">${horas.map(h => `<i class="ag-linea" style="left:${(h - h0) / (h1 - h0) * 100}%"></i>`).join('')}
        ${delDia.filter(f => f.sala_id === s.id).map(f => {
          const a = pct(new Date(f.inicio)), b = pct(new Date(f.fin)), c = pct(new Date(f.fin_limpieza));
          return `<button class="ag-func ${f.estado === 'Activa' ? '' : 'off'}" data-editar="${f.id}" style="left:${a}%;width:${Math.max(b - a, .5)}%"
                    title="${esc(f.titulo)} · ${fmtHora(f.inicio)}–${fmtHora(f.fin)} · ${esc(f.estado)}">${esc(f.titulo)}<small>${fmtHora(f.inicio)}</small></button>` +
                 `<span class="ag-limpieza ${f.estado === 'Activa' ? '' : 'off'}" style="left:${b}%;width:${c - b}%"></span>`;
        }).join('')}</div></div>`).join('')}
    </div>
    ${delDia.length ? '' : '<p class="muted vacio-tabla">No hay funciones este día.</p>'}` : '<p class="aviso">No hay salas activas.</p>'}
  </div>`;
}

// ---------- Tarifas: matriz tipo de entrada × zona ----------
function pintarMatriz() {
  const tipos = D.tipos, zonas = D.zonas;
  const celda = (t, z) => D.tarifas.filter(x => x.tipo_entrada_id === t.id && x.zona_asiento_id === z.id)
    .map(x => {
      const cuando = (x.dia_semana ? DIAS[x.dia_semana].slice(0, 3) : 'Todos') +
        (horaCorta(x.hora_desde) === '00:00' && horaCorta(x.hora_hasta) === '23:59' ? '' : ` ${horaCorta(x.hora_desde)}–${horaCorta(x.hora_hasta)}`);
      return `<button class="chip${x.activa ? '' : ' off'}" data-editar="${x.id}" title="Cargo por servicio ${dinero(x.cargo_servicio)}">
                <span>${esc(cuando)}</span><strong>${dinero(x.precio)}</strong></button>`;
    }).join('') || '<span class="muted">—</span>';
  $('panel-extra').innerHTML = `<div class="card">
    <h2>Matriz de precios</h2>
    <p class="muted">Precio por tipo de entrada y zona. "Todos" es la tarifa base; las de un día u horario específico la sustituyen. Clic para editar.</p>
    ${tipos.length && zonas.length ? `<div class="scroll"><table class="matriz">
      <thead><tr><th></th>${zonas.map(z => `<th><i class="punto" style="background:${colorZona(z.id)}"></i> ${esc(z.nombre)}</th>`).join('')}</tr></thead>
      <tbody>${tipos.map(t => `<tr><th>${esc(t.nombre)}</th>${zonas.map(z => `<td>${celda(t, z)}</td>`).join('')}</tr>`).join('')}</tbody>
    </table></div>` : '<p class="aviso">Crea tipos de entrada y zonas para armar la matriz.</p>'}
  </div>`;
}

$('panel-extra').onclick = ev => {
  const b = ev.target.closest('button'); if (!b) return;
  if (b.dataset.editar) return editar(Number(b.dataset.editar));
  if (b.dataset.dia) {
    const d = new Date(agendaFecha + 'T12:00'); d.setDate(d.getDate() + Number(b.dataset.dia));
    agendaFecha = fechaLocal(d); pintarAgenda();
  }
};
$('panel-extra').onchange = ev => { if (ev.target.id === 'agenda-fecha' && ev.target.value) { agendaFecha = ev.target.value; pintarAgenda(); } };

$('filtro').oninput = pintarTabla;
$('tabla').onclick = async ev => {
  const b = ev.target.closest('button'); if (!b) return;
  if (b.dataset.editar) return editar(Number(b.dataset.editar));
  if (b.dataset.asientos) { salaActual = Number(b.dataset.asientos); return irA('asientos'); }
  if (b.dataset.cancelar) {
    const id = Number(b.dataset.cancelar);
    if (!confirm(`¿Cancelar la función #${id}? Su horario queda libre para otra función.`)) return;
    try {
      await api(`/catalogo/admin/funciones/${id}`, { method: 'PUT', body: { estado: 'Cancelada' } });
      ok('Función cancelada.'); await cargar('funciones'); pintarTabla();
    } catch (e) { fallo(e); }
    return;
  }
  if (b.dataset.borrar) {
    const id = Number(b.dataset.borrar);
    if (!confirm(`¿Eliminar ${SECCIONES[tab].singular} #${id}? Esta acción no se puede deshacer.`)) return;
    try {
      await api(`/catalogo/admin/${tab}/${id}`, { method: 'DELETE' });
      ok('Registro eliminado.');
      await cargar();
      if (editando === id) cancelarEdicion();
      pintarTabla();
    } catch (e) { fallo(e); }
  }
};

// ---------- Editor de asientos ----------
const PALETA = ['#8b5cf6', '#0ea5e9', '#f97316', '#ec4899', '#14b8a6', '#a3a3a3', '#84cc16', '#f43f5e'];
function colorZona(id) {
  const i = D.zonas.findIndex(z => z.id === id);
  return PALETA[(i < 0 ? id : i) % PALETA.length];
}
let salaActual = null;
let asientos = [];

function opcionesZona(sel) {
  return D.zonas.map(z => `<option value="${z.id}"${z.id === sel ? ' selected' : ''}>${esc(z.nombre)}</option>`).join('');
}

async function pintarEditorAsientos() {
  if (!D.salas.length) {
    $('as-sala').innerHTML = '';
    $('as-resumen').innerHTML = '<span class="aviso">No hay salas. Crea una en la pestaña Salas.</span>';
    $('mapa').innerHTML = ''; $('leyenda').innerHTML = '';
    return;
  }
  const qsSala = Number(new URLSearchParams(location.hash.split('?')[1] || '').get('sala'));
  if (!salaActual) salaActual = qsSala || D.salas[0].id;
  if (!D.salas.some(s => s.id === salaActual)) salaActual = D.salas[0].id;
  history.replaceState(null, '', '#asientos?sala=' + salaActual);

  $('as-sala').innerHTML = D.salas.map(s => `<option value="${s.id}"${s.id === salaActual ? ' selected' : ''}>${esc(s.cine)} · ${esc(s.nombre)}</option>`).join('');
  const zonasOk = D.zonas.length > 0;
  const zonaDef = (D.zonas.find(z => /^general$/i.test(z.nombre)) || D.zonas[0])?.id;
  $('gen-zona').innerHTML = opcionesZona(zonaDef);
  $('herr-zona').innerHTML = opcionesZona(zonaDef);
  $('gen-btn').disabled = !zonasOk;
  if (!zonasOk) mostrarMensaje(msg, 'Crea al menos una zona (pestaña Zonas) antes de generar asientos.', 'err');
  pintarZonasPorFila();
  await recargarAsientos();
}

async function recargarAsientos() {
  try {
    asientos = await api(`/catalogo/admin/salas/${salaActual}/asientos`);
  } catch (e) { asientos = []; fallo(e); }
  pintarMapa();
}

function pintarZonasPorFila() {
  const n = Math.min(26, Math.max(0, parseInt($('gen-filas').value, 10) || 0));
  const def = Number($('gen-zona').value);
  const previas = [...document.querySelectorAll('#gen-zonas-fila select')].map(s => Number(s.value));
  $('gen-zonas-fila').innerHTML = Array.from({ length: n }, (_, i) =>
    `<label>Fila ${String.fromCharCode(65 + i)} <select data-fila="${i}">${opcionesZona(previas[i] || def)}</select></label>`).join('');
}

function pintarMapa() {
  const sala = D.salas.find(s => s.id === salaActual) || {};
  const activos = asientos.filter(a => a.activo).length;
  const cuadra = activos === sala.capacidad;
  $('as-resumen').innerHTML = asientos.length
    ? `Capacidad declarada <strong>${sala.capacidad}</strong> · Asientos activos <strong>${activos}</strong> de ${asientos.length} ` +
      (cuadra ? '<span class="pill si">Coincide</span>' : `<span class="aviso">⚠ No coincide con la capacidad</span> <button class="secondary chico" id="ajustar-cap">Ajustar capacidad a ${activos}</button>`)
    : `Capacidad declarada <strong>${sala.capacidad ?? '—'}</strong> · <span class="aviso">La sala aún no tiene asientos. Genéralos abajo.</span>`;
  const aj = $('ajustar-cap');
  if (aj) aj.onclick = async () => {
    try {
      await api(`/catalogo/admin/salas/${salaActual}`, { method: 'PUT', body: { capacidad: activos } });
      await cargar('salas'); ok('Capacidad actualizada.'); pintarMapa();
    } catch (e) { fallo(e); }
  };

  const porFila = new Map();
  asientos.forEach(a => { if (!porFila.has(a.fila)) porFila.set(a.fila, []); porFila.get(a.fila).push(a); });
  $('mapa').innerHTML = [...porFila].map(([fila, lista]) =>
    `<div class="fila"><button class="letra" data-fila="${esc(fila)}" title="Aplicar a toda la fila ${esc(fila)}">${esc(fila)}</button>` +
    lista.map(a => `<button class="asiento-admin${a.activo ? '' : ' inactivo'}" data-id="${a.id}"
        style="--z:${colorZona(a.zona_asiento_id)}" title="${esc(fila)}${a.numero} · ${esc(a.zona)}${a.activo ? '' : ' · inactivo'}">${a.numero}</button>`).join('') +
    `<span class="letra">${esc(fila)}</span></div>`).join('');

  const usadas = new Set(asientos.map(a => a.zona_asiento_id));
  $('leyenda').innerHTML = D.zonas.filter(z => usadas.has(z.id))
    .map(z => `<span><i style="background:${colorZona(z.id)}"></i>${esc(z.nombre)} (${asientos.filter(a => a.zona_asiento_id === z.id && a.activo).length})</span>`).join('') +
    (asientos.some(a => !a.activo) ? '<span><i class="inactivo-muestra"></i>Inactivo / pasillo</span>' : '');
}

function cambioHerramienta(lista) {
  const herr = document.querySelector('input[name="herr"]:checked').value;
  if (herr === 'zona') return { zona_asiento_id: Number($('herr-zona').value) };
  // en una fila: si hay alguno activo, desactiva todos; si no, activa todos
  return { activo: lista.length === 1 ? !lista[0].activo : !lista.some(a => a.activo) };
}

$('mapa').onclick = async ev => {
  const b = ev.target.closest('button'); if (!b) return;
  const lista = b.dataset.fila ? asientos.filter(a => a.fila === b.dataset.fila) : asientos.filter(a => a.id === Number(b.dataset.id));
  if (!lista.length) return;
  const cambio = cambioHerramienta(lista);
  try {
    if (lista.length === 1) await api(`/catalogo/admin/asientos/${lista[0].id}`, { method: 'PUT', body: cambio });
    else await api('/catalogo/admin/asientos', { method: 'PUT', body: { ids: lista.map(a => a.id), ...cambio } });
    msg.hidden = true;
    await Promise.all([recargarAsientos(), cargar('salas', 'zonas')]);
  } catch (e) { fallo(e); }
};

$('as-sala').onchange = () => { salaActual = Number($('as-sala').value); pintarEditorAsientos(); };
$('gen-filas').oninput = pintarZonasPorFila;
$('gen-zona').onchange = () => { document.querySelectorAll('#gen-zonas-fila select').forEach(s => (s.value = $('gen-zona').value)); };
$('gen-btn').onclick = async () => {
  const body = {
    filas: Number($('gen-filas').value),
    por_fila: Number($('gen-cols').value),
    zonas: [...document.querySelectorAll('#gen-zonas-fila select')].map(s => Number(s.value)),
    reemplazar: $('gen-reemplazar').checked
  };
  if (body.reemplazar && asientos.length && !confirm(`Se borrarán los ${asientos.length} asientos actuales de la sala. ¿Continuar?`)) return;
  try {
    const r = await api(`/catalogo/admin/salas/${salaActual}/asientos/generar`, { method: 'POST', body });
    ok(`Se generaron ${r.insertados} asientos.`);
    $('gen-reemplazar').checked = false;
    await Promise.all([recargarAsientos(), cargar('salas', 'zonas')]);
    pintarMapa();
  } catch (e) { fallo(e); }
};

// ---------- Inicio ----------
document.querySelectorAll('.tabs button').forEach(b => (b.onclick = () => irA(b.dataset.tab)));
(async () => {
  try { await cargar(); }
  catch (e) { return fallo(e); }
  const inicial = location.hash.slice(1).split('?')[0];
  irA(SECCIONES[inicial] || inicial === 'asientos' ? inicial : 'peliculas');
})();
