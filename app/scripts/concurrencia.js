// Prueba de concurrencia del módulo de venta.
// Uso (desde app/):  node scripts/concurrencia.js [hilos] [funcion_id] [asiento_id]
// Necesita la base con los DDL y el seed del catálogo cargados, y el .env con la conexión.
require('dotenv').config();
const { Pool } = require('pg');

const hilos = Number(process.argv[2]) || 30;
const funcion = Number(process.argv[3]) || 3;
const asiento = Number(process.argv[4]) || 70;
const pool = new Pool({ max: hilos });

async function limpiar() {
  // deja el asiento libre para poder repetir la prueba
  await pool.query(`update reserva_asiento set estado = 'LIBERADO'
                    where funcion_id = $1 and asiento_id = $2 and estado = 'BLOQUEADO'`, [funcion, asiento]);
  await pool.query(`update orden set estado = 'CANCELADA'
                    where funcion_id = $1 and estado = 'PENDIENTE'
                      and not exists (select 1 from reserva_asiento r where r.orden_id = orden.id and r.estado = 'BLOQUEADO')`, [funcion]);
}

// Prueba 1: muchos clientes intentan bloquear el mismo asiento a la vez
async function pruebaBloqueo() {
  await limpiar();
  const clientes = await Promise.all(Array.from({ length: hilos }, () => pool.connect()));
  let listos = 0;
  let abrir;
  const puerta = new Promise(r => (abrir = r));

  const intentos = clientes.map(async (c, i) => {
    const usuario = (i % 5) + 1;               // usuarios 1 a 5 del seed
    listos++;
    if (listos === hilos) abrir();             // cuando todos están listos, salen juntos
    await puerta;
    try {
      await c.query('select * from fn_bloquear_asientos($1, $2, $3::bigint[])', [usuario, funcion, [asiento]]);
      return { ok: true };
    } catch (e) {
      return { ok: false, error: e.message };
    }
  });

  const resultados = await Promise.all(intentos);
  clientes.forEach(c => c.release());

  const ganadores = resultados.filter(r => r.ok).length;
  const errores = {};
  resultados.filter(r => !r.ok).forEach(r => (errores[r.error] = (errores[r.error] || 0) + 1));

  const { rows } = await pool.query(
    `select count(*) as activas from reserva_asiento
     where funcion_id = $1 and asiento_id = $2 and estado in ('BLOQUEADO','VENDIDO')`, [funcion, asiento]);

  console.log(`Prueba 1: ${hilos} clientes bloquean el asiento ${asiento} de la función ${funcion} al mismo tiempo`);
  console.log(`  bloqueos exitosos: ${ganadores}  (esperado: 1)`);
  Object.entries(errores).forEach(([m, n]) => console.log(`  rechazados (${n}): ${m}`));
  console.log(`  reservas activas en la base: ${rows[0].activas}  (esperado: 1)`);
  return ganadores === 1 && Number(rows[0].activas) === 1;
}

// Prueba 2: el mismo pago enviado varias veces a la vez (doble clic)
async function pruebaDoblePago() {
  await limpiar();
  const { rows } = await pool.query('select * from fn_bloquear_asientos($1, $2, $3::bigint[])', [1, funcion, [asiento]]);
  const orden = rows[0].reserva_id;
  await pool.query('select * from fn_asignar_tipos($1, 1, $2::bigint[], $3::bigint[])', [orden, [asiento], [1]]);

  const veces = 10;
  const clientes = await Promise.all(Array.from({ length: veces }, () => pool.connect()));
  const resultados = await Promise.all(clientes.map(async c => {
    try {
      await c.query(`select * from fn_confirmar_pago($1, 1, 'TARJETA_SIMULADA', 'APROBADO')`, [orden]);
      return true;
    } catch (e) {
      return false;
    }
  }));
  clientes.forEach(c => c.release());

  const { rows: pagos } = await pool.query(`select count(*) as n from pago where orden_id = $1 and resultado = 'APROBADO'`, [orden]);
  const { rows: boletos } = await pool.query('select count(*) as n from boleto where orden_id = $1', [orden]);
  console.log(`Prueba 2: ${veces} envíos simultáneos del pago de la orden ${orden}`);
  console.log(`  pagos aceptados: ${resultados.filter(Boolean).length}  (esperado: 1)`);
  console.log(`  pagos aprobados guardados: ${pagos[0].n}  (esperado: 1)`);
  console.log(`  boletos emitidos: ${boletos[0].n}  (esperado: 1)`);

  // el asiento de la prueba 2 queda vendido (la bitácora no se puede borrar); para repetir usar otro asiento
  return resultados.filter(Boolean).length === 1 && Number(pagos[0].n) === 1 && Number(boletos[0].n) === 1;
}

(async () => {
  try {
    const a = await pruebaBloqueo();
    const b = await pruebaDoblePago();
    console.log(a && b ? '\nRESULTADO: FUNCIONA (sin doble venta)' : '\nRESULTADO: ERROR');
    process.exitCode = a && b ? 0 : 1;
  } catch (e) {
    console.error('Error en la prueba:', e.message);
    process.exitCode = 1;
  } finally {
    await pool.end();
  }
})();