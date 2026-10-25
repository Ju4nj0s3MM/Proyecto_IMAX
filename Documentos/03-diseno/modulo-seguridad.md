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