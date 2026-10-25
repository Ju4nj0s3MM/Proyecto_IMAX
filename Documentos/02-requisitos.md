# Recopilación y análisis de requisitos

## 1. Propósito

Este documento consolida los requisitos funcionales y no funcionales de la plataforma de venta de entradas de IMAX, a partir del flujo de negocio y de las reglas RN-01 a RN-20 de la licitación. También define los volúmenes de datos esperados, que sirven de base para el diseño (`03-diseno/`) y para el cálculo de almacenamiento (`01c-almacenamiento.md`).

## 2. Actores

| Actor | Qué hace en el sistema |
|---|---|
| Cliente o espectador | Consulta la cartelera, compra boletos en línea y ve sus propios códigos QR |
| Taquillero | Vende boletos en taquilla y consulta su propio corte de caja |
| Operador de sala (puerta) | Escanea los códigos QR en la entrada de la sala |
| Contador | Consulta y exporta reportes de ingresos y conciliación |
| Administrador o gerente | Configura cartelera, salas, funciones y precios; gestiona reembolsos, roles y auditoría |
| Pasarela de pago (simulada) | Aprueba o rechaza el pago de una orden |

Los permisos de cada actor se detallan en `rbac-matriz.md`.

## 3. Requisitos funcionales

Cada requisito indica la regla de negocio de la que sale y el módulo de base de datos responsable (A: catálogo, B: venta, C: usuarios, acceso y auditoría).

### 3.1 Catálogo y cartelera

| ID | Requisito | Regla | Módulo |
|---|---|---|---|
| RF-01 | El sistema muestra solo funciones activas cuya fecha y hora de inicio sean futuras. | RN-01 | A |
| RF-02 | Cada función listada muestra título, sinopsis, clasificación de edad, horario y ubicación exacta de la sala (cine, dirección y sala). | RN-02 | A |
| RF-03 | El usuario puede filtrar la cartelera por ubicación (cine o ciudad), fecha y género. | Proceso de comercio electrónico | A |
| RF-04 | El administrador puede crear, modificar y dar de baja películas con sinopsis, clasificación, duración, géneros y póster. | Proceso de programación | A |
| RF-05 | El administrador puede crear cines y salas, definir su capacidad y diseñar el mapa de asientos por zonas (general, VIP, accesible). | Proceso de programación | A |
| RF-06 | El administrador puede programar funciones asignando película, sala y hora de inicio. El sistema calcula la hora de fin con la duración de la película y el tiempo de limpieza de la sala. | Proceso de programación | A |
| RF-07 | El sistema rechaza una función que se traslape con otra en la misma sala, incluido el tiempo de limpieza. | Proceso de programación | A |
| RF-08 | El administrador puede definir tarifas por tipo de entrada, zona de asiento, día de la semana y franja horaria, y promociones 2x1. | Proceso de programación | A |

### 3.2 Selección de asientos y compra

| ID | Requisito | Regla | Módulo |
|---|---|---|---|
| RF-09 | El mapa de asientos muestra el estado actual de cada asiento: disponible, bloqueado, vendido o seleccionado. | RN-03 | B |
| RF-10 | El sistema limita el número de asientos por transacción. | RN-04 | B |
| RF-11 | Al seleccionar asientos, el sistema los bloquea por 2 minutos para ese usuario. Si no paga a tiempo, se liberan automáticamente. | RN-05 | B |
| RF-12 | Dos usuarios no pueden bloquear ni comprar el mismo asiento de la misma función. | RN-03, RN-05 | B |
| RF-13 | Las tarifas especiales (niño, tercera edad, estudiante) se marcan para validar el documento en la puerta. | RN-06 | A |
| RF-14 | Las promociones 2x1 se aplican automáticamente cuando se cumplen sus condiciones (cantidad par de la misma categoría o día específico). | RN-07 | A |
| RF-15 | El total de la compra es la suma exacta de las tarifas de los asientos, menos los descuentos, más los cargos por servicio, con el desglose visible. | RN-08 | A |

### 3.3 Pago y emisión de boletos

