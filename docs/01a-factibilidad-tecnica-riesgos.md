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

## 3. Análisis del escenario heredado

### 3.1 Motor de base de datos

La propuesta usa un único archivo de Microsoft Access o SQLite, guardado en un equipo de escritorio con procesador Intel Core i3 de 2012.

- **Escrituras concurrentes.** SQLite admite un solo escritor a la vez sobre el archivo; las demás escrituras esperan o fallan por bloqueo. Access está pensado para pocos usuarios en una red local. Con 50 000 TPS la cola de escrituras crecería sin control.
- **Sin arquitectura cliente-servidor.** El motor corre dentro de la aplicación que abre el archivo. No hay conexiones remotas administradas, roles de base de datos ni replicación.
- **Tamaño.** Un archivo de Access no puede superar 2 GB. Con 900 000 000 de boletos en cinco años y apenas 100 bytes por boleto, solo la tabla de boletos ocuparía unos 90 GB, 45 veces el límite. Las bitácoras de auditoría y los índices aumentan esa cifra.
- **Hardware.** Un procesador de dos núcleos de 2012 no sostiene decenas de miles de transacciones por segundo.
- **Punto único de falla.** Un disco, una fuente de poder y una tarjeta de red. Si cualquiera falla, no hay réplica ni copia activa.
- **Reglas de negocio.** Sin escritura concurrente confiable no se pueden garantizar el bloqueo temporal de asientos (RN-05) ni la prevención de doble venta.

**Veredicto: no cumple.**

### 3.2 Infraestructura y red

Todo el tráfico global se enruta por una conexión residencial de fibra de 50 Mbps con Wi-Fi de 2,4 GHz y un extensor de señal.

- **Ancho de banda por usuario.** 50 Mbps entre 8 000 000 de usuarios son 6,25 bits por segundo por persona, menos de lo que cuesta enviar un solo carácter.
- **Ancho de banda por transacción.** Con una respuesta de apenas 2 KB, 50 000 solicitudes por segundo requieren unos 100 MB/s, es decir, cerca de 800 Mbps. El enlace cubriría la dieciseisava parte de esa demanda (800 / 50 = 16). El mapa de asientos de una sala pesa bastante más que 2 KB, así que la cifra real es mayor.
- **Wi-Fi de 2,4 GHz con extensor.** Es un medio compartido y sujeto a interferencia. Un extensor de una sola radio reduce el rendimiento aproximadamente a la mitad en cada salto.
- **Conexiones simultáneas.** Los routers domésticos suelen soportar del orden de miles de conexiones concurrentes, no millones.
- **Sin protección.** No hay WAF, protección contra ataques de denegación de servicio ni balanceo de carga, y un servicio residencial no ofrece SLA.
- **Alcance global.** Sin una red de distribución de contenido, los usuarios de otros continentes reciben todo desde Los Ángeles con latencias altas.

**Veredicto: no cumple.**

### 3.3 Reserva de asientos en una hoja de cálculo compartida

La propuesta guarda las compras en una hoja de Google Drive donde cada cliente escribe su nombre a mano en el asiento deseado.

- **Límites de la plataforma.** Una hoja de Google Sheets admite hasta 10 millones de celdas, y su API limita las solicitudes a cientos por cada 100 segundos. La carga pico exige 50 000 por segundo, es decir, 5 000 000 de solicitudes cada 100 segundos. Referencia: <https://developers.google.com/workspace/sheets/api/limits>.
- **Sin atomicidad ni aislamiento.** Si dos personas escriben en la misma celda, gana la última escritura. La doble venta de asientos es inevitable.
- **Sin bloqueo temporal.** No existe el bloqueo de 2 minutos con liberación automática (RN-05) ni un estado de asiento visible en tiempo real (RN-03).
- **Sin integridad.** Cualquier persona con acceso puede modificar o borrar las reservas de otra. No hay validaciones, llaves ni restricciones.
- **Sin vínculo con el pago.** La reserva no está asociada a una transacción, por lo que no hay compensación ante un pago fallido (RN-10).
- **Sin comprobante único.** No se genera un código QR único por boleto (RN-12) ni se controla su uso en puerta (RN-14).
- **Sin auditoría confiable.** El historial de versiones de una hoja no es una bitácora inalterable, y no cumple la retención de 5 años (RN-20).

**Veredicto: no cumple.**

### 3.4 Seguridad y pagos

La propuesta reemplaza la pasarela de pago por un formulario web estático que envía los números completos de las tarjetas y los códigos CVV a un chat grupal de WhatsApp, donde un pasante los pasa manualmente por un datáfono.

