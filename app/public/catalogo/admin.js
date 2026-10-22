// MÓDULO A · Mati — Panel de administración del catálogo.
// CRUD de cines, salas, zonas, clasificaciones, géneros y películas + editor del mapa de asientos.
// Toda validación de datos la hace la BD (constraints del DDL); aquí solo se muestran sus mensajes.

const esc = v => String(v ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const $ = id => document.getElementById(id);
const msg = $('msg');
const ok = t => { mostrarMensaje(msg, t, 'ok'); clearTimeout(ok.t); ok.t = setTimeout(() => (msg.hidden = true), 4000); };
const fallo = e => mostrarMensaje(msg, e.message || e, 'err');
const estado = v => v ? '<span class="pill si">Activo</span>' : '<span class="pill no">Inactivo</span>';

// Datos cargados de la API
const D = { peliculas: [], cines: [], salas: [], zonas: [], clasificaciones: [], generos: [] };
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
      { t: 'Estado', v: p => estado(p.activa) }
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
      { t: 'Limpieza', v: s => `${s.minutos_limpieza} min` },
      { t: 'Estado', v: s => estado(s.activa) }
    ],
    extra: s => `<button class="secondary chico" data-asientos="${s.id}">Asientos</button>`
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
    return `<label${span}>${et}<select id="${id}"${req}><option value="">— Seleccionar —</option>` +
      ops.map(o => `<option value="${o.v}">${esc(o.t)}</option>`).join('') + '</select>' +
      (ops.length ? '' : `<small class="aviso">Primero crea registros en la pestaña correspondiente.</small>`) + '</label>';
  }
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
    else if (c.type === 'date') el.value = v ? String(v).slice(0, 10) : '';
    else el.value = v ?? '';
  }
  const url = $('f-poster_url'); if (url) url.oninput();
}

function leerFormulario() {
  const out = {};
  for (const c of SECCIONES[tab].campos) {
    if (c.type === 'checks') { out[c.k] = [...document.querySelectorAll(`#form input[name="${c.k}"]:checked`)].map(i => Number(i.value)); continue; }
    const el = $('f-' + c.k);
    if (c.type === 'checkbox') out[c.k] = el.checked;
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
  $('form-titulo').textContent = (/^(cine|género)$/.test(S.singular) ? 'Nuevo ' : 'Nueva ') + S.singular;
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
}

$('filtro').oninput = pintarTabla;
$('tabla').onclick = async ev => {
  const b = ev.target.closest('button'); if (!b) return;
  if (b.dataset.editar) return editar(Number(b.dataset.editar));
  if (b.dataset.asientos) { salaActual = Number(b.dataset.asientos); return irA('asientos'); }
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
