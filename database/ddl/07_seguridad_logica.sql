create or replace function fn_registrar_usuario(
    p_email text,
    p_nombre text,
    p_apellido text,
    p_password text,
    p_rol text default 'cliente'
) returns bigint
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_usuario_id bigint;
    v_rol_id bigint;
begin
    if p_password is null or length(p_password) < 8 then
        raise exception 'La contraseña debe tener al menos 8 caracteres'
            using errcode = '22023';
    end if;

    select id into v_rol_id from rol where nombre = p_rol;
    if v_rol_id is null then
        raise exception 'Rol inexistente: %', p_rol using errcode = '22023';
    end if;

    insert into usuario (email, nombre, apellido, password_hash)
    values (btrim(p_email), btrim(p_nombre), btrim(p_apellido),
            crypt(p_password, gen_salt('bf', 10)))
    returning id into v_usuario_id;

    insert into usuario_rol (usuario_id, rol_id) values (v_usuario_id, v_rol_id);

    return v_usuario_id;
end;
$$;