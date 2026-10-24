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

create or replace function fn_registrar_auditoria(
    p_usuario_id bigint,
    p_ip inet,
    p_accion text,
    p_tabla text default null,
    p_registro_id bigint default null,
    p_motivo text default null,
    p_detalle jsonb default null
) returns bigint
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_rol_id bigint;
    v_id bigint;
begin
    -- Tomar el rol del usuario, con preferencia por administrador
    select ur.rol_id into v_rol_id
      from usuario_rol ur
      join rol r on r.id = ur.rol_id
     where ur.usuario_id = p_usuario_id
     order by (r.nombre = 'administrador') desc, ur.asignado_en
     limit 1;

    if v_rol_id is null then
        raise exception 'El usuario % no tiene rol asignado', p_usuario_id
            using errcode = '22023';
    end if;

    insert into admin_operacion_audit
        (usuario_id, rol_id, ip, accion, tabla_afectada, registro_id, motivo, detalle)
    values
        (p_usuario_id, v_rol_id, p_ip, p_accion, p_tabla, p_registro_id, p_motivo, p_detalle)
    returning id into v_id;

    return v_id;
end;
$$;

create or replace function fn_validar_entrada(p_codigo_qr text, p_puerta_id bigint)
returns table (ok boolean, mensaje text)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_antes constant interval := interval '30 minutes';
    v_despues constant interval := interval '15 minutes';
    v_puerta puerta%rowtype;
    v_boleto boleto%rowtype;
    v_inicio timestamptz;
    v_estado_funcion varchar;
    v_sala bigint;
    v_motivo text;
begin
    select * into v_puerta from puerta where id = p_puerta_id and activa;
    if not found then
        v_motivo := 'Puerta no válida';
    else
        -- Bloquear el boleto para que dos lecturas simultáneas se atiendan en orden
        select * into v_boleto from boleto where codigo_qr = p_codigo_qr for update;
        if not found then
            v_motivo := 'Entrada no reconocida';
        else
            select f.inicio, f.estado, f.sala_id into v_inicio, v_estado_funcion, v_sala
              from funcion f where f.id = v_boleto.funcion_id;

            if v_boleto.estado = 'USADO' then
                v_motivo := 'Entrada ya utilizada';
            elsif v_boleto.estado = 'ANULADO' then
                v_motivo := 'Entrada anulada';
            elsif v_estado_funcion <> 'Activa' then
                v_motivo := 'Función cancelada';
            elsif v_sala <> v_puerta.sala_id then
                v_motivo := 'Entrada de otra sala';
            elsif now() < v_inicio - v_antes then
                v_motivo := 'Ingreso aún no habilitado';
            elsif now() > v_inicio + v_despues then
                v_motivo := 'Ingreso cerrado: fuera del tiempo de tolerancia';
            end if;
        end if;
    end if;

    if v_motivo is null then
        update boleto set estado = 'USADO', usado_en = now() where id = v_boleto.id;
    end if;

    insert into acceso_puerta_log (boleto_id, codigo_qr, puerta_id, resultado, motivo)
    values (v_boleto.id, left(coalesce(p_codigo_qr, ''), 64), p_puerta_id,
            case when v_motivo is null then 'EXITOSO' else 'RECHAZADO' end,
            coalesce(v_motivo, 'Ingreso permitido'));

    return query select v_motivo is null, coalesce(v_motivo, 'Ingreso permitido')::text;
end;
$$;