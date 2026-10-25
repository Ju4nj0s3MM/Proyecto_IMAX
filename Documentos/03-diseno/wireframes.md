# Wireframes de la interfaz

La interfaz es funcional y sirve para demostrar los flujos de negocio. Estos wireframes muestran la distribución de cada pantalla, qué datos presenta, a qué ruta de la API llama y qué regla de negocio demuestra. La barra superior de navegación (`nav.js`) es común a todas y solo muestra los enlaces que permite el rol del usuario (RN-17).

| N.º | Pantalla | Archivo | Roles | Pauta de revisión |
|---|---|---|---|---|
| 1 | Inicio de sesión | `login.html` | Todos | Restricción de roles |
| 2 | Cartelera y exploración | `catalogo/cartelera.html` | Todos | Exploración y filtrado |
| 3 | Mapa interactivo de la sala | `venta/mapa.html` | Cliente, taquillero | Bloqueo temporal de asientos |
| 4 | Pago | `venta/pago.html` | Cliente, taquillero | Simulación de pago |
| 5 | Confirmación y entrada digital | `venta/mis-entradas.html` | Cliente, taquillero | Emisión digital |
| 6 | Check-in en puerta | `seguridad/checkin.html` | Operador de sala | Validación en puerta |
| 7 | Dashboard | `dashboard.html` | Contador, administrador | Consultas analíticas |
| 8 | Administración del catálogo | `catalogo/admin.html` | Administrador | Gestión de cartelera y funciones |
| 9 | Auditoría | `seguridad/auditoria.html` | Administrador | Bitácora de auditoría |

## 1. Inicio de sesión

```
+------------------------------------------------------------+
| IMAX  Cartelera                               Iniciar sesión|
+------------------------------------------------------------+
|                                                            |
|              Iniciar sesión                                |
|              Correo      [ cliente@imax.test         ]     |
|              Contraseña  [ ••••••••                  ]     |
|                          [  Entrar  ]                      |
|              (mensaje de error si falla o la cuenta        |
|               está bloqueada por 5 intentos)               |
+------------------------------------------------------------+
```

API: `POST /api/seguridad/login`. La contraseña se compara con el hash bcrypt en la base de datos.

## 2. Cartelera y exploración

```
+------------------------------------------------------------+
| IMAX  Cartelera  Mis entradas ...                 Ana · Salir|
+------------------------------------------------------------+
| Cartelera                                                  |
| Cine / ubicación [ San José   ]  Fecha [ 24/10/2026 ]      |
| Género [ Terror        ]                     [ Buscar ]    |
|                                                            |
| +--------------------------------------------------------+ |
| | [póster] La Noche Eterna  · R · Drama, Terror          | |
| |          Un pueblo aislado descubre que el sol no...   | |
| |          IMAX San José — Lincoln Plaza, Moravia ·      | |
| |          Sala 1 · 24 oct 2026, 8:00 p. m.              | |
| |                                  [ Elegir asientos ]   | |
| +--------------------------------------------------------+ |
| | (una tarjeta por función)                              | |
+------------------------------------------------------------+
```

API: `GET /api/catalogo/cartelera?cine=&fecha=&genero=` → `fn_listar_cartelera`. Solo aparecen funciones activas y futuras (RN-01) con título, sinopsis, clasificación, horario y ubicación (RN-02).

## 3. Mapa interactivo de la sala

```
+------------------------------------------------------------+
| La Noche Eterna · IMAX San José · Sala 1 · 8:00 p. m.      |
|                                                            |
|               \_________ PANTALLA _________/               |
|        A  [■][■][■][■][■][■][■][■]                         |
|        B  [■][■][▒][▒][■][■][■][■]                         |
|        C  [■][■][■][□][□][■][■][■]                         |
|        D  [■][■][■][■][■][■][■][■]                         |
|                                                            |
|   ■ verde = disponible   □ gris = ocupado                  |
|   ▒ amarillo = bloqueado  █ azul = seleccionado por mí     |
|                                                            |
|   Seleccionados: B5, B6 (máx. 6)       Tiempo: 01:47       |
|   Tipo de entrada por asiento: [Adulto ▾] [Estudiante ▾]   |
|                                        [ Continuar al pago ]|
+------------------------------------------------------------+
```

API: `GET /api/venta/funciones/:id/asientos` → `fn_mapa_asientos` (RN-03); `POST /api/venta/reservas` → `fn_bloquear_asientos` (RN-04, RN-05). El contador de 2 minutos muestra cuánto falta para que se liberen los asientos.

## 4. Pago

```
+------------------------------------------------------------+
| Resumen de compra                         Tiempo: 01:12    |
| +--------------------------------------------------------+ |
| | Asiento  Zona     Tipo         Precio  Desc.   Cargo   | |
| | B5       General  Estudiante    6,50   6,50    0,75    | |
| | B6       General  Estudiante    6,50   0,00    0,75    | |
| |                       Promoción: 2x1 estudiantes       | |
| |--------------------------------------------------------| |
| | Subtotal 13,00   Descuento -6,50   Cargo 1,50          | |
| | TOTAL                                    $8,00         | |
| +--------------------------------------------------------+ |
| Método de pago  ( ) Tarjeta  ( ) PayPal  ( ) Billetera     |
| Titular [            ]  Últimos 4 dígitos [ 4242 ]         |
| (simulado: no se pide ni se guarda el número ni el CVV)    |
| Resultado simulado: ( ) Aprobado  ( ) Rechazado            |
|                                            [ Pagar ]       |
+------------------------------------------------------------+
```

