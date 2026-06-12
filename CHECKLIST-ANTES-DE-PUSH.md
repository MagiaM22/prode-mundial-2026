# ⚠️ CHECKLIST OBLIGATORIO ANTES DE HACER PUSH

**NUNCA pushear sin verificar TODOS estos puntos:**

## 1. Integridad de datos (CRÍTICO)
- [ ] GDT_PLAYERS: Verificar que existan **1248 jugadores** (grep "rating:" debe dar 1248)
- [ ] GDT_BUDGET: Debe ser 1200
- [ ] FIXTURE: Los 12 grupos con sus partidos deben estar

## 2. No editar estos archivos
- ❌ GDT_PLAYERS (solo si actualizas ratings)
- ❌ FIXTURE (solo si actualizas horarios/fechas)
- ❌ Tablas de Supabase desde aquí

## 3. Antes de pushear
```bash
# Verificar que tienes los 1248 jugadores
grep -o "rating:" index.html | wc -l  # Debe dar 1248

# Ver qué cambios vas a hacer
git diff index.html | head -20
```

## 4. Si dudas, NO pushees
- Pregunta primero
- Mejor tardío que corrupto

## Comando para restaurar si se rompe:
```bash
git reset --hard backup-20250611-stable
git push --force
```

---
**Última actualización:** 2026-06-11 13:43 (Argentina)
**Backup estable:** backup-20250611-stable
