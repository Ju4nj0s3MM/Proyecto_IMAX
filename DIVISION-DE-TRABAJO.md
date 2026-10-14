# Proyecto IMAX — División de trabajo v2 (Mati · Brandon · Juanjo)

> **Cambio respecto a la v1:** como es un curso de **Bases de Datos**, cada integrante implementa **un módulo de base de datos propio** (diseño, DDL, lógica, seeds, consultas, índices y `EXPLAIN ANALYZE`) además de una parte de la GUI y de la documentación. Juanjo conserva lo más difícil: el módulo de venta y concurrencia y la integración del modelo global.
>
> **Cómo usar este documento:** cada integrante lee la Parte 1 (contexto común), la Parte 2 (módulos y convenciones) y la sección de su nombre. Si trabaja con una IA, debe pegarle **Parte 1 + Parte 2 + su sección + Parte 7 (contratos)**.
> Repo: https://github.com/Ju4nj0s3MM/Proyecto_IMAX · Se guarda como `docs/DIVISION-DE-TRABAJO.md`.

---

# PARTE 0 — Resumen del reparto

Se divide el sistema en **tres módulos verticales**. Cada dueño hace la BD, la parte de la GUI y la documentación de su módulo.

| | **Mati** | **Juanjo** | **Brandon** |
|---|---|---|---|
| **Módulo de BD** | **A. Catálogo, salas, programación y tarifas** | **B. Venta, bloqueo de asientos, pago y boletos (concurrencia)** | **C. Usuarios, roles/RBAC, acceso en puerta, reembolsos y auditoría administrativa** |
| **Tablas principales** | cine, sala, zona, asiento, película, género, clasificación, función, tipo de entrada, tarifa, promoción | reserva de asientos, orden, detalle, pago, método de pago, boleto (QR), `transaccion_log`, `asiento_auditoria_log` | usuario, rol, puerta, reembolso, `acceso_puerta_log`, `admin_operacion_audit` |
| **Lógica de BD** | `fn_listar_cartelera`, `fn_calcular_total`, no-traslape de funciones, trigger RN-18 | bloqueo 2 min, anti doble venta, confirmar pago ACID, compensación, emisión de QR | validar entrada (RN-14/15/16), reembolso (RN-19), triggers de auditoría (RN-20), roles y permisos (RN-17) |
| **Consulta analítica** | Top 5 funciones de la semana | Ocupación y recaudación por función; métodos de pago (%) | Auditoría de operaciones críticas del último mes |
| **Prueba obligatoria** | `EXPLAIN ANALYZE` de cartelera y top 5 | **Concurrencia 20–50 hilos sobre el mismo asiento** + `EXPLAIN ANALYZE` | Doble escaneo concurrente del mismo QR + `EXPLAIN ANALYZE` |
| **GUI** | Esqueleto de la app, cartelera con filtros, panel admin de catálogo, dashboard | Mapa interactivo de sala, pago simulado, confirmación con QR, "mis entradas" | Login y menús por rol, check-in en puerta, reembolsos, visor de auditoría |
| **Documentación** | Factibilidad **económica** (cloud, 3 años, ROI), **dimensionamiento de almacenamiento**, requisitos (Fase 2) | **Diseño integrado** (DER global, modelo relacional, físico), pruebas de concurrencia | Dictamen de rechazo, **riesgos**, factibilidad técnica, **Fase 5** (RPO/RTO/SLA/backups), documento final |
| **Carga / dificultad** | ~30% · Media | ~40% · **Alta** | ~30% · Media-Alta |

**Por qué Juanjo tiene lo más difícil:** el módulo B concentra la concurrencia, el anti doble venta y las transacciones ACID (lo que la pauta califica con más severidad: "fallos de concurrencia" = *Deficiente*), y además integra el modelo global de los tres módulos.

**Ramas (una por módulo) y archivos propios**

| Integrante | Rama | Archivos propios |
|---|---|---|
| Mati | `catalogo` | `database/01_catalogo_*.sql`, `05_catalogo_*`, `09_*catalogo*`, `app/` (esqueleto + sus pantallas), `docs/01b-*`, `01c-*`, `02-requisitos.md`, `docs/03-diseno/modulo-catalogo.md`, `docs/04-pruebas/catalogo.md` |
| Juanjo | `venta` | `database/03_venta_*.sql`, `06_venta_*`, `11_*venta*`, `database/pruebas/venta/`, `app/` (sus pantallas), `docs/03-diseno/integrado.md` y `modulo-venta.md`, `docs/04-pruebas/venta.md` |
| Brandon | `seguridad` | `database/02_*`, `04_*`, `07_*`, `08_*`, `10_*`, `database/pruebas/seguridad/`, `app/` (sus pantallas), `docs/01a-*`, `05-operacion.md`, `rbac-matriz.md`, `docs/03-diseno/modulo-seguridad.md`, `docs/04-pruebas/seguridad.md`, `README.md` |

Flujo Git: trabajar en tu rama → `git pull origin main` antes de empezar → PR a `main` revisado por **otro** integrante. Lo que no está en Git no se revisa.

---

## PARTE 0.1 — Cómo ingresar a la página (2 pasos)

La base de la GUI ya está creada en `app/` (HTML + JavaScript, con un servidor Node.js + Express). Requisito: **Node.js 18 o superior** (verificar con `node -v`).

**Paso 1.** Descargar lo último e instalar. En una terminal, en la **raíz del repo**:
```bash
git pull origin main
npm install
```
(`npm install` instala todo y crea el archivo `.env` solo.)

**Paso 2.** Arrancar y entrar:
```bash
npm run dev
```
Abrir **http://localhost:3000** → *Iniciar sesión* → **"Entrar como rol"** y elegir `cliente`, `taquillero`, `operador_sala`, `contador` o `administrador` para ver las pantallas de cada perfil.

**Notas**
- Funciona **sin base de datos** (modo simulado, `MOCK=true`): el mapa, la cartelera y los pagos usan datos de ejemplo. Cuando existan los scripts SQL, poner `MOCK=false` en `app/.env` y los datos `PG*` de la BD.
- **Windows/PowerShell:** si sale "la ejecución de scripts está deshabilitada", ejecutar una sola vez `Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned` y reabrir la terminal (o escribir `npm.cmd` en lugar de `npm`).
- Si sale "Could not read package.json": la terminal está en la carpeta equivocada. Debe estar en la carpeta donde se ve `package.json` (la raíz del repo, o `app/`).
- Detalle de endpoints, formas de respuesta y cómo agregar pantallas: `app/README.md`.

**Qué archivos de la app edita cada quien**

| Integrante | Backend | Páginas |
|---|---|---|
| Mati | `app/src/routes/catalogo.js` | `app/public/catalogo/*`, `app/public/dashboard.html` |
| Juanjo | `app/src/routes/venta.js` | `app/public/venta/*` |
| Brandon | `app/src/routes/seguridad.js` | `app/public/seguridad/*`, `app/public/login.html` |

Archivos compartidos (`server.js`, `src/db.js`, `src/auth.js`, `src/mock.js`, `public/js/*`, `public/css/styles.css`): se cambian avisando al grupo. El menú por rol está en `app/public/js/nav.js`: cada quien agrega ahí sus enlaces.

---

# PARTE 1 — Contexto completo del proyecto (extraído de la especificación)

