const { Pool } = require('pg');
const pool = new Pool();   // usa PGHOST, PGUSER, PGPASSWORD, PGDATABASE, PGPORT del .env

// Ejecuta SQL parametrizado y devuelve las filas. La lógica de negocio vive en las funciones SQL.
async function call(sql, params = []) {
  const { rows } = await pool.query(sql, params);
  return rows;
}

module.exports = { pool, call };
