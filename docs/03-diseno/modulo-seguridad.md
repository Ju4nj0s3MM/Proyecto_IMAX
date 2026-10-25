# Módulo de seguridad y acceso

## 1. Alcance

Este módulo cubre la autenticación y los roles (RN-17), el control de acceso en puerta (RN-14, RN-15 y RN-16), los reembolsos (RN-19) y la auditoría inalterable de las operaciones manuales (RN-20).

Las tablas `rol`, `usuario` y `usuario_rol` se crean en `database/ddl/01_catalogo.sql`. El archivo `02_seguridad_usuarios.sql` les agrega las columnas de control de intentos y las restricciones de contraseña. Las demás tablas se crean en `04_seguridad_acceso.sql`.

## 2. Usuarios, roles y puertas

### rol

| Columna | Tipo | Restricciones |
|---|---|---|
| id | bigint | Clave primaria, generada |
| nombre | varchar(50) | Único, no nulo |
| descripcion | varchar(200) | |

Valores: `cliente`, `taquillero`, `operador_sala`, `contador` y `administrador`.

### usuario

| Columna | Tipo | Restricciones |
|---|---|---|
| id | bigint | Clave primaria, generada |
| nombre, apellido | varchar(100) | No nulos |
| email | varchar(150) | No nulo, formato válido, único sin distinguir mayúsculas |
| password_hash | varchar(200) | No nulo, solo acepta formato bcrypt |
| telefono | varchar(20) | |
| activo | boolean | Por defecto verdadero |
| creado_en | timestamptz | Por defecto la fecha actual |
| intentos_fallidos | integer | No nulo, mayor o igual a 0 |
| bloqueado_hasta | timestamptz | Fin del bloqueo temporal de la cuenta |
| ultimo_login | timestamptz | |

La restricción de formato bcrypt impide guardar una contraseña en texto plano, aunque alguien insertara el dato directamente.

### usuario_rol

| Columna | Tipo | Restricciones |
|---|---|---|
| usuario_id | bigint | Clave foránea a usuario (se borra en cascada) |
| rol_id | bigint | Clave foránea a rol (restringe el borrado) |
| asignado_en | timestamptz | Por defecto la fecha actual |
| asignado_por | bigint | Clave foránea a usuario |

La clave primaria es compuesta (usuario_id, rol_id). Resuelve la relación de muchos a muchos: un usuario puede tener más de un rol.

### puerta

| Columna | Tipo | Restricciones |
|---|---|---|
| id | bigint | Clave primaria, generada |
| sala_id | bigint | Clave foránea a sala, no nula |
| nombre | varchar(60) | No nulo; único dentro de la sala |
| activa | boolean | Por defecto verdadero |
| creado_en | timestamptz | Por defecto la fecha actual |

Cada puerta pertenece a una sala. Con esto el check-in comprueba que la entrada corresponda a la sala donde se escanea (RN-15).

## 3. Bitácoras y reembolsos

### acceso_puerta_log

Registra cada lectura de un código QR en una puerta.

| Columna | Tipo | Restricciones |
|---|---|---|
| id | bigint | Parte de la clave primaria, generada |
| fecha | timestamptz | Parte de la clave primaria y clave de partición |
| boleto_id | bigint | Nulo si el código no existe |
| codigo_qr | varchar(64) | No nulo; el valor que se leyó |
| puerta_id | bigint | |
| resultado | varchar(10) | `EXITOSO` o `RECHAZADO` |
| motivo | varchar(60) | No nulo; por ejemplo "Entrada ya utilizada" |

Está particionada por mes sobre `fecha`, con una partición por defecto. No tiene claves foráneas para poder registrar también los códigos desconocidos y para que las inserciones masivas no se frenen. Un disparador impide modificar o borrar filas.

### reembolso

| Columna | Tipo | Restricciones |
|---|---|---|
| id | bigint | Clave primaria, generada |
| boleto_id | bigint | Clave foránea a boleto; único (un boleto se reembolsa una sola vez) |
| orden_id | bigint | Clave foránea a orden |
| admin_id | bigint | Clave foránea a usuario |
| monto | numeric(12,2) | Mayor o igual a 0 |
| forzado | boolean | Verdadero si se hizo fuera de la política |
| motivo | varchar(300) | No nulo |
| creado_en | timestamptz | Por defecto la fecha actual |

### admin_operacion_audit

Bitácora de las operaciones manuales de los administradores (RN-20).

