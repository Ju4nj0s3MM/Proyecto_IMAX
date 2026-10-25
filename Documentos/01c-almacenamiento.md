# Dimensionamiento del almacenamiento a 5 años

## 1. Propósito

Este documento calcula cuánto espacio necesita la base de datos de la plataforma, mes a mes y acumulado a 5 años, para cumplir la regla RN-20 (retención de auditoría por 5 años). El resultado se usa en `01b-factibilidad-economica.md` para justificar el costo de almacenamiento de cada proveedor.

El cálculo se separa en dos grupos, como pide la licitación:

- **Tablas vivas**: las que usa la operación diaria (órdenes, reservas de asientos, pagos, boletos y funciones).
- **Bitácoras de auditoría**: `transaccion_log`, `asiento_auditoria_log`, `acceso_puerta_log` y `admin_operacion_audit`.

## 2. Datos de entrada

**Datos fijados por la licitación**

| Parámetro | Valor |
|---|---|
| Salas en el mundo | 1 500 |
| Títulos activos | 500 |
| Boletos vendidos por mes | 15 000 000 |
| Retención obligatoria de auditoría | 5 años (60 meses) |

**Supuestos del equipo**

Estos valores no vienen en la licitación. Se eligieron de forma conservadora y cualquiera se puede cambiar en el cálculo.

| Supuesto | Valor | Razón |
|---|---|---|
| Boletos por orden | 2,5 | Compras típicas de pareja o familia; el máximo por transacción es menor (RN-04) |
| Órdenes pagadas por mes | 15 000 000 / 2,5 = 6 000 000 | Se deriva del anterior |
| Órdenes abandonadas o expiradas | 1 por cada orden pagada (6 000 000) | Muchos usuarios bloquean asientos y no pagan en 2 minutos (RN-05) |
| Pagos rechazados | 10 % de las órdenes pagadas (600 000) | Tarjetas sin fondos o datos erróneos (RN-10) |
| Lecturas de QR por boleto | 1,05 | Incluye segundos intentos y rechazos por horario (RN-14 a RN-16) |
| Reembolsos | 1 % de los boletos (150 000) | Cancelaciones dentro de la política (RN-19) |
| Operaciones manuales de administradores | 50 000 por mes | Cortesías, cambios de asiento, reembolsos forzados y cambios de configuración |
| Funciones programadas | 1 500 salas × 5 funciones al día × 30 días = 225 000 por mes | Programación habitual de un cine |
| Usuarios registrados | 20 000 000 al inicio y 1 000 000 nuevos por mes | Base de clientes de una cadena global |
| Factor de índices, tablas vivas | 60 % del tamaño de los datos | Llave primaria, llaves foráneas, `codigo_qr` único e índices de consulta |
| Factor de índices, bitácoras | 30 % del tamaño de los datos | Solo llave primaria y uno o dos índices por fecha |
| Compresión al archivar | El archivo ocupa el 30 % del tamaño original | Los datos de bitácora son repetitivos y se comprimen bien |

## 3. Tamaño estimado por fila

En PostgreSQL cada fila ocupa unos 24 bytes de encabezado más 4 bytes del puntero dentro de la página, y después el tamaño de sus columnas: 8 bytes por `bigint`, `timestamptz` y `numeric(12,2)` pequeños, y el largo del texto más 1 byte en los `varchar`. Con eso se estimó cada tabla a partir de los scripts del repositorio.

