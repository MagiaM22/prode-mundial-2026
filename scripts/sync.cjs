// Sincronización automática del Gran DT (corre en GitHub Actions, sin API key).
// Resultados + stats salen de ESPN; las notas de FotMob. Escribe en Supabase.
// Reutiliza las MISMAS funciones de index.html (las extrae) para no duplicar lógica.
// Variables de entorno opcionales:
//   DRY_RUN=1   → no escribe en Supabase, solo informa
//   DAYS=4      → cuántos días hacia atrás mirar (default 4)

const fs   = require('fs');
const path = require('path');

const HTML = fs.readFileSync(path.join(__dirname, '..', 'index.html'), 'utf8');
const ex = (re, label) => { const m = HTML.match(re); if (!m) throw new Error('No se pudo extraer: ' + label); return m[0]; };

globalThis.location = { hostname: 'ci', origin: 'https://ci' }; // no-localhost → FotMob directo (sin proxy)

const src = [
  ex(/const FIXTURE = \{[\s\S]*?\n\};/, 'FIXTURE'),
  ex(/const TEAM_API_MAP = \{[\s\S]*?\n\};/, 'TEAM_API_MAP'),
  ex(/function gdtSlug\(str\) \{[\s\S]*?\n\}/, 'gdtSlug'),
  ex(/^function teamName\(group, ref\).*$/m, 'teamName'),
  ex(/const ESPN_API[\s\S]*?async function espnFindEvent\(matchId\) \{[\s\S]*?\n\}/, 'espn'),
  ex(/function buildStatsFromESPN\(summary\) \{[\s\S]*?\n\}/, 'buildStatsFromESPN'),
  ex(/function dedupeStatsRows\(rows\) \{[\s\S]*?\n\}/, 'dedupeStatsRows'),
  ex(/const FOTMOB_API[\s\S]*?async function mergeFotmobRatings\(matchId, stats\) \{[\s\S]*?\n\}/, 'fotmob'),
  ex(/const SUPABASE_URL\s*=\s*'[^']+';/, 'SUPABASE_URL'),
  ex(/const SUPABASE_KEY\s*=\s*'[^']+';/, 'SUPABASE_KEY'),
].join('\n');

// const dentro de eval no sale al scope exterior; pasarlas a var sí.
eval(src.replace(/\bconst (FIXTURE|TEAM_API_MAP|ESPN_API|FOTMOB_API|SUPABASE_URL|SUPABASE_KEY)\b/g, 'var $1'));

const SB = SUPABASE_URL;
// stats/notas se escriben con la key publishable (anon). 'results' tiene RLS de admin:
// solo se sincroniza si hay SUPABASE_SERVICE_KEY (secret opcional en el workflow).
const SERVICE_KEY = process.env.SUPABASE_SERVICE_KEY || '';
const KEY = SERVICE_KEY || SUPABASE_KEY;
const CAN_RESULTS = !!SERVICE_KEY;
const DRY  = process.env.DRY_RUN === '1';
const DAYS = parseInt(process.env.DAYS || '4', 10);
const sbHeaders = { apikey: KEY, Authorization: `Bearer ${KEY}` };

async function sbUpsert(table, rows, onConflict) {
  if (!rows.length) return { ok: true, n: 0 };
  if (DRY) return { ok: true, n: rows.length, dry: true };
  const r = await fetch(`${SB}/rest/v1/${table}?on_conflict=${onConflict}`, {
    method: 'POST',
    headers: { ...sbHeaders, 'Content-Type': 'application/json', Prefer: 'resolution=merge-duplicates' },
    body: JSON.stringify(rows),
  });
  return { ok: r.ok, n: rows.length, status: r.status, body: r.ok ? '' : await r.text() };
}

async function tieneNotas(matchId) {
  const r = await fetch(`${SB}/rest/v1/gdt_match_stats?select=match_id&match_id=eq.${matchId}&rating=not.is.null&limit=1`, { headers: sbHeaders });
  const j = await r.json().catch(() => []);
  return Array.isArray(j) && j.length > 0;
}

// equipo de un partido: número = índice al array equipos (grupos); string = nombre directo (eliminatorias)
const teamOf = (g, ref) => typeof ref === 'number' ? g.equipos[ref] : ref;
function fixtureMatch(localES, visitES) {
  for (const g of Object.values(FIXTURE))
    for (const p of g.partidos)
      if (teamOf(g, p.local) === localES && teamOf(g, p.visit) === visitES) return p;
  return null;
}

const ymd = d => d.toISOString().slice(0, 10).replace(/-/g, '');

