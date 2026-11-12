#!/usr/bin/env bash
#
# setup.sh — deixa esta maquina (zerada ou nao) pronta para o opencode-tools.
#
# Cria os links que expoem tools/skills ao OpenCode, instala as dependencias
# npm dos plugins, garante o banco de memoria, e prepara o sandbox (daemon
# docker, guard de firewall, imagens e uma tarefa de fumaça).
#
#   ./setup.sh                 configura tudo (inclui build + smoke do sandbox)
#   ./setup.sh --check         so diagnostica, nao altera nada (exit 1 se faltar algo)
#   ./setup.sh --remove        remove os links (NUNCA toca nos dados nem no firewall)
#   ./setup.sh --prefix DIR    configura sob DIR (teste/portatil; sem sandbox)
#   ./setup.sh --no-sandbox    so memoria/skills/tools (sem docker/root)
#   ./setup.sh --no-smoke      prepara o sandbox mas nao chama modelo nenhum
#   ./setup.sh --rebuild       reconstroi as imagens do sandbox
#
# Variaveis: BIN_DIR, OPENCODE_CONFIG_DIR, XDG_DATA_HOME, SANDBOX_OUT_ROOT
#
set -euo pipefail

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
CONFIG_DIR="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
MEM_DIR="$DATA_HOME/opencode/memory"
NEW_DB="$MEM_DIR/notes.db"
PLANS_DIR="$DATA_HOME/opencode/plans"
PLANS_DB="$PLANS_DIR/plans.db"

# Sandbox: same values as sandbox/host-firewall.sh (single source for the
# policy name; set SANDBOX_RELAY_PORT to move the relay).
FW_POLICY="opencode-sandbox-host-guard"

MODE=setup
SANDBOX=1
SMOKE=1
REBUILD=0

usage() {
  sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'
}
say()  { printf '%s\n' "$*"; }
warn() { printf 'aviso: %s\n' "$*" >&2; }
step() { printf '\n== %s\n' "$*"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --check)      MODE=check; shift ;;
    --remove)     MODE=remove; shift ;;
    --no-sandbox) SANDBOX=0; shift ;;
    --no-smoke)   SMOKE=0; shift ;;
    --rebuild)    REBUILD=1; shift ;;
    --prefix)
      [ -n "${2:-}" ] || { echo "--prefix exige um diretorio" >&2; exit 2; }
      BIN_DIR="$2/bin"
      CONFIG_DIR="$2/config/opencode"
      MEM_DIR="$2/data/opencode/memory"
      NEW_DB="$MEM_DIR/notes.db"
      PLANS_DIR="$2/data/opencode/plans"
      PLANS_DB="$PLANS_DIR/plans.db"
      SANDBOX=0
      shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "opcao desconhecida: $1" >&2; usage; exit 2 ;;
  esac
done

# --------------------------------------------------------------------------- #
# helpers
# --------------------------------------------------------------------------- #

link() { # link <origem> <destino>; tolera destino em filesystem read-only
  local src="$1" dst="$2"
  if ! mkdir -p "$(dirname "$dst")" 2>/dev/null; then
    warn "sem permissao em $(dirname "$dst") — rode ./setup.sh no seu terminal (sem NoNewPrivs)"
    return 1
  fi
  if [ -L "$dst" ]; then
    rm -f "$dst" 2>/dev/null || true
  elif [ -e "$dst" ]; then
    local backup="$dst.bak-$(date +%Y%m%d%H%M%S)"
    if ! mv "$dst" "$backup" 2>/dev/null; then
      warn "nao consegui mover $dst para backup — rode ./setup.sh no seu terminal"
      return 1
    fi
    say "  backup: $dst -> $backup"
  fi
  if ! ln -s "$src" "$dst" 2>/dev/null; then
    warn "nao consegui criar $dst — rode ./setup.sh no seu terminal (sem NoNewPrivs)"
    return 1
  fi
  say "  link:   $dst -> $src"
}

