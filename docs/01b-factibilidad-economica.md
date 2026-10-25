# Factibilidad económica y operativa

## 1. Propósito

Este documento estima cuánto cuesta operar la arquitectura propuesta en `01a-factibilidad-tecnica-riesgos.md` y `05-operacion.md`, compara dos proveedores de nube (AWS y Microsoft Azure) y proyecta el costo a 3 años. También justifica el retorno de la inversión y analiza si la solución es viable de operar.

Todos los precios están en dólares estadounidenses, en la región Este de EE. UU. (N. Virginia en AWS, East US en Azure), con tarifas por uso sin reservas. Se consultaron el 23 de octubre de 2026.

## 2. Arquitectura que se cotiza

Se cotiza la misma arquitectura en ambos proveedores, para que la comparación sea justa.

| Capa | Qué se necesita | AWS | Azure |
|---|---|---|---|
| Base de datos transaccional | PostgreSQL administrado con primaria, copia en otra zona con conmutación automática, réplica para reportes y réplica en otra región | Amazon Aurora PostgreSQL (I/O-Optimized) con Aurora Global Database | Azure Database for PostgreSQL Flexible Server con alta disponibilidad entre zonas y réplicas de lectura |
| Capacidad extra en estrenos | Réplicas de lectura adicionales solo durante las horas del estreno | 4 lectores extra de Aurora | 4 réplicas de lectura extra |
| Aplicación | Contenedores en al menos dos zonas, con autoescalado | Amazon EKS | Azure Kubernetes Service (AKS) |
| Entrada y protección | Balanceador de carga con firewall de aplicaciones (WAF) | Application Load Balancer y AWS WAF | Application Gateway WAF v2 |
| Bitácoras a 5 años | Almacenamiento de archivo inmutable para particiones y respaldos mensuales | Amazon S3 y S3 Glacier Deep Archive | Azure Blob Storage, niveles Hot y Archive |

**Tamaño de la base de datos.** La instancia primaria tiene 32 vCPU y 256 GB de memoria (db.r7g.8xlarge en AWS, E32ds_v5 en Azure). Con esa memoria cabe en caché todo el inventario de asientos de las funciones del día, que es la consulta más frecuente durante un estreno. Las réplicas de reportes y de la otra región son de la mitad de tamaño (16 vCPU y 128 GB); si la región principal cae, la réplica se promueve y se escala.

## 3. Supuestos de uso

| Supuesto | Valor | Cómo se obtuvo |
|---|---|---|
| Horas al mes con capacidad extra | 48 h | 2 estrenos mundiales al mes, 24 horas cada uno |
| Solicitudes a la aplicación por mes | 1 500 millones | 6 000 000 órdenes pagadas × unas 150 llamadas (cartelera, mapa de asientos actualizándose, pago, boleto) más 600 millones de visitas que no compran |
| Datos enviados a internet | 15 000 GB al mes | 1 500 millones de respuestas × 10 KB promedio; los archivos estáticos los sirve el navegador desde caché |
| Nodos de aplicación | 10 nodos de 4 vCPU y 16 GB de base, más 40 en el pico | El pico de 50 000 TPS repartido en 200 vCPU son 250 solicitudes por segundo por vCPU |
| Nodos en la región de respaldo | 2 nodos encendidos | Listos para crecer si se activa la recuperación de región |
| Capacidad del balanceador | 30 unidades de capacidad de base y 500 en el pico | Cada unidad soporta unas 25 conexiones nuevas por segundo |
| Reglas del WAF | 10 reglas | Reglas administradas y limitación de tasa |
| Almacenamiento de la BD | Promedio del año 1: 234 GB por copia | Tomado de `01c-almacenamiento.md` |
| Otros servicios | 10 % del subtotal | Monitoreo, DNS, gestión de claves, transferencia entre regiones |

## 4. Precios unitarios y fuentes

