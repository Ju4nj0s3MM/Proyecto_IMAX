# Control de acceso basado en roles (RBAC)

## 1. Principio de privilegio mínimo

Cada rol recibe únicamente los permisos que necesita para cumplir su función (RN-17). Lo que no está permitido de forma explícita queda denegado.

## 2. Roles del sistema

| Rol | Función | Lo que no puede hacer |
|---|---|---|
| Cliente / Espectador | Ver la cartelera, comprar entradas en línea y consultar sus propios códigos QR | Acceder a paneles operativos o administrativos |
| Taquillero | Vender presencialmente, emitir boletos y consultar su propio corte de caja | Modificar precios globales, salas o la auditoría |
| Operador de sala (puerta) | Validar entradas escaneando el código QR | Vender boletos, manejar dinero o cambiar configuraciones |
| Contador | Conciliar pagos, consultar ingresos y exportar informes financieros | Modificar la programación de películas o la estructura de los cines |
| Administrador / Gerente | Configurar cartelera, salas y precios, gestionar reembolsos y consultar la bitácora de auditoría | Cambiar salas con ventas activas (RN-18) |

## 3. Matriz de permisos por módulo

| Módulo | Cliente | Taquillero | Operador de sala | Contador | Administrador |
|---|---|---|---|---|---|
| Catálogo y cartelera | Lectura de funciones activas | Lectura | Lectura | Lectura | Lectura y escritura |
| Selección de asientos y pago | Ejecución (compra en línea) | Ejecución (venta presencial) | Sin acceso | Sin acceso | Configuración de reglas y precios |
| Emisión y acceso (QR) | Lectura de sus propios QR | Lectura (emitir boletos) | Ejecución (validar QR en puerta) | Sin acceso | Gestión de incidencias y reasignaciones |
| Reportes y finanzas | Sin acceso | Lectura de su propio corte de caja | Sin acceso | Lectura y exportación | Lectura total |
| Configuración de salas y funciones | Sin acceso | Sin acceso | Sin acceso | Sin acceso | Lectura y escritura (restringido por RN-18) |
| Auditoría y gestión de roles | Sin acceso | Sin acceso | Sin acceso | Sin acceso | Lectura total de la bitácora y de los roles |

## 4. Aplicación en el sistema

El control de acceso se aplica en dos capas, para que una falla en una no abra la puerta a la otra.

**Base de datos.** Cada rol de aplicación tiene un rol de PostgreSQL sin inicio de sesión (`rol_cliente`, `rol_taquillero`, `rol_operador_sala`, `rol_contador` y `rol_administrador`). Los permisos se otorgan con `GRANT` solo sobre las tablas y funciones que cada rol necesita, y todo lo demás queda sin permiso. Los roles de la aplicación no tienen `UPDATE` ni `DELETE` sobre las tablas de auditoría.

**Aplicación.** El servidor valida la sesión y el rol del usuario antes de ejecutar cada operación y rechaza con un error 403 las solicitudes de un rol sin permiso. Los menús de la interfaz solo muestran las opciones del rol, pero la restricción real está en el servidor y en la base de datos.

**Asignación de roles.** Los roles se guardan en `rol` y se asignan en `usuario_rol`. Un usuario puede tener más de un rol, por ejemplo taquillero y contador, y en ese caso recibe la suma de los permisos de ambos. La asignación y la revocación de roles son operaciones críticas que solo puede hacer un administrador y quedan registradas en `admin_operacion_audit`.

**Reglas relacionadas.**

| Regla | Efecto sobre el control de acceso |
|---|---|
| RN-17 | Segmenta el panel de administración por perfil |
| RN-18 | Impide modificar o eliminar una sala con entradas vendidas, incluso a un administrador |
| RN-19 | Limita los reembolsos a la política vigente, salvo un reembolso forzado que queda auditado |
| RN-20 | Registra fecha, hora, dirección IP, rol y usuario de cada operación manual |