ensure_memory_plugin() {
  mkdir -p "$CONFIG_DIR/plugins" 2>/dev/null || true
  # Renamed from 'toolbelt': drop the old link if it still points into the repo.
  case "$(readlink "$CONFIG_DIR/plugins/toolbelt" 2>/dev/null || true)" in
    "$ROOT"/plugins/*) rm -f "$CONFIG_DIR/plugins/toolbelt" 2>/dev/null && say "  legado: plugins/toolbelt removido (renomeado para memory)" ;;
  esac
  # The plugin now lives in the opencode-memory repo, vendored here as a git
  # submodule (plugins/memory). A fresh clone arrives without it.
  if [ ! -f "$ROOT/plugins/memory/index.ts" ]; then
    if git -C "$ROOT" submodule update --init plugins/memory >/dev/null 2>&1; then
      say "  submodule: plugins/memory inicializado (opencode-memory)"
    else
      warn "submodule plugins/memory ausente e git submodule update falhou (offline?); o plugin nao vai carregar"
      return 1
    fi
  fi
  link "$ROOT/plugins/memory" "$CONFIG_DIR/plugins/memory" || true
}

ensure_notes_plugin() {
  # The notes tools and the notes skill live in the opencode-notes repo,
  # vendored here as a git submodule (plugins/notes). A fresh clone arrives
  # without it.
  if [ ! -f "$ROOT/plugins/notes/index.ts" ]; then
    if git -C "$ROOT" submodule update --init plugins/notes >/dev/null 2>&1; then
      say "  submodule: plugins/notes inicializado (opencode-notes)"
    else
      warn "submodule plugins/notes ausente e git submodule update falhou (offline?); o plugin nao vai carregar"
      return 1
    fi
  fi
  link "$ROOT/plugins/notes" "$CONFIG_DIR/plugins/notes" || true
  # The notes skill moved out of skills/ (it documents the notes layer and
  # lives with the plugin); expose it from the submodule.
  link "$ROOT/plugins/notes/skills/notes/SKILL.md" "$CONFIG_DIR/skills/notes/SKILL.md" || true
}

ensure_plans_plugin() {
  # The plans tools and the plans side panel live in the opencode-plans repo,
  # vendored here as a git submodule (plugins/plans).
  if [ ! -f "$ROOT/plugins/plans/index.ts" ]; then
    if git -C "$ROOT" submodule update --init plugins/plans >/dev/null 2>&1; then
      say "  submodule: plugins/plans inicializado (opencode-plans)"
    else
      warn "submodule plugins/plans ausente e git submodule update falhou (offline?); o plugin nao vai carregar"
      return 1
    fi
  fi
  link "$ROOT/plugins/plans" "$CONFIG_DIR/plugins/plans" || true
}

build_plans_gui() {
  local d="$ROOT/plugins/plans"
  [ -f "$d/package.json" ] || return 0
  if (cd "$d" && npm run gui:build --silent) >/dev/null 2>&1; then
    say "  gui    : plans compilado (dist/gui-experimental.cjs)"
  else
    warn "gui    : nao consegui compilar plans (npm run gui:build)"
  fi
}

ensure_stats_plugin() {
  # The stats/side panel and the system prompt viewer live in the
  # opencode-stats repo, vendored here as a git submodule (plugins/stats).
  if [ ! -f "$ROOT/plugins/stats/index.ts" ]; then
    if git -C "$ROOT" submodule update --init plugins/stats >/dev/null 2>&1; then
      say "  submodule: plugins/stats inicializado (opencode-stats)"
    else
      warn "submodule plugins/stats ausente e git submodule update falhou (offline?); o plugin nao vai carregar"
      return 1
    fi
  fi
  link "$ROOT/plugins/stats" "$CONFIG_DIR/plugins/stats" || true
}

ensure_lsp_plugin() {
  # The lsp navigation tools and edit diagnostics live in the opencode-lsp
  # repo, vendored here as a git submodule (plugins/lsp). No GUI, no database.
  if [ ! -f "$ROOT/plugins/lsp/index.ts" ]; then
    if git -C "$ROOT" submodule update --init plugins/lsp >/dev/null 2>&1; then
      say "  submodule: plugins/lsp inicializado (opencode-lsp)"
    else
      warn "submodule plugins/lsp ausente e git submodule update falhou (offline?); o plugin nao vai carregar"
      return 1
    fi
  fi
  link "$ROOT/plugins/lsp" "$CONFIG_DIR/plugins/lsp" || true
}

build_stats_gui() {
  local d="$ROOT/plugins/stats"
  [ -f "$d/package.json" ] || return 0
  if (cd "$d" && npm run gui:build --silent) >/dev/null 2>&1; then
    say "  gui    : stats compilado (dist/gui-experimental.cjs)"
  else
    warn "gui    : nao consegui compilar stats (npm run gui:build)"
  fi
}

build_memory_gui() {
  local d="$ROOT/plugins/memory"
  [ -f "$d/package.json" ] || return 0
  if (cd "$d" && npm run gui:build --silent) >/dev/null 2>&1; then
    say "  gui    : memory compilado (dist/gui-experimental.cjs)"
  else
    warn "gui    : nao consegui compilar memory (npm run gui:build)"
  fi
}

SHARED_PKG="opencode-shared"

# The shared GUI kit is vendored as the `shared/` submodule and consumed by the
# plugins as the package @hitalloexiled/opencode-shared. dist/ is committed;
# build it only when missing.
ensure_shared() {
  if [ ! -f "$ROOT/shared/package.json" ]; then
    if git -C "$ROOT" submodule update --init shared >/dev/null 2>&1; then
      say "  submodule: shared inicializado (opencode-shared)"
    else
      warn "submodule shared ausente e git submodule update falhou (offline?); os GUIs vao falhar"
      return 1
    fi
  fi
  if [ ! -d "$ROOT/shared/node_modules" ] \
     || [ "$ROOT/shared/package-lock.json" -nt "$ROOT/shared/node_modules/.package-lock.json" ]; then
    if command -v npm >/dev/null 2>&1 \
       && (cd "$ROOT/shared" && npm install --legacy-peer-deps --no-audit --no-fund --silent) >/dev/null 2>&1; then
      say "  deps   : shared instalado via npm"
    else
      warn "shared: nao consegui instalar as dependencias (npm ausente/offline?)"
    fi
  else
    say "  deps   : shared ja presente em node_modules/"
  fi
  if [ ! -f "$ROOT/shared/dist/gui/index.js" ]; then
    if (cd "$ROOT/shared" && npm run build --silent) >/dev/null 2>&1; then
      say "  build  : shared compilado (dist/gui/index.js)"
    else
      warn "shared: dist ausente e npm run build falhou"
    fi
  fi
}

# Local development uses the working tree, not the package fetched by git:
# register shared/ once and link it into every plugin's node_modules.
link_shared() {
  local d="$ROOT/shared"
  [ -f "$d/package.json" ] || return 0
  if ! command -v npm >/dev/null 2>&1; then
    warn "shared: npm ausente — link local nao configurado"
    return 0
  fi

  if (cd "$d" && npm link --legacy-peer-deps --silent) >/dev/null 2>&1; then
    say "  link   : shared registrado (npm link)"
  else
    warn "shared: npm link falhou; usando symlink direto nos plugins"
  fi

  local p dst
  for p in "$ROOT"/plugins/*/; do
    [ -f "$p/package.json" ] || continue
    dst="$p/node_modules/$SHARED_PKG"
    mkdir -p "$(dirname "$dst")" 2>/dev/null || true
    if (cd "$p" && npm link "$SHARED_PKG" --legacy-peer-deps --silent) >/dev/null 2>&1 && [ -e "$dst" ]; then
      say "  link   : $(basename "$p") -> $SHARED_PKG"
      continue
    fi
    rm -rf "$dst" 2>/dev/null || true
    if ln -sfn "$d" "$dst" 2>/dev/null; then
      say "  link   : $(basename "$p") -> shared/ (symlink)"
    else
      warn "shared: nao consegui linkar em $(basename "$p")"
    fi
  done
}

