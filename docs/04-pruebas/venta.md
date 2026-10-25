# Pruebas del módulo B: venta, bloqueo de asientos y pago

Este documento reúne las pruebas del módulo de venta y su evidencia: las restricciones de las tablas, las seis funciones, la prueba de concurrencia (doble venta) y la comparación de rendimiento con `EXPLAIN ANALYZE`.

## Cómo correrlas

Desde la raíz del repositorio, con PostgreSQL 16 y `psql` en el PATH. En Windows, antes de empezar:

```powershell
chcp 65001
$env:PGCLIENTENCODING = "UTF8"
$env:PGPASSWORD = "su_clave"
```

```bash
psql -U postgres -c "drop database if exists imax"
psql -U postgres -c "create database imax"
psql -U postgres -d imax -f database/ddl/ddls.sql        # tablas, funciones, triggers, roles e índices
psql -U postgres -d imax -f database/seeds/seeds.sql     # datos de demostración
psql -U postgres -d imax -f database/queries/queries.sql # consultas analíticas
psql -U postgres -d postgres -f database/tests/tests.sql # todas las pruebas
```

- `tests.sql` es la unión de los scripts de `database/tests/`. Cada grupo de pruebas corre en una base nueva, copiada de `imax_base` (DDL más el seed del catálogo), porque las pruebas usan ids fijos y no se pueden mezclar. Al final borra `imax_base` e `imax_prueba`; la base `imax` no se toca.
- Las pruebas de venta están en `database/tests/01_restricciones.sql`. Cada una dice `Resultado esperado: FUNCIONA` o `ERROR` (con la causa), así que el resultado se compara a ojo contra la salida.
- Un `ERROR` en la salida no es una falla: la mayoría son pruebas que verifican que la base rechace algo.

## Resumen por grupo

| Grupo | Pruebas | Qué verifica |
|---|---|---|
| Restricciones de las tablas | 39 | CHECK de estados y totales, índice único de asiento activo, un solo pago aprobado por orden, QR y reserva únicos en boleto, bitácoras inalterables y particiones por mes |
| `fn_liberar_expirados` | 8 | Los bloqueos vencidos pasan a `EXPIRADO`, los vigentes no se tocan, la orden queda `EXPIRADA`, queda rastro en las dos bitácoras |
| `fn_mapa_asientos` | 7 | Función sin ventas, asientos vendidos, bloqueados vigentes y vencidos, solo los asientos activos de la sala |
| `fn_bloquear_asientos` | 13 | Bloqueo de 1 a 6 asientos, asiento ya tomado, más de 6, sin asientos, repetidos, asiento de otra sala, función cancelada o pasada |
| `fn_asignar_tipos` | 10 | Tipo de entrada por asiento, totales de la orden, orden ajena, orden que no está pendiente, bloqueo vencido, asientos distintos a los bloqueados |
| `fn_confirmar_pago` | 13 | Pago aprobado y rechazado, doble pago, orden ajena, sin tipos, método inexistente, resultado inválido, bloqueo vencido, bitácoras |
| Seed de venta y consultas | 6 | El seed deja 3 órdenes pagadas, 1 cancelada, 1 expirada y 1 pendiente; las consultas 1 y 3 dan los valores esperados |
| `fn_mis_boletos` | 6 | Solo se ven los boletos propios, un pago rechazado no genera boletos |

En total son 102 pruebas de venta. Las pruebas de catálogo y de seguridad están en [catalogo.md](catalogo.md) y en `database/tests/07_checkin_reembolso.sql` y `08_permisos_por_rol.sql`.

## Evidencia: pago aprobado

Prueba 1 de `fn_confirmar_pago`: el usuario 1 bloquea los asientos 1 y 2, elige tipo Adulto y paga con tarjeta simulada.

```text
 resultado_pago | boleto_id |               codigo_qr
----------------+-----------+---------------------------------------
 APROBADO       |         1 | IMAX-1D19CAB04D0D4597A54AC591A1327404
 APROBADO       |         2 | IMAX-E60E5C870C4C48AFB47048F4A6C1F0BA

 estado | tiene_fecha        asiento_id | estado
--------+-------------      ------------+---------
 PAGADA | t                           1 | VENDIDO
                                       2 | VENDIDO

 boletos | codigos_distintos
---------+-------------------
       2 |                 2
```

La orden quedó `PAGADA` con fecha de pago, las reservas `VENDIDO`, y cada asiento tiene su boleto con un QR distinto (RN-11 y RN-12). Volver a pagar la misma orden da `ERROR: La orden ya no está pendiente (PAGADA)`.

## Evidencia: pago rechazado

Prueba 5 y 6: la segunda orden se paga con resultado `RECHAZADO`.