API: `POST /api/catalogo/total` → `fn_calcular_total` (RN-07, RN-08); `POST /api/venta/pagos` → `fn_confirmar_pago` (RN-09, RN-10). Si el resultado es rechazado, se muestra el mensaje y los asientos vuelven a estar disponibles.

## 5. Confirmación y entrada digital

```
+------------------------------------------------------------+
| ✔ Compra exitosa                                           |
| +---------------------------+  +-------------------------+ |
| |  ████ ▄▄ ████             |  |  ████ ▄▄ ████           | |
| |  █ ▄▄ ██ ▄ █   (QR)       |  |  █ ▄▄ ██ ▄ █   (QR)     | |
| |  La Noche Eterna          |  |  La Noche Eterna        | |
| |  24 oct · 8:00 p. m.      |  |  24 oct · 8:00 p. m.    | |
| |  IMAX San José · Sala 1   |  |  IMAX San José · Sala 1 | |
| |  Asiento B5 · Estudiante  |  |  Asiento B6 · Estudiante| |
| |  Estado: EMITIDO          |  |  Estado: EMITIDO        | |
| +---------------------------+  +-------------------------+ |
+------------------------------------------------------------+
```

API: `GET /api/venta/mis-boletos` → `fn_mis_boletos` (RN-13). Cada boleto tiene un código único (RN-12) que solo existe después de un pago aprobado (RN-11).

## 6. Check-in en puerta

```
+------------------------------------------------------------+
| Check-in                                                   |
| Puerta   [ IMAX San José · Sala 1 · Puerta A ▾ ]           |
| Código QR [ 9f86d081884c7d65...           ] [ Validar ]    |
|                                                            |
|  +------------------------------------------------------+  |
|  | ✔ Entrada válida. Bienvenido.     (verde)            |  |
|  +------------------------------------------------------+  |
|  | ✖ Entrada ya utilizada            (rojo)             |  |
|  | ✖ La entrada es de otra función u horario            |  |
|  | ✖ Fuera del horario de ingreso                       |  |
|  +------------------------------------------------------+  |
+------------------------------------------------------------+
```

API: `POST /api/seguridad/checkin` → `fn_validar_entrada` (RN-14, RN-15, RN-16). Cada intento queda en `acceso_puerta_log`.

## 7. Dashboard

```
+------------------------------------------------------------+
| Dashboard                  Actualizado 11:12 · cada 30 s   |
| [ 3 Cines ] [ 4 Salas ] [ 3 Películas ] [ 6 en 24 h ] [ 8 ]|
| +---------------------------+ +--------------------------+ |
| | Top 5 de la semana        | | Métodos de pago          | |
| | Título   Boletos  % ▓▓▓░  | | Método   %   ▓▓▓▓░       | |
| +---------------------------+ +--------------------------+ |
| +--------------------------------------------------------+ |
| | Ocupación e ingresos por función                       | |
| | Función  Vendidos/Capacidad  % ocupación  Ingresos     | |
| +--------------------------------------------------------+ |
| +--------------------------------------------------------+ |
| | Próximas funciones        [ Programar funciones y salas]| |
| | Título   Cine   Sala   Inicio   Capacidad              | |
| +--------------------------------------------------------+ |
+------------------------------------------------------------+
```

API: `GET /api/catalogo/reportes/resumen` y `GET /api/catalogo/reportes/top5` (módulo A); `GET /api/venta/reportes/ocupacion` y `GET /api/venta/reportes/metodos-pago` (módulo B). Se refresca cada 30 segundos. El botón de programación solo aparece para el administrador; el contador solo consulta.

## 8. Administración del catálogo

```
+------------------------------------------------------------+
| Administración del catálogo                                |
| [Películas][Funciones][Cines][Salas][Mapa de asientos]     |
| [Zonas][Clasificaciones][Géneros][Tipos][Tarifas][Promos]  |
| +-------------------------+ +----------------------------+ |
| | Nueva función           | | Funciones                  | |
| | Película [ Dune ▾     ] | | Película  Sala  Inicio  Fin| |
| | Sala     [ Sala 1 ▾   ] | | ...                        | |
| | Inicio   [ 24/10 16:00 ]| |                [Editar][X] | |
| |            [ Guardar ]  | |                            | |
| +-------------------------+ +----------------------------+ |
| ✖ La sala ya tiene una función en ese horario (traslape)   |
| ✖ RN-18: la sala tiene entradas vendidas, no se puede      |
|   modificar su mapa de asientos                            |
+------------------------------------------------------------+

Mapa de asientos:
| Sala [ Sala 1 IMAX Laser ▾ ]  Filas [ 8 ] Asientos [ 10 ]  |
| Herramienta: (•) VIP ( ) General ( ) Accesible ( ) Pasillo |
|   A [V][V][V][V][V][V][V][V][V][V]                         |
|   B [G][G][G][ ][G][G][G][G][G][G]   (clic para cambiar)   |
```

API: `/api/catalogo/admin/*` (CRUD sobre las tablas de `01_catalogo.sql`). Los errores que se muestran vienen directamente de la base de datos: la restricción `ex_funcion_sin_traslape` y los triggers de RN-18.

## 9. Auditoría

```
+------------------------------------------------------------+
| Bitácora de auditoría                                      |
| Fecha            Usuario  Rol            Operación    IP   |
| 23 oct 22:10     5        administrador  cortesía     ...  |
| 23 oct 21:55     5        administrador  reembolso    ...  |
+------------------------------------------------------------+
```

API: `GET /api/seguridad/auditoria` (módulo C, RN-20).
