<div align="center">

# Ecosistema Digital de Cines IMAX

### Propuesta de licitación: diseño e implementación del ciclo de vida de la base de datos

**Proyecto 2 · Bases de Datos · II Semestre 2026**

Instituto Tecnológico de Costa Rica
[Administración de Tecnologías de la Información] · [TI-3600-Bases de Datos] · Profesora: [Jacqueline Tatiana Solis Cespedes]

![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16-336791?logo=postgresql&logoColor=white)
![Node.js](https://img.shields.io/badge/Node.js-18%2B-339933?logo=nodedotjs&logoColor=white)
![Estado](https://img.shields.io/badge/estado-en%20desarrollo-orange)
![Licitaci%C3%B3n](https://img.shields.io/badge/IMAX-licitaci%C3%B3n%20global-1f4e79)

</div>

---

## Resumen

IMAX Corporation abrió una licitación global para modernizar y escalar su plataforma de venta de entradas. El escenario heredado (una única base de datos en un computador de escritorio, tráfico por una conexión residencial, reservas en una hoja de cálculo y números de tarjeta enviados por mensajería) resulta inviable ante un estreno mundial con **8 millones de usuarios concurrentes** y picos de **50 000 transacciones por segundo**.

Este repositorio contiene la propuesta técnica del equipo: un **dictamen de rechazo** de la infraestructura heredada y el diseño, la implementación y la validación de una base de datos relacional **PostgreSQL** que garantiza propiedades **ACID**, impide la **doble venta de asientos**, cumple los principios de **PCI-DSS** (sin almacenar datos sensibles de tarjetas), controla el acceso mediante **RBAC** y conserva **auditoría inalterable durante 5 años**. Una interfaz web de apoyo permite demostrar los flujos de negocio de extremo a extremo.

## Tabla de contenido

1. [Contexto y problema](#1-contexto-y-problema)
2. [Objetivos](#2-objetivos)
3. [Alcance y fases del ciclo de vida de la BD](#3-alcance-y-fases-del-ciclo-de-vida-de-la-bd)
4. [Arquitectura propuesta](#4-arquitectura-propuesta)
5. [Modelo de datos](#5-modelo-de-datos)
6. [Reglas de negocio y su garantía en la base de datos](#6-reglas-de-negocio-y-su-garantía-en-la-base-de-datos)
7. [Seguridad y control de acceso (RBAC)](#7-seguridad-y-control-de-acceso-rbac)
8. [Estructura del repositorio](#8-estructura-del-repositorio)
9. [Instalación y ejecución](#9-instalación-y-ejecución)
10. [Pruebas y evidencias](#10-pruebas-y-evidencias)
11. [Metodología de trabajo](#11-metodología-de-trabajo)
12. [Equipo](#12-equipo)
13. [Documentación](#13-documentación)
14. [Estado del proyecto](#14-estado-del-proyecto)
15. [Referencias](#15-referencias)

---

## 1. Contexto y problema

La licitación exige una solución integral que cubra todo el ciclo de vida del servicio: exploración de cartelera, selección interactiva de asientos en tiempo real, pagos seguros, emisión de códigos QR únicos, control de acceso automatizado en puerta y un panel de administración centralizado.

La propuesta técnica del proveedor saliente fue calificada por el comité evaluador como inviable. Sus principales deficiencias, que se analizan en el dictamen de rechazo, son:

| Componente heredado | Deficiencia principal |
|---|---|
| Base de datos en Access/SQLite sobre un equipo de escritorio | Sin concurrencia de escritura, sin alta disponibilidad y con un único punto de falla |
| Red residencial de 50 Mbps | Capacidad insuficiente para millones de solicitudes simultáneas |
| Reservas en una hoja de cálculo compartida | Sin atomicidad ni aislamiento: doble venta inevitable |
| Datos de tarjeta enviados por mensajería | Incumplimiento de PCI-DSS y exposición de datos sensibles |
| Recuperación mediante "reiniciar y cruzar los dedos" | Sin RTO ni RPO definidos |

## 2. Objetivos

**Objetivo general.** Diseñar e implementar la base de datos de una plataforma de venta de entradas de alta concurrencia, documentando su viabilidad técnica, económica y operativa a lo largo del ciclo de vida de la base de datos (DBLC).

**Objetivos específicos**

1. Justificar técnicamente el rechazo de la infraestructura heredada y proponer una arquitectura escalable.
2. Modelar los datos del dominio mediante diseño conceptual, lógico y físico, con normalización e índices justificados.
3. Garantizar la integridad transaccional y la prevención de doble venta mediante restricciones y transacciones.
4. Implementar control de acceso basado en roles y trazabilidad inalterable de operaciones durante cinco años.
5. Validar el diseño con pruebas de concurrencia y análisis de planes de ejecución (`EXPLAIN ANALYZE`).
6. Definir políticas de respaldo y recuperación que cumplan RPO ≤ 5 s, RTO < 5 min y SLA de 99,99 %.

## 3. Alcance y fases del ciclo de vida de la BD

| Fase | Contenido | Documento |
|---|---|---|
| **1. Análisis de factibilidad** | Factibilidad técnica, económica y operativa; matriz de riesgos con RTO/RPO; comparativa de proveedores cloud; dimensionamiento de almacenamiento a 5 años | [`01a`](Documentos/01a-factibilidad-tecnica-riesgos.md) · [`01b`](docs/01b-factibilidad-economica.md) · [`01c`](docs/01c-almacenamiento.md) |
| **2. Requisitos** | Requisitos funcionales y no funcionales; volúmenes esperados | [`02-requisitos`](docs/02-requisitos.md) |
| **3. Diseño** | Diagrama Entidad-Relación, modelo lógico normalizado, diseño físico, índices y particionamiento | [`03-diseno/`](docs/03-diseno/) |
| **4. Implementación y pruebas** | Scripts DDL, restricciones, transacciones, triggers, pruebas de concurrencia y rendimiento | [`database/`](database/) · [`04-pruebas/`](docs/04-pruebas/) |
| **5. Operación y mantenimiento** | Copias de seguridad, recuperación ante desastres, RPO/RTO/SLA, privacidad | [`05-operacion`](Documentos/05-operacion.md) |

## 4. Arquitectura propuesta

```mermaid
flowchart LR
  U["Espectador · Taquillero · Operador · Administrador"] --> W["Interfaz web<br/>HTML + JavaScript"]
  W --> A["API<br/>Node.js + Express"]
  A -->|"funciones SQL"| P[("PostgreSQL<br/>instancia primaria")]
  P -. "replicación" .-> R[("Réplica<br/>otra zona")]
  P --> L[("Logs de auditoría<br/>particionados · 5 años")]
  P --> B[("Respaldos + WAL<br/>retención quinquenal")]
  A -. "simulada" .-> G["Pasarela de pago"]
```

**Principios de diseño**

- La **lógica de negocio crítica reside en la base de datos** (funciones, restricciones y triggers); la aplicación solo la invoca.
- Un servicio relacional administrado con **alta disponibilidad y réplica en otra zona**, en lugar de un único servidor.
- **Particionamiento por fecha** de las tablas de auditoría para sostener el volumen de cinco años sin degradar las tablas operativas.
- La pasarela de pago es **simulada**; el esquema no contiene columnas para número de tarjeta ni CVV.

**Flujo de compra**

```mermaid
sequenceDiagram
  actor U as Espectador
  participant W as Aplicación
  participant D as Base de datos
  U->>W: Selecciona asientos
  W->>D: fn_bloquear_asientos
  D-->>W: Reserva con expiración de 2 min
  U->>W: Confirma el pago (simulado)
  W->>D: fn_confirmar_pago
  alt Pago aprobado
    D-->>W: Boletos con QR único
  else Pago rechazado
    D-->>W: Asientos liberados de inmediato
  end
```

## 5. Modelo de datos

El modelo se organiza en tres módulos, cada uno con un responsable de diseño, implementación y pruebas.

| Módulo | Entidades principales |
|---|---|
| **A. Catálogo y programación** | cine, sala, zona, asiento, película, género, clasificación, función, tipo de entrada, tarifa, promoción |
| **B. Venta y boletos** | reserva de asiento, orden, detalle, pago, método de pago, boleto (QR), `transaccion_log`, `asiento_auditoria_log` |
| **C. Seguridad y acceso** | usuario, rol, puerta, reembolso, `acceso_puerta_log`, `admin_operacion_audit` |

> Diagrama Entidad-Relación y modelo relacional: [`docs/03-diseno/integrado.md`](docs/03-diseno/integrado.md) (imágenes en [`docs/imagenes/`](docs/imagenes/)).

## 6. Reglas de negocio y su garantía en la base de datos

| Requisito | Mecanismo en la base de datos |
|---|---|
| Un asiento no puede venderse dos veces (RN-03, RN-05) | Restricción de unicidad por (función, asiento) sobre reservas activas |
| Bloqueo temporal de 2 minutos con liberación automática (RN-05) | Reserva con fecha de expiración y función de liberación de vencidos |
| Dinero y estado del asiento cambian a la vez (RN-10) | Transacciones atómicas `BEGIN / COMMIT / ROLLBACK` |
| Sin datos sensibles de tarjeta (RN-09) | Esquema sin columnas de tarjeta o CVV; pasarela externa simulada |
| QR solo tras pago aprobado y único por boleto (RN-11, RN-12) | Emisión dentro de la transacción de pago; `UNIQUE` sobre el código |
| Validación única en puerta (RN-14 a RN-16) | Actualización atómica del estado del boleto y control de ventana horaria |
| No se alteran salas con ventas activas (RN-18) | Trigger de protección |
| Auditoría inalterable por 5 años (RN-20) | Tablas particionadas por fecha, sin permisos de modificación ni borrado |
| Funciones sin traslape en una sala | Restricción de exclusión sobre rangos de tiempo |

## 7. Seguridad y control de acceso (RBAC)

El acceso se rige por el **principio de privilegio mínimo**, implementado con roles de PostgreSQL y validado también en el servidor de la aplicación.

| Rol | Alcance |
|---|---|
| Cliente / Espectador | Cartelera, compra y consulta de sus propias entradas |
| Taquillero | Venta presencial y corte de caja propio |
| Operador de sala | Validación de entradas en puerta |
| Contador | Lectura y exportación de información financiera |
| Administrador / Gerente | Configuración de cartelera, salas y precios; reembolsos; consulta de auditoría |

La matriz completa se documenta en [`Documentos/rbac-matriz.md`](Documentos/rbac-matriz.md).

## 8. Estructura del repositorio

```
Proyecto_IMAX/
├── README.md
├── DIVISION-DE-TRABAJO.md    Reparto por módulo y contratos entre módulos
├── package.json              Atajos para ejecutar la aplicación
├── app/                      Interfaz web de apoyo (Node.js + Express + HTML/JS)
│   ├── src/                  API y conexión a la base de datos
│   ├── public/               Páginas de catálogo, venta y seguridad
│   └── scripts/              Prueba de concurrencia (concurrencia.js)
├── database/
│   ├── ddl/                  Esquemas, lógica, roles, permisos e índices (01 a 10) y ddls.sql (todos unidos)
│   ├── seeds/                Datos de demostración y masivos, y seeds.sql / seeds_masivos.sql
│   ├── queries/              Consultas analíticas y queries.sql
│   ├── tests/                Pruebas SQL por módulo y tests.sql (todas, cada grupo en una base nueva)
│   └── explain/              Planes de ejecución antes y después de los índices
└── docs/
    ├── 01a … 05              Documento técnico por fase
    ├── 03-diseno/            Diseño integrado y por módulo
    ├── 04-pruebas/           Evidencias de pruebas
    └── imagenes/             Diagramas (DER)
```

## 9. Instalación y ejecución

**Requisitos:** Node.js 18 o superior, PostgreSQL 16 (con `psql` en el PATH) y Git.

### 9.1 Base de datos

Desde la raíz del repositorio. Cada archivo `ddls.sql`, `seeds.sql`, `queries.sql` y `tests.sql` es la unión de los scripts numerados de su carpeta, en el orden en que deben ejecutarse.

```bash
psql -U postgres -c "drop database if exists imax"
psql -U postgres -c "create database imax"
psql -U postgres -d imax -f database/ddl/ddls.sql         # tablas, funciones, triggers, roles e índices
psql -U postgres -d imax -f database/seeds/seeds.sql      # datos de demostración
psql -U postgres -d imax -f database/queries/queries.sql  # consultas analíticas
psql -U postgres -d postgres -f database/tests/tests.sql  # pruebas (crea y borra sus propias bases)
```

Para los planes de ejecución, que usan datos masivos y tardan varios minutos: `database/seeds/seeds_masivos.sql` y luego `database/explain/explain.sql`.

En Windows (PowerShell), antes de correr `psql`:

```powershell
chcp 65001
$env:PGCLIENTENCODING = "UTF8"
$env:PGPASSWORD = "su_clave"
```

### 9.2 Interfaz web

```bash
cd app
npm install        # instala dependencias y crea el archivo .env
```

Con la base cargada, editar `app/.env`: `MOCK=false`, `AUTH_DEV_BYPASS=false` y las variables `PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD` y `PGDATABASE=imax`. Luego:

```bash
npm run dev        # inicia el servidor en http://localhost:3000
```

La terminal debe indicar `MOCK=false`. Usuarios de demostración (contraseña `Imax2026!`): `cliente@imax.test`, `taquilla@imax.test`, `operador@imax.test`, `contador@imax.test` y `admin@imax.test`.

Para probar el check-in, el seed deja una función en la Sala 1 de San José que empieza 20 minutos después de cargarlo, con las entradas `IMAX-DEMO-1` e `IMAX-DEMO-2`. Si ya pasó la hora, se vuelve a correr `psql -U postgres -d imax -f database/seeds/13_demo_checkin.sql`.

Sin base de datos, con `MOCK=true`, la aplicación responde datos de ejemplo y permite **"Entrar como rol"** en la pantalla de inicio de sesión.

> En PowerShell, si aparece el error de ejecución de scripts, ejecutar una vez `Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned` o utilizar `npm.cmd`.

### 9.3 Prueba de concurrencia

Con la base cargada y el `.env` configurado, desde `app/`:

```bash
node scripts/concurrencia.js 30
```

Lanza 30 clientes que bloquean el mismo asiento a la vez y 10 pagos simultáneos de la misma orden. Debe terminar en `RESULTADO: FUNCIONA (sin doble venta)`.

## 10. Pruebas y evidencias

| Prueba | Criterio de aceptación | Evidencia |
|---|---|---|
| **Concurrencia (doble venta)** | Entre 20 y 50 solicitudes simultáneas sobre el mismo asiento: exactamente una exitosa | [`docs/04-pruebas/venta.md`](docs/04-pruebas/venta.md), `app/scripts/concurrencia.js` |
| **Pruebas de venta** | Bloqueo, pago aprobado y rechazado, boletos con QR único, expiración | [`docs/04-pruebas/venta.md`](docs/04-pruebas/venta.md), `database/tests/01_restricciones.sql` |
| **Pruebas de catálogo** | Programación sin traslapes, cartelera, total con 2x1, RN-18 | [`docs/04-pruebas/catalogo.md`](docs/04-pruebas/catalogo.md), `database/tests/05_catalogo_logica.sql` |
| **Doble escaneo de QR y reembolsos** | Entre múltiples lecturas simultáneas, una sola válida; el resto "Entrada ya utilizada" | `database/tests/07_checkin_reembolso.sql`, `database/tests/doble_escaneo.py` |
| **Rendimiento de consultas** | `EXPLAIN ANALYZE` antes y después de crear índices: de *Seq Scan* a *Index Scan* | [`docs/04-pruebas/venta.md`](docs/04-pruebas/venta.md), [`database/explain/`](database/explain/) |
| **Consultas analíticas** | Ocupación y recaudación, top 5 semanal, métodos de pago y auditoría, sin errores | [`database/queries/`](database/queries/) |
| **RBAC** | Roles sin privilegio no pueden modificar salas ni precios | [`Documentos/rbac-matriz.md`](Documentos/rbac-matriz.md), `database/tests/08_permisos_por_rol.sql` |

## 11. Metodología de trabajo

- **Ramas por módulo:** `catalogo`, `venta` y `seguridad`; `main` contiene la versión entregable y solo recibe cambios mediante *Pull Request* revisado por otro integrante.
- **Commits** siguiendo [Conventional Commits](https://www.conventionalcommits.org/es/): `feat(db):`, `docs:`, `fix(app):`, `test:`.
- **Scripts SQL numerados**, ejecutables en orden sobre una base de datos vacía.
- **Seguimiento:** reuniones breves dos veces por semana y entregables por hito.
- Detalle del reparto y de los contratos entre módulos: [`DIVISION-DE-TRABAJO.md`](DIVISION-DE-TRABAJO.md).

## 12. Equipo

| Integrante | Carné | Módulo | Rama | Responsabilidades principales |
|---|---|---|---|---|
| Matías Esquivel Lizano | 2025064711 | A · Catálogo y programación | `catalogo` | Catálogo, funciones, tarifas, factibilidad económica, requisitos, base de la aplicación |
| Juan José Morales Montero | 2025085203 | B · Venta y boletos | `venta` | Bloqueo de asientos, pago, concurrencia, diseño integrado, pantallas de venta |
| Brandon Rojas Garita | 2024089186 | C · Seguridad y acceso | `seguridad` | RBAC, check-in, auditoría, dictamen, riesgos, operación, documento final |

## 13. Documentación

| Documento | Descripción |
|---|---|
| [`DIVISION-DE-TRABAJO.md`](DIVISION-DE-TRABAJO.md) | Contexto completo, reglas de negocio y reparto por módulo |
| [`Documentos/01a-factibilidad-tecnica-riesgos.md`](Documentos/01a-factibilidad-tecnica-riesgos.md) | Dictamen de rechazo y matriz de riesgos |
| [`docs/01b-factibilidad-economica.md`](docs/01b-factibilidad-economica.md) | Comparativa cloud, CAPEX/OPEX a 3 años y ROI |
| [`docs/01c-almacenamiento.md`](docs/01c-almacenamiento.md) | Dimensionamiento de almacenamiento a 5 años |
| [`docs/02-requisitos.md`](docs/02-requisitos.md) | Requisitos y volúmenes |
| [`docs/03-diseno/integrado.md`](docs/03-diseno/integrado.md) | Diseño integrado: DER global, modelo relacional y decisiones entre módulos |
| [`docs/03-diseno/modulo-catalogo.md`](docs/03-diseno/modulo-catalogo.md) | Módulo A: catálogo, programación y tarifas |
| [`docs/03-diseno/modulo-venta.md`](docs/03-diseno/modulo-venta.md) | Módulo B: venta, bloqueo de asientos y pago |
| [`docs/03-diseno/wireframes.md`](docs/03-diseno/wireframes.md) | Bocetos de las pantallas |
| [`docs/04-pruebas/catalogo.md`](docs/04-pruebas/catalogo.md) y [`venta.md`](docs/04-pruebas/venta.md) | Pruebas y evidencias por módulo |
| [`Documentos/05-operacion.md`](Documentos/05-operacion.md) | Respaldos, recuperación ante desastres y SLA |
| [`Documentos/rbac-matriz.md`](Documentos/rbac-matriz.md) | Matriz de roles y permisos |
| [`app/README.md`](app/README.md) | Guía de la interfaz web y contrato con la base de datos |

## 14. Estado del proyecto

- [x] Estructura del repositorio y metodología de trabajo
- [x] Interfaz web conectada a la base de datos (catálogo, venta y seguridad)
- [x] Fase 1 — Análisis de factibilidad
- [x] Fase 2 — Requisitos y dimensionamiento
- [x] Fase 3 — Diseño conceptual, lógico y físico
- [x] Fase 4 — Implementación y pruebas (concurrencia y EXPLAIN ANALYZE incluidos)
- [x] Fase 5 — Operación y mantenimiento
- [ ] Documento técnico final y video de demostración

## 15. Referencias

1. PostgreSQL Global Development Group. *PostgreSQL 16 Documentation*. <https://www.postgresql.org/docs/16/>
2. PostgreSQL. *Table Partitioning*. <https://www.postgresql.org/docs/16/ddl-partitioning.html>
3. PostgreSQL. *EXPLAIN*. <https://www.postgresql.org/docs/16/sql-explain.html>
4. PCI Security Standards Council. *PCI DSS*. <https://www.pcisecuritystandards.org/>
5. Amazon Web Services. *AWS Pricing Calculator*. <https://calculator.aws/>
6. Microsoft. *Azure Pricing Calculator*. <https://azure.microsoft.com/pricing/calculator/>

---

<div align="center">

Proyecto académico · Instituto Tecnológico de Costa Rica · II Semestre 2026

</div>