(async () => {
  const now  = new Date();
  const from = new Date(now.getTime() - DAYS * 86400000);
  const to   = new Date(now.getTime() + 1 * 86400000);  // +1 día: partidos cuya fecha local va adelantada por UTC/huso
  const url  = `${ESPN_API}/scoreboard?dates=${ymd(from)}-${ymd(to)}`;
  console.log(`[sync] ${DRY ? '(DRY) ' : ''}ventana ${ymd(from)}-${ymd(to)} · resultados:${CAN_RESULTS ? 'ON' : 'OFF (sin service key)'}`);

  const data     = await (await fetch(url)).json();
  // 'completed' cubre tiempo completo, prórroga Y penales (STATUS_FINAL_PEN). El score que da
  // ESPN es el de los 90'/prórroga (NO la tanda); el ganador que avanza es el competidor con winner:true.
  const finished = (data.events || []).filter(e => e.status?.type?.completed === true);
  console.log(`[sync] partidos terminados en ESPN: ${finished.length}`);

  let res = 0, stats = 0, notas = 0, skip = 0;
  for (const e of finished) {
    const comp = e.competitions?.[0];
    const home = comp?.competitors?.find(c => c.homeAway === 'home');
    const away = comp?.competitors?.find(c => c.homeAway === 'away');
    if (!home || !away) continue;
    const homeES = TEAM_API_MAP[home.team.displayName] || home.team.displayName;
    const awayES = TEAM_API_MAP[away.team.displayName] || away.team.displayName;
    const partido = fixtureMatch(homeES, awayES);
    if (!partido) { console.log(`  ⚠️ sin mapear: ${homeES} vs ${awayES}`); continue; }
    const matchId = partido.id;

    // Resultado (desde ESPN) — solo con service key (la tabla results es admin-only)
    const gl = Number(home.score), gv = Number(away.score);
    // "Quién pasó" (solo eliminatoria, jornada>=4): el competidor con winner:true (decide penales incl.)
    let pasaES = null;
    if (partido.jornada >= 4) {
      const w = comp.competitors.find(c => c.winner);
      if (w) pasaES = TEAM_API_MAP[w.team.displayName] || w.team.displayName;
    }
    if (CAN_RESULTS && Number.isFinite(gl) && Number.isFinite(gv)) {
      const row = { match_id: matchId, goals_local: gl, goals_visit: gv, updated_at: now.toISOString() };
      if (pasaES) row.pasa = pasaES;
      const r = await sbUpsert('results', [row], 'match_id');
      if (r.ok) { res++; if (pasaES) console.log(`  🔑 ${matchId} ${gl}-${gv}: pasó ${pasaES}`); }
      else console.log(`  ❌ result ${matchId}: ${r.status} ${r.body}`);
    }

    // Stats + notas (skip si ya tiene notas cargadas)
    if (await tieneNotas(matchId)) { skip++; continue; }
    const summary = await (await fetch(`${ESPN_API}/summary?event=${e.id}`)).json();
    const arr = buildStatsFromESPN(summary);
    if (!arr.length) continue;
    let conNotas = false;
    try { conNotas = await mergeFotmobRatings(matchId, arr); } catch (err) { console.log(`  ⚠️ FotMob ${matchId}: ${err.message}`); }
    let rows = dedupeStatsRows(arr.map(s => ({
      match_id: matchId, player_name: s.player_name, player_slug: gdtSlug(s.player_name),
      team: s.team, goals: s.goals || 0, assists: s.assists || 0, yellow_cards: s.yellow_cards || 0,
      red_cards: s.red_cards || 0, own_goals: s.own_goals || 0, minutes_played: s.minutes_played || 0,
      is_mvp: s.is_mvp || false, rating: s.rating ?? null, synced_at: now.toISOString(),
    })));
    // Si no se consiguieron notas, NO tocar la columna rating (no pisar las que ya estén)
    if (!conNotas) rows = rows.map(({ rating, ...r }) => r);
    const up = await sbUpsert('gdt_match_stats', rows, 'match_id,player_slug');
    if (up.ok) { stats++; if (conNotas) notas++; console.log(`  ✅ ${matchId} ${homeES} ${gl}-${gv} ${awayES} — ${rows.length} jug${conNotas ? ', con notas' : ' (sin notas)'}`); }
    else console.log(`  ❌ stats ${matchId}: ${up.status} ${up.body}`);
  }
  console.log(`[sync] resultados:${res} stats:${stats} (notas:${notas}) yaCompletos:${skip}${DRY ? ' (DRY: nada escrito)' : ''}`);
})().catch(e => { console.error('[sync] ERROR', e); process.exit(1); });
