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

  local bar pct_int color reset
  reset="\033[0m"

  # Genera bar + pct_int en una sola pasada de awk.
  # Evita `seq 1 0`, que en BSD (macOS) emite "1\n0" en vez de nada y añadía
  # 2 caracteres extra a la barra en los extremos (pct=0 y pct=100).
  IFS=$'\t' read -r bar pct_int <<<"$(awk -v p="$pct" 'BEGIN {
    f = int(p / 10 + 0.5); if (f > 10) f = 10; if (f < 0) f = 0;
    b = "";
    for (i = 0; i < f;  i++) b = b "█";
    for (i = 0; i < 10 - f; i++) b = b "░";
    printf "%s\t%d", b, int(p + 0.5)
  }')"
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

# ── Extraer porcentajes y timestamps (una sola llamada a jq) ─────────────────
# Una invocación con @tsv en vez de cinco: reduce el coste de fork/exec en
# cada render de la statusline, importante cuando hay ráfagas de repaints.
IFS=$'\t' read -r ctx_pct five_pct five_reset seven_pct seven_reset <<<"$(
  printf '%s' "$input" | jq -r '
    [
      (.context_window.used_percentage // .transcript.used_percentage // .used_percentage // ""),
      (.rate_limits.five_hour.used_percentage // .rate_limits.five_hour.utilization // .five_hour.used_percentage // ""),
      (.rate_limits.five_hour.resets_at // ""),
      (.rate_limits.seven_day.used_percentage // .rate_limits.seven_day.utilization // ""),
      (.rate_limits.seven_day.resets_at // "")
    ] | @tsv' 2>/dev/null
)"

# ── Helper: formatea Unix epoch en BSD (macOS) o GNU (Linux/WSL) date ────────
fmt_epoch() {
  date -r "$1" "+$2" 2>/dev/null || date -d "@$1" "+$2" 2>/dev/null
}

# ── Helper: añade ↻ HH:MM al segmento si pct>0 y hay epoch parseable ─────────
append_reset() {
  local seg="$1" pct="$2" epoch="$3" fmt="$4"
  local pct_int reset_time
  [ -z "$epoch" ] && { printf '%s' "$seg"; return; }
  pct_int=$(echo "$pct" | awk '{printf "%d", int($1 + 0.5)}')
  [ "$pct_int" -le 0 ] && { printf '%s' "$seg"; return; }
  reset_time=$(fmt_epoch "$epoch" "$fmt")
  [ -z "$reset_time" ] && { printf '%s' "$seg"; return; }
  printf '%s ↻ %s' "$seg" "$reset_time"
}

# ── Helper: valida que un valor sea un porcentaje en rango 0-100 ─────────────
# Defensa contra JSONs transitorios (ej. tras /clear) donde el campo de
# porcentaje puede llegar como epoch o con basura: si no es 0-100, omitimos
# el segmento en vez de renderizar valores absurdos como "178000000%".
is_valid_pct() {
  [ -z "$1" ] && return 1
  awk -v v="$1" 'BEGIN { exit !(v ~ /^[0-9]+(\.[0-9]+)?$/ && v+0 >= 0 && v+0 <= 100) }'
}

# ── Detectar ancho del terminal para evitar wrapping ─────────────────────────
# Si la línea completa no cabe, omitimos los segmentos menos críticos en vez
# de dejar que la statusline wrappee sobre la conversación.
cols=${COLUMNS:-$(tput cols 2>/dev/null || echo 120)}

# ── Render ─────────────────────────────────────────────────────────────────────
segments=()

is_valid_pct "$ctx_pct" && segments+=("$(make_bar "ctx" "$ctx_pct")")

if is_valid_pct "$five_pct" && [ "$cols" -ge 50 ]; then
  segments+=("$(append_reset "$(make_bar "5h" "$five_pct")" "$five_pct" "$five_reset" "%H:%M")")
fi

if is_valid_pct "$seven_pct" && [ "$cols" -ge 80 ]; then
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
