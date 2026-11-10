#!/usr/bin/env bash
#
# gui-lint — guardrails for the plugin side panels.
#
# Rejects, under plugins/*/src/gui and shared/src/gui:
#   - raw hex colors (var() fallbacks and custom-property series are allowed)
#   - theme tokens that do not exist
#   - Portuguese literals outside i18n.ts / setup.tsx
#   - the old scoped package name and relative imports into shared/
#
# Usage: scripts/gui-lint.sh   (or `bun run lint:gui` from the parent)
#
set -euo pipefail

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

found="$(
  find "$ROOT/plugins" "$ROOT/shared/src" \
    -path '*/src/gui/*' \( -name '*.ts' -o -name '*.tsx' \) \
    -not -path '*/node_modules/*' -not -path '*/dist/*' -print0 \
  | sort -z \
  | xargs -0 -r awk '
    {
      n = split(FILENAME, parts, "/")
      base = parts[n]
      trimmed = $0
      sub(/^[ \t]+/, "", trimmed)
      if (trimmed ~ /^\/\// || trimmed ~ /^\*/ || trimmed ~ /^\/\*/) next

      if ($0 ~ /--v2-(text-text-(danger|success|warning|info)|background-bg-(danger|warning)|border-border-danger)/) {
        printf "%s:%d: invalid token: %s\n", FILENAME, FNR, $0
        failed = 1
        next
      }
      if (base != "i18n.ts" && $0 ~ /#[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]/ \
          && $0 !~ /var\(--/ \
          && $0 !~ /--[a-zA-Z0-9-]+: *#[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]/) {
        printf "%s:%d: raw hex color: %s\n", FILENAME, FNR, $0
        failed = 1
        next
      }
      if (base != "i18n.ts" && base != "setup.tsx" \
          && ($0 ~ /[ãõçáéíóúâêôà]/ \
              || $0 ~ /(^|[^a-zA-Z])(nada|Limpar|Carregar|Nenhum|Nenhuma|Abrir|Fechar|Salvar|Remover|Página|erro ao|Ir para)([^a-zA-Z]|$)/)) {
        printf "%s:%d: PT literal outside i18n: %s\n", FILENAME, FNR, $0
        failed = 1
        next
      }
      if ($0 ~ /@hitalloexiled\/opencode-shared/ || $0 ~ /from[ \t]+["'"'"'][.]{1,2}\/[^"'"'"']*shared\//) {
        printf "%s:%d: shared import must be \"opencode-shared/gui\": %s\n", FILENAME, FNR, $0
        failed = 1
        next
      }
    }
    END { exit failed }
  ' || true
)"

if [ -n "$found" ]; then
  printf '%s\n' "$found" >&2
  printf '\ngui-lint: %s violacao(oes). Veja docs/gui-guideline.md.\n' "$(printf '%s\n' "$found" | wc -l)" >&2
  exit 1
fi

printf 'gui-lint: ok\n'
