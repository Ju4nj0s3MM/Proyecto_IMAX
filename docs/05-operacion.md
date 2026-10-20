# Operación y mantenimiento

## 1. Objetivos de servicio

| Métrica | Objetivo | Qué mide |
|---|---|---|
| RPO | ≤ 5 segundos (ideal 0) en fallas de infraestructura | Cantidad máxima de datos que se puede perder |
| RTO | Menos de 5 minutos | Tiempo máximo para restablecer el servicio |
| SLA | 99,99 % de disponibilidad | Porcentaje del tiempo en que el servicio está operativo |

En una plataforma de venta de entradas, perder datos significa perder pagos confirmados o asientos ya vendidos, lo que produce dobles ventas, disputas con los clientes y pérdida de ingresos. Durante un estreno mundial cada minuto de inactividad afecta a millones de usuarios en espera, por lo que el plan de recuperación debe ser automático y no depender de una intervención manual.

## 2. Disponibilidad

Un SLA de 99,99 % limita la inactividad permitida a lo siguiente.

| Periodo | Inactividad máxima |
|---|---|
| Año (525 600 min × 0,0001) | 52,6 minutos |
| Mes de 30 días | 4,3 minutos |
| Semana | 1,0 minuto |
| Día | 8,6 segundos |

Con un SLA de 99,95 % se permitirían 262,8 minutos al año (4,4 horas), y con 99,9 % serían 525,6 minutos (8,8 horas). Esos valores son demasiado altos para una plataforma que concentra sus ventas en estrenos de pocas horas, por lo que se adopta 99,99 %.

El SLA de extremo a extremo depende de cada componente en serie, así que no basta con elegir un solo servicio confiable. La arquitectura duplica cada capa: si dos copias independientes tienen una disponibilidad individual de A, la disponibilidad combinada es 1 − (1 − A)². Con A = 99,9 % el resultado es 99,9999 %.

## 3. Arquitectura de alta disponibilidad

| Capa | Componente | Qué falla cubre |
|---|---|---|
| Borde | Red de distribución de contenido (CDN) y firewall de aplicaciones (WAF) | Ataques de denegación de servicio y picos de tráfico estático |
| Entrada | Balanceador de carga | Caída de un servidor de aplicación |
| Aplicación | Contenedores en al menos dos zonas, con autoescalado | Caída de una zona y picos del estreno |
| Base de datos | PostgreSQL primaria con réplica síncrona en otra zona | Caída de la instancia primaria |
| Región | Réplica asíncrona en otra región | Caída de una región completa |
| Reportes | Réplica de lectura | Consultas analíticas que compiten con las ventas |
| Respaldo | Copias completas y archivo continuo de transacciones | Corrupción o borrado de datos |

**Falla de una zona.** La réplica síncrona vive en otra zona de la misma región. Si la primaria falla, el servicio administrado promueve la réplica de forma automática. Como cada transacción se confirma en ambas copias, no se pierden datos (RPO cercano a 0), y la conmutación toma del orden de uno a dos minutos según el proveedor.

**Falla de una región.** La réplica asíncrona en otra región se promueve a primaria y el tráfico se redirige por DNS. El retraso de replicación se monitorea y genera una alerta si supera los 5 segundos, de modo que el RPO se mantenga en ese límite.

## 4. Justificación de RPO y RTO

Cada escenario de falla se resuelve con un mecanismo distinto, y cada mecanismo alcanza valores distintos.

| Escenario | Mecanismo | RPO logrado | RTO logrado |
|---|---|---|---|
| Falla de instancia o de zona | Réplica síncrona y conmutación automática | 0 | 1 a 2 min |
| Falla de región | Réplica asíncrona y cambio de DNS (TTL de 60 s) | ≤ 5 s | < 5 min |
| Corrupción o borrado lógico de datos | Restauración a un punto en el tiempo | ≤ 5 min | < 30 min |
| Alteración de bitácoras o ransomware | Copias inmutables en otra región | ≤ 5 min | < 1 h |

**Por qué se cumple el RPO de 5 segundos o menos.** En una falla de zona la réplica es síncrona: una transacción no se confirma hasta que está en ambas copias, así que no se pierde ninguna. En una falla de región la réplica es asíncrona, por lo que puede existir un pequeño retraso. Ese retraso se mide de forma continua y se emite una alerta cuando supera los 5 segundos, antes de que el riesgo se materialice.

**Por qué se cumple el RTO menor a 5 minutos.** La conmutación entre zonas es automática y no requiere intervención humana, y los servicios administrados la completan en uno o dos minutos. Para una falla de región se suman la promoción de la réplica y la propagación del DNS, que con un TTL de 60 segundos mantienen el total por debajo de los 5 minutos.

**Excepción para los datos dañados.** Si los datos se corrompen o se borran por error, la réplica copia el daño, por lo que la conmutación no sirve. Hay que restaurar desde un respaldo y reproducir el registro de transacciones hasta el instante anterior al incidente. Esto toma más tiempo y por eso el RTO y el RPO objetivo de esos escenarios son mayores, como se indica en los riesgos R-08 y R-09 de `01a-factibilidad-tecnica-riesgos.md`.

