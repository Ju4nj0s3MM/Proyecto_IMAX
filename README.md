# 🎬 IMAX Ticketing Platform — Ecosistema Digital de Cines

![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16-336791?logo=postgresql&logoColor=white)
![CI](https://img.shields.io/badge/DB%20CI-GitHub%20Actions-2088FF?logo=githubactions&logoColor=white)

Propuesta de licitación para modernizar la plataforma global de venta de entradas de IMAX:
cartelera, mapa de asientos en tiempo real, pago simulado, emisión de QR únicos, control de
acceso en puerta, panel de administración y auditoría a 5 años.

> Proyecto 2 — curso de Bases de Datos. La interfaz gráfica es de soporte; el foco es el
> **ciclo de vida de la base de datos (DBLC)**.

## Contenido
| Carpeta | Qué contiene |
|---|---|
| [`docs/`](docs) | Documento técnico por fase: factibilidad, requisitos, diseño, pruebas, operación |
| [`database/`](database) | DDL, seeds, consultas analíticas, pruebas y evidencias de `EXPLAIN ANALYZE` |
| [`backend/`](backend) | API que orquesta los flujos de negocio |
| [`frontend/`](frontend) | Cartelera, mapa de sala, pago, QR, check-in y dashboard |

## Arranque rápido
```bash
cp .env.example .env
make db-up        # levanta PostgreSQL
make db-reset     # recrea esquema y carga seeds
make db-shell     # consola psql
```

## Equipo
| Rol | Integrante | Responsabilidad principal |
|---|---|---|
| Arquitectura y documentación | @USUARIO_A | Fases 1, 2, 5, documento final, consultas analíticas |
| Datos | @USUARIO_B | Fases 3 y 4: modelo, DDL, triggers, índices, RBAC en BD |
| Aplicación | @USUARIO_C | GUI, backend, prueba de concurrencia, demo |

## Fases (DBLC) y estado
- [ ] Fase 1 — Análisis de factibilidad
- [ ] Fase 2 — Requisitos y dimensionamiento
- [ ] Fase 3 — Diseño conceptual, lógico y físico
- [ ] Fase 4 — Implementación y pruebas
- [ ] Fase 5 — Operación y mantenimiento

## Flujo de trabajo
Ver [`CONTRIBUTING.md`](CONTRIBUTING.md) y [`docs/GUIA-DE-TRABAJO.md`](docs/GUIA-DE-TRABAJO.md).
