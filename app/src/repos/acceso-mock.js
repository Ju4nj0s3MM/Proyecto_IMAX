// MÓDULO C · Check-in, reembolsos y auditoría — versión en memoria (MOCK=true), misma interfaz que acceso-sql.js.
const ahora = () => new Date().toISOString();

const puertas = [
  { id: 1, nombre: 'Tótem 1', sala: 'Sala 1', cine: 'IMAX San José' },
  { id: 2, nombre: 'Tótem 1', sala: 'Sala 2', cine: 'IMAX San José' }
];
const accesos = [];
const bitacora = [
  { fecha: ahora(), usuario_id: 5, usuario: 'Admin IMAX', rol: 'administrador', operacion: 'cortesia', ip: '127.0.0.1', motivo: 'Cortesía a prensa' }
];
const boletos = {
  'IMAX-MOCK-0001': { id: 1, codigo_qr: 'IMAX-MOCK-0001', estado: 'EMITIDO', titulo: 'Dune: Parte Tres', asiento: 'A1', monto: 9.25 }
};

module.exports = {
  async puertas() { return puertas; },

  async accesosRecientes(limite = 15) { return accesos.slice(0, limite); },

  // Solo en modo simulado: la BD real registra la lectura dentro de fn_validar_entrada
  registrarLectura(codigo, puertaId, r) {
    const p = puertas.find(x => x.id === Number(puertaId));
    accesos.unshift({ fecha: ahora(), codigo_qr: codigo, puerta: p ? p.nombre : null,
                      resultado: r.ok ? 'EXITOSO' : 'RECHAZADO', motivo: r.mensaje });
  },

  async buscarBoleto(q) {
    const b = Object.values(boletos).find(x => x.codigo_qr === q || String(x.id) === q);
    return b ? { ...b, inicio: ahora() } : null;
  },

  async reembolsar(boletoId, adminId, motivo) {
    const b = Object.values(boletos).find(x => x.id === Number(boletoId));
    if (!b) return { ok: false, mensaje: 'Boleto inexistente' };
    if (b.estado === 'ANULADO') return { ok: false, mensaje: 'La entrada ya está anulada' };
    if (!motivo || motivo.trim().length < 5) return { ok: false, mensaje: 'Indique el motivo del reembolso (mínimo 5 caracteres)' };
    b.estado = 'ANULADO';
    bitacora.unshift({ fecha: ahora(), usuario_id: adminId, usuario: 'Administrador (mock)', rol: 'administrador',
                       operacion: 'reembolso_forzado', ip: '127.0.0.1', motivo: motivo.trim() });
    return { ok: true, mensaje: 'Reembolso registrado por ' + b.monto };
  },

  async auditoria(limite = 100) { return bitacora.slice(0, limite); },

  async resumenAuditoria() {
    const por = new Map();
    for (const o of bitacora) {
      const r = por.get(o.usuario_id) || { usuario_id: o.usuario_id, administrador: o.usuario, total_operaciones: 0,
        cortesias: 0, reembolsos_forzados: 0, otras_modificaciones: 0, ultima_operacion: o.fecha };
      r.total_operaciones++;
      if (o.operacion === 'cortesia') r.cortesias++;
      else if (o.operacion === 'reembolso_forzado') r.reembolsos_forzados++;
      else r.otras_modificaciones++;
      por.set(o.usuario_id, r);
    }
    return [...por.values()];
  }
};