## 1.1 Qué es
Curso de Bases de Datos, Proyecto 2: **"Licitación para el Ecosistema Digital de Cines IMAX"**. IMAX abrió una licitación global para modernizar y escalar su plataforma de venta de entradas. El equipo es finalista y debe proponer una solución integral que cubra: exploración de cartelera, selección interactiva de asientos en tiempo real, pagos seguros, emisión de QR únicos, control de acceso en puerta y panel de administración.

**Objetivo de la propuesta:** modelo operativo y funcional completo con mitigación de riesgos (p. ej. **doble venta de asientos**), cumplimiento de **PCI-DSS** y buena experiencia de usuario.

**NOTA MUY IMPORTANTE:** es un curso de bases de datos. La interfaz gráfica es **estrictamente funcional y de soporte** para demostrar los flujos de negocio. El peso del proyecto está en la base de datos. **Los pagos se simulan** (no se conecta pasarela real; basta una notificación y el comportamiento esperado en la BD).

## 1.2 Escenario legado (lo que hay que rechazar con un dictamen técnico)
El proveedor saliente propuso, para un estreno mundial con **8 millones de usuarios concurrentes** en el primer minuto:
1. Una sola instancia de **Microsoft Access o SQLite** en un PC de escritorio Intel Core i3 de 2012 bajo el escritorio del gerente de sistemas en Los Ángeles.
2. **Sin cloud**; todo el tráfico global por una conexión residencial de fibra de **50 Mbps** con Wi-Fi 2.4 GHz y un extensor barato.
3. Compras de 8 millones de usuarios guardadas en una **hoja de cálculo compartida de Google Drive** donde cada cliente "escribe a mano" su nombre en el asiento.
4. Pagos: formulario estático que envía **números completos de tarjeta y CVV a un chat de WhatsApp** corporativo; un pasante los pasa a mano por un datáfono.
5. Disaster Recovery: si el PC se apaga, **"reiniciarla y cruzar los dedos"**.
6. Dimensionamiento que se debe calcular para la nueva arquitectura: **8M usuarios concurrentes**, pico de **50,000 TPS** (compras + lecturas) durante los primeros **10 minutos** de taquilla; almacenamiento para **500 títulos activos en 1,500 salas**, **15 millones de boletos mensuales**, y **logs de auditoría retenidos mínimo 5 años** (transacciones, bloqueos de asientos, accesos en puerta).

El comité lo calificó como "suicidio corporativo": hay que redactar un **dictamen técnico de rechazo** y una **propuesta de factibilidad real y escalable**.

## 1.3 Dinámica del negocio

**Flujo de compra del usuario:** (1) Explorar cartelera → (2) Seleccionar función y asientos en mapa interactivo → (3) Tipos de entrada y tarifas (adulto, niño, tercera edad, estudiante, 2x1) → (4) Pasarela de pago → (5) Emisión de entrada con **QR** guardado en la app.

**Control de acceso:** en la puerta se escanea el QR; el sistema verifica en la BD que el ticket sea válido, de la función correcta y **no usado antes**.

**Backend:** al elegir un asiento se **bloquea temporalmente (2 min)** mientras se paga; si expira, vuelve a estar disponible. La BD debe ser transaccional **ACID**: dinero y estado del asiento cambian a la vez (si el pago falla, el asiento se libera).

**Panel de administración:** configuración de funciones/salas/precios; reportes (ocupación, ingresos por función, métodos de pago, tendencias); reembolsos y cancelaciones.

## 1.4 Reglas de negocio (RN)

**Catálogo y cartelera**
- **RN-01** Solo mostrar funciones/películas **activas** y con inicio **futuro**.
- **RN-02** Toda función listada incluye título, sinopsis, clasificación de edad, horarios y ubicación exacta de la sala.

**Selección de función y asientos**
- **RN-03** El mapa refleja en tiempo real el estado de cada asiento (disponible, ocupado, reservado, bloqueado).
- **RN-04** Máximo de asientos por transacción (ej. 6 o 10).
- **RN-05** Bloqueo temporal (ej. 2 min) para ese usuario; si expira sin pago, se libera automáticamente.

**Tipos de entrada y tarifas**
- **RN-06** Tarifas especiales (niños, tercera edad, estudiantes) pueden validarse físicamente con documento en la puerta.
- **RN-07** Promociones (2x1) se aplican automáticamente según condiciones (n.º par de entradas de la misma categoría o días específicos).
- **RN-08** Total = suma exacta de tarifas de asientos, menos descuentos de promociones, más cargos por servicio si aplican.

**Pasarela de pago**
- **RN-09** Datos financieros procesados por pasarela externa certificada (PCI-DSS); **prohibido guardar datos sensibles de tarjeta (CVV, etc.) en la BD propia**.
- **RN-10** Pago rechazado → transacción cancelada, no se debita y los asientos se **liberan inmediatamente**. (Pagos simulados.)

**Emisión de la entrada**
- **RN-11** **Ningún comprobante ni QR** se genera/envía antes de la aprobación del pago.
- **RN-12** Cada entrada tiene identificador único (QR/código de barras) asociado unívocamente a función, localidad y asiento.
- **RN-13** El comprobante queda accesible en el perfil de la app.

**Control de acceso**
- **RN-14** Cada QR se valida con éxito **una sola vez**; intentos posteriores se rechazan con **"Entrada ya utilizada"**.
- **RN-15** Rechazar entradas de otra función, fecha u hora.
- **RN-16** Ventana de tolerancia (ej. desde 30 min antes hasta 15 min después del inicio); fuera de ella se bloquea la lectura.

**Gestión del negocio**
- **RN-17** **RBAC**: solo perfiles autorizados (administradores, taquilleros, contabilidad) hacen acciones críticas (modificar precios, anular ventas, crear funciones).
- **RN-18** No se puede eliminar ni modificar el mapa de asientos de una sala si hay entradas vendidas/reservadas para funciones programadas.
- **RN-19** Anulación y reembolso solo bajo la política del cine (ej. hasta 2 horas antes de la función); libera el asiento automáticamente.
- **RN-20** Toda modificación manual de un administrador (cortesías, cambios de asiento, reembolsos forzados) queda en bitácora con fecha, hora e ID del admin. Persistencia y trazabilidad inalterable **mínimo 5 años**.

## 1.5 Logs de auditoría (5 años) — tablas separadas por dominio
Se recomienda **no mezclar** logs operativos masivos con la bitácora administrativa. Todas con **particionamiento por fecha** y respaldos con retención quinquenal.

| Tabla | Contenido |
|---|---|
| `transaccion_log` | Cada intento de pago, confirmación de pasarela, montos, impuestos y emisión de boletos |
| `asiento_auditoria_log` | Cuándo un asiento fue bloqueado, liberado por expiración (2 min) o comprado |
| `acceso_puerta_log` | Cada escaneo QR: timestamp, id del boleto, puerta/dispositivo, resultado (exitoso o rechazado por duplicidad/horario) |
| `admin_operacion_audit` | Operaciones manuales de admins: fecha, hora, **IP**, ID del rol y usuario responsable |

(La especificación dice "tres categorías" y luego lista cuatro; se implementan **las cuatro**.)

## 1.6 Matriz de roles (privilegio mínimo)

