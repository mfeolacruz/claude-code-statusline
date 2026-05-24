# claude-code-statusline

Statusline custom para [Claude Code](https://claude.com/claude-code) que muestra en una sola línea:

- **`ctx`** — porcentaje de la ventana de contexto del modelo consumido.
- **`5h`** — porcentaje de la cuota rolling de 5 horas + hora exacta de reset.
- **`7d`** — porcentaje de la cuota rolling de 7 días + día/hora de reset.

Toda la data sale del JSON que Claude Code pasa por stdin al script. **Cero llamadas HTTP, cero credenciales, cero dependencias de terceros.**

## Cómo se ve

```
ctx [███░░░░░░░] 34% │ 5h [█░░░░░░░░░] 6% ↻ 18:30 │ 7d [██░░░░░░░░] 22% ↻ vie 09:00
```

Coloreado por umbral:
- Verde — <60%
- Amarillo — 60-85%
- Rojo — >85%

El `↻ HH:MM` (reset) aparece solo cuando esa ventana tiene consumo >0%. Para la barra `7d`, si el reset está a más de 24h vista, se muestra el día abreviado además de la hora (`vie 09:00`); si es hoy, solo la hora.

## Instalación

1. Copia el script a tu carpeta de Claude Code:

   ```bash
   mkdir -p ~/.claude
   curl -fsSL https://raw.githubusercontent.com/mfeolacruz/claude-code-statusline/main/.claude/statusline-command.sh \
     -o ~/.claude/statusline-command.sh
   ```

   (O clona el repo y copia el archivo manualmente.)

2. Añade el bloque `statusLine` a tu `~/.claude/settings.json`. Si el archivo no existe, créalo con este contenido:

   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "bash /Users/YOUR_USER/.claude/statusline-command.sh"
     }
   }
   ```

   Reemplaza `YOUR_USER` por tu usuario real (`echo $USER` te lo dice). Si ya tienes otras claves en `settings.json`, añade solo el bloque `statusLine` sin tocar el resto.

3. La barra aparece en tu próximo mensaje a Claude Code. No hace falta reiniciar.

## Requisitos

- macOS, Linux o WSL con `bash` (≥3.2), `jq`, `date` y `awk` en PATH.
- Plan Pro/Max de Claude para que los campos `rate_limits.*` aparezcan en stdin (en otros planes, solo se mostrará la barra `ctx`).
- Terminal con soporte UTF-8 y ANSI colors.

> El script detecta automáticamente si tu `date` es BSD (macOS) o GNU (Linux/WSL) y usa la sintaxis correcta para convertir el Unix epoch a hora local — no hace falta tocarlo.

## Cómo funciona

Claude Code tiene un hook nativo de statusline: en `settings.json` declaras un comando shell, y en cada redraw de la barra inferior Claude Code lo invoca pipeándole un JSON con info de la sesión por stdin. El script captura ese stdout y lo renderiza literal.

```
[mandas un mensaje]
        ↓
[Claude Code redibuja la UI]
        ↓
[forka `bash <script>` y pipea JSON de sesión]
        ↓
[el script parsea con jq, formatea barras + colores, printf a stdout]
        ↓
[Claude Code renderiza ese stdout en la barra inferior]
```

Campos del stdin que el script consume:

| Campo | Uso |
|---|---|
| `.context_window.used_percentage` | Barra `ctx` |
| `.rate_limits.five_hour.used_percentage` | Barra `5h` |
| `.rate_limits.five_hour.resets_at` (Unix epoch) | Hora reset `5h` |
| `.rate_limits.seven_day.used_percentage` | Barra `7d` |
| `.rate_limits.seven_day.resets_at` (Unix epoch) | Día/hora reset `7d` |

Hay paths de fallback con `//` por si Claude Code cambia algún nombre de campo: `.transcript.used_percentage`, `.used_percentage`, `.five_hour.used_percentage`, `.rate_limits.{five_hour,seven_day}.utilization`.

## Caveats

- Si tu plan no incluye `rate_limits` en stdin, las barras `5h`/`7d` se omiten silenciosamente y solo se muestra `ctx` — el script no rompe.
- Anthropic puede cambiar el esquema del JSON de stdin sin previo aviso; los fallbacks `//` mitigan, pero si un día deja de mostrar algún campo, abrir el script y añadir el nuevo path.

## Verificar qué hay en tu stdin

Si quieres confirmar qué campos llegan en TU sesión, añade temporalmente esta línea al script tras `input=$(cat)`:

```bash
printf '%s' "$input" > /tmp/cc-stdin.json
```

Manda cualquier mensaje, inspecciona `cat /tmp/cc-stdin.json | jq .`, quita la línea.

## License

MIT.
