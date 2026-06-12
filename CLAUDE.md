# Prode Mundial 2026 — Gran DT

App web **single-file** de prode + Gran DT (fantasy football) del Mundial 2026.
Todo vive en `index.html` (HTML + CSS + JS inline, ~3700 líneas). No hay build ni dependencias locales.

## Cómo correr

Doble clic en **`iniciar.bat`** (o `powershell -ExecutionPolicy Bypass -File servidor.ps1`).
Levanta un server local en **http://localhost:8080** y abre el navegador.

## Arquitectura

- **`index.html`** — toda la app: maqueta, estilos y lógica JS inline.
- **`servidor.ps1`** — server estático en PowerShell + **proxy** a APIs externas (resuelve CORS):
  - `/api/sync` → football-data.org (fixture/resultados, necesita API key)
  - `/api/sofascore` → Sofascore (stats por partido para el Gran DT: goles, asistencias, tarjetas, MVP)
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
- Scoring `GDT_PTS` (validado vs FPL y WC Fantasy oficial): gol GK10/DEF8/MED6/DEL5, valla invicta GK4/DEF3, asist 3, amarilla -1, roja -3, gol en contra -2, MVP +2, minutos +1 (60'+). Capitán ×2. Motor de cálculo: `calcGDTMatchPoints` (~línea 4189).

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