| Módulo | Cliente | Taquillero | Operador de Sala (Puerta) | Contador | Admin / Gerente |
|---|---|---|---|---|---|
| Catálogo y cartelera | Lectura (funciones activas) | Lectura | Lectura | Lectura | Lectura/Escritura (CRUD) |
| Selección de asientos y pago | Ejecución (compra online) | Ejecución (venta presencial) | Sin acceso | Sin acceso | Configuración de reglas y precios |
| Emisión y acceso (QR) | Lectura (sus propios QR) | Lectura (emitir boletos) | Ejecución (validar/escanear QR) | Sin acceso | Gestión de incidencias / reasignaciones |
| Reportes y finanzas | Sin acceso | Lectura (corte de caja propio) | Sin acceso | Lectura/Exportación (conciliación, ingresos) | Lectura total (métricas globales) |
| Configuración de salas y funciones | Sin acceso | Sin acceso | Sin acceso | Sin acceso | Lectura/Escritura (restringido por RN-18) |
| Auditoría y gestión de roles | Sin acceso | Sin acceso | Sin acceso | Sin acceso | Lectura total (bitácora y RBAC) |

## 1.7 Procesos de negocio
- **Gestión de cartelera y funciones:** alta/baja/modificación de películas con metadatos (sinopsis, clasificación, póster, duración); configuración de salas y asientos (platea, palcos, VIP) con capacidad; programación de funciones **sin traslapes** que impidan la limpieza de la sala; matriz de tarifas (día, horario, tipo de asiento, promociones).
- **Checkout:** búsqueda y filtrado (ubicación, fecha, género); bloqueo/reserva temporal; procesamiento de pago y compensación (libera asientos si falla); emisión y entrega digital del QR.
- **Acceso en sala:** validación de QR (autenticidad, vigencia, unicidad); gestión de incidencias (QR ilegible, rezagados fuera de tolerancia).
- **Gestión financiera:** conciliación bancaria; cancelaciones y reembolsos (totales o parciales); corte y liquidación (diario/semanal/mensual).
- **Administración y auditoría:** RBAC (asignar/revocar permisos) y bitácora de acciones sensibles.

## 1.8 Consultas analíticas mínimas (SQL obligatorio)
1. **Ocupación y recaudación por función:** % de asientos vendidos vs. capacidad de la sala e ingresos totales de una función.
2. **Top 5 de funciones más demandadas:** 5 películas/obras con más boletos vendidos en la **última semana** a nivel global.
3. **Métodos de pago preferidos:** reporte porcentual por pasarela/método de pago.
4. **Auditoría de operaciones críticas:** modificaciones manuales, cortesías o reembolsos del **último mes**, agrupados por ID de administrador.

## 1.9 Ciclo de vida de la BD (DBLC) — fases obligatorias

**Fase 1 — Factibilidad.** Técnica (¿el legado soporta picos?), económica y operativa (costos de infraestructura, almacenamiento, licencias, mantenimiento vs. ROI) y análisis de riesgos con **Matriz Única de Riesgo y Mitigación** en el formato:

| ID Riesgo | Descripción | Probabilidad (Baja/Media/Alta) | Impacto (Bajo/Medio/Crítico) | Estrategia de mitigación / Plan de respaldo (DRP) | RTO / RPO objetivo |
|---|---|---|---|---|---|
| R-01 | Ej: caída de la instancia principal de BD durante el estreno | Media | Crítico | Failover automático a réplica multirregión | RTO < 5 min / RPO ≈ 0 |

Debe incluir una **tabla de cálculo de almacenamiento** (GB/TB mensuales y acumulados a 5 años) con 1,500 salas, 500 títulos y 15M boletos/mes.

Análisis económico (reglas): proyección a **3 años** (CAPEX inicial + OPEX mensual); comparar **al menos dos nubes** (AWS vs Azure o Google Cloud) para: BD relacional administrada, almacenamiento masivo de logs a 5 años y balanceador/WAF; basarse en **calculadoras públicas de precios** o cotizaciones estándar, **citando fuente/enlace**, y justificar el costo mensual por millón de transacciones. *(La especificación trae un ejemplo referencial: AWS ≈ $24,000/mes vs Azure ≈ $22,850/mes; CAPEX $15,000; OPEX año 1 $274,200, año 2 $301,620 (+10%), año 3 $331,780; total a 3 años $922,600; ~45 TB acumulados; ~$0.0015 por boleto. Es solo ejemplo: hay que calcular y citar los propios.)*

**Fase 2 — Requisitos.** Requerimientos funcionales y no funcionales (cartelera, mapas en tiempo real, transacciones ACID, control de acceso, auditoría) y volúmenes esperados (concurrentes, TPS, histórico de boletos, registros de auditoría).

**Fase 3 — Diseño.** Conceptual: DER (Usuario, Película, Función, Sala, Asiento, Boleto, Transacción, Rol, Auditoría y cardinalidades). Lógico: normalización, PK/FK. Físico: SGBD (PostgreSQL), **índices** para búsqueda de asientos disponibles y filtrado de funciones, justificados con **`EXPLAIN ANALYZE`**, y particionamiento si se requiere.

**Fase 4 — Implementación y pruebas.**
- Scripts **DDL**, restricciones de integridad, **transacciones** (bloqueo temporal y pago atómicos), triggers/procedimientos.
- **Prueba de concurrencia obligatoria** con script automatizado o herramienta estándar (Python multihilo, JMeter, k6): **mínimo 20 a 50 solicitudes simultáneas idénticas** sobre el **mismo asiento exacto**; debe pasar **una sola** y el resto rechazadas por colisión de restricción o bloqueo transaccional.
- Doblemente: **`EXPLAIN ANALYZE` "antes y después"** de crear índices en las consultas más pesadas (disponibilidad de asientos, analíticas), mostrando la reducción de **Seq Scan → Index Scan** y del tiempo.
- La pauta evalúa que una **restricción de unicidad impida físicamente** dos inserciones del mismo asiento para la misma función, usando transacciones básicas `BEGIN/COMMIT/ROLLBACK` (sin exigir bloqueos explícitos complejos si no se vieron en el curso).

**Fase 5 — Operación y mantenimiento.** Backups automáticos, disaster recovery, privacidad de datos. Investigar y justificar por qué la propuesta cumple: **RPO ≤ 5 s (ideal 0)**, **RTO < 5 min**, **SLA 99.99%**, y definir la **frecuencia de respaldo aceptable**.

## 1.10 Entregables finales
1. **Documento Técnico de Arquitectura de Datos y Propuesta de Licitación:** dictamen de rechazo + propuesta (factibilidad técnica, económica, operativa, riesgos); requisitos y dimensionamiento; diseño conceptual/lógico/físico.
2. **Modelo relacional documentado** (representación gráfica).
3. **Interfaz gráfica** con: cartelera y exploración (sinopsis, clasificación, horarios filtrados por ubicación); **mapa interactivo de sala** (verde = disponible, gris = ocupado, amarillo = bloqueado temporalmente, azul = seleccionado por el usuario); módulo de pago (resumen, desglose de tarifas/2x1, campos de pago simulados); confirmación con boleto digital y QR; panel de administración (métricas en tiempo real, control de funciones, gestión de salas).
4. **Scripts SQL (DDL)** completos con restricciones, listos para auditar.
5. **Repositorio Git público**, con commits progresivos y estructurados; el enlace se entrega en **TecDigital**. **Lo que no está en el Git no se revisa.**