install_plugin_deps() {
  # A fresh clone (git submodule) arrives without node_modules: install the
  # npm deps inside every plugin that declares its own package.json. A newer
  # package-lock.json means a dependency was added since the last install.
  local d
  for d in "$ROOT"/plugins/*/; do
    [ -f "$d/package.json" ] || continue
    if [ -d "$d/node_modules" ] && [ -f "$d/node_modules/.package-lock.json" ] \
       && [ ! "$d/package-lock.json" -nt "$d/node_modules/.package-lock.json" ]; then
      say "  deps   : $(basename "$d") ja presente em node_modules/"
      continue
    fi
    # --legacy-peer-deps: @opencode/plugin declares an optional vite >= 6 peer
    # while the plugins build against vite 5.
    if command -v npm >/dev/null 2>&1 \
       && (cd "$d" && npm install --legacy-peer-deps --no-audit --no-fund --silent) >/dev/null 2>&1; then
      say "  deps   : $(basename "$d") instalado via npm"
    else
      warn "deps   : nao consegui instalar em $(basename "$d") (npm ausente/offline?) — o plugin pode nao carregar"
    fi
  done
}

unlink_ours() { # remove symlink apenas se apontar para dentro do repo
  local dst="$1"
  [ -L "$dst" ] || return 0
  case "$(readlink "$dst")" in
    "$ROOT"/*) rm -f "$dst"; say "  removido: $dst" ;;
  esac
}

# O sistema ja se chamou "notebook"/"nb"; limpa restos de configuracoes antigas
# para nao sobrar um binario quebrado no PATH.
cleanup_legacy_bin() {
  local legacy
  for legacy in "$BIN_DIR/notebook" "$BIN_DIR/nb"; do
    [ -e "$legacy" ] || [ -L "$legacy" ] || continue
    case "$(readlink "$legacy" 2>/dev/null || true)" in
      "$ROOT"/*|"$BIN_DIR/notebook")
        rm -f "$legacy" 2>/dev/null && say "  legado: removido $legacy" || true ;;
      *)
        if [ -f "$legacy" ] && grep -q "opencode/memory" "$legacy" 2>/dev/null; then
          mv "$legacy" "$legacy.bak-$(date +%Y%m%d%H%M%S)" 2>/dev/null \
            && say "  legado: $legacy -> backup" || true
        fi ;;
    esac
  done
}

# The Python CLI is retired: the notes plugin (GUI + notes.* tools) talks to
# SQLite directly. Remove only our old symlink, never a real file.
cleanup_notes_cli() {
  local legacy="$BIN_DIR/notes"
  [ -e "$legacy" ] || [ -L "$legacy" ] || return 0
  case "$(readlink "$legacy" 2>/dev/null || true)" in
    "$ROOT"/*)
      rm -f "$legacy" 2>/dev/null && say "  legado: removido $legacy (CLI notes aposentado)" || true ;;
  esac
}

cleanup_legacy_skill() {
  local legacy="$CONFIG_DIR/skills/notebook"
  [ -d "$legacy" ] || return 0
  if [ -L "$legacy/SKILL.md" ]; then
    rm -f "$legacy/SKILL.md" 2>/dev/null || true
  elif [ -f "$legacy/SKILL.md" ]; then
    mv "$legacy/SKILL.md" "$legacy/SKILL.md.bak-$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
  fi
  rmdir "$legacy" 2>/dev/null || true
  say "  legado: skill 'notebook' aposentada (-> 'notes')"
}

# The notes store runs on the runtime's built-in `node:sqlite` (in-process,
# synchronous, FTS5). Bun, the Electron main process and plain Node all ship
# it, so there is no dependency to install; check that a Node on this machine
# exposes it (informational — the plugin also runs inside Bun/Electron).
check_notes_store() {
  local bin
  for bin in "${NOTES_NODE:-}" node /usr/local/bin/node /usr/bin/node \
             "$(ls -d "$HOME"/.nvm/versions/node/*/bin/node 2>/dev/null | sort -r | head -n1)"; do
    [ -n "$bin" ] || continue
    command -v "$bin" >/dev/null 2>&1 || [ -x "$bin" ] || continue
    if "$bin" -e '
      const { DatabaseSync } = require("node:sqlite");
      const db = new DatabaseSync(":memory:");
      db.exec("CREATE VIRTUAL TABLE t USING fts5(x)");
      db.close();
    ' >/dev/null 2>&1; then
      printf '%s\n' "$bin"
      return 0
    fi
  done
  return 1
}

