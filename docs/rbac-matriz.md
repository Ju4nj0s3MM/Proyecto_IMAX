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