## 1.11 Pauta de revisión (demo en vivo o grabada)
1. **Cartelera y funciones:** alta de película con sinopsis/clasificación/duración/póster; asignar sala a función sin traslapes; matriz de precios por tipo de asiento o promoción.
2. **Checkout:** filtrar por ubicación/fecha/género; seleccionar asientos y ver que arranca el temporizador de bloqueo (2 min); pago simulado, y que **un fallo libera de inmediato los asientos**; QR y comprobante **solo tras pago exitoso**.
3. **Acceso en sala:** escaneo simulado; primer intento entra, **segundo se rechaza con "Entrada ya utilizada"**; rechazo por otra función o fuera de tolerancia.
4. **Financiero y analítico:** correr las 4 consultas SQL; mostrar `EXPLAIN ANALYZE` con uso real de índices.
5. **RBAC y auditoría:** taquillero/cliente **no** pueden entrar a configuración de salas o precios; toda alteración manual (reembolso forzado, cambio de asiento) queda en la tabla de auditoría con fecha, hora e ID del responsable.

**Criterio:** *Satisfactorio* = procesos fluidos desde la GUI, con integridad ACID y scripts SQL funcionales. *Deficiente* = fallos de concurrencia, **QR reutilizables**, o consultas analíticas con errores de sintaxis.

---

---

# PARTE 2 — Módulos, convenciones y archivos de base de datos (para los tres)

## 2.1 Sesión de diseño conjunta (obligatoria, 1–2 h, Etapa 1)
Antes de escribir DDL, los tres acuerdan en una reunión: (1) las convenciones de abajo, (2) las **tablas compartidas** y sus llaves (para que las FK entre módulos no se rompan) y (3) el contrato de funciones (Parte 7). Juanjo deja el resultado escrito en `docs/03-diseno/integrado.md`.

## 2.2 Convenciones de la BD
- PostgreSQL 16. Nombres en `snake_case` y en singular (`funcion`, `asiento`, `boleto`).
- PK numérica `id` (`bigint GENERATED ALWAYS AS IDENTITY`) salvo que se justifique otra; FK con el nombre `<tabla>_id`.
- Fechas/horas en `timestamptz`. Dinero en `numeric(12,2)`.
- Estados con `CHECK` o `ENUM` (documentar los valores en el DER).
- Cada script `.sql` se ejecuta sobre BD vacía y en orden numérico, sin errores.
- Prohibido guardar número de tarjeta o CVV (RN-09).

## 2.3 Dueños de tablas y dependencias entre módulos

| Módulo | Dueño | Tablas | Depende de |
|---|---|---|---|
| **A. Catálogo** | Mati | `cine`, `sala`, `zona_asiento`, `asiento`, `pelicula`, `genero`, `pelicula_genero`, `clasificacion`, `funcion`, `tipo_entrada`, `tarifa`, `promocion` | — (es la base de los demás) |
| **C-1. Usuarios y roles** | Brandon | `usuario`, `rol`, `usuario_rol` | — |
| **B. Venta** | Juanjo | `reserva`, `reserva_asiento`, `orden`, `orden_detalle`, `metodo_pago`, `pago`, `boleto`, `transaccion_log`, `asiento_auditoria_log` | A (`funcion`, `asiento`, `tipo_entrada`, `tarifa`) y C-1 (`usuario`) |
| **C-2. Acceso y auditoría** | Brandon | `puerta`, `acceso_puerta_log`, `reembolso`, `admin_operacion_audit` | B (`boleto`, `orden`), C-1 |

Los nombres de las tablas arriba son **propuestos**: se confirman en la sesión conjunta.

## 2.4 Orden de ejecución de los scripts (`database/`)

| N.º | Archivo | Dueño |
|---|---|---|
| 01 | `01_catalogo_schema.sql` | Mati |
| 02 | `02_seguridad_usuarios_schema.sql` | Brandon |
| 03 | `03_venta_schema.sql` (incluye logs particionados de venta) | Juanjo |
| 04 | `04_seguridad_acceso_schema.sql` (puerta, reembolso, 2 logs particionados) | Brandon |
| 05 | `05_catalogo_logica.sql` (funciones y triggers) | Mati |
| 06 | `06_venta_logica.sql` | Juanjo |
| 07 | `07_seguridad_logica.sql` | Brandon |
| 08 | `08_roles_permisos.sql` (roles de PostgreSQL y `GRANT`) | Brandon |
| 09–11 | `09_seed_catalogo.sql`, `10_seed_seguridad.sql`, `11_seed_venta.sql` | Mati, Brandon, Juanjo |
| 12–14 | `12_masivo_catalogo.sql`, `13_masivo_seguridad.sql`, `14_masivo_venta.sql` (datos con `generate_series` para `EXPLAIN ANALYZE`) | cada dueño |
| 20+ | `20_consulta_*.sql` (las 4 consultas analíticas, cada dueña la suya) | según la tabla de la Parte 0 |

Pruebas y evidencias en `database/pruebas/<modulo>/`.

## 2.5 Qué debe hacer cada dueño en su módulo de BD (checklist común)
1. **DER del módulo** (entidades, cardinalidades) y **modelo lógico** (PK/FK, tipos, `NOT NULL`, `CHECK`, `UNIQUE`, 3FN).
2. **DDL** con restricciones de integridad.
3. **Lógica**: funciones/procedimientos/triggers de sus reglas de negocio.
4. **Seeds** pequeños y realistas + masivos.
5. **Consulta(s) analítica(s)** asignadas, sin errores de sintaxis.
6. **Índices** justificados y **`EXPLAIN ANALYZE` antes/después** (Seq Scan → Index Scan) sobre sus consultas más pesadas.
7. **Prueba** propia (ver Parte 0) con evidencia en `docs/04-pruebas/<modulo>.md`.
8. Documentar en `docs/03-diseno/modulo-<nombre>.md` el diseño del módulo y las decisiones.

---

# PARTE 3 — MATI · Módulo A (Catálogo, salas, programación y tarifas) + esqueleto de la app

**Misión:** que el catálogo y la programación sean correctos y consistentes, y que la app tenga una base funcional. Su módulo es la base de datos sobre la que se apoyan los demás; por eso su DDL se necesita **primero**.

**Rama:** `catalogo`.

## Parte de base de datos (Módulo A)

**M1 · Diseño y DDL (`01_catalogo_schema.sql`) — PRIORIDAD 1**
- Tablas: `cine` (ubicación exacta), `sala` (capacidad), `zona_asiento` (platea, palcos, VIP/general), `asiento` (fila, número, zona; único por sala), `pelicula` (título, sinopsis, duración, póster, estado activo/inactivo), `clasificacion` de edad, `genero` y `pelicula_genero` (N:M), `funcion` (película, sala, inicio, fin, estado), `tipo_entrada` (adulto, niño, tercera edad, estudiante), `tarifa` (matriz de precios por día de la semana, horario, zona/tipo de asiento y tipo de entrada), `promocion` (2x1: condiciones por día o por cantidad par de la misma categoría).
- **No traslape de funciones en una sala** (proceso de programación): restricción `EXCLUDE USING gist (sala_id WITH =, tstzrange(inicio, fin_con_limpieza) WITH &&)` (requiere `CREATE EXTENSION btree_gist`). El fin debe incluir el tiempo de limpieza/preparación.
- `CHECK`s: duración > 0, fin > inicio, precios ≥ 0, estados válidos. `ON DELETE RESTRICT` donde haya historial.
- Entregar este script **lo antes posible**: Juanjo (`funcion`, `asiento`, `tipo_entrada`, `tarifa`) depende de él.

