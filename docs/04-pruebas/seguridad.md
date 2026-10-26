# Pruebas del módulo de seguridad

## 1. Entorno

Las pruebas se ejecutaron en PostgreSQL 16, con la base armada desde los scripts de `database/ddl` en orden y los datos de `database/seeds/01_catalogo_demo.sql`. Los scripts de cada prueba están en `database/tests`.

## 2. Autenticación (`fn_autenticar` y `fn_registrar_usuario`)

| Caso | Resultado esperado | Resultado |
|---|---|---|
| Login con correo y contraseña correctos (el correo en mayúsculas) | Devuelve el usuario y sus roles | Aprobado |
| Contraseña incorrecta | Sin filas | Aprobado |
| Correo inexistente | Sin filas | Aprobado |
| Cinco intentos fallidos seguidos | La cuenta se bloquea, incluso con la contraseña correcta | Aprobado |
| Vence el bloqueo (15 minutos) | Entra y el contador de intentos vuelve a 0 | Aprobado |
| Usuario inactivo | No entra | Aprobado |
| Insertar una contraseña en texto plano | La base de datos la rechaza (restricción de formato bcrypt) | Aprobado |
| Registrar con contraseña corta, rol inexistente o correo repetido | Rechazado | Aprobado |

## 3. Check-in en puerta (`fn_validar_entrada`)

Script: `database/tests/07_checkin_reembolso.sql`. Crea funciones y entradas respecto a la hora actual y termina con `rollback`, por lo que no deja datos.

| # | Caso | Resultado esperado | Resultado |
|---|---|---|---|
| 1 | Primer escaneo de una entrada válida | Ingreso permitido; el boleto queda en estado `USADO` | Aprobado |
| 2 | Segundo escaneo del mismo código | Entrada ya utilizada | Aprobado |
| 3 | Código que no existe | Entrada no reconocida | Aprobado |
| 4 | Entrada escaneada en una puerta de otra sala | Entrada de otra sala | Aprobado |
| 5 | Función que empieza en 6 horas | Ingreso aún no habilitado | Aprobado |
| 6 | Función que empezó hace 30 minutos | Ingreso cerrado: fuera del tiempo de tolerancia | Aprobado |
| 7 | Función cancelada | Función cancelada | Aprobado |
| 8 | Entrada anulada | Entrada anulada | Aprobado |
| 9 | Puerta inexistente | Puerta no válida | Aprobado |

Cada lectura, exitosa o rechazada, queda registrada en `acceso_puerta_log` con su motivo. Los intentos de modificar o borrar esa bitácora son rechazados.

## 4. Reembolsos (`fn_reembolsar`)

Mismo script de la sección anterior.

| # | Caso | Resultado esperado | Resultado |
|---|---|---|---|
| 10 | Reembolso con la función a más de 2 horas | Boleto `ANULADO`, asiento `LIBERADO` y orden `REEMBOLSADA`; el código ya no ingresa | Aprobado |
| 11 | Reembolso con la función a menos de 2 horas | Se registra como reembolso forzado | Aprobado |
| 12 | Reembolso de un boleto ya usado | Rechazado | Aprobado |
| 13 | Reembolso solicitado por un taquillero | Solo un administrador puede reembolsar | Aprobado |
| 14 | Reembolso sin motivo | Rechazado | Aprobado |
| 15 | Segundo reembolso del mismo boleto | La entrada ya está anulada | Aprobado |

Cada reembolso queda registrado en `reembolso`, en `transaccion_log` (tipo `REEMBOLSO`) y en `admin_operacion_audit` con el usuario, el rol, la IP, la fecha y la hora.

## 5. Concurrencia: doble escaneo

Script: `database/tests/doble_escaneo.py`. Lanza N lecturas simultáneas del mismo código en la misma puerta, con una barrera que hace que todos los hilos disparen a la vez, cada uno con su propia conexión.

| Hilos simultáneos | Ingresos exitosos | Rechazados con "Entrada ya utilizada" | Estado final del boleto |
|---|---|---|---|
| 20 | 1 | 19 | `USADO` |
| 30 | 1 | 29 | `USADO` |
| 50 | 1 | 49 | `USADO` |

En las tres corridas la bitácora registró un único ingreso exitoso. Esto se logra porque `fn_validar_entrada` bloquea la fila del boleto (`for update`): la segunda lectura espera a que termine la primera y, al continuar, encuentra el boleto ya usado.

## 6. Permisos por rol (RN-17)

Script: `database/tests/08_permisos_por_rol.sql`. Cambia de rol con `set role` y comprueba lo que cada uno puede y no puede hacer.

| Rol | Permitido | Rechazado por la base de datos |
|---|---|---|
| Cliente | Ver la cartelera | Leer `usuario`, cambiar tarifas, registrarse como administrador |
| Taquillero | Ver tarifas | Cambiar precios, crear salas, leer la bitácora |
| Operador de sala | Ver puertas y validar entradas | Crear puertas, modificar funciones, reembolsar, leer `boleto` directamente |
| Contador | Ver funciones y reembolsos | Modificar o borrar la programación |
| Administrador | Gestionar catálogo, puertas y usuarios; reembolsar; registrar auditoría | Leer `password_hash`, alterar la bitácora, crear particiones |

Además, la aplicación responde con el error 403 cuando un rol sin permiso intenta usar una pantalla o una ruta de otro rol.

## 7. Rendimiento: `EXPLAIN ANALYZE`

Script: `database/explain/04_explain_auditoria.sql`. Genera 300 000 operaciones de 50 administradores dentro de una transacción y la revierte al final.

| Consulta | Sin índice | Con índice `idx_admin_audit_usuario` |
|---|---|---|
| Operaciones de un administrador en la última semana | `Seq Scan`, unos 31 ms | `Bitmap Index Scan`, unos 2,8 ms |

El índice reduce el tiempo unas 11 veces. La consulta analítica #4 (operaciones del último mes agrupadas por administrador) también se mide en el mismo script.

## 8. Cómo repetir las pruebas

Con la base `imax` creada y los scripts aplicados:

    psql -U postgres -d imax -f database/tests/07_checkin_reembolso.sql
    psql -U postgres -d imax -f database/tests/08_permisos_por_rol.sql
    psql -U postgres -d imax -f database/explain/04_explain_auditoria.sql
    python database/tests/doble_escaneo.py 30

La prueba de concurrencia se conecta por defecto a `localhost:5432` con el usuario `postgres`, la contraseña `postgres` y la base `imax`. Si la configuración es otra, se cambia con las variables `PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD` y `PGDATABASE`.