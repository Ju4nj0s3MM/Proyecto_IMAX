# Pruebas del módulo A: catálogo, salas, programación y tarifas

Este documento reúne las pruebas del módulo A y su evidencia: las reglas de programación, la cartelera (RN-01, RN-02), el cálculo del total con 2x1 (RN-07, RN-08) y la restricción de salas con ventas (RN-18). Al final está la comparación de rendimiento con `EXPLAIN ANALYZE`.

## Cómo correrlas

```bash
dropdb --if-exists imax && createdb imax
psql -d imax -v ON_ERROR_STOP=1 \
  -f database/ddl/01_catalogo.sql -f database/ddl/02_seguridad_usuarios.sql \
  -f database/ddl/03_venta.sql -f database/ddl/03_venta_logs.sql \
  -f database/ddl/04_seguridad_acceso.sql -f database/ddl/05_catalogo_logica.sql \
  -f database/ddl/07_seguridad_logica.sql -f database/seeds/01_catalogo_demo.sql
psql -d imax -f database/tests/05_catalogo_logica.sql
```

- Script: `database/tests/05_catalogo_logica.sql`. Las pruebas que cambian datos terminan en `rollback`, así que se puede correr varias veces.
- Salida completa de la última ejecución: `database/tests/05_catalogo_logica_resultado.txt` (PostgreSQL 16.15, 23 de octubre de 2026).
- El seed crea funciones para mañana y pasado mañana; la prueba 8 usa funciones con fechas fijas para no depender del día en que se corre.

## Resumen

| N.º | Prueba | Regla | Esperado | Obtenido | Resultado |
|---|---|---|---|---|---|
| 1 | Función que se traslapa en la misma sala | Programación | Rechazo | `ERROR: ... ex_funcion_sin_traslape` | Aprobada |
| 2 | Reprogramar en el horario de una función cancelada | Programación | Se permite | `UPDATE 1`, `INSERT 0 1` | Aprobada |
| 3 | Fin y fin de limpieza calculados por el trigger | Programación | Duración y limpieza correctas | Las 8 funciones coinciden | Aprobada |
| 4 | Asiento repetido en una sala | Integridad | Rechazo | `ERROR: ... uq_asiento_sala_fila_numero` | Aprobada |
| 5 | Tarifa repetida | Integridad | Rechazo | `ERROR: ... uq_tarifa_combinacion` | Aprobada |
| 6 | Promoción sin condición | RN-07 | Rechazo | `ERROR: ... ck_promocion_condicion` | Aprobada |
| 7 | Cartelera: solo activas y futuras, con filtros | RN-01, RN-02 | 7 / 3 / 1 / 2 funciones | 7 / 3 / 1 / 2 funciones | Aprobada |
| 8 | Total con tarifas por día y 2x1 | RN-07, RN-08 | Igual al cálculo manual | 8,00 / 27,75 / 6,75 / 16,25 | Aprobada |
| 9 | Modificar una sala con ventas activas | RN-18 | Rechazo con ventas, permitido sin ventas | 4 rechazos y 3 cambios permitidos | Aprobada |

## Prueba 1: traslape de funciones

La función de "Dune: Parte Tres" de mañana a las 14:00 en la sala de Los Ángeles dura 165 minutos y la sala necesita 25 de limpieza, así que la sala está ocupada hasta las 17:10. Se intenta programar otra película a las 16:00.

```text
ERROR:  conflicting key value violates exclusion constraint "ex_funcion_sin_traslape"
DETAIL:  Key (sala_id, tstzrange(inicio, fin_limpieza))=(1, ["2026-10-24 16:00:00-06","2026-10-24 17:10:00-06"))
         conflicts with existing key (sala_id, tstzrange(inicio, fin_limpieza))=(1, ["2026-10-24 14:00:00-06","2026-10-24 17:10:00-06")).
```

La base de datos rechaza la función. El mensaje muestra que el rango incluye el tiempo de limpieza (hasta las 17:10).

## Prueba 2: reprogramar sobre una función cancelada

Se cancela la función de las 21:00 en Los Ángeles y se programa otra película en ese mismo horario: `UPDATE 1` e `INSERT 0 1`. La restricción ignora las funciones canceladas, como se definió con `where (estado <> 'Cancelada')`.

## Prueba 3: cálculo automático del fin

| Película | Sala | Duración | Limpieza |
|---|---|---|---|
| Dune: Parte Tres | Sala 1 IMAX Laser | 02:45:00 | 00:25:00 |
| Océano Profundo | Sala 1 | 00:45:00 | 00:20:00 |
| La Noche Eterna | Sala Premium | 01:52:00 | 00:30:00 |
| La Noche Eterna | Sala 1 | 01:52:00 | 00:20:00 |
| Océano Profundo | Sala 2 | 00:45:00 | 00:20:00 |
| Océano Profundo | Sala 1 IMAX Laser | 00:45:00 | 00:25:00 |

(Se muestra una fila por combinación; la salida completa tiene las 8 funciones.) La duración coincide con `pelicula.duracion_min` y la limpieza con `sala.minutos_limpieza`.

## Pruebas 4, 5 y 6: integridad

```text
ERROR:  duplicate key value violates unique constraint "uq_asiento_sala_fila_numero"
DETAIL:  Key (sala_id, fila, numero)=(1, A, 1) already exists.

ERROR:  duplicate key value violates unique constraint "uq_tarifa_combinacion"
DETAIL:  Key (tipo_entrada_id, zona_asiento_id, COALESCE(dia_semana::integer, 0), hora_desde)=(1, 1, 0, 00:00:00) already exists.

ERROR:  new row for relation "promocion" violates check constraint "ck_promocion_condicion"
```

