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

create or replace function fn_autenticar(
    p_email text,
    p_password text
) returns table (usuario_id bigint, nombre text, roles text[])
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_max_intentos constant integer := 5;
    v_bloqueo constant interval := interval '15 minutes';
    v_u usuario%rowtype;
begin
    select * into v_u from usuario
     where lower(email) = lower(btrim(p_email)) for update;

    if not found then
        -- Igualar el tiempo de respuesta si el correo no existe
        perform crypt(coalesce(p_password, ''), gen_salt('bf', 10));
        return;
    end if;

    if not v_u.activo then
        return;
    end if;

    -- Rechazar cuenta bloqueada
    if v_u.bloqueado_hasta is not null and v_u.bloqueado_hasta > now() then
        return;
    end if;

    if v_u.password_hash = crypt(coalesce(p_password, ''), v_u.password_hash) then
        update usuario
           set intentos_fallidos = 0,
               bloqueado_hasta = null,
               ultimo_login = now()
         where id = v_u.id;

        return query
        select v_u.id,
               (v_u.nombre || ' ' || v_u.apellido)::text,
               coalesce(array_agg(r.nombre::text order by r.nombre), array[]::text[])
          from usuario_rol ur
          join rol r on r.id = ur.rol_id
         where ur.usuario_id = v_u.id;
    else
        -- Contar el fallo y bloquear al llegar al máximo
        update usuario
           set intentos_fallidos = intentos_fallidos + 1,
               bloqueado_hasta = case when intentos_fallidos + 1 >= v_max_intentos
                                      then now() + v_bloqueo end
         where id = v_u.id;
    end if;
end;
$$;