- **Incumple PCI DSS 4.0, requisito 3.3.1.** Los datos sensibles de autenticación, como el CVV, no pueden conservarse después de la autorización, ni siquiera cifrados. Un chat los conserva indefinidamente en los dispositivos de todos los participantes y en sus copias de respaldo.
- **Incumple PCI DSS 4.0, requisito 4.2.2.** Se prohíbe enviar números de tarjeta sin protección por mensajería de usuario final (correo, SMS, chat). Referencia: <https://www.pcisecuritystandards.org/faqs/1085>.
- **Sin pasarela certificada ni tokenización.** El número completo de la tarjeta circula y queda guardado en sistemas de la empresa, en lugar de ser reemplazado por un token.
- **Alcance ampliado.** Todos los dispositivos de las personas que participan en el chat pasan a formar parte del entorno que PCI DSS obliga a proteger.
- **Capacidad.** Un pasante que procese una tarjeta cada 30 segundos atiende 2 por minuto. Si solo 1 de cada 100 transacciones del pico fuera una compra, serían 300 000 compras: 300 000 × 30 s = 9 000 000 s, unos 104 días de trabajo continuo.
- **Reglas de negocio.** Se viola RN-09 (pasarela certificada y prohibición de guardar el CVV) y RN-11 (no hay confirmación automática de la pasarela antes de emitir el comprobante).
- **Exposición legal.** Una fuga de datos de tarjetas expone a la empresa a sanciones de las marcas y del adquirente, y a reclamos bajo las leyes de protección de datos de cada país, como la Ley 8968 en Costa Rica.

**Veredicto: no cumple. Es una falla crítica.**

### 3.5 Recuperación ante desastres

El plan de contingencia consiste en reiniciar el equipo y esperar que los clientes aguarden a que el sistema regrese.

- **Sin copias de seguridad.** No existe respaldo de la base de datos. Si el disco falla, se pierden todas las ventas, reservas y registros de auditoría. El RPO (pérdida máxima de datos aceptable) es, en la práctica, todo el historial.
- **Sin tiempo de recuperación definido.** El RTO depende de que el mismo equipo vuelva a encender. La licitación exige menos de 5 minutos.
- **Disponibilidad.** Un SLA de 99,99 % permite 525 600 min × 0,0001 ≈ 52,6 minutos de inactividad al año. Un solo apagón de una hora consumiría más que el tiempo permitido en todo el año.
- **Sin redundancia eléctrica ni de hardware.** Un equipo de 2012 bajo carga sostenida es propenso al sobrecalentamiento, y no hay fuente de poder ininterrumpida, segundo servidor ni conmutación automática.
- **Riesgo de corrupción.** Un apagado abrupto durante una escritura puede dejar dañado el archivo de la base de datos, especialmente en Access, y no hay copia desde la cual restaurarlo.
- **Impacto en el estreno.** Con millones de usuarios esperando, cada minuto sin servicio significa ventas perdidas y una experiencia negativa a escala global.
- **Retención de 5 años.** Sin respaldos no se puede cumplir la persistencia obligatoria de los registros de auditoría (RN-20).

**Veredicto: no cumple.**

### 3.6 Dimensionamiento de la carga

La propuesta heredada no incluye ningún cálculo de capacidad. Al aplicar la carga de referencia de la sección 2 se obtiene lo siguiente.

- **Rendimiento de escritura.** Un único escritor serial que tarde 1 ms por transacción atiende como máximo 1 / 0,001 s = 1 000 TPS. El pico exige 50 000 TPS, 50 veces más, y 1 ms es un supuesto optimista para un equipo de 2012.
- **Tiempo de atención.** Para dar una operación a cada uno de los 8 000 000 de usuarios a 50 000 TPS se necesitan 8 000 000 / 50 000 = 160 segundos, siempre que el sistema no se detenga.
- **Volumen de boletos.** 15 000 000 al mes equivalen a 900 000 000 en cinco años, sin contar las bitácoras de transacciones, bloqueos de asientos, accesos en puerta y operaciones administrativas. El cálculo de almacenamiento completo se presenta en `01c-almacenamiento.md`.
- **Carga de lectura.** Los 8 000 000 de usuarios consultan el mapa de asientos antes de comprar, por lo que las lecturas superan a las compras. La propuesta heredada no contempla réplicas de lectura ni caché.

**Veredicto: no cumple.**

## 4. Resumen del análisis

| Componente | Requisito de la licitación | Propuesta heredada | Resultado |
|---|---|---|---|
| Base de datos | 50 000 TPS, escrituras concurrentes y 900 000 000 de boletos | Un escritor, límite de 2 GB en Access | No cumple |
| Red | Cerca de 800 Mbps para 50 000 solicitudes de 2 KB | 50 Mbps residenciales | No cumple |
| Reservas | Bloqueo atómico de 2 minutos, sin doble venta | Hoja de cálculo compartida | No cumple |
| Pagos | Pasarela certificada, sin guardar CVV (RN-09) | Chat de WhatsApp y datáfono manual | No cumple (crítico) |
| Recuperación | RTO < 5 min, RPO ≤ 5 s, SLA 99,99 % | Reiniciar el equipo | No cumple |
| Dimensionamiento | Cálculo de carga y de 5 años de datos | Sin cálculo; máximo cercano a 1 000 TPS | No cumple |

