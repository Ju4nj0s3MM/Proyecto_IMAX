-- Índices del módulo A para la cartelera y el Top 5
-- Matías Esquivel Lizano
-- Se ejecuta después de 03_venta.sql (idx_boleto_emitido es sobre la tabla boleto)
-- Justificación con EXPLAIN ANALYZE en database/explain/README.md

create index idx_funcion_activa_inicio on funcion (inicio) where estado = 'Activa';

create index idx_sala_cine on sala (cine_id);

create index idx_pelicula_genero_genero on pelicula_genero (genero_id);

create index idx_funcion_pelicula on funcion (pelicula_id);

create index idx_boleto_emitido on boleto (emitido_en) include (funcion_id, estado);

analyze funcion, sala, pelicula_genero, boleto;

