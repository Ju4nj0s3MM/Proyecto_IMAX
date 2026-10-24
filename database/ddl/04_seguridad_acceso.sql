create table puerta (
    id bigint generated always as identity primary key,
    sala_id bigint not null references sala(id) on delete restrict,
    nombre varchar(60) not null,
    activa boolean not null default true,
    creado_en timestamptz not null default now(),
    constraint uq_puerta_sala_nombre unique (sala_id, nombre)
);

-- Indexar la llave foránea
create index idx_puerta_sala on puerta (sala_id);

