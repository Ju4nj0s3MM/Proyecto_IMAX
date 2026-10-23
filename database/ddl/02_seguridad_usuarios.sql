create extension if not exists pgcrypto;

alter table usuario
    add column intentos_fallidos integer not null default 0,
    add column bloqueado_hasta timestamptz,
    add column ultimo_login timestamptz;

alter table usuario
    add constraint ck_usuario_intentos check (intentos_fallidos >= 0),
    -- Exigir formato bcrypt
    add constraint ck_usuario_hash check (password_hash ~ '^\$2[aby]\$[0-9]{2}\$.{53}$');