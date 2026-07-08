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
  ex(/^function teamName\(group, ref\) \{[\s\S]*?function partidoDefinido\(group, p\) \{[\s\S]*?\n\}/m, 'teamName+cuadro'),
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

// Mapea por nombre resuelto. teamName resuelve grupos (índice), eliminatorias con nombre (string)
// y cruces del cuadro ({w:'ID'}/{l:'ID'}) contra globalThis._results (cargado abajo).
function fixtureMatch(localES, visitES) {
  for (const g of Object.values(FIXTURE))
    for (const p of g.partidos)
      if (teamName(g, p.local) === localES && teamName(g, p.visit) === visitES) return p;
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

  // Resultados ya guardados → resuelven los cruces del cuadro ({w:'ID'}/{l:'ID'}) para mapear cuartos→final.
  try {
    const rr = await (await fetch(`${SB}/rest/v1/results?select=match_id,goals_local,goals_visit,pasa`, { headers: sbHeaders })).json();
    const map = {};
    for (const r of (Array.isArray(rr) ? rr : [])) map[r.match_id] = { local: r.goals_local, visit: r.goals_visit, pasa: r.pasa || undefined };
    globalThis._results = map;
    console.log(`[sync] resultados previos: ${Object.keys(map).length} (resuelven el cuadro)`);
  } catch (e) { globalThis._results = {}; console.log('[sync] ⚠️ resultados previos: ' + e.message); }

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
    let gl = Number(home.score), gv = Number(away.score);
    const st = e.status?.type?.name || '';
    const trasLos90 = st === 'STATUS_FINAL_AET' || st === 'STATUS_FINAL_PEN' || st === 'STATUS_FINAL_ET';
    let summary = null;  // se reusa para las stats
    if (trasLos90) {
      // El .score incluye los goles de la PRÓRROGA → el prode se puntúa con el marcador de los 90'
      // (los goles de períodos 1 y 2). El del alargue no cuenta para el resultado, solo el "quién pasó".
      try {
        summary = await (await fetch(`${ESPN_API}/summary?event=${e.id}`)).json();
        let rl = 0, rv = 0;
        for (const kev of (summary.keyEvents || [])) {
          if (!kev.scoringPlay || (kev.period?.number || 99) > 2) continue;   // solo 90' (no prórroga/penales)
          // ESPN pone kev.team = el equipo que SE ANOTA el gol (incluso en goles en contra el
          // team ya es el beneficiario). Se cuenta para ese equipo tal cual, sin invertir.
          const t = kev.team?.displayName;
          if (t === home.team.displayName) rl++; else if (t === away.team.displayName) rv++;
        }
        gl = rl; gv = rv;
      } catch (err) { console.log(`  ⚠️ 90' ${matchId}: ${err.message}`); }
    }
    // "Quién pasó" (solo eliminatoria, jornada>=4): el competidor con winner:true (decide prórroga/penales)
    let pasaES = null;
    if (partido.jornada >= 4) {
      const w = comp.competitors.find(c => c.winner);
      if (w) pasaES = TEAM_API_MAP[w.team.displayName] || w.team.displayName;
    }
    if (CAN_RESULTS && Number.isFinite(gl) && Number.isFinite(gv)) {
      const row = { match_id: matchId, goals_local: gl, goals_visit: gv, updated_at: now.toISOString() };
      if (pasaES) row.pasa = pasaES;
      const r = await sbUpsert('results', [row], 'match_id');
      if (r.ok) { res++; globalThis._results[matchId] = { local: gl, visit: gv, pasa: pasaES || undefined }; if (pasaES) console.log(`  🔑 ${matchId} ${gl}-${gv}${trasLos90 ? ' (90min)' : ''}: pasó ${pasaES}`); }
      else console.log(`  ❌ result ${matchId}: ${r.status} ${r.body}`);
    }

    // Stats + notas (skip si ya tiene notas cargadas)
    if (await tieneNotas(matchId)) { skip++; continue; }
    if (!summary) summary = await (await fetch(`${ESPN_API}/summary?event=${e.id}`)).json();
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
