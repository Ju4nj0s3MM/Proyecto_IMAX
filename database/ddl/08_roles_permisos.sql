-- Crear los roles de PostgreSQL sin inicio de sesión
do $$
declare
    v_rol text;
begin
    foreach v_rol in array array['rol_cliente', 'rol_taquillero', 'rol_operador_sala',
                                 'rol_contador', 'rol_administrador']
    loop
        if not exists (select 1 from pg_roles where rolname = v_rol) then
            execute format('create role %I nologin', v_rol);
        end if;
    end loop;
end;
$$;

-- Quitar los permisos por defecto de PUBLIC
revoke all on all tables in schema public from public;
revoke execute on function fn_registrar_usuario(text, text, text, text, text) from public;
revoke execute on function fn_registrar_auditoria(bigint, inet, text, text, bigint, text, jsonb) from public;
revoke execute on function fn_crear_particion_admin_audit(date) from public;

grant usage on schema public to rol_cliente, rol_taquillero, rol_operador_sala,
    rol_contador, rol_administrador;

-- Lectura de cartelera para cliente, taquillero, operador y contador
grant select on cine, sala, zona_asiento, asiento, clasificacion, genero, pelicula,
    pelicula_genero, funcion, tipo_entrada, tarifa, promocion
    to rol_cliente, rol_taquillero, rol_operador_sala, rol_contador;

-- El operador de sala solo consulta las puertas
grant select on puerta to rol_operador_sala;

-- Administrador: gestión completa del catálogo y las puertas
grant select, insert, update, delete on cine, sala, zona_asiento, asiento, clasificacion,
    genero, pelicula, pelicula_genero, funcion, tipo_entrada, tarifa, promocion, puerta
    to rol_administrador;

-- Administrador: usuarios y roles, sin acceso al hash de la contraseña
grant select on rol to rol_administrador;
grant select, insert, delete on usuario_rol to rol_administrador;
grant select (id, nombre, apellido, email, telefono, activo, creado_en,
              intentos_fallidos, bloqueado_hasta, ultimo_login)
    on usuario to rol_administrador;
grant update (nombre, apellido, telefono, activo, intentos_fallidos, bloqueado_hasta)
    on usuario to rol_administrador;

-- Bitácora: el administrador solo la consulta y registra mediante la función
grant select on admin_operacion_audit to rol_administrador;
grant execute on function fn_registrar_usuario(text, text, text, text, text) to rol_administrador;
grant execute on function fn_registrar_auditoria(bigint, inet, text, text, bigint, text, jsonb)
    to rol_administrador;

-- Check-in y reembolsos
revoke execute on function fn_validar_entrada(text, bigint) from public;
revoke execute on function fn_reembolsar(bigint, bigint, text, inet) from public;

grant execute on function fn_validar_entrada(text, bigint) to rol_operador_sala, rol_administrador;
grant execute on function fn_reembolsar(bigint, bigint, text, inet) to rol_administrador;
grant select on reembolso to rol_administrador, rol_contador;
grant select on acceso_puerta_log to rol_administrador;