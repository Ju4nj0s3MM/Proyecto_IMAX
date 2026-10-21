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

## 5. Política de respaldos

| Tipo de copia | Frecuencia | Retención | Destino |
|---|---|---|---|
| Respaldo completo de la base de datos | Diario | 35 días | Otra región |
| Archivo continuo del registro de transacciones (WAL) | Cada 5 minutos como máximo | 35 días | Otra región |
| Copia mensual de bitácoras de auditoría | Mensual | 5 años | Almacenamiento de archivo inmutable |
| Prueba de restauración | Mensual | No aplica | Entorno aislado |

**Frecuencia.** El respaldo completo diario fija el punto de partida de cualquier restauración. El archivo continuo del registro de transacciones permite avanzar desde ese respaldo hasta cualquier instante de los últimos 35 días. Para que ese archivo no dependa de que se llene un segmento, se configura `archive_timeout` en 300 segundos, de modo que nunca pasen más de 5 minutos sin una copia. De ahí sale el RPO de 5 minutos para los escenarios de datos dañados.

**Regla 3-2-1 adaptada a la nube.** Se mantienen tres copias de los datos (la primaria, la réplica y el respaldo), en al menos dos tipos de almacenamiento (disco de base de datos y almacenamiento de objetos), y una copia en una región distinta a la primaria.

**Cifrado.** Los respaldos se cifran en reposo y las claves se administran con un servicio de gestión de claves, separado del acceso a los datos.

## 6. Retención de la auditoría

La regla RN-20 exige conservar durante al menos 5 años los registros de auditoría. Las cuatro bitácoras se guardan en tablas separadas y particionadas por mes:

- `transaccion_log`: intentos de pago, confirmaciones y emisión de boletos.
- `asiento_auditoria_log`: bloqueos, liberaciones y compras de asientos.
- `acceso_puerta_log`: lecturas de códigos QR en puerta.
- `admin_operacion_audit`: operaciones manuales de administradores.

| Antigüedad | Dónde se guardan | Cómo se consultan |
|---|---|---|
| Meses 1 a 12 | Particiones activas en la base de datos | Directamente con SQL |
| Meses 13 a 60 | Particiones desvinculadas y exportadas a almacenamiento de archivo inmutable | Se restauran bajo demanda |
| Después de 60 meses | Elegibles para eliminación según la política de la empresa | No aplica |

**Por qué particionar.** Las particiones mensuales mantienen pequeñas las tablas de uso diario, de modo que las consultas recientes no recorren años de historia. Mover una partición antigua es una operación de metadatos, no un borrado masivo de filas, y no bloquea las ventas.

**Inalterabilidad.** El almacenamiento de archivo se configura con una política de inmutabilidad: durante el periodo de retención nadie, ni siquiera un administrador, puede modificar o borrar los objetos. Dentro de la base de datos, los roles de la aplicación no tienen permisos de `UPDATE` ni de `DELETE` sobre estas tablas.

El volumen de datos y el costo de este almacenamiento se calculan en `01c-almacenamiento.md`.

## 7. Procedimientos de recuperación

**Falla de zona o de instancia.** Es automática.

1. El servicio administrado detecta la falla y promueve la réplica síncrona.
2. La aplicación se reconecta mediante el punto de conexión del clúster, sin cambios de configuración.
3. El equipo de operaciones verifica la nueva primaria y crea una nueva réplica en la zona recuperada.

**Falla de región.**

1. Las alertas de disponibilidad declaran el incidente.
2. Se promueve la réplica de otra región a primaria.
3. Se cambia el DNS hacia la región activa (TTL de 60 segundos).
4. Se mide el retraso de replicación al momento de la falla para conocer cuántos segundos de datos se pudieron perder.
5. Se reconstruye una nueva réplica en la región afectada cuando esta se recupere.

**Datos corruptos o borrados por error.**

1. Se pone la aplicación en modo de mantenimiento para detener las escrituras.
2. Se identifica el instante anterior al incidente consultando las bitácoras de auditoría.
3. Se restaura el último respaldo completo y se reproduce el registro de transacciones hasta ese instante, en una instancia nueva.
4. Se validan los conteos y las sumas de control contra los datos esperados.
5. Se conmuta el tráfico a la instancia restaurada o se reconcilian solo las filas afectadas.

**Alteración de bitácoras o ransomware.**

1. Se aíslan las cuentas comprometidas y se rotan las credenciales.
2. Se restauran las bitácoras desde las copias inmutables de otra región.
3. Se compara el contenido restaurado con la base viva para detectar las filas alteradas.

## 8. Pruebas de recuperación

Un respaldo que nunca se ha restaurado no garantiza nada, por lo que los procedimientos se ensayan de forma periódica.

| Prueba | Frecuencia | Criterio de aceptación |
|---|---|---|
| Restauración de un respaldo en un entorno aislado | Mensual | Restauración completa y conteos de filas iguales a los de producción |
| Restauración a un punto en el tiempo | Trimestral | Datos correctos hasta el instante pedido, en menos de 30 minutos |
| Conmutación entre zonas | Trimestral | Servicio restablecido en menos de 5 minutos, sin pérdida de datos |
| Simulacro de falla de región | Semestral | Servicio restablecido en menos de 5 minutos con un retraso de replicación de 5 segundos o menos |
| Prueba de carga y conmutación antes de un estreno mundial | Antes de cada estreno | Sostiene 50 000 TPS y cumple los tiempos de recuperación |

Cada prueba deja un registro con la fecha, el tiempo medido y los problemas encontrados. Si algún resultado supera los objetivos de RTO o RPO, se corrige el procedimiento y se repite la prueba.