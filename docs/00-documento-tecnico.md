# Documento técnico de arquitectura de datos y propuesta de licitación

Ecosistema digital de cines IMAX · Proyecto 2 · TI-3600 Bases de Datos · II Semestre 2026

Equipo: Matías Esquivel Lizano (módulo A), Juan José Morales Montero (módulo B) y Brandon Rojas Garita (módulo C).

## 1. La propuesta en resumen

La infraestructura heredada (un archivo de Access o SQLite en un equipo de escritorio, una conexión residencial de 50 Mbps, una hoja de cálculo compartida para los asientos y números de tarjeta enviados por chat) se rechaza por no poder sostener 50 000 transacciones por segundo, impedir la doble venta de asientos ni cumplir PCI DSS.

En su lugar se propone una base de datos relacional PostgreSQL 16 administrada en la nube, con réplica en otra zona y otra región, y estos principios:

- Integridad transaccional (ACID) y una restricción de unicidad que impide vender dos veces el mismo asiento.
- Bloqueo temporal de asientos de 2 minutos con liberación automática.
- Ningún dato de tarjeta ni CVV en la base de datos; los pagos se delegan a una pasarela certificada (simulada en este proyecto).
- Control de acceso por roles con privilegio mínimo, aplicado en la base de datos y en la aplicación.
- Bitácoras de transacciones, bloqueos, accesos y operaciones administrativas, particionadas por mes, inalterables y conservadas 5 años.
- Objetivos de recuperación: RPO de 5 segundos o menos, RTO inferior a 5 minutos y SLA de 99,99 %.

## 2. Dónde está cada parte de la licitación

| Lo que pide la licitación | Dónde está |
|---|---|
| Dictamen de rechazo, factibilidad técnica y matriz de riesgos | `01a-factibilidad-tecnica-riesgos.md` |
| Factibilidad económica y comparativa de proveedores cloud | `01b-factibilidad-economica.md` |
| Dimensionamiento del almacenamiento a 5 años | `01c-almacenamiento.md` |
| Requisitos funcionales, no funcionales y volúmenes de datos | `02-requisitos.md` |
| Diseño conceptual, lógico y físico (modelo, índices, particiones) | carpeta `03-diseno/` |
| Interfaz gráfica (pantallas) | `03-diseno/wireframes.md` y carpeta `app/` |
| Scripts SQL de creación (DDL) | carpeta `database/ddl/` |
| Funciones y reglas de negocio en la base de datos | `database/ddl/` (catálogo, venta y seguridad) |
| Consultas analíticas | carpeta `database/queries/` |
| `EXPLAIN ANALYZE` antes y después de los índices | carpeta `database/explain/` |
| Pruebas de concurrencia y funcionales | carpeta `04-pruebas/` y `database/tests/` |
| Respaldos, recuperación ante desastres, RPO, RTO y SLA | `05-operacion.md` |
| Control de acceso basado en roles | `rbac-matriz.md` |
| Datos de prueba | carpeta `database/seeds/` |

## 3. Módulos y responsables

| Módulo | Contenido | Responsable |
|---|---|---|
| A · Catálogo y programación | Cines, salas, asientos, películas, funciones, tarifas y promociones | Matías Esquivel Lizano |
| B · Venta y boletos | Bloqueo de asientos, órdenes, pagos, boletos con QR y bitácoras de venta | Juan José Morales Montero |
| C · Seguridad y acceso | Usuarios y roles, check-in en puerta, reembolsos y auditoría administrativa | Brandon Rojas Garita |

## 4. Cómo ejecutar el proyecto

Las instrucciones de instalación, el orden de los scripts y el uso de la aplicación están en el `README.md` de la raíz del repositorio.