# Executa um comando privilegiado: direto se root, sudo sem senha se possivel,
# senao um unico `sudo -v` quando ha terminal. 127 = nao ha como elevar.
as_root() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"; return $?
  fi
  if sudo -n true >/dev/null 2>&1; then
    sudo "$@"; return $?
  fi
  if [ -t 0 ]; then
    say "  root: pedindo a senha do sudo (uma vez)"
    sudo -v || return 1
    sudo "$@"; return $?
  fi
  return 127
}

ensure_plugin() {
  if [ -e "$ROOT/node_modules/@opencode-ai/plugin" ]; then
    say "  plugin: ja presente em node_modules/"
    return 0
  fi
  if command -v npm >/dev/null 2>&1 && (cd "$ROOT" && npm install --no-audit --no-fund --silent) >/dev/null 2>&1; then
    say "  plugin: instalado via npm"
    return 0
  fi
  if [ -e "$CONFIG_DIR/node_modules/@opencode-ai/plugin" ]; then
    mkdir -p "$ROOT/node_modules/@opencode-ai"
    ln -sfn "$CONFIG_DIR/node_modules/@opencode-ai/plugin" "$ROOT/node_modules/@opencode-ai/plugin"
    say "  plugin: symlink (sem npm) -> $CONFIG_DIR/node_modules/@opencode-ai/plugin"
    return 0
  fi
  warn "@opencode-ai/plugin indisponivel — as tools podem nao carregar"
}