Los precios se tomaron de las páginas oficiales de cada proveedor y de comparadores que publican las mismas tarifas. Varias páginas oficiales cargan sus tablas con JavaScript y no se pueden citar como texto; por eso se citan también los comparadores con su fecha. **Antes de presentar la propuesta, cada valor debe confirmarse en la calculadora oficial** ([AWS Pricing Calculator](https://calculator.aws/) y [calculadora de precios de Azure](https://azure.microsoft.com/pricing/calculator/)).

### 4.1 AWS

| Servicio | Precio | Fuente |
|---|---|---|
| Aurora PostgreSQL db.r7g.8xlarge (32 vCPU, 256 GB) | $3 228 al mes (Aurora Standard) | [Bytebase, precios de Aurora, 19 oct 2026](https://www.bytebase.com/dbcost/aurora-pricing/) |
| Aurora PostgreSQL db.r7g.4xlarge (16 vCPU, 128 GB) | $1 614 al mes (Aurora Standard) | [Bytebase, precios de Aurora](https://www.bytebase.com/dbcost/aurora-pricing/) |
| Recargo de Aurora I/O-Optimized | Unos 30 % más en cómputo, sin cobro por operación de E/S | [Bytebase, precios de Aurora](https://www.bytebase.com/dbcost/aurora-pricing/) |
| Almacenamiento de Aurora I/O-Optimized | $0,225 por GB al mes (**supuesto, verificar**) | [Página oficial de precios de Aurora](https://aws.amazon.com/rds/aurora/pricing/) |
| Clúster de EKS | $0,10 por hora ($73 al mes) | [Spendark, EKS vs AKS vs GKE, mar 2026](https://spendark.com/blog/eks-vs-aks-vs-gke-pricing/) |
| Nodo m7i.xlarge (4 vCPU, 16 GB) | $0,2016 por hora | [Spendark](https://spendark.com/blog/eks-vs-aks-vs-gke-pricing/) |
| Application Load Balancer | $0,0225 por hora y $0,008 por unidad de capacidad (LCU) por hora | [CloudZero, precios de ALB, jul 2026](https://www.cloudzero.com/blog/aws-alb-pricing/) |
| AWS WAF | $5 por lista de control al mes, $1 por regla al mes, $0,60 por millón de solicitudes | [WAF Pricing, AWS WAF, sep 2026](https://wafpricing.com/aws-waf-pricing) |
| S3 Standard | $0,023 por GB al mes | [CostGoat, precios de S3, 20 oct 2026](https://costgoat.com/pricing/amazon-s3) |
| S3 Glacier Deep Archive | $0,00099 por GB al mes | [CostGoat, precios de S3](https://costgoat.com/pricing/amazon-s3) |
| Transferencia de datos a internet | $0,09 por GB (primer tramo) | [Akave, guía de costos de egreso, abr 2026](https://akave.com/blog/what-are-egress-fees-the-complete-guide-for-data-engineers) |

### 4.2 Azure

| Servicio | Precio | Fuente |
|---|---|---|
| PostgreSQL Flexible Server E32ds_v5 (32 vCore, 256 GB) | $2 920 al mes | [Bytebase, precios de Flexible Server, 19 oct 2026](https://www.bytebase.com/dbcost/azure-flexible-server-pricing/) |
| PostgreSQL Flexible Server E16ds_v5 (16 vCore, 128 GB) | $1 460 al mes | [Bytebase, precios de Flexible Server](https://www.bytebase.com/dbcost/azure-flexible-server-pricing/) |
| Alta disponibilidad entre zonas | Duplica aproximadamente el cómputo (se paga el servidor de espera) | [Bytebase, precios de Flexible Server](https://www.bytebase.com/dbcost/azure-flexible-server-pricing/) |
| Almacenamiento de Flexible Server | Unos $0,115 por GB aprovisionado al mes | [C3X, costo de PostgreSQL Flexible Server, jun 2026](https://c3x.dev/blog/azure-postgresql-flexible-server-cost/) |
| AKS, nivel Standard | $0,10 por clúster por hora ($73 al mes) | [Spendark](https://spendark.com/blog/eks-vs-aks-vs-gke-pricing/) |
| Nodo D4s v5 (4 vCPU, 16 GB) | $0,192 por hora | [Spendark](https://spendark.com/blog/eks-vs-aks-vs-gke-pricing/) |
| Application Gateway WAF v2 | $0,36 por hora y $0,0144 por unidad de capacidad por hora | [WAF Pricing, Azure WAF, sep 2026](https://wafpricing.com/azure-waf-pricing) |
| Blob Storage Hot (LRS) | $0,018 por GB al mes | [Finout, comparación de almacenamiento, sep 2026](https://www.finout.io/blog/cloud-storage-pricing-comparison) |
| Blob Storage Archive (LRS) | $0,00099 por GB al mes | [Finout](https://www.finout.io/blog/cloud-storage-pricing-comparison) |
| Transferencia de datos a internet | $0,087 por GB (primer tramo) | [Akave](https://akave.com/blog/what-are-egress-fees-the-complete-guide-for-data-engineers) |

## 5. Comparativa de costos mensuales (año 1)

### 5.1 Cálculo de cada línea

**AWS**

- **Base de datos (cómputo):** primaria db.r7g.8xlarge $3 228 + lector en otra zona db.r7g.8xlarge $3 228 + lector de reportes db.r7g.4xlarge $1 614 + lector en otra región db.r7g.4xlarge $1 614 = $9 684 con Aurora Standard. Con I/O-Optimized: $9 684 × 1,3 = **$12 589**. Se elige I/O-Optimized porque un estreno genera millones de lecturas y escrituras de asientos, y así el costo no depende de cuántas operaciones de E/S se hagan.
- **Lectores extra en estrenos:** 4 × ($3 228 / 730 h) × 48 h × 1,3 = **$1 104**.
- **Almacenamiento de la BD:** 234 GB × 2 copias × $0,225 = **$105**.
- **Kubernetes:** 2 clústeres × $73 = $146; 10 nodos × $0,2016 × 730 h = $1 471,68; pico de 40 nodos × 48 h × $0,2016 = $387,07; 2 nodos en la región de respaldo = $294,34. Total **$2 299**.
- **Balanceador y WAF:** ALB $0,0225 × 730 = $16,43; 30 LCU × $0,008 × 730 = $175,20; pico de 500 LCU × 48 h × $0,008 = $192,00; WAF $5 + 10 reglas × $1 + 1 500 millones × $0,60 = $915. Total **$1 299**.
- **Bitácoras a 5 años:** copia caliente de las bitácoras del último año (unos 60 GB × $0,023 = $1,38) más respaldos mensuales en Deep Archive (unos 333 GB en promedio el primer año × $0,00099 = $0,33). Total **$2**.
- **Transferencia a internet:** 15 000 GB × $0,09 = **$1 350**.

**Azure**

- **Base de datos (cómputo):** primaria E32ds_v5 $2 920 + servidor de espera de alta disponibilidad $2 920 + réplica de reportes E16ds_v5 $1 460 + réplica en otra región E16ds_v5 $1 460 = **$8 760**.
- **Réplicas extra en estrenos:** 4 × ($2 920 / 730 h) × 48 h = **$768**.
- **Almacenamiento de la BD:** cada servidor tiene su propio disco; con 512 GB aprovisionados en los 4 servidores: 512 × 4 × $0,115 = **$236**.
- **Kubernetes:** 2 clústeres × $73 = $146; 10 nodos × $0,192 × 730 h = $1 401,60; pico de 40 nodos × 48 h × $0,192 = $368,64; 2 nodos en la región de respaldo = $280,32. Total **$2 197**.
- **Balanceador y WAF:** $0,36 × 730 = $262,80; 30 unidades × $0,0144 × 730 = $315,36; pico de 500 unidades × 48 h × $0,0144 = $345,60. Total **$924**. En Application Gateway WAF v2 el firewall no cobra por solicitud.
- **Bitácoras a 5 años:** 60 GB × $0,018 = $1,08 más unos 333 GB × $0,00099 = $0,33. Total **$1**.
- **Transferencia a internet:** 15 000 GB × $0,087 = **$1 305**.

### 5.2 Tabla comparativa

| Componente | AWS | Azure |
|---|---|---|
| Base de datos transaccional (cómputo) | $12 589 | $8 760 |
| Capacidad extra en estrenos | $1 104 | $768 |
| Almacenamiento de la base de datos | $105 | $236 |
| Cómputo de aplicación (Kubernetes) | $2 299 | $2 197 |
| Balanceador de carga y WAF | $1 299 | $924 |
| Almacenamiento de bitácoras y respaldos a 5 años | $2 | $1 |
| Transferencia de datos a internet | $1 350 | $1 305 |
| **Subtotal** | **$18 748** | **$14 191** |
| Otros servicios (10 %) | $1 875 | $1 419 |
| **Costo mensual total (OPEX)** | **$20 623** | **$15 610** |

**Lo que más pesa es la base de datos.** Sumando cómputo, capacidad extra y almacenamiento, representa el 74 % del subtotal en AWS y el 69 % en Azure. El almacenamiento de las bitácoras a 5 años, en cambio, es casi gratis en el nivel de archivo: incluso al quinto año, con unos 12 TB archivados (ver `01c-almacenamiento.md`), cuesta 12 000 GB × $0,00099 ≈ $12 al mes.

### 5.3 Costo por millón de transacciones

| Indicador | AWS | Azure |
|---|---|---|
| Costo mensual | $20 623 | $15 610 |
| Solicitudes por mes | 1 500 millones | 1 500 millones |
| **Costo por millón de solicitudes** | **$13,75** | **$10,41** |
| Costo por boleto vendido (15 000 000 al mes) | $0,0014 | $0,0010 |

## 6. Selección del proveedor

Se selecciona **Microsoft Azure**. Su costo mensual es 24 % menor ($15 610 contra $20 623), y la diferencia viene casi toda de la base de datos.

| Criterio | AWS | Azure |
|---|---|---|
| Costo mensual | $20 623 | **$15 610** |
| Motor | PostgreSQL compatible (Aurora) | **PostgreSQL de la comunidad**, el mismo que usa el proyecto |
| Conmutación entre zonas | Automática | Automática |
| Lecturas desde la copia de alta disponibilidad | Sí, el lector de la otra zona atiende consultas | No, el servidor de espera no atiende consultas |
| Réplica en otra región | Aurora Global Database | Réplica de lectura entre regiones |
| Cumplimiento de RTO < 5 min y RPO ≤ 5 s | Sí | Sí |

AWS tiene una ventaja técnica (el lector de la otra zona también atiende consultas, mientras que en Azure el servidor de espera solo sirve para la conmutación), pero ambas opciones cumplen los objetivos de `05-operacion.md`. Como los dos cumplen, decide el costo. Además, Azure usa PostgreSQL de la comunidad, lo que facilita mover la base de datos a otro proveedor si en el futuro conviene.

## 7. Proyección financiera a 3 años

**CAPEX (inversión inicial, pago único): $40 000.** Es un supuesto del equipo:

- Diseño de la arquitectura, implementación inicial y migración: 600 horas × $50 por hora = $30 000.
- Pruebas de carga del estreno (50 000 TPS) y evaluación de seguridad previa a la certificación PCI DSS: $10 000.

**OPEX (operación mensual):** se parte del costo del año 1 y se aplica un crecimiento de 10 % anual en volumen, el mismo criterio del ejemplo de la licitación. El aumento del almacenamiento en los años 2 y 3 (unos $235 al mes en Azure por pasar a discos de 1 TB) queda cubierto dentro de ese 10 %.

| Concepto | Azure (seleccionado) | AWS (referencia) |
|---|---|---|
| CAPEX inicial | $40 000 | $40 000 |
| OPEX año 1 (mensual × 12) | $187 320 | $247 476 |
| OPEX año 2 (+10 %) | $206 052 | $272 224 |
| OPEX año 3 (+10 %) | $226 657 | $299 446 |
| **Costo total a 3 años** | **$660 029** | **$859 146** |

Con Azure, la propuesta cuesta $199 117 menos en 3 años que con AWS.

**Posible ahorro adicional.** Ambos proveedores ofrecen descuentos por reservar capacidad a 1 o 3 años en la base de datos y los nodos. No se aplicaron, para mantener un escenario conservador; se deben evaluar una vez que la carga real esté estable.

## 8. Retorno de la inversión (ROI)

**Costo por boleto.** Con $15 610 al mes y 15 000 000 de boletos, la infraestructura cuesta $0,0010 por boleto. Si un boleto IMAX cuesta en promedio $15 (supuesto), la infraestructura es el 0,007 % del precio de venta.

**Pérdidas que se evitan.** Se plantea un escenario conservador: con la infraestructura heredada, basta una caída de una hora durante un estreno mundial al año. Si en esa hora se pierden 300 000 boletos (2 % de las ventas de un mes, supuesto), la pérdida es 300 000 × $15 = $4 500 000 por año, sin contar reembolsos, reclamos ni el daño a la marca.

| Indicador | Valor |
|---|---|
| Pérdidas evitadas en 3 años | 3 × $4 500 000 = $13 500 000 |
| Costo total a 3 años | $660 029 |
| **ROI** | ($13 500 000 − $660 029) / $660 029 = **1 945 %** |
| Recuperación de la inversión | $660 029 / ($4 500 000 / 12) ≈ 1,8 meses |

El escenario no incluye las multas por incumplir PCI DSS que implicaría la propuesta heredada (envío de tarjetas y CVV por chat), que por sí solas pueden superar el costo de toda la plataforma.

## 9. Factibilidad operativa

- **Servicios administrados.** El proveedor se encarga de los parches del motor, los respaldos automáticos, la conmutación por error y el reemplazo de hardware. El equipo de IMAX no administra servidores físicos.
- **Tecnología conocida.** PostgreSQL y Kubernetes son tecnologías estándar con mucha oferta de personal capacitado. No hay licencias de base de datos que pagar.
- **Equipo de operación sugerido.** Dos personas de operaciones o administración de bases de datos en turnos, más una guardia reforzada durante cada estreno. El costo de personal no se incluye en este documento porque no es infraestructura.
- **Escalamiento por evento.** Las réplicas y nodos extra se encienden antes del estreno y se apagan al terminar, por lo que el costo del pico solo se paga 48 horas al mes.
- **Puesta en marcha.** Se recomienda migrar por etapas: primero catálogo y cartelera, después la venta, y una prueba de carga completa antes del primer estreno mundial.

## 10. Limitaciones del estimado

- Varios precios vienen de comparadores con fecha, no directamente de la calculadora oficial. Deben confirmarse en las calculadoras de AWS y Azure antes de la entrega.
- El precio del almacenamiento de Aurora I/O-Optimized ($0,225 por GB) es un supuesto que no se pudo verificar en texto.
- La transferencia a internet se calculó con el primer tramo de precios; con 15 TB al mes parte del volumen entra en tramos más baratos, así que la cifra es conservadora.
- No se incluyen impuestos, soporte empresarial del proveedor ni costos de personal.
- El número de solicitudes y de horas de pico son supuestos; si cambian, las líneas de WAF, transferencia y capacidad extra cambian en proporción.