**M2 · Lógica (`05_catalogo_logica.sql`)**
- `fn_listar_cartelera(cine, fecha, genero)`: solo películas/funciones **activas** y con **inicio futuro** (RN-01); devuelve título, sinopsis, clasificación, horarios y ubicación de la sala (RN-02). Filtros opcionales por ubicación, fecha y género.
- `fn_calcular_total(...)`: dado el conjunto de asientos y el tipo de entrada de cada uno, calcula la suma exacta de tarifas, aplica la **promoción 2x1 automática** (n.º par de entradas de la misma categoría o día específico) y suma cargos por servicio (RN-07, RN-08). Devuelve el desglose y el total.
- **Trigger RN-18:** impedir `UPDATE`/`DELETE` sobre la distribución de asientos o la sala si existen entradas vendidas o reservas para funciones programadas en esa sala. (Se escribe cuando exista el DDL de Juanjo, porque consulta `boleto`/`reserva_asiento`.)
- Validaciones de la programación (RN-17: las modificaciones críticas solo las puede hacer un rol autorizado, ver módulo C).

**M3 · Seeds (`09_seed_catalogo.sql`, `12_masivo_catalogo.sql`)**
- Pequeño y realista: 3–4 cines con salas y mapas de asientos por zonas, 8–10 películas con sinopsis/clasificación/género/duración, funciones futuras (activas) y alguna pasada o inactiva para probar RN-01, tipos de entrada, tarifas y una promoción 2x1.
- Masivo (con `generate_series`): decenas de miles de funciones para que el filtro de cartelera muestre diferencias reales en `EXPLAIN ANALYZE`. Estos datos son la base para los seeds de Juanjo y Brandon: **compartir los IDs** de funciones y asientos con ellos.

**M4 · Consulta analítica #2 — Top 5**
Las 5 películas/obras con más boletos vendidos en la **última semana** a nivel global (`database/20_consulta_top5.sql`). Además, 2–3 vistas o consultas de apoyo para el dashboard de la app.

**M5 · Índices y `EXPLAIN ANALYZE`**
Sobre: filtro de cartelera (función activa y futura por fecha/cine/género) y el top 5. Mostrar el plan **antes** (Seq Scan) y **después** (Index Scan) con costo y tiempo. *Candidatos:* índice parcial en funciones activas futuras, `funcion(sala_id, inicio)`, índices de las FK de `pelicula_genero`.

## Parte de la aplicación

**M6 · Esqueleto y pantallas propias**
- La base de `app/` **ya está creada** (HTML + JavaScript con Node.js + Express + `pg`, ver Parte 0.1). Mati la mantiene: conexión a la BD por variables de entorno (sin contraseñas en el repo), menú por rol en `nav.js` y `app/README.md` al día.
- La estructura de rutas/páginas por módulo ya separa los archivos de cada quien para evitar conflictos; revisar que se respete.
- **Cartelera y exploración** (RN-01, RN-02): sinopsis, clasificación, horarios, filtros por ubicación, fecha y género.
- **Panel de administración de catálogo:** alta de película con póster, configuración de salas y mapa de asientos (mostrar el error de RN-18), programación de funciones (mostrar el error de traslape), matriz de precios y promociones.
- **Dashboard** con métricas en tiempo real: % de ocupación, ingresos por función (consulta de Juanjo), métodos de pago (consulta de Juanjo) y top de funciones (la suya).
- Wireframes simples de todas las pantallas (los tres los usan).

## Documentación de Mati
- **`01b-factibilidad-economica.md`:** comparar **al menos dos nubes** (AWS vs Azure o Google Cloud) en BD relacional administrada, almacenamiento de logs a 5 años y balanceador/WAF; usar **calculadoras públicas** y **citar el enlace/fuente**; costo mensual por millón de transacciones; proyección a **3 años** (CAPEX inicial + OPEX con crecimiento) y justificación del **ROI**; factibilidad operativa. *(Los números del ejemplo del PDF son solo referenciales: hay que calcular y citar los propios.)*
- **`01c-almacenamiento.md`:** tabla en **GB/TB mensual y acumulado a 5 años** con 1,500 salas, 500 títulos y 15M boletos/mes: supuestos explícitos (tamaño promedio de fila por tabla usando el modelo integrado, n.º de eventos de log por boleto, factor de índices, replicación), cálculo por separado de tablas vivas y de las 4 tablas de log, y capas caliente/archivo. Depende del modelo integrado de Juanjo; empezar con estimaciones y refinar.
- **`02-requisitos.md`:** requisitos funcionales (derivados del flujo y de RN-01…RN-20) y no funcionales (disponibilidad 99.99%, RTO < 5 min, RPO ≤ 5 s, PCI-DSS, 50,000 TPS, escalabilidad, auditabilidad a 5 años); volúmenes: 8M concurrentes, 50,000 TPS durante 10 min, 15M boletos/mes, logs a 5 años.
- **Video demo** de los 5 procesos de la pauta y ensayo final con el equipo.

## Criterios de "listo" de Mati
- [ ] `01_catalogo_schema.sql` corre desde cero; las funciones se ejecutan.
- [ ] Dos funciones no pueden solaparse en la misma sala (la BD lo rechaza).
- [ ] Solo se listan funciones activas y futuras; los filtros funcionan.
- [ ] `fn_calcular_total` aplica 2x1 y el total coincide con el cálculo manual.
- [ ] No se puede modificar una sala con ventas activas (RN-18).
- [ ] Top 5 sin errores y `EXPLAIN ANALYZE` antes/después documentado.
- [ ] Esqueleto de la app corre y la cartelera filtra.
- [ ] Documentos de factibilidad económica, almacenamiento y requisitos con fuentes y supuestos.

## Prompt sugerido para su IA
> "Eres un experto en PostgreSQL y desarrollo web. Te doy el contexto de un proyecto universitario de bases de datos (adjunto la Parte 1, la Parte 2, mi sección y el contrato de funciones). Ayúdame con `[tarea MX]` respetando las reglas RN-xx. Entrégame SQL ejecutable sobre una BD vacía, explica las decisiones y cómo probarlas. Para precios cloud, cita solo calculadoras oficiales y marca como supuesto lo que no puedas verificar."

---

# PARTE 4 — JUANJO · Módulo B (Venta, bloqueo de asientos, pago y boletos) + integración global

**Misión:** que **nunca** se venda dos veces el mismo asiento y que dinero y estado del asiento cambien de forma atómica. Es el módulo que la pauta evalúa con más severidad, y además integra el modelo global.

**Rama:** `venta`.

## Parte de base de datos (Módulo B)