| ID | Requisito | Regla | Módulo |
|---|---|---|---|
| RF-16 | El pago se procesa con una pasarela externa simulada. La base de datos no guarda número de tarjeta ni CVV. | RN-09 | B |
| RF-17 | Si el pago es rechazado, la orden se cancela y sus asientos se liberan de inmediato. | RN-10 | B |
| RF-18 | El cobro y el cambio de estado de los asientos ocurren en una sola transacción: o se completan los dos o ninguno. | Arquitectura ACID | B |
| RF-19 | El boleto y su código QR solo se generan después de un pago aprobado. | RN-11 | B |
| RF-20 | Cada boleto tiene un código QR único, asociado a una sola función y un solo asiento. | RN-12 | B |
| RF-21 | El cliente puede ver sus boletos y códigos QR en su perfil. | RN-13 | B |

### 3.4 Control de acceso en puerta

| ID | Requisito | Regla | Módulo |
|---|---|---|---|
| RF-22 | Un código QR solo se acepta una vez. Los intentos posteriores se rechazan con el mensaje "Entrada ya utilizada". | RN-14 | C |
| RF-23 | El sistema rechaza un boleto de otra función, fecha u hora. | RN-15 | C |
| RF-24 | El acceso solo se permite dentro de la tolerancia definida (por ejemplo, desde 30 minutos antes hasta 15 minutos después del inicio). | RN-16 | C |
| RF-25 | Cada lectura de QR, aceptada o rechazada, queda registrada con fecha, boleto, puerta y resultado. | Logs de acceso | C |

### 3.5 Administración, finanzas y auditoría

| ID | Requisito | Regla | Módulo |
|---|---|---|---|
| RF-26 | Solo los roles autorizados pueden modificar precios, anular ventas o crear funciones. | RN-17 | C |
| RF-27 | No se puede modificar ni eliminar el mapa de asientos de una sala que tenga boletos vendidos o reservas para funciones programadas. | RN-18 | A |
| RF-28 | Un boleto solo se puede reembolsar dentro de la política (por ejemplo, hasta 2 horas antes de la función); el asiento queda libre para la venta. | RN-19 | C |
| RF-29 | Toda operación manual de un administrador queda en la bitácora con fecha, hora, IP, rol y usuario. | RN-20 | C |
| RF-30 | El sistema registra en bitácoras separadas las transacciones financieras, los cambios de estado de asientos, los accesos en puerta y las operaciones administrativas, y las conserva 5 años. | RN-20 | B, C |
| RF-31 | El dashboard muestra en tiempo real el porcentaje de ocupación, los ingresos por función, los métodos de pago más usados y el top de funciones. | Panel de administración | A, B |
| RF-32 | La gerencia puede consultar las cuatro consultas analíticas mínimas: ocupación y recaudación por función, top 5 de la semana, métodos de pago preferidos y auditoría de operaciones críticas. | Consultas analíticas | A, B, C |

## 4. Requisitos no funcionales

