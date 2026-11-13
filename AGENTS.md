# AGENTS.md — working on `opencode-tools`

Agent-facing operating notes for the **parent** repo. It is the bootstrap/glue
layer: agent tools + skills, a Docker sandbox, and the OpenCode plugins
vendored as **git submodules**. The product code mostly lives *inside the
submodules*, not here — read that before touching anything.

## ⚠️ Submodule dependency (read this first)

`opencode-tools` does **not** contain the plugin source. Five submodules are
vendored in — the four plugins plus the shared GUI library:

| Path | Repo | What it is |
|---|---|---|
| `plugins/memory` | [opencode-memory](https://github.com/HitalloExiled/opencode-memory) | summaries, session timeline, cross-session search, index maintenance |
| `plugins/notes` | [opencode-notes](https://github.com/HitalloExiled/opencode-notes) | `notes.*` tools + notes skill + desktop side-panel GUI + `<notes-context>` session injection, over `notes.db` |
| `plugins/plans` | [opencode-plans](https://github.com/HitalloExiled/opencode-plans) | `plans.*` tools + desktop side-panel GUI, over a dedicated `plans.db` |
| `plugins/stats` | [opencode-stats](https://github.com/HitalloExiled/opencode-stats) | statistics side panel (tok/s gauge + history + tools/reasoning) and the session system-prompt viewer, captured server-side |
| `plugins/lsp` | [opencode-lsp](https://github.com/HitalloExiled/opencode-lsp) | `lsp.*` navigation tools (definition, references, hover, symbols, implementations, calls) and error diagnostics appended to file edits, over the V1-shaped `lsp` config block |
| `shared` | [opencode-shared](https://github.com/HitalloExiled/opencode-shared) | `opencode-shared/gui`: scroll nav (infinite scroll + Home/End/PageUp/PageDown), states, status chip, i18n factory, panel registration |

Consequences:

- **A fresh clone arrives with empty submodule dirs.** You must initialize
  them before anything builds or loads:
  ```bash
  git submodule update --init --recursive
  # or clone with --recurse-submodules
  ```
- **Each submodule pins a specific commit** of its own repo. The parent only
  stores that SHA (the "pointer"), not the files.
- **Never edit submodule files and commit them from the parent.** Changes to
  `plugins/memory/**`, `plugins/notes/**`, `plugins/plans/**`,
  `plugins/stats/**`, `plugins/lsp/**` or `shared/**` must be committed **inside
  the submodule repo first**, then the parent pointer is bumped. Doing it backwards
  produces a dirty/invalid submodule state.
- **The parent's typecheck/test only see submodule code once it is
  initialized** — an empty submodule dir means those files are absent.
- **Plugins consume the shared GUI as a package**, never by a relative path:
  `opencode-shared` is declared in each plugin's
  `package.json` (pinned by commit). The checked-out `shared/` submodule is the
  development tree; `setup.sh` links it into each plugin's `node_modules`.

`setup.sh` automates all of this (see below): it runs
`git submodule update --init` for all of them, symlinks the plugins into
`~/.config/opencode/plugins/`, runs `npm install` inside each, and `npm link`s
the shared package into the four plugins.

### Commit protocol (shared → plugin → parent)

For a change inside `shared`:

1. `cd shared` → commit + `git push origin main` (+ tag when the API changes).
2. In each affected plugin: bump the `opencode-shared` commit in
   `package.json` + lock → commit + push.
3. Back in `opencode-tools`: `git add shared plugins/<name>` → commit the
   pointers → `git push origin main`.

For a change inside `plugins/notes`, `plugins/memory`, `plugins/plans`,
`plugins/stats` or `plugins/lsp`:

1. `cd plugins/<name>` → `git add … && git commit`
2. `git push origin main` (the submodule's own origin)
3. Back in `opencode-tools`: `git add plugins/<name>` → commit the pointer bump
4. `git push origin main` (the parent's origin)

The submodule **must** be pushed before the parent, or the parent points at a
SHA that doesn't exist upstream yet. Keep the parent's `shared` pointer and the
plugins' pinned commits on the same commit.

## Layout

```
opencode-tools/
├── setup.sh            # the ONLY OpenCode coupling: links + DB + sandbox bootstrap
├── tools/
│   └── sandbox.ts      # sandbox_* tools (delegated risky work)
├── skills/
│   └── sandbox/SKILL.md
├── plugins/
│   ├── memory/         # SUBMODULE → opencode-memory
│   ├── notes/          # SUBMODULE → opencode-notes (its own AGENTS.md)
│   ├── plans/          # SUBMODULE → opencode-plans (its own AGENTS.md)
│   ├── stats/          # SUBMODULE → opencode-stats (its own AGENTS.md)
│   └── lsp/            # SUBMODULE → opencode-lsp (its own AGENTS.md)
├── shared/             # SUBMODULE → opencode-shared (opencode-shared)
├── sandbox/            # Docker sandbox: opencode-sb CLI, run.sh, Dockerfile, proxy/
└── README.md
```

The content (`tools/`, `skills/`, `sandbox/`, `plugins/`, `shared/`) is
harness-agnostic; all OpenCode wiring lives in `setup.sh`.

## Parent-level build / typecheck / test

Run from the `opencode-tools/` root:

```bash
bun install                                  # root deps (@opencode/* v2, typescript, zod, bun types)
bun run typecheck                            # tsc --noEmit over tools/** + plugins/**/*.ts
bun run test                                 # = bun test plugins/memory/test plugins/notes/test plugins/plans/test plugins/stats/test plugins/lsp/test
```

Notes on scope:

- The root `tsconfig.json` typechecks `plugins/**/*.ts` (the `.ts` files of both
  submodules, plus `tools/`). The **GUI `.tsx`** is *not* covered here — that's
  the notes plugin's own `typecheck:gui`.
- `bun test` only picks up submodule tests once the submodules are
  initialized. Run each plugin's own scripts for its full build:
  - **shared** → `shared`: `npm run typecheck`, `npm test`, `npm run build`
    (guide: **`shared/AGENTS.md`**)
  - **notes** → `plugins/notes`: `bun run gui:build`, `bun run typecheck:gui`
    (full guide: **`plugins/notes/AGENTS.md`**)
  - **plans** → `plugins/plans`: `bun run gui:build`, `bun run typecheck:gui`
    (full guide: **`plugins/plans/AGENTS.md`**)
  - **stats** → `plugins/stats`: `bun run gui:build`, `bun run typecheck:gui`
    (full guide: **`plugins/stats/AGENTS.md`**)
  - **lsp** → `plugins/lsp`: `bun run typecheck`, `bun test test`
    (full guide: **`plugins/lsp/AGENTS.md`**)
  - **memory** → `plugins/memory`: `bun run typecheck`, `bun run typecheck:gui`,
    `bun run gui:build`, `bun test test` (product docs:
    `plugins/memory/README.md`)

## Per-submodule docs

| Submodule | Doc |
|---|---|
| `plugins/notes` | **`plugins/notes/AGENTS.md`** — build, the two typechecks, `bun test` from the parent, hot-reload dev loop, schema v9, `ctx.*` cheatsheet, git workflow |
| `plugins/plans` | **`plugins/plans/AGENTS.md`** — build, the two typechecks, `bun test` from the parent, hot-reload dev loop, plans schema, `ctx.*` cheatsheet, git workflow |
| `plugins/stats` | **`plugins/stats/AGENTS.md`** — server capture + GUI, the two typechecks, `bun test` from the parent, RPC, prompt classification, git workflow |
| `plugins/lsp` | **`plugins/lsp/AGENTS.md`** — LSP client/pool, config reader, fake-server tests, project boundary, git workflow |
| `plugins/memory` | `plugins/memory/README.md` — summaries, injection, cross-session search |
| `shared` | **`shared/AGENTS.md`** — the shared GUI kit, the `dist/` rule, the three-level commit protocol; `shared/README.md` for the API |

When working on a plugin, open *its* AGENTS.md/README first; this file only
covers the parent glue.

## GUI guideline

The side panels (`memory`, `notes`, `plans`, `stats`) share one visual and
behavioral contract: **`docs/gui-guideline.md`**. It covers the allowed tokens,
the type/spacing/radius scale, the shared components, infinite scroll and
keyboard navigation, i18n, accessibility, the `Panel` contract and the
shared → plugin → parent commit protocol. New panels start from it; components
used by two or more plugins go to `shared/`.

`bun run lint:gui` enforces the mechanical rules (`scripts/gui-lint.sh`): raw
hex colors, tokens that do not exist, PT literals outside `i18n.ts`/`setup.tsx`
and relative imports into `shared/`.

## setup.sh (bootstrap)

`setup.sh` is the single place that ties this repo to OpenCode. It is idempotent
and, for the plugins, it:

- `git submodule update --init plugins/memory`, `plugins/notes`,
  `plugins/plans`, `plugins/stats`, `plugins/lsp` and `shared` (skipped if
  already present; warns if offline).
- Symlinks `plugins/memory` → `~/.config/opencode/plugins/memory`,
  `plugins/notes` → `~/.config/opencode/plugins/notes`,
  `plugins/plans` → `~/.config/opencode/plugins/plans`,
  `plugins/stats` → `~/.config/opencode/plugins/stats` and
  `plugins/lsp` → `~/.config/opencode/plugins/lsp`.
- Symlinks the notes skill: `plugins/notes/skills/notes/SKILL.md` →
  `~/.config/opencode/skills/notes/SKILL.md`.
- Runs `npm install --legacy-peer-deps` inside each plugin and `shared` (fresh
  clones have no `node_modules`).
- `npm link`s `shared` and links `opencode-shared` into each
  plugin, so the working tree is used instead of the git package. Falls back to
  a direct symlink when `npm link` cannot write the global prefix.
- Builds the plans, memory and stats GUI bundles (`npm run gui:build` in
  `plugins/plans`, `plugins/memory` and `plugins/stats`).
- Places `notes.db` under `~/.local/share/opencode/memory/` and `plans.db`
  under `~/.local/share/opencode/plans/` (never in the repo) and checks the
  runtime's built-in `node:sqlite`.

It also stands up the sandbox (daemon, guard, images, smoke) and retires
legacy paths. Re-running it is safe; use it instead of doing the submodule/symlink
steps by hand.

## Sandbox subsystem

`tools/sandbox.ts` exposes the `sandbox_*` tools; `sandbox/` holds the
`opencode-sb` CLI, `run.sh` orchestrator, Dockerfile, proxy and host firewall
guard. Risky/uncertain work is delegated to a disposable container there. See
`sandbox/README.md`.

## Conventions / hard rules

- **UI copy is PT-BR; code is English.**
- **Every user-facing message — UI copy, toasts and synthetic/session
  messages — must exist in PT-BR and EN-US, with EN-US as the fallback.** Code
  and identifiers stay English. Never hardcode a UI or synthetic string in a
  single language.
- **Never read OpenCode's `opencode.db` directly** — GUI/app data comes from the
  official `ctx.client.*` APIs only.
- **Tool descriptions fit the Code Mode catalog budget.** The catalog truncates
  a description around 119 characters, so keep it ≤110 with the load-bearing
  sentence first; parameter descriptions stay ≤6 words. Each plugin's tests
  enforce both.
- **No `*.db` in the repo.** Databases live on disk under
  `~/.local/share/opencode/…` and are gitignored; override the notes DB with
  `$NOTES_DB` for isolated work.
- Respect each submodule's own AGENTS.md/README — they are the authoritative
  guides for their code.
- **GUI code used by two or more plugins lives in `shared/`**, imported as
  `opencode-shared/gui` — never copied between plugins.
- **Package names stay unscoped** (`opencode-notes`, `opencode-shared`):
  OpenCode 2.2.7 does not discover a local plugin whose `package.json` name is
  scoped (`@scope/name`); it disappears from the server inventory and its GUI
  never loads.

## Quick checklist for a change

- **Change inside `shared`**: edit → `npm run typecheck && npm test && npm run
  build` in `shared/` → commit + push (tag) → bump the package commit in each
  affected plugin + push → bump the parent pointers + push.
- **Change inside a plugin submodule** (`plugins/*`): edit → submodule
  typecheck/test → build (if GUI) → commit + push the submodule → bump + commit
  + push the parent pointer.
- **Change in `tools/`, `skills/`, `sandbox/`, or `setup.sh`**: edit →
  `bun run typecheck` (and `bun run test`) at the root → commit + push the
  parent only.
- **Fresh machine**: `git clone --recurse-submodules …`, then `bun install`,
  then `./setup.sh`.
