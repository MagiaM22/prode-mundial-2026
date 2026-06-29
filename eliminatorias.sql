-- ============================================================
-- ELIMINATORIAS — columna "quién pasa" (penales / quién avanza)
-- ============================================================
-- En la fase eliminatoria, si pronosticás un EMPATE tenés que decir qué selección
-- pasa de ronda. Eso suma +1 si acertás / -1 si errás (además del 2/4 del resultado).
-- Para eso necesitamos guardar:
--   * predictions.pasa  = la selección que el usuario cree que pasa (texto, ej "Japón")
--   * results.pasa      = la selección que REALMENTE pasó (la carga el admin / el sync)
--
-- Correr este SQL UNA VEZ en Supabase → SQL Editor → Run.
-- Es aditivo y seguro: no toca datos existentes (las columnas quedan NULL para los partidos de grupos).

alter table public.predictions add column if not exists pasa text;
alter table public.results     add column if not exists pasa text;

-- (opcional, a futuro) si se quiere guardar el marcador de penales:
-- alter table public.results add column if not exists pens_local  int;
-- alter table public.results add column if not exists pens_visit  int;

-- Verificar:
-- select column_name from information_schema.columns where table_name = 'predictions' and column_name = 'pasa';
-- select column_name from information_schema.columns where table_name = 'results'     and column_name = 'pasa';
