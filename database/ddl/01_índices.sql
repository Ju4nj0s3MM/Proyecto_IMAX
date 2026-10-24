create index idx_funcion_activa_inicio on funcion (inicio) where estado = 'Activa';

create index idx_sala_cine on sala (cine_id);

create index idx_pelicula_genero_genero on pelicula_genero (genero_id);

create index idx_funcion_pelicula on funcion (pelicula_id);

create index idx boleto_emitido on boleto (emitido_en) include (funcion_id, estado);

analyze funcion, sala, pelicula_genero, boleto;

