// MÓDULO A · Catálogo — acceso a PostgreSQL para el panel de administración.
// Tablas de database/ddl/01_catalogo.sql: cine, sala, zona_asiento, asiento, clasificacion, genero, pelicula, pelicula_genero.
// Los nombres de tabla/columna salen SOLO de RECURSOS (lista blanca); los valores siempre van parametrizados.
const { pool } = require('../db');

const RECURSOS = {
  cines: {
    tabla: 'cine',
    cols: ['nombre', 'direccion', 'ciudad', 'pais', 'latitud', 'longitud', 'activo'],
    select: `select c.*, (select count(*) from sala s where s.cine_id = c.id)::int as salas
               from cine c order by c.pais, c.ciudad, c.nombre`
  },
  salas: {
    tabla: 'sala',
    cols: ['cine_id', 'nombre', 'capacidad', 'minutos_limpieza', 'activa'],
    select: `select s.*, c.nombre as cine, c.ciudad,
                    (select count(*) from asiento a where a.sala_id = s.id and a.activo)::int as asientos_activos,
                    (select count(*) from asiento a where a.sala_id = s.id)::int as asientos_total
               from sala s join cine c on c.id = s.cine_id
              order by c.nombre, s.nombre`
  },
  zonas: {
    tabla: 'zona_asiento',
    cols: ['nombre', 'descripcion'],
    select: `select z.*, (select count(*) from asiento a where a.zona_asiento_id = z.id)::int as asientos
               from zona_asiento z order by z.nombre`
  },
  clasificaciones: {
    tabla: 'clasificacion',
    cols: ['codigo', 'descripcion', 'edad_minima'],
    select: 'select * from clasificacion order by edad_minima, codigo'
  },
  generos: {
    tabla: 'genero',
    cols: ['nombre'],
    select: `select g.*, (select count(*) from pelicula_genero pg where pg.genero_id = g.id)::int as peliculas
               from genero g order by g.nombre`
    },
  // fin y fin_limpieza los calcula el trigger trg_funcion_calcular_fin; el traslape lo impide ex_funcion_sin_traslape
  funciones: {
    tabla: 'funcion',
    cols: ['pelicula_id', 'sala_id', 'inicio', 'estado'],
    select: `select f.*, p.titulo, p.duracion_min, s.nombre as sala, s.minutos_limpieza, c.nombre as cine, c.ciudad
               from funcion f
               join pelicula p on p.id = f.pelicula_id
               join sala s on s.id = f.sala_id
               join cine c on c.id = s.cine_id
              order by f.inicio desc, c.nombre, s.nombre`
  },
  tipos: {
    tabla: 'tipo_entrada',
    cols: ['nombre', 'descripcion', 'requiere_documento'],
    select: `select t.*, (select count(*) from tarifa x where x.tipo_entrada_id = t.id)::int as tarifas
               from tipo_entrada t order by t.nombre`
  },
  tarifas: {
    tabla: 'tarifa',
    cols: ['tipo_entrada_id', 'zona_asiento_id', 'dia_semana', 'hora_desde', 'hora_hasta', 'precio', 'cargo_servicio', 'activa'],
    select: `select t.*, te.nombre as tipo_entrada, z.nombre as zona
               from tarifa t
               join tipo_entrada te on te.id = t.tipo_entrada_id
               join zona_asiento z on z.id = t.zona_asiento_id
              order by te.nombre, z.nombre, coalesce(t.dia_semana, 0), t.hora_desde`
  },
  promociones: {
    tabla: 'promocion',
    cols: ['nombre', 'tipo', 'dia_semana', 'requiere_cantidad_par', 'tipo_entrada_id', 'fecha_desde', 'fecha_hasta', 'activa'],
    select: `select p.*, te.nombre as tipo_entrada
               from promocion p left join tipo_entrada te on te.id = p.tipo_entrada_id
              order by p.activa desc, p.nombre`
  }
};

const PELICULA_COLS = ['titulo', 'sinopsis', 'duracion_min', 'poster_url', 'clasificacion_id', 'fecha_estreno', 'activa'];

// Solo columnas permitidas; '' se guarda como NULL.
function limpiar(body, cols) {
  const out = {};
  for (const c of cols) if (body[c] !== undefined) out[c] = body[c] === '' ? null : body[c];
  return out;
}

function noEncontrado() { const e = new Error('Registro no encontrado'); e.status = 404; return e; }

async function insertar(db, tabla, data) {
  const k = Object.keys(data);
  const { rows } = await db.query(
    `insert into ${tabla} (${k.join(', ')}) values (${k.map((_, i) => '$' + (i + 1)).join(', ')}) returning *`,
    Object.values(data));
  return rows[0];
}