**J1 · Diseño y DDL (`03_venta_schema.sql`)** — depende de `funcion`, `asiento`, `tipo_entrada`, `tarifa` (Mati) y `usuario` (Brandon).
- **Anti doble venta (RN-03, RN-05):** `reserva_asiento(funcion_id, asiento_id, usuario_id, estado, bloqueado_hasta, ...)` con **índice único parcial** `UNIQUE (funcion_id, asiento_id) WHERE estado IN ('BLOQUEADO','VENDIDO')`. Un asiento liberado o expirado se puede volver a tomar, pero dos transacciones no pueden tener el mismo asiento activo. La pauta evalúa que esta restricción **impida físicamente** la doble inserción.
- `orden` y `orden_detalle` (asiento, tipo de entrada, precio aplicado), `metodo_pago`, `pago` (resultado, ID de autorización simulado).
- **RN-09:** el esquema **no tiene columnas** de número de tarjeta ni CVV; solo método de pago, referencia simulada de la pasarela y, como máximo, últimos 4 dígitos.
- **`boleto`** (RN-12, RN-13, RN-14): `codigo_qr UNIQUE`, estado (`EMITIDO`, `USADO`, `ANULADO`), ligado unívocamente a función + asiento. **Se crea solo si el pago fue aprobado** (RN-11).
- `CHECK`s: precios ≥ 0, estados válidos.

**J2 · Logs particionados (en `03_venta_schema.sql`)**
- `transaccion_log` (intentos de pago, confirmación de pasarela, montos, impuestos, emisión de boletos) y `asiento_auditoria_log` (bloqueo, liberación por expiración de 2 min, compra definitiva).
- `PARTITION BY RANGE` por fecha (mensual) con varias particiones y una `DEFAULT`; la PK debe incluir la columna de partición. Función que cree particiones futuras.
- Inalterables: `REVOKE UPDATE, DELETE` a todos los roles o trigger que lance excepción.

**J3 · Lógica transaccional (`06_venta_logica.sql`)** — todas atómicas con `BEGIN/COMMIT/ROLLBACK`:
1. `fn_bloquear_asientos(usuario, funcion, asientos[])`: valida el **máximo por transacción** (RN-04), limpia bloqueos expirados, inserta con `bloqueado_hasta = now() + 2 min`; si el índice único falla, devuelve error controlado ("asiento no disponible"). Registra en `asiento_auditoria_log`.
2. `fn_liberar_expirados()`: marca `EXPIRADO` los bloqueos vencidos y los registra (RN-05).
3. `fn_mapa_asientos(funcion)`: estado de cada asiento (disponible, bloqueado, vendido) (RN-03).
4. `fn_confirmar_pago(reserva, metodo, resultado)`: recibe el resultado simulado. **Aprobado:** asientos a `VENDIDO`, crea la orden y **solo entonces** emite los boletos con QR único; escribe `transaccion_log` (RN-10, RN-11, RN-12). **Rechazado:** libera los asientos de inmediato, cancela la transacción y registra el intento. Usa `fn_calcular_total` de Mati.
5. `fn_mis_boletos(usuario)` (RN-13).

**J4 · Seeds (`11_seed_venta.sql`, `14_masivo_venta.sql`)**
Pequeño: órdenes, pagos, boletos y reservas de ejemplo (incluir un caso de pago rechazado y un bloqueo expirado). Masivo con `generate_series`: cientos de miles de reservas/boletos y logs para que `EXPLAIN ANALYZE` muestre Seq Scan vs Index Scan reales. Usa los IDs de Mati.

**J5 · Consultas analíticas #1 y #3**
- **Ocupación y recaudación por función:** % de asientos vendidos vs. capacidad de la sala e ingresos totales de una función.
- **Métodos de pago preferidos:** reporte porcentual por método/pasarela.

**J6 · Índices y `EXPLAIN ANALYZE`**
Sobre: disponibilidad de asientos de una función, consulta #1 y #3. Antes (Seq Scan) y después (Index Scan) con costo y tiempo. *Candidatos:* `reserva_asiento(funcion_id, asiento_id)` parcial por estado, `boleto(codigo_qr)`, índices de las FK, BRIN/b-tree por fecha en los logs.

**J7 · Prueba de concurrencia (OBLIGATORIA)**
- `database/pruebas/venta/concurrencia.py` (Python `threading` + `psycopg` con una **barrera** para que todos disparen a la vez), o k6/JMeter.
- **20 a 50 hilos** intentando bloquear **el mismo asiento de la misma función**. Esperado: **exactamente 1 éxito** y el resto rechazado por colisión de restricción.
- Guardar la salida (éxitos/fallos y tiempos) en `docs/04-pruebas/venta.md` como evidencia.

## Integración global (la parte más difícil de coordinar)

**J8 · Modelo global y diseño físico (`docs/03-diseno/integrado.md`)**
- Conducir la sesión conjunta (Parte 2.1) y dejar acordadas las tablas compartidas.
- **DER global** y **modelo relacional gráfico** que unan los tres módulos (usuario, película, función, sala, asiento, boleto, transacción, rol, auditoría); exportar a `docs/img/`.
- Normalización global y **diseño físico**: selección de PostgreSQL, resumen de índices y estrategia de particionamiento de los 4 logs.
- Revisar los PR de los otros dos módulos para verificar que las FK y los scripts corren en el orden de la Parte 2.4 (script de `make db-reset` desde cero).

**J9 · Administración del repositorio (10 min)**
Como dueño del repo: proteger `main` (PR obligatorio), crear las ramas `catalogo`, `venta`, `seguridad` e invitar a Mati y Brandon.

## Parte de la aplicación (pantallas de venta)
- **Mapa interactivo de la sala** (RN-03, RN-04, RN-05): colores **verde** disponible, **gris** ocupado, **amarillo** bloqueado temporalmente, **azul** seleccionado por el usuario; actualización casi en tiempo real (polling o SSE); **cuenta regresiva de 2 min** (la expiración real la decide la BD); manejo del error "asiento no disponible".
- **Pago simulado** (RN-08, RN-09, RN-10): resumen de compra con desglose de tarifas y 2x1 (calculados por la BD), campos de pago **simulados** (nunca guardar ni enviar número de tarjeta/CVV) y botones "Aprobar" / "Rechazar".
- **Confirmación y entrada digital** (RN-11, RN-12, RN-13): boleto con QR único generado desde el código que devuelve la BD y sección "Mis entradas".

## Criterios de "listo" de Juanjo
- [ ] Scripts de venta corren desde cero sin errores.
- [ ] 20–50 hilos sobre el mismo asiento → **1 solo éxito** (evidencia guardada).
- [ ] Pago rechazado libera los asientos al instante; no se emite QR sin pago aprobado.
- [ ] No existe ninguna columna con datos de tarjeta/CVV.
- [ ] Logs particionados e inalterables.
- [ ] Consultas #1 y #3 sin errores y `EXPLAIN ANALYZE` antes/después documentado.
- [ ] DER global y modelo relacional publicados; `make db-reset` corre todo el orden de la Parte 2.4.
- [ ] Pantallas de mapa, pago y QR funcionan.

## Prompt sugerido para su IA
> "Eres un experto en PostgreSQL, transacciones y concurrencia. Te doy el contexto de un proyecto universitario de bases de datos (adjunto la Parte 1, la Parte 2, mi sección y el contrato de funciones). Ayúdame con `[tarea JX]` respetando las reglas RN-xx. Entrégame SQL ejecutable, explica por qué no puede haber doble venta y cómo probarlo con concurrencia. No guardes datos de tarjeta."