migrate_db() {
  mkdir -p "$MEM_DIR"
  local legacy
  for legacy in "$CONFIG_DIR/memory/notes.db" "$CONFIG_DIR/memory/bookkeeping.db"; do
    [ -f "$legacy" ] || continue
    if [ -f "$NEW_DB" ]; then
      warn "ja existe $NEW_DB; preservando $legacy como $legacy.orphan"
      mv "$legacy" "$legacy.orphan"
    else
      mv "$legacy" "$NEW_DB"
      say "  banco:  $legacy -> $NEW_DB"
    fi
  done

  # O diretorio antigo guardava o script; agora a fonte e este repo. Preserva
  # (nao apaga) e sai do caminho para nao confundir.
  if [ -d "$CONFIG_DIR/memory" ] && [ -n "$(ls -A "$CONFIG_DIR/memory" 2>/dev/null || true)" ]; then
    local archive="$MEM_DIR/legacy-config-memory"
    rm -rf "$archive"
    mv "$CONFIG_DIR/memory" "$archive"
    say "  legado: $CONFIG_DIR/memory -> $archive"
  elif [ -d "$CONFIG_DIR/memory" ]; then
    rmdir "$CONFIG_DIR/memory" 2>/dev/null || true
  fi
  [ -f "$NEW_DB" ] || say "  banco:  sera criado sob demanda em $NEW_DB"
}

# --------------------------------------------------------------------------- #
# sandbox helpers
# --------------------------------------------------------------------------- #

docker_ok() { command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; }

# The OpenCode agent shell (and some service managers) run with NoNewPrivs=1.
# Executing docker then asks SELinux for a bounded transition to
# container_runtime_t, which NNP forbids: every call logs an `nnp_transition`
# AVC even though docker works (it stays in unconfined_t). Not a failure, but
# the setroubleshoot popups are noise — a normal terminal has NNP=0.
nnp_enabled() {
  [ "$(awk '/^NoNewPrivs:/{print $2}' /proc/self/status 2>/dev/null)" = 1 ]
}

warn_selinux_noise() {
  nnp_enabled || return 0
  warn "este shell roda com NoNewPrivs=1: cada chamada do docker gera um AVC"
  warn "  SELinux 'nnp_transition' (transicao bloqueada, comando funciona)."
  warn "  Para nao gerar alertas, rode ./setup.sh no seu terminal normal (NNP=0)."
}

ensure_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    warn "docker ausente — as tools de sandbox nao funcionam"
    return 1
  fi
  if docker_ok; then
    say "  docker: ok"
    return 0
  fi

  if systemctl list-unit-files --no-legend docker.service 2>/dev/null | grep -q '^docker.service'; then
    say "  docker: daemon parado; iniciando (root)"
    as_root systemctl enable --now docker >/dev/null 2>&1 || true
    local i
    for i in $(seq 1 15); do
      docker_ok && break
      sleep 1
    done
  fi

  if docker_ok; then
    say "  docker: ok (iniciado)"
    return 0
  fi

  if systemctl is-active docker >/dev/null 2>&1; then
    warn "daemon ativo, mas este usuario nao tem acesso a ele."
    warn "  rode: sudo usermod -aG docker $USER   e entre de novo na sessao"
  else
    warn "nao consegui falar com o daemon docker"
  fi
  return 1
}

guard_active() {
  "$ROOT/sandbox/host-firewall.sh" check >/dev/null 2>&1
}