| ID | Categoría | Requisito | Cómo se cumple |
|---|---|---|---|
| RNF-01 | Disponibilidad | SLA de 99,99 % (máximo 52,6 minutos de inactividad al año) | Copias en varias zonas y regiones (`05-operacion.md`) |
| RNF-02 | Recuperación | RTO menor a 5 minutos | Conmutación automática a la réplica |
| RNF-03 | Pérdida de datos | RPO de 5 segundos o menos (ideal 0) | Réplica síncrona entre zonas y asíncrona monitoreada entre regiones |
| RNF-04 | Rendimiento | Soportar 50 000 transacciones por segundo durante los 10 minutos de apertura de taquilla | Réplicas de lectura, autoescalado e índices sobre las consultas de cartelera y asientos |
| RNF-05 | Concurrencia | 8 000 000 de usuarios concurrentes en un estreno sin doble venta | Restricción de unicidad por función y asiento activo, y transacciones ACID |
| RNF-06 | Tiempo de respuesta | La cartelera y el mapa de asientos responden en menos de 1 segundo con carga normal | Índices justificados con `EXPLAIN ANALYZE` |
| RNF-07 | Seguridad de pagos | Cumplimiento de PCI DSS: sin número de tarjeta ni CVV en la base de datos | Pasarela certificada y solo los últimos 4 dígitos |
| RNF-08 | Seguridad de acceso | Contraseñas guardadas solo como hash bcrypt; acceso con privilegio mínimo por rol | `pgcrypto` y roles de PostgreSQL |
| RNF-09 | Auditabilidad | Bitácoras inalterables, retenidas 5 años | Tablas de solo inserción, particionadas por mes, con copias inmutables |
| RNF-10 | Escalabilidad | Crecer en volumen sin rediseñar el esquema | Particionamiento por fecha y archivado de particiones antiguas |
| RNF-11 | Privacidad | Cumplir leyes de protección de datos (GDPR, Ley 8968 de Costa Rica) | Enmascaramiento y anonimización a solicitud |
| RNF-12 | Integridad | Toda regla de negocio crítica se valida en la base de datos, no solo en la aplicación | Llaves, `CHECK`, `UNIQUE`, `EXCLUDE` y triggers |
| RNF-13 | Portabilidad | Usar un motor estándar sin dependencia de un solo proveedor | PostgreSQL 16 |
| RNF-14 | Usabilidad | La interfaz es funcional y sirve para demostrar los flujos de negocio | Pantallas mínimas de la pauta de revisión |

## 5. Volúmenes de datos esperados

### 5.1 Carga transaccional

| Parámetro | Valor | Origen |
|---|---|---|
| Usuarios concurrentes en un estreno | 8 000 000 | Licitación |
| Transacciones por segundo en el pico | 50 000 TPS | Licitación |
| Duración del pico | 10 minutos | Licitación |
| Operaciones en la ventana pico | 50 000 × 600 s = 30 000 000 | Cálculo |
| Tiempo para atender una operación por usuario | 8 000 000 / 50 000 = 160 s | Cálculo |
| Boletos por mes | 15 000 000 | Licitación |
| Boletos por segundo en promedio | 15 000 000 / 2 592 000 s ≈ 5,8 | Cálculo |
| Órdenes pagadas por mes | 6 000 000 (2,5 boletos por orden) | Supuesto |
| Solicitudes a la aplicación por mes | 1 500 millones | Supuesto de `01b-factibilidad-economica.md` |

El sistema se dimensiona para el pico y no para el promedio: el pico es unas 8 600 veces el promedio de boletos por segundo (aunque el pico incluye lecturas).

### 5.2 Catálogo

| Parámetro | Valor |
|---|---|
| Salas | 1 500 |
| Asientos (unos 300 por sala) | 450 000 |
| Títulos activos | 500 |
| Funciones programadas por mes (5 por sala al día) | 225 000 |

### 5.3 Histórico y auditoría

| Parámetro | Valor |
|---|---|
| Boletos en 5 años | 900 000 000 |
| Filas nuevas de bitácora por mes | Unas 115 600 000 (las cuatro bitácoras) |
| Crecimiento de datos por mes | 33,8 GB (13,2 GB tablas vivas y 20,6 GB bitácoras) |
| Base de datos al final del año 5 | Unos 1,1 TB por copia |
| Total físico a 5 años, con copias y respaldos | Entre 15 y 17 TB |
| Retención mínima | 5 años |

El detalle del cálculo, los supuestos y el desglose por tabla están en `01c-almacenamiento.md`.

## 6. Restricciones del proyecto

- La interfaz gráfica es funcional y sirve de soporte para demostrar los flujos; el foco es la base de datos.
- Los pagos se simulan: basta con un resultado aprobado o rechazado y el comportamiento esperado en la base de datos.
- La prevención de doble venta se demuestra con una restricción de unicidad y transacciones básicas (`BEGIN`, `COMMIT`, `ROLLBACK`), con una prueba de 20 a 50 solicitudes simultáneas sobre el mismo asiento.
- Todo el código y la documentación deben estar en el repositorio público de Git.
