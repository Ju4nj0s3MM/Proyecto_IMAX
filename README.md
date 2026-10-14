# Proyecto IMAX — Licitación para el Ecosistema Digital de Cines

<<<<<<< HEAD
Proyecto 2 del curso de Bases de Datos (II Sem 2026). Propuesta de una plataforma de venta de entradas
de alta concurrencia: cartelera, asientos en tiempo real, pago simulado, QR, check-in y auditoría.
=======
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16-336791?logo=postgresql&logoColor=white)
![CI](https://img.shields.io/badge/DB%20CI-GitHub%20Actions-2088FF?logo=githubactions&logoColor=white)
>>>>>>> 2d881226cd4190057d3ac00366a3f0b466a02622

**Stack:** PostgreSQL · (backend y frontend: definir) · Git

## Estructura

```
Proyecto_IMAX/
├── README.md
├── .gitignore
├── docs/
│   ├── 01-factibilidad.md      # dictamen, riesgos, costos, almacenamiento
│   ├── 02-requisitos.md        # funcionales, no funcionales, volúmenes
│   ├── 03-diseno.md            # DER, modelo lógico, diseño físico
│   ├── 04-pruebas.md           # concurrencia y EXPLAIN ANALYZE
│   ├── 05-operacion.md         # backups, DR, RTO/RPO, SLA
│   └── img/                    # DER, modelo relacional, capturas
├── database/
│   ├── 01_schema.sql           # tablas, constraints
│   ├── 02_auditoria.sql        # 4 tablas de logs
│   ├── 03_logica.sql           # funciones, triggers, transacciones
│   ├── 04_roles.sql            # RBAC
│   ├── 05_seeds.sql            # datos de prueba
│   ├── 06_consultas.sql        # 4 consultas analíticas
│   └── pruebas/                # script de concurrencia
└── app/                        # interfaz gráfica de soporte
```

## Equipo y responsabilidades

Cada integrante edita **solo sus carpetas**; así casi no hay conflictos.

| Rol | Integrante | Rama | Carpetas |
|---|---|---|---|
| A · Arquitectura y documentación | ______ | `arquitectura` | `docs/` y `database/06_consultas.sql` |
| B · Datos | ______ | `datos` | `database/` (01 a 05) |
| C · Aplicación | ______ | `app` | `app/` y `database/pruebas/` |

## Avance (marcar al terminar)

### A · Arquitectura y documentación
- [ ] Dictamen de rechazo del escenario legado
- [ ] Matriz de riesgos con RTO/RPO
- [ ] Comparativa de 2 nubes, CAPEX/OPEX a 3 años y ROI (con fuentes)
- [ ] Requisitos funcionales, no funcionales y volúmenes
- [ ] Matriz RBAC
- [ ] 4 consultas analíticas
- [ ] Backups, DR, RPO/RTO, SLA y frecuencia de respaldo
- [ ] Ensamblar el documento técnico final

### B · Datos
- [ ] Dimensionamiento de almacenamiento a 5 años
- [ ] DER y modelo lógico (3FN)
- [ ] Diseño físico: índices y particionamiento
- [ ] DDL núcleo con restricción de unicidad contra la doble venta
- [ ] 4 tablas de auditoría
- [ ] Bloqueo temporal de 2 min, pago simulado y compensación (transacciones)
- [ ] Triggers de check-in (QR único, horario, tolerancia) y auditoría
- [ ] Roles y GRANTs (RBAC)
- [ ] Seeds de datos
- [ ] EXPLAIN ANALYZE antes y después de índices

### C · Aplicación
- [ ] Wireframes y flujos
- [ ] Cartelera con filtros
- [ ] Mapa de sala con colores y temporizador
- [ ] Pago simulado
- [ ] Confirmación con QR
- [ ] Check-in en puerta
- [ ] Panel de administración con roles
- [ ] Script de concurrencia (20–50 hilos, 1 solo éxito)
- [ ] Video demo

## Cómo trabajamos con Git

- `main` = versión que se entrega. No se hace push directo.
- Cada quien trabaja en **su rama** (`arquitectura`, `datos`, `app`).

```bash
git switch <tu-rama>
git pull origin main          # traer lo último de main antes de empezar
# ... trabajar ...
git add .
git commit -m "feat(db): crea tabla asiento"
git push origin <tu-rama>
```

Cuando termines un bloque, abre un **Pull Request** de tu rama hacia `main`.
Un compañero lo revisa y aprueba, y luego se hace merge.

**Mensajes de commit:** `feat(db): ...` · `docs: ...` · `fix(app): ...` · `test: ...`

**Reglas:**
- Los `.sql` deben correr en orden sobre una BD vacía, sin errores.
- No subir contraseñas ni datos reales de tarjetas.
- Lo que no está en Git no se revisa.

## Hitos sugeridos
1. Factibilidad y requisitos → 2. Diseño de BD → 3. Implementación de BD → 4. GUI → 5. Pruebas → 6. Documento final y video
