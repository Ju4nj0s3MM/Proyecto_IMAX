// MÓDULO C — Panel de usuarios y roles (tablas usuario, rol, usuario_rol).
// Las validaciones de datos las hace la BD (constraints) y el backend (contraseña, protecciones); aquí solo se muestran sus mensajes.

const $ = id => document.getElementById(id);
const esc = v => String(v ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const msg = $('msg');
const ok = t => { mostrarMensaje(msg, t, 'ok'); clearTimeout(ok.t); ok.t = setTimeout(() => (msg.hidden = true), 4000); };
const fallo = e => mostrarMensaje(msg, e.message || e, 'err');
const fmtDia = iso => new Date(iso).toLocaleDateString('es-CR', { dateStyle: 'medium' });

// Color fijo por rol del sistema (los demás toman uno de la paleta)
const COLOR_ROL = { cliente: '#0ea5e9', taquillero: '#f97316', operador_sala: '#14b8a6', contador: '#a855f7', administrador: '#ef4444' };
const PALETA = ['#84cc16', '#ec4899', '#eab308', '#6366f1'];
const colorRol = r => COLOR_ROL[r.nombre] || PALETA[r.id % PALETA.length];
const pillRol = r => `<span class="pill-rol" style="--c:${colorRol(r)}">${esc(r.nombre)}</span>`;

const D = { usuarios: [], roles: [] };
let tab = 'usuarios';
let editU = null, editR = null;
const yo = () => Number(window.currentUser?.id);

async function cargar() {
  [D.usuarios, D.roles] = await Promise.all([api('/seguridad/admin/usuarios'), api('/seguridad/admin/roles')]);
}

// ---------- Pestañas ----------
function irA(nombre) {
  tab = nombre;
  document.querySelectorAll('.tabs button').forEach(b => b.setAttribute('aria-selected', b.dataset.tab === nombre));
  $('tab-usuarios').hidden = nombre !== 'usuarios';
  $('tab-roles').hidden = nombre !== 'roles';
  msg.hidden = true;
  history.replaceState(null, '', '#' + nombre);
  if (nombre === 'usuarios') { cancelarU(); pintarUsuarios(); } else { cancelarR(); pintarRoles(); }
}
document.querySelectorAll('.tabs button').forEach(b => (b.onclick = () => irA(b.dataset.tab)));

// ---------- Usuarios: formulario ----------
function pintarChecksRoles(marcados = []) {
  const set = new Set(marcados.map(Number));
  $('u-roles').innerHTML = D.roles.map(r => `
    <label class="check rol-check" title="${esc(r.descripcion)}">
      <input type="checkbox" name="rol" value="${r.id}"${set.has(r.id) ? ' checked' : ''}>
      ${pillRol(r)} <small class="muted">${esc(r.descripcion || '')}</small>
    </label>`).join('') || '<span class="muted">No hay roles. Créalos en la pestaña Roles.</span>';
}

function cancelarU() {
  editU = null;
  $('u-form').reset();
  $('u-activo').checked = true;
  pintarChecksRoles([]);
  $('u-titulo').textContent = 'Nuevo usuario';
  $('u-guardar').textContent = 'Crear';
  $('u-cancelar').hidden = true;
  $('u-password').required = true;
  $('u-pass-label').innerHTML = 'Contraseña <b class="req">*</b>';
  $('u-pass-ayuda').textContent = 'Mínimo 8 caracteres.';
  $('u-activo').disabled = false;
  document.querySelectorAll('#u-tabla tr.editando').forEach(tr => tr.classList.remove('editando'));
}

function editarU(id) {
  const u = D.usuarios.find(x => x.id === id); if (!u) return;
  editU = id;
  $('u-nombre').value = u.nombre; $('u-apellido').value = u.apellido; $('u-email').value = u.email;
  $('u-telefono').value = u.telefono || ''; $('u-activo').checked = u.activo; $('u-password').value = '';
  pintarChecksRoles(u.roles_ids);
  $('u-titulo').textContent = `Editar usuario #${id}` + (id === yo() ? ' (tú)' : '');
  $('u-guardar').textContent = 'Guardar cambios';
  $('u-cancelar').hidden = false;
  $('u-password').required = false;
  $('u-pass-label').textContent = 'Nueva contraseña';
  $('u-pass-ayuda').textContent = 'Déjala vacía para no cambiarla.';
  $('u-activo').disabled = id === yo();
  document.querySelectorAll('#u-tabla tr').forEach(tr => tr.classList.toggle('editando', Number(tr.dataset.id) === id));
  $('u-form').scrollIntoView({ behavior: 'smooth', block: 'center' });
}

$('u-ver').onclick = () => { const p = $('u-password'); p.type = p.type === 'password' ? 'text' : 'password'; };
$('u-cancelar').onclick = cancelarU;

$('u-form').onsubmit = async ev => {
  ev.preventDefault();
  const body = {
    nombre: $('u-nombre').value, apellido: $('u-apellido').value, email: $('u-email').value,
    telefono: $('u-telefono').value, activo: $('u-activo').checked,
    roles: [...document.querySelectorAll('#u-roles input:checked')].map(i => Number(i.value))
  };
  if ($('u-password').value) body.password = $('u-password').value;
  if (!body.roles.length && !confirm('El usuario no tiene ningún rol, así que no podrá ver nada privado. ¿Guardar de todas formas?')) return;
  const btn = $('u-guardar'); btn.disabled = true;
  try {
    if (editU) await api(`/seguridad/admin/usuarios/${editU}`, { method: 'PUT', body });
    else await api('/seguridad/admin/usuarios', { method: 'POST', body });
    ok(editU ? 'Cambios guardados.' : 'Usuario creado.');
    await cargar(); cancelarU(); pintarUsuarios();
  } catch (e) { fallo(e); }
  finally { btn.disabled = false; }
};

// ---------- Usuarios: tabla ----------
function pintarUsuarios() {
  const rolSel = $('u-filtro-rol');
  const previo = rolSel.value;
  rolSel.innerHTML = '<option value="">Todos</option><option value="-">Sin rol</option>' +
    D.roles.map(r => `<option value="${r.id}">${esc(r.nombre)}</option>`).join('');
  rolSel.value = previo;

  $('u-resumen').innerHTML = D.roles.map(r => `<button class="chip-rol${rolSel.value === String(r.id) ? ' activo' : ''}" data-rol="${r.id}" style="--c:${colorRol(r)}">
      ${esc(r.nombre)} <strong>${D.usuarios.filter(u => u.roles_ids.includes(r.id)).length}</strong></button>`).join('');

  const f = $('u-filtro').value.trim().toLowerCase();
  const filas = D.usuarios.filter(u =>
    (!f || `${u.nombre} ${u.apellido} ${u.email} ${u.telefono || ''}`.toLowerCase().includes(f)) &&
    (!rolSel.value || (rolSel.value === '-' ? !u.roles_ids.length : u.roles_ids.includes(Number(rolSel.value)))));
  $('u-tabla-titulo').textContent = `Usuarios (${filas.length})`;
  const rolesDe = u => u.roles_ids.map(id => D.roles.find(r => r.id === id)).filter(Boolean);

  $('u-tabla').innerHTML = `<thead><tr><th class="id">#</th><th>Usuario</th><th>Teléfono</th><th>Roles</th><th>Estado</th><th>Creado</th><th></th></tr></thead><tbody>` +
    (filas.length ? filas.map(u => `<tr data-id="${u.id}"${u.id === editU ? ' class="editando"' : ''}>
      <td class="id muted">${u.id}</td>
      <td><strong>${esc(u.nombre)} ${esc(u.apellido)}</strong>${u.id === yo() ? ' <span class="pill tu">tú</span>' : ''}<div class="muted">${esc(u.email)}</div></td>
      <td>${esc(u.telefono) || '<span class="muted">—</span>'}</td>
      <td>${rolesDe(u).map(pillRol).join(' ') || '<span class="aviso">Sin rol</span>'}</td>
      <td>${u.activo ? '<span class="pill si">Activo</span>' : '<span class="pill no">Inactivo</span>'}</td>
      <td class="nowrap muted">${esc(fmtDia(u.creado_en))}</td>
      <td class="acciones-fila">
        ${u.id === yo() ? '' : `<button class="secondary chico" data-activo="${u.id}">${u.activo ? 'Desactivar' : 'Activar'}</button>`}
        <button class="secondary chico" data-editar="${u.id}">Editar</button>
        ${u.id === yo() ? '' : `<button class="danger chico" data-borrar="${u.id}">Eliminar</button>`}
      </td></tr>`).join('')
      : `<tr><td colspan="7" class="muted vacio-tabla">${f || rolSel.value ? 'Sin coincidencias.' : 'Todavía no hay usuarios.'}</td></tr>`) + '</tbody>';
}

$('u-filtro').oninput = pintarUsuarios;
$('u-filtro-rol').onchange = pintarUsuarios;
$('u-resumen').onclick = ev => {
  const b = ev.target.closest('[data-rol]'); if (!b) return;
  $('u-filtro-rol').value = $('u-filtro-rol').value === b.dataset.rol ? '' : b.dataset.rol;
  pintarUsuarios();
};

$('u-tabla').onclick = async ev => {
  const b = ev.target.closest('button'); if (!b) return;
  if (b.dataset.editar) return editarU(Number(b.dataset.editar));
  try {
    if (b.dataset.activo) {
      const u = D.usuarios.find(x => x.id === Number(b.dataset.activo));
      await api(`/seguridad/admin/usuarios/${u.id}`, { method: 'PUT', body: { activo: !u.activo } });
      ok(u.activo ? 'Usuario desactivado: ya no podrá iniciar sesión.' : 'Usuario activado.');
    } else if (b.dataset.borrar) {
      const u = D.usuarios.find(x => x.id === Number(b.dataset.borrar));
      if (!confirm(`¿Eliminar a ${u.nombre} ${u.apellido} (${u.email})? Se borran también sus roles. ` +
                   'Si ya tiene compras, conviene desactivarlo en lugar de eliminarlo.')) return;
      await api(`/seguridad/admin/usuarios/${u.id}`, { method: 'DELETE' });
      ok('Usuario eliminado.');
      if (editU === u.id) cancelarU();
    } else return;
    await cargar(); pintarUsuarios();
  } catch (e) { fallo(e); }
};

// ---------- Roles ----------
function cancelarR() {
  editR = null;
  $('r-form').reset();
  $('r-nombre').disabled = false;
  $('r-aviso').hidden = true;
  $('r-titulo').textContent = 'Nuevo rol';
  $('r-guardar').textContent = 'Crear';
  $('r-cancelar').hidden = true;
}

function editarR(id) {
  const r = D.roles.find(x => x.id === id); if (!r) return;
  editR = id;
  $('r-nombre').value = r.nombre; $('r-descripcion').value = r.descripcion || '';
  $('r-nombre').disabled = r.sistema;
  $('r-aviso').hidden = !r.sistema;
  $('r-aviso').textContent = 'Rol del sistema: solo se puede cambiar la descripción.';
  $('r-titulo').textContent = `Editar rol #${id}`;
  $('r-guardar').textContent = 'Guardar cambios';
  $('r-cancelar').hidden = false;
  $('r-form').scrollIntoView({ behavior: 'smooth', block: 'center' });
}
$('r-cancelar').onclick = cancelarR;

$('r-form').onsubmit = async ev => {
  ev.preventDefault();
  const body = { descripcion: $('r-descripcion').value };
  if (!$('r-nombre').disabled) body.nombre = $('r-nombre').value;
  try {
    if (editR) await api(`/seguridad/admin/roles/${editR}`, { method: 'PUT', body });
    else await api('/seguridad/admin/roles', { method: 'POST', body });
    ok(editR ? 'Rol actualizado.' : 'Rol creado.');
    await cargar(); cancelarR(); pintarRoles();
  } catch (e) { fallo(e); }
};

function pintarRoles() {
  $('r-tabla-titulo').textContent = `Roles (${D.roles.length})`;
  $('r-tabla').innerHTML = '<thead><tr><th class="id">#</th><th>Rol</th><th>Descripción</th><th>Usuarios</th><th></th></tr></thead><tbody>' +
    D.roles.map(r => `<tr>
      <td class="id muted">${r.id}</td>
      <td>${pillRol(r)}${r.sistema ? ' <span class="pill no">Sistema</span>' : ''}</td>
      <td>${esc(r.descripcion) || '<span class="muted">—</span>'}</td>
      <td><a href="#usuarios" data-ver="${r.id}">${r.usuarios}</a></td>
      <td class="acciones-fila">
        <button class="secondary chico" data-editar="${r.id}">Editar</button>
        ${r.sistema ? '' : `<button class="danger chico" data-borrar="${r.id}">Eliminar</button>`}
      </td></tr>`).join('') + '</tbody>';
}

$('r-tabla').onclick = async ev => {
  const v = ev.target.closest('[data-ver]');
  if (v) { ev.preventDefault(); irA('usuarios'); $('u-filtro-rol').value = v.dataset.ver; return pintarUsuarios(); }
  const b = ev.target.closest('button'); if (!b) return;
  if (b.dataset.editar) return editarR(Number(b.dataset.editar));
  if (b.dataset.borrar) {
    const r = D.roles.find(x => x.id === Number(b.dataset.borrar));
    if (!confirm(`¿Eliminar el rol "${r.nombre}"?`)) return;
    try { await api(`/seguridad/admin/roles/${r.id}`, { method: 'DELETE' }); ok('Rol eliminado.'); await cargar(); pintarRoles(); }
    catch (e) { fallo(e); }
  }
};

// ---------- Inicio ----------
(async () => {
  // esperar a que nav.js deje window.currentUser
  for (let i = 0; i < 40 && window.currentUser === undefined; i++) await new Promise(r => setTimeout(r, 50));
  try { await cargar(); } catch (e) { return fallo(e); }
  irA(location.hash.slice(1) === 'roles' ? 'roles' : 'usuarios');
})();
