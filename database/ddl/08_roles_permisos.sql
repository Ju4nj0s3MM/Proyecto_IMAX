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