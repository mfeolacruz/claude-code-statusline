#!/usr/bin/env bash
# Statusline para Claude Code.
# Lee el JSON de sesión desde stdin y muestra tres barras de uso:
#   ctx — porcentaje de la ventana de contexto del modelo
#   5h  — porcentaje de la cuota rolling de 5h + hora de reset
#   7d  — porcentaje de la cuota rolling de 7d + día/hora de reset

# --- Construye una barra de progreso con etiqueta coloreada ---
# Uso: make_bar LABEL PCT_FLOAT
# Imprime: "LABEL [████░░░░░░] 45%"  con color ANSI según umbral.
make_bar() {
  local label="$1"
  local pct="$2"

  local filled empty bar pct_int color reset
  reset="\033[0m"

  filled=$(echo "$pct" | awk '{printf "%d", int($1 / 10 + 0.5)}')
  [ "$filled" -gt 10 ] && filled=10
  empty=$((10 - filled))

  bar=""
  for i in $(seq 1 "$filled"); do bar="${bar}█"; done
  for i in $(seq 1 "$empty");  do bar="${bar}░"; done

  pct_int=$(echo "$pct" | awk '{printf "%d", int($1 + 0.5)}')
  if   [ "$pct_int" -gt 85 ]; then color="\033[31m"   # rojo
  elif [ "$pct_int" -ge 60 ]; then color="\033[33m"   # amarillo
  else                              color="\033[32m"   # verde
  fi

  printf "%s [%s] %b%d%%%b" "$label" "$bar" "$color" "$pct_int" "$reset"
}

# ── Leer JSON de sesión ────────────────────────────────────────────────────────
input=$(cat)

# jq es requerido; sin él no hay nada que mostrar
command -v jq >/dev/null 2>&1 || exit 0

# ── Extraer porcentajes y timestamps ──────────────────────────────────────────
ctx_pct=$(printf '%s' "$input" | jq -r '
  .context_window.used_percentage //
  .transcript.used_percentage     //
  .used_percentage                //
  empty' 2>/dev/null)

five_pct=$(printf '%s' "$input" | jq -r '
  .rate_limits.five_hour.used_percentage //
  .rate_limits.five_hour.utilization     //
  .five_hour.used_percentage             //
  empty' 2>/dev/null)

five_reset=$(printf '%s' "$input" | jq -r '
  .rate_limits.five_hour.resets_at //
  empty' 2>/dev/null)

seven_pct=$(printf '%s' "$input" | jq -r '
  .rate_limits.seven_day.used_percentage //
  .rate_limits.seven_day.utilization     //
  empty' 2>/dev/null)

seven_reset=$(printf '%s' "$input" | jq -r '
  .rate_limits.seven_day.resets_at //
  empty' 2>/dev/null)

# ── Helper: añade ↻ HH:MM al segmento si pct>0 y hay epoch parseable ─────────
append_reset() {
  local seg="$1" pct="$2" epoch="$3" fmt="$4"
  local pct_int reset_time
  [ -z "$epoch" ] && { printf '%s' "$seg"; return; }
  pct_int=$(echo "$pct" | awk '{printf "%d", int($1 + 0.5)}')
  [ "$pct_int" -le 0 ] && { printf '%s' "$seg"; return; }
  reset_time=$(date -r "$epoch" "+$fmt" 2>/dev/null)
  [ -z "$reset_time" ] && { printf '%s' "$seg"; return; }
  printf '%s ↻ %s' "$seg" "$reset_time"
}

# ── Render ─────────────────────────────────────────────────────────────────────
segments=()

[ -n "$ctx_pct" ] && segments+=("$(make_bar "ctx" "$ctx_pct")")

if [ -n "$five_pct" ]; then
  segments+=("$(append_reset "$(make_bar "5h" "$five_pct")" "$five_pct" "$five_reset" "%H:%M")")
fi

if [ -n "$seven_pct" ]; then
  # 7d: si reset >24h, "DDD HH:MM"; si no, "HH:MM"
  fmt_7d="%H:%M"
  if [ -n "$seven_reset" ]; then
    diff=$(( seven_reset - $(date +%s) ))
    [ "$diff" -gt 86400 ] && fmt_7d="%a %H:%M"
  fi
  segments+=("$(append_reset "$(make_bar "7d" "$seven_pct")" "$seven_pct" "$seven_reset" "$fmt_7d")")
fi

sep=""
for s in "${segments[@]}"; do
  printf '%s%s' "$sep" "$s"
  sep=' │ '
done
