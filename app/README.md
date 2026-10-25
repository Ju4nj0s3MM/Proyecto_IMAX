# App (GUI de soporte) — Proyecto IMAX

Interfaz **funcional y simple** en **HTML + JavaScript** con un servidor **Node.js + Express** que llama a las funciones SQL de PostgreSQL. La lógica de negocio vive en la base de datos; la app solo la invoca y muestra el resultado.

## Arranque rápido (sin necesitar la BD)
```bash
cd app
npm install
cp .env.example .env      # MOCK=true y AUTH_DEV_BYPASS=true vienen activados
npm run dev               # abre http://localhost:3000
```
En el login usa **"Entrar como rol"** para probar cada perfil (cliente, taquillero, operador_sala, contador, administrador).

## Pasar a la BD real
1. Levantar PostgreSQL y cargar `database/ddl/ddls.sql` + `database/seeds/seeds.sql`
2. En `.env`: `MOCK=false`, `AUTH_DEV_BYPASS=false` y las variables `PG*`.
3. Cada ruta llama a la función SQL del contrato (ver tabla). Si la función aún no existe, la ruta devolverá error: es la señal de qué falta.

## Estructura y dueños (cada quien edita SOLO lo suyo)

| Módulo | Dueño | Backend | Páginas |
|---|---|---|---|
| A. Catálogo | Mati | `src/routes/catalogo.js` | `public/catalogo/*`, `public/dashboard.html` |
| B. Venta | Juanjo | `src/routes/venta.js` | `public/venta/*` |
| C. Seguridad | Brandon | `src/routes/seguridad.js` | `public/seguridad/*`, `public/login.html` |
| Compartido | Mati (base) | `server.js`, `src/db.js`, `src/auth.js`, `src/mock.js` | `public/js/*`, `public/css/styles.css`, `public/index.html` |

Archivos compartidos: se cambian con aviso al grupo para no pisarse. El menú por rol está en `public/js/nav.js`: cada dueño agrega ahí sus enlaces.

## Contrato API ↔ función SQL

| Endpoint | Función SQL | Dueño |
|---|---|---|
| `GET /api/catalogo/cartelera?cine&fecha&genero` | `fn_listar_cartelera` | Mati |
| `POST /api/catalogo/total` | `fn_calcular_total` | Mati |
| `GET /api/venta/funciones/:id/asientos` | `fn_mapa_asientos` | Juanjo |
| `POST /api/venta/reservas` | `fn_bloquear_asientos` | Juanjo |
| `POST /api/venta/pagos` | `fn_confirmar_pago` | Juanjo |
| `GET /api/venta/mis-boletos` | `fn_mis_boletos` | Juanjo |
| `POST /api/seguridad/login` | `fn_autenticar(email, password)` → `usuario_id, nombre, roles[]` | Brandon |
| `POST /api/seguridad/checkin` | `fn_validar_entrada` → `ok, mensaje` | Brandon |
| `POST /api/seguridad/reembolsos` | `fn_reembolsar` | Brandon |

**Forma de las respuestas** (la BD debe devolver estas columnas; `src/mock.js` tiene ejemplos):
- Cartelera: `funcion_id, titulo, sinopsis, clasificacion, genero, inicio, cine, ubicacion, sala`
- Mapa de asientos: `asiento_id, fila, numero, zona, estado` (`DISPONIBLE`, `BLOQUEADO`, `VENDIDO`)
- Reserva: `reserva_id, expira_en`
- Mis boletos: `boleto_id, codigo_qr, titulo, inicio, sala, fila, numero, estado`
- Check-in: `ok, mensaje`

Si una función SQL devuelve otras columnas, se ajusta la página correspondiente y esta tabla.

## Reglas
- **RN-09:** nunca enviar ni guardar número de tarjeta/CVV. `POST /api/venta/pagos` rechaza esos campos.
- **RN-17:** el control de roles se aplica en el **backend** (`requireRole`), no solo ocultando botones.
- El `usuario_id` y el `admin_id` salen de la **sesión**, nunca del body.
- No poner reglas de negocio en JavaScript: van en funciones SQL.
- Colores del mapa: verde disponible, gris ocupado, amarillo bloqueado, azul seleccionado.

## Cómo agregar una pantalla
1. Crear `public/<modulo>/pantalla.html` copiando una existente.
2. Incluir `api.js` y `nav.js` (con `data-auth="required"` y `data-roles="..."` si es privada).
3. Agregar el enlace en el menú de `nav.js`.
4. Si necesita datos nuevos: endpoint en la ruta de tu módulo (+ respuesta de ejemplo en `mock.js`).
