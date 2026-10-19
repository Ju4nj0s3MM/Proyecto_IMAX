# Dictamen técnico de rechazo y análisis de riesgos

## 1. Propósito

Este documento evalúa la infraestructura propuesta por el proveedor saliente para la plataforma de venta de entradas de IMAX y determina si es viable para el estreno mundial simultáneo descrito en la licitación. Incluye además la matriz de riesgos de la solución propuesta, con sus planes de mitigación y sus objetivos de recuperación (RTO y RPO).

El dictamen se limita a la factibilidad técnica y a los riesgos. La factibilidad económica se desarrolla en `01b-factibilidad-economica.md` y el dimensionamiento de almacenamiento en `01c-almacenamiento.md`.

## 2. Carga de referencia

Los datos de la licitación fijan la carga contra la cual se mide cada componente heredado.

| Parámetro | Valor |
|---|---|
| Usuarios concurrentes en el estreno | 8 000 000 |
| Pico de transacciones (compras y lecturas) | 50 000 TPS durante 10 minutos |
| Transacciones en la ventana pico | 50 000 × 600 s = 30 000 000 |
| Salas | 1 500 |
| Títulos activos | 500 |
| Boletos vendidos por mes | 15 000 000 |
| Boletos por año | 180 000 000 |
| Boletos en 5 años | 900 000 000 |
| Promedio de boletos por segundo | 15 000 000 / 2 592 000 s ≈ 5,8 |
| Retención de auditoría | 5 años |
| Disponibilidad objetivo (SLA) | 99,99 % |

El promedio mensual equivale a unos 6 boletos por segundo, mientras que el pico es de 50 000 operaciones por segundo. Ambas cifras no son directamente comparables, porque el pico incluye lecturas, pero muestran que el sistema debe dimensionarse para el pico y no para el promedio.