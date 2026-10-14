// Sesión simple en memoria. req.session.user = { id, nombre, roles: [...] }
function requireLogin(req, res, next) {
  if (!req.session.user) return res.status(401).json({ error: 'Debes iniciar sesión' });
  next();
}

// Control de acceso en el BACKEND (no basta con ocultar botones en la GUI) - RN-17
function requireRole(...roles) {
  return (req, res, next) => {
    const u = req.session.user;
    if (!u) return res.status(401).json({ error: 'Debes iniciar sesión' });
    if (!u.roles.some(r => roles.includes(r))) {
      return res.status(403).json({ error: 'Tu rol no tiene permiso para esta acción' });
    }
    next();
  };
}

// Envuelve handlers async para que los errores lleguen al manejador central
const wrap = fn => (req, res, next) => fn(req, res, next).catch(next);
const isMock = () => process.env.MOCK === 'true';

module.exports = { requireLogin, requireRole, wrap, isMock };
