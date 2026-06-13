-- ============================================================
-- Seguridad Supabase — Prode Mundial 2026
-- Correr en: Supabase → SQL Editor → Run
-- ============================================================
-- Estado detectado (06/2026):
--   results          → escritura solo admins  ✅ (ya estaba)
--   gdt_user_teams   → escritura solo dueño   ✅ (ya estaba)
--   predictions      → lectura pública (ok para un prode)
--   gdt_match_stats  → ⚠️ ESCRITURA/BORRADO ANÓNIMO ABIERTO  ← esto cierra este script
--
-- ⚠️ ORDEN IMPORTANTE: antes de correr esto, dejá andando el cron con la
-- service key (ver más abajo), si no la sincronización automática deja de escribir.
-- ============================================================

alter table public.gdt_match_stats enable row level security;

-- Lectura pública (todos ven las stats)
drop policy if exists "stats lectura publica" on public.gdt_match_stats;
create policy "stats lectura publica" on public.gdt_match_stats
  for select using (true);

-- Borrar políticas permisivas previas (anon). Si quedó con OTRO nombre,
-- revisá Authentication → Policies de gdt_match_stats y borrá la que da
-- INSERT/UPDATE/DELETE/ALL al rol "anon".
drop policy if exists "stats escritura abierta"        on public.gdt_match_stats;
drop policy if exists "Enable insert for all users"     on public.gdt_match_stats;
drop policy if exists "Enable insert for anon"          on public.gdt_match_stats;
drop policy if exists "Enable write for all"            on public.gdt_match_stats;

-- Escritura solo para admins autenticados (el cron usa service_role y saltea RLS)
drop policy if exists "admins escriben gdt_match_stats" on public.gdt_match_stats;
create policy "admins escriben gdt_match_stats" on public.gdt_match_stats
  for all to authenticated
  using      ((auth.jwt() ->> 'email') in ('marcosjmanzi@gmail.com','federicowf@gmail.com'))
  with check ((auth.jwt() ->> 'email') in ('marcosjmanzi@gmail.com','federicowf@gmail.com'));

-- ============================================================
-- Cómo dejar el cron con service key (para que siga escribiendo tras el lockdown):
-- 1) Supabase → Project Settings → API → copiar la "service_role key" (secreta).
-- 2) GitHub → repo → Settings → Secrets and variables → Actions → New secret:
--    nombre: SUPABASE_SERVICE_KEY   valor: (la service_role key)
-- 3) En .github/workflows/sync.yml, el step de node debe pasar el secret:
--      - run: node scripts/sync.cjs
--        env:
--          SUPABASE_SERVICE_KEY: ${{ secrets.SUPABASE_SERVICE_KEY }}
-- (scripts/sync.cjs ya usa SUPABASE_SERVICE_KEY si está; sin él, cae a la key
--  pública y NO podrá escribir resultados ni stats una vez cerrado el acceso.)
-- ============================================================