---

# PARTE 5 — BRANDON · Módulo C (Usuarios, RBAC, acceso en puerta, reembolsos y auditoría) + documentación de arquitectura

**Misión:** que solo entre quien debe, que cada rol haga solo lo que le corresponde y que toda acción sensible quede registrada de forma inalterable. Además redacta el dictamen y la parte de riesgos y operación.

**Rama:** `seguridad`.

## Parte de base de datos (Módulo C)

**B1 · Diseño y DDL**
- **`02_seguridad_usuarios_schema.sql`:** `usuario`, `rol`, `usuario_rol` (cliente, taquillero, operador de sala, contador, administrador). Contraseñas **solo como hash** (nunca en claro). Entregar pronto: Juanjo depende de `usuario`.
- **`04_seguridad_acceso_schema.sql`** (depende de `boleto` y `orden` de Juanjo): `puerta` (dispositivo/tótem), **`acceso_puerta_log`** (timestamp, id del boleto, puerta, resultado exitoso/rechazado por duplicidad o por horario), **`reembolso`** (monto total/parcial, motivo, quién y cuándo) y **`admin_operacion_audit`** (fecha, hora, **IP**, ID del rol y del usuario responsable, operación y detalle).
- Las dos tablas de log son **particionadas por fecha** (mensual, con varias particiones y una `DEFAULT`; la PK incluye la columna de partición) e **inalterables** (`REVOKE UPDATE, DELETE` o trigger que lance excepción).

**B2 · Lógica (`07_seguridad_logica.sql`)**
- **`fn_validar_entrada(codigo_qr, puerta)`** (RN-14, RN-15, RN-16): rechaza si el QR no existe, si el boleto ya fue usado (mensaje **"Entrada ya utilizada"**), si corresponde a otra función/fecha u hora, o si está fuera de la ventana de tolerancia (ej. 30 min antes a 15 min después del inicio). Marca el boleto como `USADO` de forma **atómica** (`UPDATE ... WHERE estado = 'EMITIDO' RETURNING ...`) para que dos escaneos simultáneos no puedan pasar ambos. Registra **cada intento** en `acceso_puerta_log`.
- **`fn_reembolsar(boleto, admin, motivo)`** (RN-19): solo si faltan ≥ 2 h para la función; anula el boleto, libera el asiento asociado y registra el reembolso; si es una operación manual, escribe en `admin_operacion_audit`.
- **Triggers de auditoría (RN-20):** registrar automáticamente en `admin_operacion_audit` las operaciones manuales (cortesías, cambios de asiento, reembolsos forzados, cambios de precios/configuración crítica). Coordinar con Mati y Juanjo qué tablas lleva el trigger.

**B3 · Roles y permisos (`08_roles_permisos.sql`) (RN-17)**
Implementar la matriz de la sección 1.6 con roles `NOLOGIN` (`rol_cliente`, `rol_taquillero`, `rol_operador_sala`, `rol_contador`, `rol_admin`) y `GRANT` mínimos sobre tablas, vistas y funciones de **los tres módulos** (cada dueño le indica qué funciones/tablas debe ver cada rol). Ejemplos: el operador de sala solo ejecuta `fn_validar_entrada`; el contador solo lee vistas financieras; el cliente solo ve sus propios boletos (opcional **Row-Level Security**). Demostrar con `SET ROLE` que un taquillero o cliente **no puede** modificar precios ni salas. Documentar en `docs/rbac-matriz.md`.

**B4 · Seeds (`10_seed_seguridad.sql`, `13_masivo_seguridad.sql`)**
Usuarios de cada rol, puertas, y accesos de ejemplo (incluir intentos rechazados por duplicidad y por horario). Masivo con `generate_series` para los logs de acceso y de auditoría.

**B5 · Consulta analítica #4 — Auditoría**
Modificaciones manuales, cortesías o reembolsos del **último mes** agrupados por ID de administrador (`database/20_consulta_auditoria.sql`).

**B6 · Índices y `EXPLAIN ANALYZE`**
Sobre: la consulta de auditoría y la búsqueda de boleto por QR en `fn_validar_entrada`. Antes (Seq Scan) y después (Index Scan), con costo y tiempo. Si la consulta filtra por fecha, mostrar también la **poda de particiones**.

**B7 · Prueba de doble escaneo concurrente**
`database/pruebas/seguridad/doble_escaneo.py`: 20+ hilos escaneando **el mismo QR** a la vez → **exactamente 1 entrada válida** y el resto "Entrada ya utilizada". Guardar la evidencia en `docs/04-pruebas/seguridad.md`.

## Parte de la aplicación (pantallas de seguridad)
- **Login** y menús por rol según la matriz (cliente, taquillero, operador de sala, contador, administrador). El bloqueo se aplica en el **backend**, no solo ocultando botones; demostrar que un taquillero o cliente no puede entrar a configuración de salas/precios.
- **Check-in en puerta** (para el operador de sala): campo para pegar/escanear el código QR + puerta; mostrar el resultado de la BD (válido, "Entrada ya utilizada", otra función, fuera de tolerancia).
- **Reembolsos/anulaciones** y **visor de la bitácora de auditoría** para el administrador.
- Pasar siempre el ID del administrador a las funciones que auditan.

## Documentación de Brandon
- **`01a-factibilidad-tecnica-riesgos.md`:**
  - **Dictamen técnico de rechazo** de los **6 puntos del escenario legado**: qué propone, por qué falla (con cifras: 50 Mbps vs 50,000 TPS; una instancia sin alta disponibilidad vs SLA 99.99%; Access/SQLite sin concurrencia de escritura; PCI-DSS y RN-09 violadas por enviar tarjetas/CVV a WhatsApp; Google Sheets sin ACID; "reiniciar" vs RTO < 5 min / RPO ≤ 5 s) y qué lo reemplaza.
  - **Matriz Única de Riesgo y Mitigación** en el formato exacto de la sección 1.9, recomendado 8–10 riesgos (caída de la BD, DDoS, caída de la pasarela, pérdida de consistencia/doble venta, fuga de datos de tarjeta, saturación en el estreno, corrupción de backups, falla de región cloud, error humano del administrador), cada uno con probabilidad, impacto, mitigación/DRP y RTO/RPO.
  - Propuesta de arquitectura escalable (factibilidad técnica y operativa) que reemplaza al legado.
- **`05-operacion.md` (Fase 5):** definir y **justificar** cómo la propuesta cumple **RPO ≤ 5 s** (replicación síncrona/casi síncrona, archivado de WAL, recuperación a un punto en el tiempo), **RTO < 5 min** (failover automático a réplica multizona/región), **SLA 99.99%** (≈ 52 min de caída al año), **frecuencia de backup** (snapshots + WAL continuo + retención quinquenal), pruebas de restauración, plan de DR y privacidad de datos.
- **Documento final y README:** ensamblar el **Documento Técnico de Arquitectura de Datos y Propuesta de Licitación** con todas las secciones exigidas (dictamen y propuesta; requisitos y dimensionamiento; diseño conceptual/lógico/físico; modelo relacional; capturas de la GUI; evidencias de pruebas; scripts). Mantener el `README.md` actualizado y coordinar el **ensayo de la pauta** (sección 1.11) con los otros dos.