ensure_guard() {
  if guard_active; then
    say "  guard:  ja aplicado"
    return 0
  fi
  say "  guard:  instalando (root)"
  if as_root "$ROOT/sandbox/host-firewall.sh" install-unit; then
    return 0
  fi
  warn "guard de firewall nao aplicado — rode: sudo $ROOT/sandbox/host-firewall.sh install-unit"
  return 1
}

sandbox_up() {
  say "  imagens: construindo (so as que faltam) e subindo a sessao"
  ( cd "$ROOT/sandbox" && REBUILD="$REBUILD" ./run.sh up )
}

sandbox_down() {
  ( cd "$ROOT/sandbox" && ./run.sh down ) >/dev/null 2>&1 || true
}

sandbox_selftest() {
  say "  guard:  self-test"
  "$ROOT/sandbox/host-firewall.sh" selftest
}

sandbox_smoke() {
  local out rc
  say "  smoke:  tarefa real (modelo free; precisa de rede)"
  set +e
  out="$( cd "$ROOT/sandbox" && ./run.sh task --prompt 'Reply with exactly: OK' --no-follow 2>&1 )"
  rc=$?
  set -e
  if [ "$rc" = 0 ]; then
    say "  smoke:  ok"
    return 0
  fi
  warn "smoke falhou (exit $rc); ultimas linhas:"
  printf '%s\n' "$out" | tail -n 15 | sed 's/^/    /' >&2
  return 1
}

# --------------------------------------------------------------------------- #
# modes
# --------------------------------------------------------------------------- #

