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
