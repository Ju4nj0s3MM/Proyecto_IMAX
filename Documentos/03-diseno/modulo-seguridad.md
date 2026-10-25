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