| Tabla | Script | Columnas que más pesan | Bytes por fila |
|---|---|---|---|
| `orden` | `03_venta.sql` | 3 llaves, estado, 4 montos, 2 fechas | 120 |
| `reserva_asiento` | `03_venta.sql` | 5 llaves, estado, 3 montos, 2 fechas | 120 |
| `pago` | `03_venta.sql` | 3 llaves, monto, resultado, referencia, últimos 4 dígitos | 120 |
| `boleto` | `03_venta.sql` | 5 llaves, `codigo_qr` de 64 caracteres, estado, 2 fechas | 160 |
| `funcion` | `01_catalogo.sql` | 3 llaves, 3 fechas, estado | 100 |
| `usuario` | `01_catalogo.sql` y `02_seguridad_usuarios.sql` | nombre, correo, hash bcrypt de 60 caracteres, teléfono | 300 |
| `transaccion_log` | `03_venta_logs.sql` | 3 llaves, tipo, monto, resultado, detalle de hasta 200 caracteres | 200 |
| `asiento_auditoria_log` | `03_venta_logs.sql` | 5 llaves, estado anterior y nuevo, fecha | 100 |
| `acceso_puerta_log` | `04_seguridad_acceso.sql` | boleto, puerta, `codigo_qr` de 64 caracteres, resultado, motivo, fecha | 120 |
| `admin_operacion_audit` | `04_seguridad_acceso.sql` | usuario, rol, IP, acción, tabla, registro, motivo de hasta 300 caracteres y detalle `jsonb` | 600 |

El tamaño de las dos últimas se estimó antes de que existiera su DDL. Con el script actual, `acceso_puerta_log` guarda el código QR completo y una fila ronda los 150 bytes en vez de 120. La diferencia es de unos 0,6 GB al mes (menos del 2 % del total), así que no cambia las conclusiones; al medir con el método de la sección 8 se puede ajustar.

## 4. Volumen mensual por tabla

**Cantidad de filas por mes**

- `reserva_asiento`: cada boleto vendido deja una reserva `VENDIDO` y cada orden abandonada deja reservas `EXPIRADO` o `LIBERADO`. Con una orden abandonada por cada pagada: 15 000 000 × 2 = 30 000 000.
- `transaccion_log`: cada orden pagada registra un bloqueo, un pago y 2,5 emisiones de boleto (6 000 000 × 4,5 = 27 000 000); cada orden abandonada registra un bloqueo y una liberación (6 000 000 × 2 = 12 000 000); se suman 600 000 pagos rechazados y 150 000 reembolsos. Total: 39 750 000.
- `asiento_auditoria_log`: cada asiento vendido pasa por `BLOQUEADO` y `VENDIDO`, y cada asiento abandonado por `BLOQUEADO` y `EXPIRADO`. Total: 15 000 000 × 2 + 15 000 000 × 2 = 60 000 000.
- `acceso_puerta_log`: 15 000 000 × 1,05 = 15 750 000.

| Grupo | Tabla | Filas por mes | Bytes por fila | Datos (GB) | Con índices (GB) |
|---|---|---|---|---|---|
| Vivas | `orden` | 12 000 000 | 120 | 1,44 | 2,30 |
| Vivas | `reserva_asiento` | 30 000 000 | 120 | 3,60 | 5,76 |
| Vivas | `pago` | 6 600 000 | 120 | 0,79 | 1,27 |
| Vivas | `boleto` | 15 000 000 | 160 | 2,40 | 3,84 |
| Vivas | `funcion` | 225 000 | 100 | 0,02 | 0,04 |
| **Subtotal vivas** | | | | | **13,21** |
| Bitácora | `transaccion_log` | 39 750 000 | 200 | 7,95 | 10,34 |
| Bitácora | `asiento_auditoria_log` | 60 000 000 | 100 | 6,00 | 7,80 |
| Bitácora | `acceso_puerta_log` | 15 750 000 | 120 | 1,89 | 2,46 |
| Bitácora | `admin_operacion_audit` | 50 000 | 600 | 0,03 | 0,04 |
| **Subtotal bitácoras** | | | | | **20,63** |
| **Total mensual** | | | | | **33,84** |

Se usa 1 GB = 1 000 000 000 bytes.

A esto se suma la tabla `usuario`: 20 000 000 × 300 bytes × 1,6 = 9,6 GB al inicio, más 0,48 GB por mes. El resto del catálogo (cines, salas, 450 000 asientos, películas, tarifas y promociones) cabe en menos de 1 GB y se cuenta como 1 GB fijo. Los pósteres de las películas no se guardan en la base de datos sino en almacenamiento de objetos: 500 títulos × 5 MB = 2,5 GB.