## 5. Dictamen

Se rechaza la propuesta técnica del proveedor saliente. Ninguno de los seis componentes evaluados cumple los requisitos de la licitación, y las fallas se presentan en todas las capas: datos, red, control de inventario, pagos y recuperación.

Dos de ellas son críticas por sí solas. La reserva de asientos en una hoja de cálculo hace inevitable la doble venta, y el envío de números de tarjeta y CVV por chat incumple PCI DSS y expone a la empresa a sanciones y a una fuga de datos. Aunque se corrigieran las demás, cualquiera de estas dos bastaría para descartar la propuesta.

La solución que se propone en su lugar se apoya en estos principios:

- Una base de datos relacional PostgreSQL administrada en la nube, con alta disponibilidad y réplica en otra zona.
- Integridad transaccional ACID y una restricción de unicidad que impide vender dos veces el mismo asiento.
- Pasarela de pago externa certificada, sin almacenar datos de tarjeta en la base de datos propia.
- Balanceo de carga, WAF y red de distribución de contenido para absorber el tráfico del estreno.
- Particionamiento por fecha de las bitácoras de auditoría y respaldos con retención de 5 años.
- Objetivos de recuperación de RPO ≤ 5 segundos, RTO inferior a 5 minutos y SLA de 99,99 %.

El análisis económico se presenta en `01b-factibilidad-economica.md`, los requisitos en `02-requisitos.md`, el diseño en `03-diseno/` y la estrategia de operación en `05-operacion.md`. A continuación se presenta la matriz de riesgos de la solución propuesta.

## 6. Matriz de riesgos y mitigación

La matriz evalúa los riesgos de la solución propuesta. La probabilidad se estima antes de aplicar la mitigación, el impacto describe el efecto sobre la operación si el riesgo ocurre, y el RTO y el RPO son los objetivos que debe cumplir el plan de respaldo.

| ID Riesgo | Descripción del Riesgo | Probabilidad (Baja/Media/Alta) | Impacto (Bajo/Medio/Crítico) | Estrategia de Mitigación / Plan de Respaldo (DRP) | RTO / RPO Objetivo |
|---|---|---|---|---|---|
| R-01 | Caída de la instancia principal de base de datos durante el estreno | Media | Crítico | Alta disponibilidad con réplica síncrona en otra zona y conmutación automática (failover) | RTO < 5 min / RPO ≈ 0 |
| R-02 | Doble venta de asientos por solicitudes simultáneas | Alta | Crítico | Restricción UNIQUE por función y asiento sobre reservas activas, transacciones ACID y prueba de concurrencia con 20 a 50 solicitudes idénticas | RTO 0 (preventivo) / RPO 0 |
| R-03 | Caída o lentitud de la pasarela de pago | Media | Crítico | Segunda pasarela de respaldo, reintentos idempotentes, expiración del bloqueo a los 2 minutos y liberación inmediata de los asientos ante un rechazo (RN-10) | RTO < 2 min / RPO 0 |
| R-04 | Ataque de denegación de servicio (DDoS) durante el estreno | Alta | Crítico | Red de distribución de contenido, WAF y limitación de tasa en el borde, fila virtual de entrada y autoescalado del cómputo | RTO < 5 min / RPO 0 |
| R-05 | Pérdida de consistencia del inventario: bloqueos de asientos que no se liberan | Media | Crítico | Función de liberación de reservas vencidas, bitácora `asiento_auditoria_log` y conciliación periódica del inventario | RTO < 1 min / RPO 0 |
| R-06 | Fuga de datos de tarjetas o incumplimiento de PCI DSS | Baja | Crítico | Sin número de tarjeta ni CVV en la base de datos (RN-09), pasarela certificada con tokenización, TLS 1.2 o superior y cifrado en reposo | No aplica (preventivo) |
| R-07 | Caída total de una región de la nube | Baja | Crítico | Réplica en otra región con promoción a primaria y conmutación del tráfico por DNS | RTO < 5 min / RPO ≤ 5 s |
| R-08 | Corrupción o borrado accidental de datos | Media | Crítico | Respaldo completo diario, archivado continuo del registro de transacciones (WAL) para recuperar a un punto en el tiempo y pruebas periódicas de restauración | RTO < 30 min / RPO ≤ 5 s |
