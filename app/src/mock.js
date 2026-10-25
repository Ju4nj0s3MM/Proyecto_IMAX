// Datos de ejemplo para avanzar la GUI sin base de datos (MOCK=true). Mantener la misma FORMA que devolverán las funciones SQL.
const estados = ['DISPONIBLE', 'DISPONIBLE', 'DISPONIBLE', 'VENDIDO', 'BLOQUEADO'];

module.exports = {
  cartelera: [
    { funcion_id: 1, titulo: 'Dune: Parte Tres', sinopsis: 'La saga continúa en Arrakis.', clasificacion: 'PG-13', genero: 'Ciencia ficción',
      inicio: new Date(Date.now() + 86400000).toISOString(), cine: 'IMAX Los Ángeles', ubicacion: 'Los Ángeles, CA', sala: 'Sala 1' },
    { funcion_id: 2, titulo: 'Océano Profundo', sinopsis: 'Documental inmersivo.', clasificacion: 'G', genero: 'Documental',
      inicio: new Date(Date.now() + 2 * 86400000).toISOString(), cine: 'IMAX San José', ubicacion: 'San José, CR', sala: 'Sala 2' }
  ],
  mapa(funcionId) {
    const filas = 'ABCDEFGH'.split('');
    const out = [];
    let id = 1;
    filas.forEach((f, i) => {
      for (let n = 1; n <= 10; n++) {
        out.push({ asiento_id: id++, fila: f, numero: n, zona: i < 3 ? 'VIP' : 'General',
                   estado: estados[(i * 7 + n * 3) % estados.length] });
      }
    });
    return out;
  },
  reserva: () => ({ reserva_id: 1, expira_en: new Date(Date.now() + 120000).toISOString() }),
  orden: () => ({ orden_id: 1, estado: 'PENDIENTE', total: 0, titulo: 'Dune: Parte Tres', sala: 'Sala 1', inicio: new Date(Date.now() + 86400000).toISOString(),
                  expira_en: new Date(Date.now() + 120000).toISOString(),
                  asientos: [{ asiento_id: 5, fila: 'A', numero: 5, precio: null }, { asiento_id: 6, fila: 'A', numero: 6, precio: null }] }),
  pago: ({ resultado }) => resultado === 'APROBADO'
    ? { resultado: 'APROBADO', boletos: [{ boleto_id: 1, codigo_qr: 'IMAX-MOCK-0001' }] }
    : { resultado: 'RECHAZADO', mensaje: 'Pago rechazado: los asientos fueron liberados' },
  boletos: [{ boleto_id: 1, codigo_qr: 'IMAX-MOCK-0001', titulo: 'Dune: Parte Tres', inicio: new Date(Date.now() + 86400000).toISOString(),
              sala: 'Sala 1', fila: 'A', numero: 5, estado: 'EMITIDO' }],
  checkin: codigo => codigo === 'IMAX-MOCK-0001'
    ? { ok: true, mensaje: 'Entrada válida. Bienvenido.' }
    : { ok: false, mensaje: 'Entrada ya utilizada' },
  auditoria: [{ fecha: new Date().toISOString(), usuario_id: 1, rol: 'administrador', operacion: 'REEMBOLSO_FORZADO', ip: '127.0.0.1' }]
};