En la tarifa, el `coalesce(dia_semana, 0)` del índice es lo que detecta el duplicado: sin él, PostgreSQL no considera iguales dos tarifas con `dia_semana` nulo.

## Prueba 7: cartelera

Antes de consultar se agrega una función de ayer y se cancela la de la Sala Premium. Ninguna de las dos debe salir.

| Caso | Esperado | Obtenido |
|---|---|---|
| Sin filtros | 7 funciones (las 8 del seed menos la cancelada), todas futuras | 7 funciones, columna `futura` en `t` en todas |
| Ciudad "San José" | 3 funciones de IMAX San José | Océano Profundo (Sala 1), La Noche Eterna (Sala 1), Océano Profundo (Sala 2) |
| Género "Terror" | Solo La Noche Eterna en San José | La Noche Eterna, "Drama, Terror", IMAX San José |
| Fecha de pasado mañana | 2 funciones | Océano Profundo (San José) y Dune: Parte Tres (Los Ángeles) |

Cada fila trae título, sinopsis, clasificación, géneros, cine, dirección completa (dirección, ciudad y país), sala y hora de inicio, como pide RN-02.

## Prueba 8: total de la compra

Tarifas del seed en zona General: Adulto $8,50, Estudiante $6,50, Adulto mayor $5,50; Adulto los martes $6,00; matiné de Adulto (10:00 a 14:59) $7,00; cargo por servicio $0,75 por boleto. Promociones: "2x1 estudiantes" (vigente 60 días) y "2x1 los miércoles".

| Caso | Cálculo manual | Obtenido (subtotal / descuento / cargo / total) |
|---|---|---|
| 2 estudiantes, sábado | 2 × 6,50 − 6,50 + 2 × 0,75 = **8,00** | 13,00 / 6,50 / 1,50 / **8,00** |
| 3 adultos, sábado, sin promoción | 3 × 8,50 + 3 × 0,75 = **27,75** | 25,50 / 0,00 / 2,25 / **27,75** |
| 1 adulto, martes 11:00 | Tarifa del martes 6,00 (gana a la matiné de 7,00 por ser del día) + 0,75 = **6,75** | 6,00 / 0,00 / 0,75 / **6,75** |
| Miércoles: 2 adultos y 1 adulto mayor | 2 × 8,50 + 5,50 − 8,50 (un adulto gratis) + 3 × 0,75 = **16,25** | 22,50 / 8,50 / 2,25 / **16,25** |
| Asiento de otra sala | Error | `ERROR: Hay asientos que no pertenecen a la sala de la función` |

En el caso del miércoles, el adulto mayor queda solo en su categoría y paga completo: el 2x1 se aplica dentro de cada tipo de entrada, como dice RN-07 ("número par de entradas de la misma categoría"). El cargo por servicio se cobra también en la entrada gratis; es una decisión del equipo documentada en `03-diseno/modulo-catalogo.md`.

## Prueba 9: RN-18

Se vende el asiento A1 de la primera función de mañana en la Sala 1 IMAX Laser (una orden pagada y una reserva `VENDIDO`) y se intenta cambiar la sala.

| Caso | Esperado | Obtenido |
|---|---|---|
| Cambiar la zona de la fila A | Rechazo | `ERROR: RN-18: la sala 1 tiene entradas vendidas o reservadas para funciones programadas, no se puede modificar su mapa de asientos` |
| Borrar la fila H | Rechazo | Mismo error |
| Agregar el asiento I1 | Rechazo | Mismo error |
| Cambiar la capacidad de la sala | Rechazo | `ERROR: RN-18: ... no se puede modificar ni eliminar` |
| Cambiar solo el nombre de la sala | Se permite (no es la distribución) | `UPDATE 1` |
| Cambiar zona en la Sala 1 de San José, sin ventas | Se permite | `UPDATE 8` |
| Con el bloqueo vencido (más de 2 minutos), desactivar un asiento | Se permite | `UPDATE 1` |

El último caso muestra que un bloqueo temporal vencido ya no cuenta como reserva, aunque todavía no lo haya liberado `fn_liberar_expirados`.

## Rendimiento (EXPLAIN ANALYZE)

Medido sobre 907 508 funciones, 270 128 asientos y 2 039 880 boletos, antes y después de `database/ddl/10_catalogo_indices.sql`. El detalle, los planes completos y la explicación de cada índice están en `database/explain/README.md`.

| Consulta | Antes | Después | Tiempo |
|---|---|---|---|
| Cartelera sin filtros | `Seq Scan on funcion` | `Bitmap Index Scan on idx_funcion_activa_inicio` | 529,0 → 341,8 ms |
| Cartelera por ciudad y fecha | Índice GiST recorrido 150 veces | `Bitmap Index Scan on idx_funcion_activa_inicio` | 41,9 → 7,8 ms |
| Cartelera por género | `Seq Scan` en `funcion` y `pelicula_genero` | `Bitmap Index Scan` en ambas | 208,8 → 118,8 ms |
| Top 5 de la semana | `Parallel Seq Scan on boleto` | `Parallel Index Only Scan using idx_boleto_emitido` | 409,0 → 191,1 ms |

Resultado de la consulta Top 5 sobre esos datos:

| Película | Boletos | Funciones | % de la semana |
|---|---|---|---|
| Película 007 | 780 | 60 | 0,85 |
| Película 123 | 660 | 60 | 0,72 |
| Película 250 | 540 | 60 | 0,59 |
| Película 333 | 420 | 60 | 0,46 |
| Película 499 | 360 | 60 | 0,39 |
