require('dotenv').config();
// Valores por defecto: sin .env la app arranca en modo MOCK (sin BD). Para usar la BD real: MOCK=false en .env
process.env.MOCK ??= 'true';
process.env.AUTH_DEV_BYPASS ??= process.env.MOCK;
const express = require('express');
const session = require('express-session');
const path = require('path');

const app = express();
app.use(express.json());
app.use(session({
  secret: process.env.SESSION_SECRET || 'dev-secret',
  resave: false,
  saveUninitialized: false,
  cookie: { httpOnly: true, sameSite: 'lax' }
}));

// API: un archivo de rutas por módulo (cada dueño edita SOLO el suyo)
app.use('/api/catalogo',  require('./src/routes/catalogo'));   // Mati
app.use('/api/venta',     require('./src/routes/venta'));      // Juanjo
app.use('/api/seguridad', require('./src/routes/seguridad'));  // Brandon

// Páginas estáticas
app.use(express.static(path.join(__dirname, 'public')));

// Manejo de errores: los RAISE EXCEPTION de PostgreSQL llegan como mensaje legible
app.use((err, req, res, next) => {
  let status = err.status || 500;
  let message = err.message || 'Error interno';
  if (err.code === '23505') { status = 409; message = 'Conflicto: el registro ya existe o el asiento no está disponible'; }
  else if (err.code === 'P0001') { status = 400; }   // RAISE EXCEPTION en PL/pgSQL
  else if (err.code === '42501') { status = 403; message = 'Permiso denegado por la base de datos'; }
  else if (err.code === '22P02') { status = 400; message = 'Formato inválido: se esperaba un número'; }   // ej. funcion_id = 'abc'
  if (status >= 500) console.error(err);
  res.status(status).json({ error: message });
});

const port = process.env.PORT || 3000;
app.listen(port, () => {
  console.log(`IMAX app en http://localhost:${port}  (MOCK=${process.env.MOCK === 'true'})`);
});