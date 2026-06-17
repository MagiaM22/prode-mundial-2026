# Cambios recientes (para Marcos)

Resumen de lo que se tocó, agrupado por tema. El detalle fino está en `CLAUDE.md`
y en los mensajes de cada commit (`git log`).

## Sincronización automática (lo más importante)
- **`.github/workflows/sync.yml` + `scripts/sync.cjs`**: un cron corre cada ~20 min en
  los servidores de GitHub y carga **resultados + stats + notas** solo. No necesita la
  PC de nadie. Resultados/stats salen de **ESPN**, las notas de **FotMob**. Para escribir
  resultados usa el secret `SUPABASE_SERVICE_KEY` (ya configurado).
- El script reutiliza las funciones del `index.html` (las extrae), así que mejoras en el
  index las toma el cron solo. Probar en local: `DRY_RUN=1 node scripts/sync.cjs`.
- Fixes del camino: nombres que ESPN/FotMob escriben distinto (Bosnia-Herzegovina, Turkiye),
  jugadores con nombre repetido que rompían el guardado (Ederson/Éderson), ventana de fechas
  ampliada +1 día, y que un sync sin notas no pise las notas ya cargadas.

## Gran DT
- **Notas del partido (1-10, FotMob)**: ahora la nota es la **base del puntaje** y los
  eventos (gol, asistencia, valla, tarjetas, MVP, 60') suman encima. Vuelve el MVP (+2).
- **Suplentes (FIX)**: el suplente entra **solo si el titular jugó 0 minutos** y toma su lugar
  el primer suplente del mismo puesto que sí jugó esa fecha. (Antes metía suplentes mal.)
- **Edición por fecha**: lo que editás aplica a la **próxima fecha que no empezó**; las
  fechas ya jugadas quedan **congeladas** (no se recalculan con el equipo nuevo). Reemplazó
  al sistema viejo de "3 cambios por ventana".
- **Tabla GDT**: es **global** (todos los que armaron equipo) y tiene selector
  **General + Fecha 1/2/3**. Más una **Cancha** rediseñada (círculo con puntaje + nombre).

## Prode / torneos
- **Pronósticos que "no se guardaban"**: la base guarda bien; el problema era el lío de
  varios torneos. Ahora **todos quedan en el torneo principal por defecto** y se aclara en la
  UI que jugás todos a la vez (el botón "Ver" solo cambia la vista, no te baja de ninguno).
- Red de seguridad: si el formulario aparece vacío por un glitch, **no borra** los pronósticos.
- Bonus manual configurable (`PRODE_BONUS` en index.html).

## Seguridad
- **`seguridad.sql`**: cierra la escritura anónima a `gdt_match_stats` (correr DESPUÉS de
  tener el `SUPABASE_SERVICE_KEY` en el workflow, ver el archivo).
- Gag para curiosos en la consola del navegador y al fondo del Inicio (chistes internos).

## Pendiente del lado de Marcos (opcional)
1. Correr `seguridad.sql` en Supabase → SQL Editor (después del paso de la service key).
2. Limpiar el usuario de prueba de diagnóstico (alias `testdiag`): ver SQL al final de esta sesión.