La bitácora de bloqueos de asientos es la tabla con más filas, pero `transaccion_log` es la que más espacio ocupa, porque guarda un texto de detalle por evento. Juntas, las bitácoras son el 61 % del crecimiento mensual.

## 5. Acumulado a 5 años y capas de almacenamiento

Siguiendo la política de `05-operacion.md`:

- **Capa caliente (base de datos)**: las tablas vivas se conservan completas y las bitácoras solo los últimos 12 meses, en particiones mensuales.
- **Capa de archivo**: las particiones de bitácora con más de 12 meses se desvinculan, se exportan comprimidas sin índices a almacenamiento de archivo inmutable y se borran de la base de datos.
- **Respaldos mensuales a 5 años**: además de los respaldos diarios de 35 días, se guarda un respaldo completo y comprimido al cierre de cada mes, durante 60 meses, para cumplir la retención quinquenal de la nota de arquitectura.

| Mes | Tablas vivas y usuarios (GB) | Bitácoras en la BD (GB) | **Total en la BD (GB)** | Bitácoras archivadas (GB) | Respaldos mensuales acumulados (GB) |
|---|---|---|---|---|---|
| 1 | 24,3 | 20,6 | **44,9** | 0,0 | 13,5 |
| 6 | 92,7 | 123,8 | **216,5** | 0,0 | 235,3 |
| 12 | 174,8 | 247,6 | **422,4** | 0,0 | 841,2 |
| 24 | 339,1 | 247,6 | **586,7** | 57,1 | 2 682,2 |
| 36 | 503,3 | 247,6 | **750,9** | 114,3 | 5 114,5 |
| 48 | 667,6 | 247,6 | **915,2** | 171,4 | 8 138,0 |
| 60 | 831,8 | 247,6 | **1 079,4** | 228,5 | 11 752,9 |

Cómo se leen las columnas:

- **Bitácoras en la BD** deja de crecer en el mes 12, porque cada mes entra una partición nueva y sale la más vieja (12 × 20,63 GB = 247,6 GB).
- **Bitácoras archivadas**: cada partición archivada ocupa 20,63 / 1,3 × 0,30 = 4,76 GB (sin índices y comprimida). Al mes 60 hay 48 particiones: 48 × 4,76 = 228,5 GB.
- **Respaldos mensuales acumulados**: suma de 30 % del tamaño de la BD de cada cierre de mes. Es la capa que más crece, y aun así se guarda en el nivel de archivo más barato.

Si no se archivara nada y todo quedara en la base de datos sin comprimir, al mes 60 la BD ocuparía (13,21 + 20,63) × 60 + 9,6 + 0,48 × 60 + 1 ≈ 2 069 GB, casi el doble de la cifra con capas.

### 5.1 Escenario con crecimiento de 10 % anual

Si el volumen de ventas crece 10 % cada año (el mismo supuesto que se usa en la proyección financiera), los totales quedan así:

| Mes | Total en la BD (GB) | Bitácoras archivadas (GB) | Total (GB) |
|---|---|---|---|
| 12 | 422,4 | 0,0 | 422,4 |
| 24 | 627,3 | 57,1 | 684,4 |
| 36 | 852,0 | 120,0 | 972,0 |
| 48 | 1 098,7 | 189,1 | 1 287,8 |
| 60 | 1 369,4 | 265,1 | 1 634,6 |

El escenario con crecimiento termina el quinto año con unos 1,4 TB en la base de datos, 27 % más que el escenario base.

## 6. Almacenamiento físico (copias y respaldos)

La tabla anterior es el tamaño de una sola copia de los datos. La arquitectura de `05-operacion.md` mantiene varias copias, y cada proveedor las cobra distinto:

- **AWS (Aurora)**: el volumen del clúster se replica en tres zonas sin cobrar cada copia por separado, pero la réplica en otra región (Aurora Global Database) es un segundo volumen que sí se cobra. Total: 2 copias.
- **Azure (PostgreSQL Flexible Server)**: cada servidor tiene su propio disco. Primaria, réplica de alta disponibilidad, réplica de lectura y réplica en otra región son 4 discos.
- **Respaldos diarios de 35 días**: una copia completa más el registro de transacciones (WAL). Se estima que el WAL generado es el doble de lo escrito: 2 × 33,84 GB ≈ 67,7 GB por mes, es decir, 79 GB en 35 días.

| Mes | 1 copia de la BD | BD en AWS (2 copias) | BD en Azure (4 discos) | Respaldos de 35 días | Respaldos mensuales | Bitácoras archivadas | **Total AWS** | **Total Azure** |
|---|---|---|---|---|---|---|---|---|
| 12 | 422,4 | 844,8 | 1 689,7 | 501,4 | 841,2 | 0,0 | **2 187,4 GB** | **3 032,3 GB** |
| 36 | 750,9 | 1 501,8 | 3 003,6 | 829,9 | 5 114,5 | 114,3 | **7 560,4 GB** | **9 062,2 GB** |
| 60 | 1 079,4 | 2 158,8 | 4 317,6 | 1 158,4 | 11 752,9 | 228,5 | **15 298,6 GB** | **17 457,4 GB** |

Al final de los 5 años el almacenamiento total ronda los 15 a 17 TB, de los cuales unos 12 TB son respaldos y bitácoras en la capa de archivo.

## 7. Resumen para el análisis de costos

| Capa | Año 1 | Año 3 | Año 5 | Dónde se guarda |
|---|---|---|---|---|
| Base de datos (1 copia, promedio del año) | 234 GB | 676 GB | 1,0 TB | Disco de la BD administrada |
| Bitácoras archivadas (al cierre del año) | 0 | 114 GB | 229 GB | S3 Glacier Deep Archive o Azure Archive |
| Respaldos mensuales a 5 años (al cierre del año) | 841 GB | 5,1 TB | 11,8 TB | S3 Glacier Deep Archive o Azure Archive |
| Crecimiento mensual de datos nuevos | 33,8 GB | 33,8 GB | 33,8 GB | — |

`01b-factibilidad-economica.md` toma de aquí el promedio anual de la base de datos y el tamaño de la capa de archivo.

## 8. Cómo verificar las estimaciones con datos reales

Cuando estén cargados los seeds masivos (`12_masivo_catalogo.sql`, `13_masivo_seguridad.sql` y `14_masivo_venta.sql`), se puede medir el tamaño real por fila y reemplazar los supuestos de la sección 3:

```sql
-- tamaño promedio de una fila (solo datos)
select avg(pg_column_size(b.*)) as bytes_por_fila from boleto b;

-- tamaño de la tabla, de sus índices y total
select relname,
       pg_size_pretty(pg_relation_size(relid))       as datos,
       pg_size_pretty(pg_indexes_size(relid))        as indices,
       pg_size_pretty(pg_total_relation_size(relid)) as total,
       n_live_tup                                    as filas
  from pg_stat_user_tables
 order by pg_total_relation_size(relid) desc;
```

Si el tamaño medido difiere mucho de la sección 3, se actualizan los bytes por fila y se recalculan las tablas.

## 9. Limitaciones

- Los tamaños por fila son estimaciones de diseño. No incluyen el espacio libre que deja PostgreSQL en las páginas después de actualizaciones (bloat), que el `autovacuum` mantiene acotado.
- Las filas de `acceso_puerta_log` y `admin_operacion_audit` se estimaron antes de tener su DDL (ver la nota de la sección 3).
- La compresión al 30 % depende del formato de exportación. Si la compresión fuera peor, la capa de archivo crece en la misma proporción, pero su costo sigue siendo bajo porque es el nivel más barato.
- El número de órdenes abandonadas puede ser mucho mayor en un estreno mundial. Esos eventos caen en las bitácoras de bloqueo y de transacciones, que se archivan a los 12 meses.