| Columna | Tipo | Restricciones |
|---|---|---|
| id | bigint | Parte de la clave primaria, generada |
| creado_en | timestamptz | Parte de la clave primaria y clave de partición; fecha y hora |
| usuario_id | bigint | Clave foránea a usuario; responsable |
| rol_id | bigint | Clave foránea a rol |
| ip | inet | No nulo; dirección desde donde se hizo |
| accion | varchar(40) | `cortesia`, `cambio_asiento`, `reembolso_forzado`, `anulacion_venta`, `cambio_precio`, `cambio_sala`, `cambio_rol` u `otro` |
| tabla_afectada, registro_id | varchar(60), bigint | Qué se modificó |
| motivo | varchar(300) | |
| detalle | jsonb | Datos adicionales de la operación |

Está particionada por mes (de octubre de 2026 a diciembre de 2027, más una partición por defecto). Un disparador rechaza cualquier `UPDATE` o `DELETE`, y los roles de la aplicación no tienen esos permisos sobre la tabla. Los registros se conservan 5 años, según se describe en `05-operacion.md`.

## 4. Relaciones con los demás módulos

| Tabla de este módulo | Se relaciona con | Módulo |
|---|---|---|
| puerta | sala | Catálogo |
| reembolso | boleto, orden | Venta |
| acceso_puerta_log | boleto, puerta (sin clave foránea, por el motivo ya explicado) | Venta |
| usuario_rol, admin_operacion_audit | usuario, rol | Seguridad |

## 5. Funciones y disparadores

| Función | Qué hace |
|---|---|
| fn_registrar_usuario | Crea un usuario con la contraseña cifrada con bcrypt y le asigna un rol |
| fn_autenticar | Verifica correo y contraseña; bloquea la cuenta 15 minutos tras 5 intentos fallidos |
| fn_validar_entrada | Valida el código QR en puerta: estado, función, sala y ventana de ingreso; bloquea la fila del boleto para que dos lecturas simultáneas se atiendan en orden |
| fn_reembolsar | Anula el boleto, libera el asiento, registra el reembolso y la auditoría; marca como forzado lo que ocurre a menos de 2 horas de la función |
| fn_registrar_auditoria | Inserta una operación manual en la bitácora con el rol y la IP |
| trg_audit_inmutable | Impide modificar o borrar las bitácoras |

## 6. Índices

| Índice | Tabla | Para qué sirve |
|---|---|---|
| uq_usuario_email | usuario (lower(email)) | Login y unicidad del correo |
| idx_puerta_sala | puerta | Buscar las puertas de una sala |
| idx_acceso_log_boleto | acceso_puerta_log (boleto_id, fecha) | Historial de lecturas de un boleto |
| idx_acceso_log_puerta | acceso_puerta_log (puerta_id, fecha) | Lecturas por puerta |
| idx_reembolso_orden | reembolso | Reembolsos de una orden |
| idx_reembolso_admin | reembolso (admin_id, creado_en) | Reembolsos por administrador |
| idx_admin_audit_usuario | admin_operacion_audit (usuario_id, creado_en) | Operaciones de un administrador |
| idx_admin_audit_fecha | admin_operacion_audit (creado_en) | Consultas por rango de fechas |

En la consulta de las operaciones de un administrador en la última semana, el índice `idx_admin_audit_usuario` cambió el plan de `Seq Scan` a `Bitmap Index Scan` y bajó el tiempo de 31 ms a 2,8 ms, sobre 300 000 filas (`database/explain/04_explain_auditoria.sql`).

## 7. Reglas de negocio cubiertas

| Regla | Cómo se garantiza |
|---|---|
| RN-09 | No existe ninguna columna de tarjeta ni CVV; la contraseña solo se guarda como hash bcrypt |
| RN-14 | `fn_validar_entrada` cambia el estado del boleto a `USADO` bajo bloqueo de fila; una segunda lectura recibe "Entrada ya utilizada" |
| RN-15 | Se rechaza si la función no está activa o si la sala de la puerta no coincide con la de la entrada |
| RN-16 | Ingreso permitido desde 30 minutos antes hasta 15 minutos después del inicio |
| RN-17 | Roles de PostgreSQL con privilegios mínimos (`08_roles_permisos.sql`) y validación del rol en el servidor |
| RN-19 | Reembolso solo por un administrador, con motivo, y liberando el asiento; fuera de política queda como forzado |
| RN-20 | `admin_operacion_audit` guarda fecha, hora, IP, rol y usuario; es inalterable y se conserva 5 años |