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