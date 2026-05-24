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

## Requisitos

- macOS, Linux o WSL con `bash` (≥3.2), `jq`, `date` y `awk` en PATH.
- Plan Pro/Max de Claude (en planes inferiores `rate_limits.*` no aparece en stdin y solo se mostrará la barra `ctx`).
- Terminal con soporte UTF-8 y ANSI colors.

## Instalación

### 1. Instala `jq` si no lo tienes

| SO | Comando |
|---|---|
| macOS | `brew install jq` |
| Debian/Ubuntu | `sudo apt install jq` |
| Fedora/RHEL | `sudo dnf install jq` |
| Arch | `sudo pacman -S jq` |
| WSL | mismo que la distro Linux subyacente |
| Windows nativo | no soportado, usa WSL |

Verifica con `command -v jq` (debe imprimir un path).

### 2. Copia el script a tu carpeta de Claude Code

```bash
mkdir -p ~/.claude
curl -fsSL https://raw.githubusercontent.com/mfeolacruz/claude-code-statusline/main/.claude/statusline-command.sh \
  -o ~/.claude/statusline-command.sh
```

(O clona el repo y copia el archivo manualmente.)

### 3. Añade el bloque `statusLine` a `~/.claude/settings.json`

**Si NO tienes ya un `settings.json`**, créalo con este contenido:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash /Users/YOUR_USER/.claude/statusline-command.sh"
  }
}
```

**Si YA tienes un `settings.json` con otras claves**, abre el archivo y añade solo el bloque `statusLine` sin tocar lo demás. Ejemplo de cómo queda tras el merge:

Antes:
```json
{
  "model": "claude-opus-4-7"
}
```

Después (añades `statusLine`, conservas todo lo demás):
```json
{
  "model": "claude-opus-4-7",
  "statusLine": {
    "type": "command",
    "command": "bash /Users/YOUR_USER/.claude/statusline-command.sh"
  }
}
```

Reemplaza `/Users/YOUR_USER/` por el path absoluto a tu home según tu SO:

| SO | Path al script |
|---|---|
| macOS | `/Users/<tu-usuario>/.claude/statusline-command.sh` |
| Linux | `/home/<tu-usuario>/.claude/statusline-command.sh` |
| WSL | `/home/<tu-usuario>/.claude/statusline-command.sh` |

`echo $HOME` te lo dice exacto en tu terminal.

### 4. Verifica

La barra debería aparecer en tu próximo mensaje a Claude Code. No hace falta reiniciar nada.

## Si no aparece la barra

Pasa estos 4 checks copy-pasteables; el primero que falle te dice dónde está el problema:

```bash
# 1. ¿jq está instalado?
command -v jq && echo OK || echo "INSTALA jq (ver Requisitos)"

# 2. ¿settings.json tiene sintaxis JSON válida?
jq . ~/.claude/settings.json > /dev/null && echo OK || echo "JSON ROTO en settings.json"

# 3. ¿el path al script en settings.json apunta a un archivo real?
jq -r '.statusLine.command' ~/.claude/settings.json | awk '{print $2}' | xargs ls -la

# 4. ¿el script renderiza con un JSON de prueba?
echo '{"context_window":{"used_percentage":45}}' | bash ~/.claude/statusline-command.sh
```

Si los 4 pasan pero la barra sigue sin aparecer, dump del stdin real para ver qué llega:

```bash
# Añade temporalmente esta línea al script tras `input=$(cat)`:
printf '%s' "$input" > /tmp/cc-stdin.json

# Manda cualquier mensaje a Claude Code, luego inspecciona:
cat /tmp/cc-stdin.json | jq 'keys'
cat /tmp/cc-stdin.json | jq '.rate_limits'
```

Te dice qué campos hay realmente y puedes ajustar los paths jq del script si Claude Code cambió el esquema.

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

El script detecta automáticamente si tu `date` es BSD (macOS) o GNU (Linux/WSL) y usa la sintaxis correcta para convertir el Unix epoch a hora local — no hace falta tocarlo.

## Caveats

- Si tu plan no incluye `rate_limits` en stdin, las barras `5h`/`7d` se omiten silenciosamente y solo se muestra `ctx` — el script no rompe.
- Anthropic puede cambiar el esquema del JSON de stdin sin previo aviso; los fallbacks `//` mitigan, pero si un día deja de mostrar algún campo, abrir el script y añadir el nuevo path.

## Desinstalar

1. Edita `~/.claude/settings.json` y elimina el bloque `statusLine` entero (deja el resto intacto).
2. Opcional: borra el script con `rm ~/.claude/statusline-command.sh`.
3. La barra desaparece en tu próximo mensaje.

## License

MIT.