async function actualizar(db, tabla, id, data) {
  const k = Object.keys(data);
  if (!k.length) { const { rows } = await db.query(`select * from ${tabla} where id = $1`, [id]); if (!rows[0]) throw noEncontrado(); return rows[0]; }
  const { rows } = await db.query(
    `update ${tabla} set ${k.map((c, i) => `${c} = $${i + 1}`).join(', ')} where id = $${k.length + 1} returning *`,
    [...Object.values(data), id]);
  if (!rows[0]) throw noEncontrado();
  return rows[0];
}

async function enTransaccion(fn) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const r = await fn(client);
    await client.query('COMMIT');
    return r;
  } catch (e) {
    await client.query('ROLLBACK');
    throw e;
  } finally {
    client.release();
  }
}

module.exports = {
  RECURSOS,

  // ---- CRUD genérico (cines, salas, zonas, clasificaciones, generos) ----
  async listar(nombre) {
    return (await pool.query(RECURSOS[nombre].select)).rows;
  },
  async crear(nombre, body) {
    const r = RECURSOS[nombre];
    return insertar(pool, r.tabla, limpiar(body, r.cols));
  },
  async editar(nombre, id, body) {
    const r = RECURSOS[nombre];
    return actualizar(pool, r.tabla, id, limpiar(body, r.cols));
  },
  async borrar(nombre, id) {
    const { rowCount } = await pool.query(`delete from ${RECURSOS[nombre].tabla} where id = $1`, [id]);
    if (!rowCount) throw noEncontrado();
  },

  // ---- Películas (con sus géneros en pelicula_genero, todo en una transacción) ----
  async listarPeliculas() {
    const { rows } = await pool.query(`
      select p.*, c.codigo as clasificacion,
             coalesce(array_agg(g.id order by g.nombre) filter (where g.id is not null), '{}') as generos_ids,
             coalesce(string_agg(g.nombre, ', ' order by g.nombre), '') as generos
        from pelicula p
        join clasificacion c on c.id = p.clasificacion_id
        left join pelicula_genero pg on pg.pelicula_id = p.id
        left join genero g on g.id = pg.genero_id
       group by p.id, c.codigo
       order by p.activa desc, p.titulo`);
    return rows;
  },
  async crearPelicula(body) {
    return enTransaccion(async db => {
      const p = await insertar(db, 'pelicula', limpiar(body, PELICULA_COLS));
      await guardarGeneros(db, p.id, body.generos);
      return p;
    });
  },
  async editarPelicula(id, body) {
    return enTransaccion(async db => {
      const p = await actualizar(db, 'pelicula', id, limpiar(body, PELICULA_COLS));
      if (Array.isArray(body.generos)) {
        await db.query('delete from pelicula_genero where pelicula_id = $1', [id]);
        await guardarGeneros(db, id, body.generos);
      }
      return p;
    });
  },
  async borrarPelicula(id) {
    const { rowCount } = await pool.query('delete from pelicula where id = $1', [id]);   // pelicula_genero cae en cascada
    if (!rowCount) throw noEncontrado();
  },

  // ---- Asientos de una sala ----
  async asientos(salaId) {
    const { rows } = await pool.query(`
      select a.id, a.fila, a.numero, a.activo, a.zona_asiento_id, z.nombre as zona
        from asiento a join zona_asiento z on z.id = a.zona_asiento_id
       where a.sala_id = $1
       order by length(a.fila), a.fila, a.numero`, [salaId]);
    return rows;
  },
  // Genera la cuadrícula filas × asientos_por_fila. zonas[i] = zona de la fila i (A, B, C...).
  async generarAsientos(salaId, { filas, por_fila, zonas, reemplazar }) {
    return enTransaccion(async db => {
      const s = await db.query('select id from sala where id = $1 for update', [salaId]);
      if (!s.rows[0]) throw noEncontrado();
      if (reemplazar) await db.query('delete from asiento where sala_id = $1', [salaId]);
      const { rowCount } = await db.query(`
        insert into asiento (sala_id, zona_asiento_id, fila, numero)
        select $1, ($4::bigint[])[f], chr(64 + f), n
          from generate_series(1, $2::int) f, generate_series(1, $3::int) n`,
        [salaId, filas, por_fila, zonas]);
      return { insertados: rowCount };
    });
  },
  async editarAsiento(id, body) {
    return actualizar(pool, 'asiento', id, limpiar(body, ['zona_asiento_id', 'activo']));
  },
  async editarAsientos(ids, body) {
    const data = limpiar(body, ['zona_asiento_id', 'activo']);
    const k = Object.keys(data);
    if (!k.length || !ids.length) return { actualizados: 0 };
    const { rowCount } = await pool.query(
      `update asiento set ${k.map((c, i) => `${c} = $${i + 1}`).join(', ')} where id = any($${k.length + 1}::bigint[])`,
      [...Object.values(data), ids]);
    return { actualizados: rowCount };
  }
};

async function guardarGeneros(db, peliculaId, generos) {
  if (!Array.isArray(generos) || !generos.length) return;
  await db.query(
    'insert into pelicula_genero (pelicula_id, genero_id) select $1, unnest($2::bigint[]) on conflict do nothing',
    [peliculaId, generos]);
}
