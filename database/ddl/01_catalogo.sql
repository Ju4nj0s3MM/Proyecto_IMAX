-- 01 esquema del catalogo en sql ... Módulo A : Catalogo, salas, programación y tatifas 
-- Además se le agregan las tablas de usuarios y roles para que los demás miembros trabajen con estas tablas
-- Dueño de la rama/módulo: Matias Esquivel Lizano 
-- Fecha de creación domingo 18 de octubre del 2026 / Hora: 22:22
--                  =============================================================

create extension if not eexists btree_gist; 