- La función responde `RECHAZADO` sin boleto ni QR.
- La orden queda `CANCELADA` y las reservas `LIBERADO`.
- En `fn_mapa_asientos` los asientos 10 y 11 vuelven a salir `DISPONIBLE` al instante (RN-10).
- No se emitió ningún boleto: la tabla `boleto` sigue con los 2 de la compra anterior.
- Otro usuario puede bloquear el asiento 10 apenas se rechaza el pago (prueba 7).

## Evidencia: concurrencia y doble venta

Script: `app/scripts/concurrencia.js` (Node, usa el paquete `pg` de la aplicación). Corre dos pruebas: muchos clientes bloqueando el mismo asiento a la vez, y el mismo pago enviado varias veces a la vez. Cada hilo usa su propia conexión a la base y todos arrancan juntos al abrir una compuerta.

```bash
cd app
node scripts/concurrencia.js 30
```

Salida de la ejecución del 25 de octubre de 2026 (PostgreSQL 16, base `imax` con el seed de demostración):

```text
Prueba 1: 30 clientes bloquean el asiento 70 de la función 3 al mismo tiempo
  bloqueos exitosos: 1  (esperado: 1)
  rechazados (29): Asiento no disponible: otro usuario lo tiene bloqueado o comprado
  reservas activas en la base: 1  (esperado: 1)
Prueba 2: 10 envíos simultáneos del pago de la orden 39
  pagos aceptados: 1  (esperado: 1)
  pagos aprobados guardados: 1  (esperado: 1)
  boletos emitidos: 1  (esperado: 1)

RESULTADO: FUNCIONA (sin doble venta)
```

De 30 solicitudes idénticas sobre el mismo asiento solo una prospera; las otras 29 chocan con `uq_asiento_activo` y reciben el mensaje de asiento no disponible. En la prueba 2, de 10 pagos simultáneos de la misma orden solo uno se acepta, porque `fn_confirmar_pago` bloquea la orden con `for update` y el resto la encuentra ya `PAGADA`. Cumple el umbral de 20 a 50 solicitudes simultáneas que pide el enunciado. Se puede repetir con más hilos: `node scripts/concurrencia.js 50`.

## Rendimiento: EXPLAIN ANALYZE antes y después

Datos masivos: `12_masivo_catalogo.sql` (unas 907 000 funciones) y `14_masivo_venta.sql` (726 375 órdenes pagadas, 726 375 pagos y 2 011 500 boletos). Script: `database/explain/02_explain_venta.sql`. Se corrió una vez sin los índices y otra con `09_venta_indices.sql`. Salidas completas en `database/explain/resultados/`.

| Consulta | Antes | Después | Plan después |
|---|---|---|---|
| Ocupación y recaudación de una función (consulta 1) | 280,6 ms | 0,26 ms | `Index Only Scan` en `idx_boleto_funcion` e `Index Scan` en `idx_orden_funcion_estado` (antes: `Seq Scan` en `boleto` y en `orden`) |
| Liberar bloqueos vencidos | 107,8 ms | 0,009 ms | `Index Scan` en `idx_reserva_bloqueo` |
| Mapa de asientos de una función | 1,2 ms | 2,4 ms | Sin cambio de plan: ya usaba `uq_asiento_activo` y el índice de asientos de la sala |
| Métodos de pago (consulta 3) | 263,6 ms | 254,3 ms | Sin cambio: `Seq Scan` en `pago`, a propósito |

La consulta de ocupación baja de 281 ms a 0,26 ms, unas mil veces menos, al pasar de `Seq Scan` sobre más de 2 millones de boletos a un `Index Only Scan`. La consulta de bloqueos vencidos pasa de recorrer toda `reserva_asiento` a un índice parcial que solo contiene los bloqueos vigentes.

El mapa de asientos es la consulta más frecuente y ya era rápida gracias al índice único parcial del diseño; la diferencia de 1,2 a 2,4 ms es ruido entre ejecuciones (el plan es el mismo). La consulta de métodos de pago agrupa más del 90 % de los pagos, así que PostgreSQL elige recorrer la tabla completa; un índice no ayudaría y por eso no se creó.

## Pruebas de la interfaz

Con la aplicación en modo real (`MOCK=false`), usuario `cliente@imax.test`:

| Paso | Resultado |
|---|---|
| Entrar con correo y contraseña (hash en la base) | Sesión como "Ana Cliente · cliente" |
| Mapa: elegir asientos y reservar | Bloqueo de 2 minutos con contador |
| Pantalla de pago: tipo de entrada por asiento y total | Desglose con subtotal, descuento, cargo y total |
| Pago aprobado | Redirige a "Mis entradas" con un boleto y un QR por asiento |
| Mis entradas | Ocho boletos del seed (seis de venta y dos de la demo de check-in) más los de la compra nueva, ordenados por fecha |
| Reportes con `cliente` | Error de permiso (403) |
| Reportes con `admin@imax.test` | Ocupación y recaudación de la función, porcentaje por método de pago |

El flujo completo por la API (reservar, elegir tipos, pagar, mis boletos y los dos reportes) también se verificó por separado contra la base real.