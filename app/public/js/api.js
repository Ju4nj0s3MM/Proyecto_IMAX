// Envoltorio de fetch para llamar a la API. Lanza Error con el mensaje del servidor.
async function api(path, { method = 'GET', body } = {}) {
  const res = await fetch('/api' + path, {
    method,
    headers: { 'Content-Type': 'application/json' },
    credentials: 'same-origin',
    body: body ? JSON.stringify(body) : undefined
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) { const e = new Error(data.error || res.statusText); e.status = res.status; throw e; }
  return data;
}

function mostrarMensaje(el, texto, tipo = 'ok') {
  el.className = 'msg ' + tipo;
  el.textContent = texto;
  el.hidden = false;
}

function fmtFecha(iso) { return new Date(iso).toLocaleString('es-CR', { dateStyle: 'medium', timeStyle: 'short' }); }
function qs(name) { return new URLSearchParams(location.search).get(name); }