## Criterios de "listo" de Brandon
- [ ] Scripts de seguridad corren desde cero sin errores.
- [ ] Segundo escaneo del mismo QR → "Entrada ya utilizada"; 20+ hilos sobre el mismo QR → 1 solo válido.
- [ ] Se rechaza la entrada de otra función o fuera de tolerancia, y cada intento queda en `acceso_puerta_log`.
- [ ] Reembolso solo hasta 2 h antes y libera el asiento.
- [ ] Toda operación manual queda en `admin_operacion_audit` con fecha, hora, IP y usuario; los logs son inalterables.
- [ ] Un taquillero/cliente no puede modificar precios ni salas (demostrado con `SET ROLE` y en la GUI).
- [ ] Consulta #4 sin errores y `EXPLAIN ANALYZE` antes/después documentado.
- [ ] Dictamen, matriz de riesgos y Fase 5 completos con cifras justificadas; documento final ensamblado.

## Prompt sugerido para su IA
> "Eres un experto en seguridad de bases de datos PostgreSQL y en arquitectura de TI. Te doy el contexto de un proyecto universitario de bases de datos (adjunto la Parte 1, la Parte 2, mi sección y el contrato de funciones). Ayúdame con `[tarea BX]` respetando las reglas RN-xx. Entrégame SQL ejecutable, explica las decisiones y cómo probarlas. En las partes de documentación, no inventes cifras: si no puedes verificar un dato, márcalo como supuesto."

---

# PARTE 6 — Orden de trabajo y puntos de entrega

| Etapa | Mati (A) | Juanjo (B) | Brandon (C) |
|---|---|---|---|
| **0. Setup** | Elegir stack | Repo, ramas, protección de `main` (J9) | README base |
| **1. Diseño** | **Sesión conjunta** · DER y DDL del catálogo (M1) · wireframes | **Sesión conjunta** · DER del módulo de venta | **Sesión conjunta** · DDL de usuarios/roles (B1) · dictamen y riesgos |
| **2. Esquemas** | Funciones de catálogo (M2) | DDL de venta y logs particionados (J1, J2) · DER global (J8) | DDL de acceso y auditoría (B1) · Fase 5 |
| **3. Lógica** | Seeds (M3) · esqueleto y cartelera (M6) | Lógica de venta (J3) · seeds (J4) | Lógica de seguridad (B2) · roles y permisos (B3) · seeds (B4) |
| **4. Integración y pruebas** | Consulta #2, índices, `EXPLAIN` · panel admin y dashboard | **Concurrencia (J7)** · consultas #1 y #3 · `EXPLAIN` · pantallas de venta | Doble escaneo (B7) · consulta #4 · `EXPLAIN` · pantallas de seguridad |
| **5. Entrega** | Factibilidad económica, almacenamiento, requisitos · video demo | `docs/04-pruebas/venta.md` y diseño integrado | Documento final · **ensayo de la pauta con todos** |

**Puntos de entrega obligatorios entre personas**
1. **H0:** sesión de diseño conjunta (convenciones y tablas compartidas).
2. **H1:** Mati entrega `01_catalogo_schema.sql` y Brandon `02_seguridad_usuarios_schema.sql` → Juanjo puede crear sus FK.
3. **H2:** Juanjo entrega `03_venta_schema.sql` (boleto, orden) → Brandon puede crear acceso/reembolso y Mati el trigger RN-18.
4. **H3:** Mati entrega `fn_calcular_total` y `fn_listar_cartelera` → Juanjo y la app de venta las usan.
5. **H4:** los tres entregan seeds con IDs consistentes → `make db-reset` corre todo desde cero.
6. **H5:** todos entregan evidencias (capturas, planes de `EXPLAIN`, salidas de pruebas) a Brandon para el documento final.

**Cuellos de botella:** el DDL de Mati y el de usuarios de Brandon son pequeños y salen primero; después el DDL de venta de Juanjo desbloquea a los otros dos. Si alguno se retrasa, avisar de inmediato.

**Una semana antes de entregar:** congelar funcionalidades y dedicarla al ensayo de la pauta y al video.

---

# PARTE 7 — Contrato entre la base de datos y la aplicación (propuesta)

La app llama a estas funciones; cada dueño implementa las suyas. Si cambia un nombre o parámetro, avisa a todos y actualiza esta tabla.

| Función SQL (propuesta) | Dueño | Entrada | Salida | Reglas |
|---|---|---|---|---|
| `fn_listar_cartelera(p_cine, p_fecha, p_genero)` | Mati | filtros opcionales | funciones con título, sinopsis, clasificación, horario, sala y ubicación | RN-01, RN-02 |
| `fn_calcular_total(p_asientos, p_tipos_entrada)` | Mati | asientos y tipo de entrada por asiento | desglose, promoción 2x1, cargo por servicio y total | RN-07, RN-08 |
| `fn_mapa_asientos(p_funcion_id)` | Juanjo | función | asientos con zona y estado (`DISPONIBLE`, `BLOQUEADO`, `VENDIDO`) | RN-03 |
| `fn_bloquear_asientos(p_usuario_id, p_funcion_id, p_asientos[])` | Juanjo | usuario, función, asientos | `reserva_id`, `expira_en` o error "asiento no disponible" | RN-04, RN-05 |
| `fn_confirmar_pago(p_reserva_id, p_metodo, p_resultado)` | Juanjo | resultado simulado `APROBADO`/`RECHAZADO` | boletos con QR (solo si aprobado) o liberación de asientos | RN-09 a RN-12 |
| `fn_mis_boletos(p_usuario_id)` | Juanjo | usuario | boletos y códigos QR | RN-13 |
| `fn_liberar_expirados()` | Juanjo | — | n.º de bloqueos liberados | RN-05 |
| `fn_validar_entrada(p_codigo_qr, p_puerta_id)` | Brandon | QR y puerta | `OK` o motivo: "Entrada ya utilizada", función/hora incorrecta, fuera de tolerancia | RN-14 a RN-16 |
| `fn_reembolsar(p_boleto_id, p_admin_id, p_motivo)` | Brandon | boleto, admin, motivo | confirmación o error de política | RN-19, RN-20 |

El CRUD del administrador (películas, salas, funciones, precios) puede hacerse con `INSERT/UPDATE` directos o con funciones de Mati; en todos los casos deben dispararse los triggers de RN-18 (Mati) y RN-20 (Brandon).

---

# PARTE 8 — Reglas del equipo

- Cada quien trabaja en su rama (`catalogo`, `venta`, `seguridad`); PR a `main` revisado por **otro** integrante; nunca push directo a `main`.
- Commits pequeños y descriptivos: `feat(db): ...`, `docs: ...`, `fix(app): ...`, `test: ...`.
- Los `.sql` van numerados y deben correr en orden sobre una BD vacía.
- Nada de contraseñas ni datos reales de tarjetas en el repo (usar `.env` y `.gitignore`).
- Si una IA propone algo que contradice una RN de la Parte 1, **manda la Parte 1**.
- Cada quien debe entender y poder explicar su módulo: en la defensa pueden preguntar a cualquiera sobre cualquier parte de la BD.
- Reunión corta 2 veces por semana: qué hice, qué haré, qué me bloquea.
- Lo que no está en Git no se revisa.