cmd_check() {
  local failed=0
  say "opencode-tools — diagnostico"
  say "repo: $ROOT"

  step "dependencias"
  if command -v python3 >/dev/null 2>&1; then
    say "  python3 : $(python3 -c 'import sys;print("%d.%d.%d"%sys.version_info[:3])')  (opcional)"
  else
    say "  python3 : ausente  (opcional)"
  fi
  local node_sqlite
  if node_sqlite="$(check_notes_store)"; then
    say "  sqlite  : $node_sqlite  (node:sqlite, FTS5)"
  else
    warn "nenhum Node com node:sqlite — o plugin notes precisa de Node >= 22 (Bun/Electron ja trazem)"
    failed=1
  fi
  if command -v docker >/dev/null 2>&1; then
    say "  docker  : $(docker --version 2>/dev/null | head -n1)"
  else
    warn "docker ausente"
    if [ "$SANDBOX" = 1 ]; then failed=1; fi
  fi
  if command -v opencode >/dev/null 2>&1; then
    say "  opencode: $(command -v opencode)"
  else
    say "  opencode: nao esta no PATH deste shell (ok se voce o lanca de outro)"
  fi

  step "componentes"
  local f
  for f in "$CONFIG_DIR/skills/notes/SKILL.md" "$CONFIG_DIR/skills/sandbox/SKILL.md"; do
    if [ -e "$f" ]; then say "  skill   : $f"; else say "  skill   : (ausente) $f"; failed=1; fi
  done
  for f in "$CONFIG_DIR/tools/sandbox.ts"; do
    if [ -e "$f" ]; then say "  tool    : $f"; else say "  tool    : (ausente) $f"; failed=1; fi
  done
  for f in "$CONFIG_DIR/plugins/memory" "$CONFIG_DIR/plugins/notes" "$CONFIG_DIR/plugins/plans" "$CONFIG_DIR/plugins/stats" "$CONFIG_DIR/plugins/lsp"; do
    if [ -e "$f" ]; then say "  plugin  : $f"; else say "  plugin  : (ausente) $f"; failed=1; fi
  done
  if [ -f "$ROOT/shared/dist/gui/index.js" ]; then
    say "  shared  : dist/gui/index.js"
  else
    say "  shared  : (ausente) dist/gui/index.js"; failed=1
  fi
  local p link
  for p in "$ROOT"/plugins/*/; do
    [ -f "$p/package.json" ] || continue
    link="$p/node_modules/$SHARED_PKG"
    if [ -e "$link" ]; then
      say "  link    : $(basename "${p%/}") -> $SHARED_PKG"
    else
      say "  link    : (ausente) $(basename "${p%/}")"; failed=1
    fi
  done
  say "  banco   : $NEW_DB"
  say "  planos  : $PLANS_DB"

  if [ "$SANDBOX" = 1 ]; then
    step "sandbox"
    if docker_ok; then
      say "  daemon  : ok"
    else
      say "  daemon  : (inacessivel)"; failed=1
    fi
    if [ -x "$ROOT/sandbox/opencode-sandboxed" ] && [ -e "$BIN_DIR/opencode-sb" ]; then
      say "  cli     : $BIN_DIR/opencode-sb"
    else
      say "  cli     : (ausente) $BIN_DIR/opencode-sb"; failed=1
    fi
    if guard_active; then
      say "  guard   : ativo ($FW_POLICY)"
    else
      say "  guard   : (ausente) — sudo $ROOT/sandbox/host-firewall.sh install-unit"; failed=1
    fi
    for img in opencode-sandbox:latest opencode-sandbox-proxy:latest; do
      if docker image inspect "$img" >/dev/null 2>&1; then
        say "  imagem  : $img"
      else
        say "  imagem  : (ausente) $img"; failed=1
      fi
    done
    if docker network inspect opencode-sandbox-net >/dev/null 2>&1; then
      say "  rede    : opencode-sandbox-net"
    else
      say "  rede    : (ausente) opencode-sandbox-net"; failed=1
    fi
    ( cd "$ROOT/sandbox" && ./run.sh status 2>/dev/null | sed 's/^/  /' ) || true
  fi

  if [ "$failed" = 0 ]; then
    say ""
    say "tudo pronto."
  else
    warn "ha componentes faltando — rode ./setup.sh"
  fi
  exit "$failed"
}

cmd_remove() {
  say "opencode-tools — removendo os links (dados preservados)"
  unlink_ours "$BIN_DIR/notes"
  local d t
  for d in "$ROOT"/skills/*/; do
    [ -d "$d" ] || continue
    unlink_ours "$CONFIG_DIR/skills/$(basename "$d")/SKILL.md"
  done
  # The notes skill lives in the opencode-notes submodule.
  unlink_ours "$CONFIG_DIR/skills/notes/SKILL.md"
  for t in "$ROOT"/tools/*.ts; do
    [ -e "$t" ] || continue
    unlink_ours "$CONFIG_DIR/tools/$(basename "$t")"
  done
  # notes.ts moved to plugins/notes; drop the legacy flat-tool link too.
  unlink_ours "$CONFIG_DIR/tools/notes.ts"
  local name
  for name in opencode-sandboxed opencode-sb; do
    unlink_ours "$BIN_DIR/$name"
  done
  unlink_ours "$CONFIG_DIR/plugins/memory"
  unlink_ours "$CONFIG_DIR/plugins/notes"
  unlink_ours "$CONFIG_DIR/plugins/plans"
  unlink_ours "$CONFIG_DIR/plugins/stats"
  unlink_ours "$CONFIG_DIR/plugins/lsp"
  unlink_ours "$CONFIG_DIR/plugins/toolbelt"   # nome antigo

  # Drop the local shared link (node_modules is generated; never touch
  # package.json) and the global npm link.
  local p link
  for p in "$ROOT"/plugins/*/; do
    [ -f "$p/package.json" ] || continue
    link="$p/node_modules/$SHARED_PKG"
    rm -rf "$link" 2>/dev/null || true
  done
  if command -v npm >/dev/null 2>&1; then
    npm unlink -g "$SHARED_PKG" >/dev/null 2>&1 || true
  fi
  say "shared: links locais removidos (working tree preservada)"
  say ""
  say "banco preservado em: $NEW_DB"
  say "planos preservados em: $PLANS_DB"
  say "resumos/indice preservados em: \${XDG_DATA_HOME:-~/.local/share}/opencode/memory"
  say "sandbox: imagens/rede/guard ficam; para remover o guard (root):"
  say "  sudo $ROOT/sandbox/host-firewall.sh uninstall-unit"
  exit 0
}

permissions_hint() {
  cat <<EOF

  Permissoes (opcional — adicione ao seu opencode config para uma allow-list):
    "permissions": [
      { "action": "skill", "resource": "*",       "effect": "deny"  },
      { "action": "skill", "resource": "notes",   "effect": "allow" },
      { "action": "skill", "resource": "sandbox", "effect": "allow" }
    ]
EOF
}

