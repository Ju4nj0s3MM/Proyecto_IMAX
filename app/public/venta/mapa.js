// MÓDULO B · Juanjo — RN-03, RN-04, RN-05. Mapa con colores, selección y cuenta regresiva.
// El servidor/BD manda: el temporizador de la UI es solo informativo y el bloqueo real expira en la BD.
const funcionId = qs('funcion');
const MAX_ASIENTOS = 6;              // RN-04 (la BD también lo valida)
const POLL_MS = 5000;                // "tiempo real" por polling; se puede cambiar a SSE
let asientos = [];
const seleccion = new Set();
let timerInt = null;

document.getElementById('max').textContent = MAX_ASIENTOS;

async function cargarMapa() {
  asientos = await api(`/venta/funciones/${funcionId}/asientos`);
  // si alguien más tomó un asiento que yo había marcado, lo saco de mi selección
  for (const id of [...seleccion]) {
    const a = asientos.find(x => x.asiento_id === id);
    if (!a || a.estado !== 'DISPONIBLE') seleccion.delete(id);
  }
  render();
}

function render() {
  const porFila = {};
  asientos.forEach(a => (porFila[a.fila] ||= []).push(a));
  document.getElementById('mapa').innerHTML = Object.keys(porFila).sort().map(f => `
    <div class="fila"><span class="letra">${f}</span>${
      porFila[f].sort((a, b) => a.numero - b.numero).map(a => {
        const sel = seleccion.has(a.asiento_id);
        const cls = sel ? 'seleccionado' : a.estado;
        return `<button class="asiento ${cls}" data-id="${a.asiento_id}" title="${a.zona || ''} ${f}${a.numero}"
                 ${a.estado !== 'DISPONIBLE' ? 'disabled' : ''}>${a.numero}</button>`;
      }).join('')}</div>`).join('');
  document.querySelectorAll('.asiento.DISPONIBLE, .asiento.seleccionado').forEach(b => b.onclick = () => toggle(+b.dataset.id));
  document.getElementById('seleccion').textContent = seleccion.size
    ? [...seleccion].map(id => { const a = asientos.find(x => x.asiento_id === id); return a.fila + a.numero; }).join(', ') : 'ninguno';
  document.getElementById('bloquear').disabled = seleccion.size === 0;
}

function toggle(id) {
  if (seleccion.has(id)) seleccion.delete(id);
  else if (seleccion.size < MAX_ASIENTOS) seleccion.add(id);
  else mostrarMensaje(document.getElementById('msg'), `Máximo ${MAX_ASIENTOS} asientos por compra`, 'err');
  render();
}

document.getElementById('bloquear').onclick = async () => {
  const msg = document.getElementById('msg'); msg.hidden = true;
  try {
    const r = await api('/venta/reservas', { method: 'POST', body: { funcion_id: +funcionId, asientos: [...seleccion] } });
    const expira = r.expira_en ? new Date(r.expira_en).getTime() : Date.now() + 120000;
    iniciarCuenta(expira);
    document.getElementById('irPago').href = `/venta/pago.html?reserva=${r.reserva_id}&funcion=${funcionId}`;
    document.getElementById('cuenta').hidden = false;
    await cargarMapa();
  } catch (e) {            // p. ej. "asiento no disponible" si otro usuario ganó la carrera
    mostrarMensaje(msg, e.message, 'err');
    await cargarMapa();
  }
};

function iniciarCuenta(expiraMs) {
  clearInterval(timerInt);
  timerInt = setInterval(() => {
    const resta = Math.max(0, Math.floor((expiraMs - Date.now()) / 1000));
    document.getElementById('timer').textContent =
      String(Math.floor(resta / 60)).padStart(2, '0') + ':' + String(resta % 60).padStart(2, '0');
    if (resta === 0) {
      clearInterval(timerInt);
      document.getElementById('cuenta').hidden = true;
      mostrarMensaje(document.getElementById('msg'), 'Se agotó el tiempo: los asientos fueron liberados.', 'err');
      seleccion.clear(); cargarMapa();
    }
  }, 500);
}

cargarMapa();
setInterval(() => cargarMapa().catch(() => {}), POLL_MS);
