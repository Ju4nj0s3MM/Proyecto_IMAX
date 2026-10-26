// Barra de navegación según el rol (matriz de privilegio mínimo). Incluir con:
// <script src="/js/api.js"></script><script src="/js/nav.js" data-auth="required" data-roles="administrador,taquillero"></script>
(async function () {
  const s = document.currentScript;
  const required = s.dataset.auth === 'required';
  const allowed = (s.dataset.roles || '').split(',').filter(Boolean);
  const me = await api('/seguridad/me').catch(() => null);

  if (required && !me) { location.href = '/login.html?next=' + encodeURIComponent(location.pathname + location.search); return; }
  if (me && allowed.length && !me.roles.some(r => allowed.includes(r))) {
    document.body.innerHTML = '<main><div class="msg err">Tu rol no tiene acceso a esta pantalla.</div><a href="/index.html">Volver</a></main>';
    return;
  }

  // Menú por rol. Cada dueño agrega aquí sus enlaces.
  const menu = [
    { href: '/catalogo/cartelera.html', txt: 'Cartelera', roles: ['*'] },
    { href: '/venta/mis-entradas.html', txt: 'Mis entradas', roles: ['cliente', 'taquillero', 'administrador'] },
    { href: '/seguridad/checkin.html', txt: 'Check-in', roles: ['operador_sala', 'administrador'] },
    { href: '/dashboard.html', txt: 'Dashboard', roles: ['contador', 'administrador'] },
    { href: '/venta/reportes.html', txt: 'Reportes', roles: ['contador', 'administrador'] },
    { href: '/catalogo/admin.html', txt: 'Admin catálogo', roles: ['administrador'] },
    { href: '/seguridad/usuarios.html', txt: 'Usuarios', roles: ['administrador'] },
    { href: '/seguridad/auditoria.html', txt: 'Auditoría', roles: ['administrador'] }
  ];
  const visibles = menu.filter(m => m.roles.includes('*') || (me && me.roles.some(r => m.roles.includes(r))));

  const nav = document.createElement('nav');
  nav.innerHTML = '<span class="brand">🎬 IMAX</span>' +
    visibles.map(m => `<a href="${m.href}">${m.txt}</a>`).join('') +
    '<span class="spacer"></span>' +
    (me ? `<span class="muted">${me.nombre} · ${me.roles.join(', ')}</span><button class="secondary" id="logout">Salir</button>`
        : '<a href="/login.html">Iniciar sesión</a>');
  document.body.prepend(nav);
  const out = document.getElementById('logout');
  if (out) out.onclick = async () => { await api('/seguridad/logout', { method: 'POST' }); location.href = '/index.html'; };
  window.currentUser = me;
})();