cmd_setup() {
  say "opencode-tools — configurando"
  say "repo:   $ROOT"
  say "bin:    $BIN_DIR"
  say "config: $CONFIG_DIR"

  step "1/7 plugin (@opencode-ai/plugin)"
  ensure_plugin

  step "2/7 memoria"
  cleanup_legacy_bin
  cleanup_notes_cli
  migrate_db

  step "3/7 skills"
  local name
  cleanup_legacy_skill
  for d in "$ROOT"/skills/*/; do
    [ -f "$d/SKILL.md" ] || continue
    name="$(basename "${d%/}")"
    link "${d%/}/SKILL.md" "$CONFIG_DIR/skills/$name/SKILL.md" || true
  done

  step "4/7 tools"
  mkdir -p "$CONFIG_DIR/tools" 2>/dev/null || true
  for t in "$ROOT"/tools/*.ts; do
    [ -f "$t" ] || continue
    link "$t" "$CONFIG_DIR/tools/$(basename "$t")" || true
  done
  # notes.ts moved to plugins/notes; drop the legacy flat-tool link if present.
  unlink_ours "$CONFIG_DIR/tools/notes.ts"

  step "5/7 plugins (memory + notes + plans + stats + lsp)"
  ensure_shared
  ensure_memory_plugin
  ensure_notes_plugin
  ensure_plans_plugin
  ensure_stats_plugin
  ensure_lsp_plugin
  install_plugin_deps
  link_shared
  build_plans_gui
  build_memory_gui
  build_stats_gui

  local sandbox_failed=0
  if [ "$SANDBOX" = 1 ]; then
    step "6/7 sandbox"
    warn_selinux_noise
    ensure_docker || sandbox_failed=1
    if [ "$sandbox_failed" = 0 ]; then
      BIN_DIR="$BIN_DIR" "$ROOT/sandbox/setup.sh" || sandbox_failed=1
    fi
    if [ "$sandbox_failed" = 0 ]; then
      ensure_guard || sandbox_failed=1
    fi
    if [ "$sandbox_failed" = 0 ]; then
      sandbox_up || sandbox_failed=1
    fi
    if [ "$sandbox_failed" = 0 ]; then
      sandbox_selftest || sandbox_failed=1
    fi
    if [ "$sandbox_failed" = 0 ] && [ "$SMOKE" = 1 ]; then
      sandbox_smoke || sandbox_failed=1
    fi
    sandbox_down
  else
    step "6/7 sandbox (pulado)"
    say "  use ./setup.sh sem --no-sandbox para preparar o sandbox"
  fi

  step "7/7 verificacao"
  mkdir -p "$MEM_DIR" 2>/dev/null || true
  mkdir -p "$PLANS_DIR" 2>/dev/null || true
  if [ -f "$NEW_DB" ]; then
    say "  banco:  ok ($NEW_DB)"
  else
    say "  banco:  sera criado no primeiro uso ($NEW_DB)"
  fi
  if [ -f "$PLANS_DB" ]; then
    say "  planos: ok ($PLANS_DB)"
  else
    say "  planos: sera criado no primeiro uso ($PLANS_DB)"
  fi
  if check_notes_store >/dev/null; then
    say "  sqlite: ok (node:sqlite, FTS5)"
  else
    warn "nenhum Node com node:sqlite — o plugin notes precisa de Node >= 22"
  fi
  case ":$PATH:" in
    *":$BIN_DIR:"*) say "  PATH   : ok ($BIN_DIR)" ;;
    *) warn "$BIN_DIR nao esta no PATH. Adicione: export PATH=\"$BIN_DIR:\$PATH\"" ;;
  esac

  permissions_hint
  say ""
  if [ "$sandbox_failed" = 1 ]; then
    warn "sandbox incompleto — os comandos acima dizem o que falta (root/docker); memoria e tools estao prontas."
    exit 1
  fi
  say "pronto."
  say "Reinicie o OpenCode para carregar as tools e skills novas."
  if [ "$BIN_DIR" = "$HOME/.local/bin" ]; then
    say "Obs.: se a configuracao rodou de um shell com NoNewPrivs/read-only em"
    say "      ~/.local/bin, reexecute ./setup.sh no seu terminal normal."
  fi
}

case "$MODE" in
  check)  cmd_check ;;
  remove) cmd_remove ;;
  setup)  cmd_setup ;;
esac
