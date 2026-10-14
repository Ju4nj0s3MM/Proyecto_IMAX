// MÓDULO A · Mati — RN-01, RN-02. Muestra título, sinopsis, clasificación, horario y ubicación de la sala.
async function cargar() {
  const msg = document.getElementById('msg'); msg.hidden = true;
  const p = new URLSearchParams();
  for (const id of ['cine', 'fecha', 'genero']) { const v = document.getElementById(id).value; if (v) p.set(id, v); }
  try {
    const funciones = await api('/catalogo/cartelera?' + p.toString());
    const cont = document.getElementById('lista');
    if (!funciones.length) { cont.innerHTML = '<p class="muted">No hay funciones con esos filtros.</p>'; return; }
    cont.innerHTML = funciones.map(f => `
      <div class="card">
        <h3>${f.titulo} <small class="muted">· ${f.clasificacion} · ${f.genero || ''}</small></h3>
        <p>${f.sinopsis}</p>
        <p class="muted">${f.cine} — ${f.ubicacion} · ${f.sala} · ${fmtFecha(f.inicio)}</p>
        <a class="btn" href="/venta/mapa.html?funcion=${f.funcion_id}">Elegir asientos</a>
      </div>`).join('');
  } catch (e) { mostrarMensaje(msg, e.message, 'err'); }
}
document.getElementById('buscar').onclick = cargar;
cargar();
