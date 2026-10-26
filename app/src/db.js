const { Pool, types } = require('pg');
// bigint (ids identity y count) llega como número, no como texto ("1"): los ids no superan 2^53.
types.setTypeParser(20, v => Number(v));
// date llega tal cual ('2026-12-18'), sin convertirlo a Date con la zona horaria del servidor.
types.setTypeParser(1082, v => v);
const pool = new Pool();   // usa PGHOST, PGUSER, PGPASSWORD, PGDATABASE, PGPORT del .env
// Si PostgreSQL cierra una conexión inactiva (reinicio del servicio, etc.) el pool la descarta; sin esto se cae la app.
pool.on('error', e => console.error('PostgreSQL cerró una conexión inactiva:', e.message));

// Ejecuta SQL parametrizado y devuelve las filas. La lógica de negocio vive en las funciones SQL.
async function call(sql, params = []) {
  const { rows } = await pool.query(sql, params);
  return rows;
}

module.exports = { pool, call };
