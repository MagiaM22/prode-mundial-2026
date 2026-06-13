# Prode Mundial 2026 — Gran DT

App web **single-file** de prode + Gran DT (fantasy football) del Mundial 2026.
Todo vive en `index.html` (HTML + CSS + JS inline, ~3700 líneas). No hay build ni dependencias locales.

## Cómo correr

Doble clic en **`iniciar.bat`** (o `powershell -ExecutionPolicy Bypass -File servidor.ps1`).
Levanta un server local en **http://localhost:8080** y abre el navegador.

## Arquitectura

- **`index.html`** — toda la app: maqueta, estilos y lógica JS inline.
- **`servidor.ps1`** — server estático en PowerShell + **proxy** a football-data.org (resuelve CORS):
  - `/api/sync` → lista de partidos del Mundial para **resultados** (necesita API key de football-data; solo funciona desde localhost).
- **Stats del Gran DT: ESPN** (`site.api.espn.com/.../soccer/fifa.world`), directo desde el browser — tiene CORS abierto, **sin key y sin servidor local**. `espnFindEvent` (scoreboard por fecha ±1 día + `TEAM_API_MAP`) → `summary?event=` → `buildStatsFromESPN` (rosters = titulares 90'; keyEvents = goles/asistencias/tarjetas/cambios; en sustituciones participants=[entra, sale]).
  - ⚠️ APIs descartadas para stats, no volver a intentarlas: **Sofascore** (403 challenge anti-bot, 06/2026) y **football-data** (el detalle de partido viene vacío en el tier gratis).
- **Notas del partido (1-10): FotMob** (`www.fotmob.com/api/data`, sin key; ojo: la ruta es `/api/data/...`, `/api/...` a secas da 404). ⚠️ FotMob **bloquea `matchDetails` desde browsers cross-origin** ("Failed to fetch"; `matches` sí responde — verificado en Chrome headless 06/2026) → en localhost las llamadas van por el proxy `/api/fotmob?path=...` de `servidor.ps1`; desde la página publicada el sync guarda stats sin notas y avisa. `mergeFotmobRatings` mezcla la nota por slug del nombre (con fallback de tokens ordenados porque FotMob invierte nombres asiáticos: "In-Beom Hwang") y marca `is_mvp` al mejor puntuado → ahí aplica el +2 del scoring. FotMob agrupa por fecha UTC: se busca la fecha del fixture y el día siguiente. Requiere columna `rating numeric` en `gdt_match_stats`.
  - Ojo nombres coreanos/romanización: algunos suplentes de Corea no matchean por slug con la base (ej. Lee Gi-Hyuk). Si un jugador así puntúa, revisar el nombre en `GDT_PLAYERS`.
- **`iniciar.bat`** — lanza el server y abre el navegador.
- **Backend de datos y auth: Supabase** (cliente JS por CDN, `SUPABASE_URL`/`SUPABASE_KEY` en index.html). Tablas: `profiles`, `tournaments`, predicciones, resultados, equipos GDT.

## Gran DT — base de jugadores

- `const GDT_PLAYERS` (~línea 2400): **48 selecciones × 26 = 1248 jugadores** (convocatorias oficiales reales del Mundial 2026).
- Forma de cada jugador:
  ```js
  {id:'ARG-22', nombre:'Lautaro Martínez', pos:'DEL', seleccion:'Argentina', rating:88, precio:104, flag:'🇦🇷'}
  ```
  - **`rating`** = overall EA FC 26 (dato base **inmutable**).
  - **`precio`** = `round(rating × multiplicador[pos])` = costo en fichas.
    Multiplicadores: **DEL ×1.18 · MED ×1.00 · DEF ×0.94 · GK ×0.88**
    (delantero rinde más puntos → cuesta más; arquero el más barato porque solo se usa 1).
  - **`est:1`** (opcional) = precio estimado a ojo (jugador que no figura en EA FC 26: juveniles, selecciones chicas).
- Config del juego (~línea 2386): `GDT_BUDGET = 1200`, 11 titulares + 4 suplentes, límites por puesto (`GDT_LIMITS`), scoring `GDT_PTS`.
- **Para re-tunear precios:** reaplicar la fórmula **sobre `rating`** (nunca acumular sobre `precio`). Es una pasada idempotente: leer `rating`, recalcular `precio`.
- Scoring (motor `calcGDTMatchPoints`): **base = nota del partido (1-10, FotMob; 6 de oficio si jugó sin nota)** + eventos `GDT_PTS`: gol GK10/DEF8/MED6/DEL5, valla invicta GK4/DEF3, asist 3, amarilla -1, roja -3, gol en contra -2, MVP +2, minutos +1 (60'+). Capitán ×2 (multiplica todo, nota incluida). Total redondeado a 1 decimal.
- **Equipo de la Fecha** (pestaña ⭐, visible a todos): mejor 11 por jornada según puntos GDT en **formación fija 4-3-3**; se recalcula de `_gdtMatchStats`. Funciones `calcTeamOfWeek`/`renderTeamOfWeek`.
- **Cambios**: **3 por ventana** (`GDT_SWAPS_PER_WINDOW`). Ventanas: J2 (de inicio J1 a 30 min antes de J2) y J3; después, bloqueado. Solo titulares. Contador en `gdt_user_teams.transfers` formato `{j2:n, j3:n, fix:n, fixSeen:bool}` (el viejo `{j2_used:bool}` se normaliza con `gdtNormalizeTransfers`). Guardar equipo exige 11 titulares + 4 suplentes + capitán.
- **Arreglo por única vez** (`GDT_FIX_CHANGES=6`): SOLO los equipos **rotos** (`gdtTeamRoto()`: ≠11 titulares, ≠4 suplentes, o >1200 fichas) reciben edición libre fuera de ventana, con tope de 6 cambios (contados vs `_gdtBaseline` al guardar). `_gdtFixEligible` se calcula al cargar y se apaga al guardar un equipo válido. Los equipos válidos NO reciben nada. Modal "HOLA MAÑERO" (`maybeShowFixWelcome`) se muestra una vez (`transfers.fixSeen`) solo a equipos rotos.
- **Ventana de gracia para nuevos** (`GDT_NEW_TEAM_DEADLINE`, ~24hs): quien no tiene equipo (`gdtGraceNewTeam()`) puede armarlo aunque el torneo ya empezó.
- **Anti-trampa**: al editar fuera de 'pre' (arreglo o gracia) NO se pueden AGREGAR jugadores de selecciones que ya jugaron (`gdtNacionesJugaron()`: partido con kickoff pasado o con resultado). Se bloquea en el pool (gris + "ya jugó 🔒"), en `toggleGDTPlayer` y al guardar. Los que ya estaban en el equipo (en `_gdtBaseline`) se pueden mantener.

## Seguridad (Supabase RLS)

- `gdt_user_teams` y `results` ya tienen RLS (escritura solo dueño / solo admins). `gdt_match_stats` estaba **abierta a escritura anónima** (la key publishable es pública) → `seguridad.sql` la cierra a admins + service_role. Correr ese SQL **después** de poner el secret `SUPABASE_SERVICE_KEY` en el workflow (si no, el cron deja de escribir). Detalle e instrucciones en `seguridad.sql`.

### Cómo actualizar la base más adelante
Convocatorias: prensa / `worldcuppass.com/<pais>-world-cup-squad-2026`.
Ratings EA FC 26: `fcratings.com/nations/<slug>-<id>` (ojo: el listado mezcla jugadoras mujeres, filtrar).

## Auth (Supabase)

Login / Registro / **Recuperar contraseña**.
Flujo de recuperación: link "¿Olvidaste tu contraseña?" → `sb.auth.resetPasswordForEmail` → mail → al volver dispara el evento `PASSWORD_RECOVERY` → muestra form de clave nueva → `sb.auth.updateUser`.

### ⚠️ PENDIENTE DE CONFIG (para que el reset de contraseña funcione)
En el panel de **Supabase → Authentication → URL Configuration**:
1. Agregar **`http://localhost:8080`** y **`https://magiam22.github.io/prode-mundial-2026/`** a la lista de **Redirect URLs** (y poner la de github.io como **Site URL**).
2. Tener el **envío de emails activo** (el built-in de Supabase alcanza para poco volumen; o configurar SMTP).

> El link del mail apunta a `localhost`, así que hay que abrir el mail **en la misma compu** donde corre el server.
> Mientras esto no esté configurado, para resetear una clave: Supabase → Authentication → Users → buscar el email → "Send password recovery" / setear clave nueva.

## Sincronización automática (GitHub Actions)

- `.github/workflows/sync.yml` corre `scripts/sync.cjs` **cada 20 min en los servidores de GitHub** (sin PC ni API key): resultados + stats desde ESPN, notas desde FotMob, escribe en Supabase con la `SUPABASE_KEY` publishable (RLS abierta). El script **extrae las mismas funciones de index.html** (no duplica lógica); si cambiás `buildStatsFromESPN`/`mergeFotmobRatings`/`FIXTURE`/`TEAM_API_MAP`, el cron usa la versión nueva sola. Probar local: `DRY_RUN=1 node scripts/sync.cjs`.
- Salta partidos que ya tienen notas (idempotente y liviano). El sync manual desde localhost (botón Sync stats / football-data) sigue funcionando en paralelo.
- **Permisos Supabase**: `gdt_match_stats` es escribible con la key anon (publishable) → el cron sincroniza stats+notas sin secret. `results` tiene RLS admin-only → el cron solo escribe resultados si está el secret `SUPABASE_SERVICE_KEY` en el workflow (`CAN_RESULTS`); sin él, los resultados se cargan desde localhost (football-data) como siempre. ⚠️ Nota de seguridad: con anon se puede escribir/borrar `gdt_match_stats` (riesgo de vandalismo, aceptado para juego entre amigos).
- ⚠️ Riesgo conocido: FotMob podría bloquear las IPs de GitHub Actions (datacenter). Si pasa, resultados y stats igual entran; las notas quedan para el sync desde localhost. Verificar en la pestaña Actions del repo.

## Publicación

- **Hosting: GitHub Pages** (Settings → Pages → Deploy from a branch → `main` / root) → `https://magiam22.github.io/prode-mundial-2026/`. Se redeploya solo con cada push a `main`.
- No hace falta server en la nube: el sync de resultados/stats es solo-admin y corre desde localhost con `servidor.ps1`; los datos quedan en Supabase y la página publicada los lee de ahí.
- ⚠️ **Antes de pushear: `git pull` siempre.** El 11/06/2026 un push con una copia local vieja de `index.html` pisó la base GDT completa, el reset de contraseña, la tabla general y los links de invitación (restaurado en `76f113d`). Canario rápido: `rating:` debe aparecer **1248 veces** en `index.html`; si un commit chico toca miles de líneas, es una versión vieja pisando la actual.

## Horarios

- Los `fecha`/`hora` del FIXTURE están en **hora argentina** y se parsean con offset explícito: `new Date(`${fecha}T${hora}:00-03:00`)`. **No** "corregirlos" a UTC (`Z`): eso adelanta los bloqueos 3 horas (ya pasó, revertido en 2a53f55). JS los convierte solo a la zona del visitante.
- Pronósticos: se bloquean **5 min** antes de cada partido (`isMatchLocked`). Ventanas del Gran DT: 30 min antes del primer partido de cada jornada, derivadas del FIXTURE (`jornadaLock`), sin fechas hardcodeadas.

## Convenciones

- Castellano (argentino). Mensajes de UI informales.
- Todo en `index.html`: al editar, respetar el estilo inline existente. No hay framework.
- Datos del Gran DT: mantener `id` únicos y 26 jugadores por selección.
