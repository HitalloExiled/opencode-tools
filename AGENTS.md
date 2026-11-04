# AGENTS.md — working on `opencode-tools`

Agent-facing operating notes for the **parent** repo. It is the bootstrap/glue
layer: agent tools + skills, a Docker sandbox, and the OpenCode plugins
vendored as **git submodules**. The product code mostly lives *inside the
submodules*, not here — read that before touching anything.

## ⚠️ Submodule dependency (read this first)

`opencode-tools` does **not** contain the plugin source. Two submodules are
vendored in:

| Path | Repo | What it is |
|---|---|---|
| `plugins/memory` | [opencode-memory](https://github.com/HitalloExiled/opencode-memory) | summaries, repo/session injection, cross-session search |
| `plugins/notes` | [opencode-notes](https://github.com/HitalloExiled/opencode-notes) | `notes.*` tools + notes skill + desktop side-panel GUI, over `notes.db` |

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
  `plugins/memory/**` or `plugins/notes/**` must be committed **inside the
  submodule repo first**, then the parent pointer is bumped. Doing it backwards
  produces a dirty/invalid submodule state.
- **The parent's typecheck/test only see submodule code once it is
  initialized** — an empty submodule dir means those files are absent.

`setup.sh` automates all of this (see below): it runs
`git submodule update --init` for both, symlinks them into
`~/.config/opencode/plugins/`, and runs `npm install` inside each.

### Two-part commit protocol (always)

For a change inside `plugins/notes` or `plugins/memory`:

1. `cd plugins/<name>` → `git add … && git commit`
2. `git push origin main` (the submodule's own origin)
3. Back in `opencode-tools`: `git add plugins/<name>` → commit the pointer bump
4. `git push origin main` (the parent's origin)

The submodule **must** be pushed before the parent, or the parent points at a
SHA that doesn't exist upstream yet.

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
│   └── notes/          # SUBMODULE → opencode-notes (its own AGENTS.md)
├── sandbox/            # Docker sandbox: opencode-sb CLI, run.sh, Dockerfile, proxy/
└── README.md
```

The content (`tools/`, `skills/`, `sandbox/`, `plugins/`) is harness-agnostic;
all OpenCode wiring lives in `setup.sh`.

## Parent-level build / typecheck / test

Run from the `opencode-tools/` root:

```bash
bun install                                  # root deps (@opencode/* v2, typescript, zod, bun types)
bun run typecheck                            # tsc --noEmit over tools/** + plugins/**/*.ts
bun run test                                 # = bun test plugins/memory/test plugins/notes/test
```

Notes on scope:

- The root `tsconfig.json` typechecks `plugins/**/*.ts` (the `.ts` files of both
  submodules, plus `tools/`). The **GUI `.tsx`** is *not* covered here — that's
  the notes plugin's own `typecheck:gui`.
- `bun test` only picks up submodule tests once the submodules are
  initialized. Run each plugin's own scripts for its full build:
  - **notes** → `plugins/notes`: `bun run gui:build`, `bun run typecheck:gui`
    (full guide: **`plugins/notes/AGENTS.md`**)
  - **memory** → `plugins/memory`: `bun run typecheck`, `bun test test`
    (product docs: `plugins/memory/README.md`)

## Per-submodule docs

| Submodule | Doc |
|---|---|
| `plugins/notes` | **`plugins/notes/AGENTS.md`** — build, the two typechecks, `bun test` from the parent, hot-reload dev loop, schema v9, `ctx.*` cheatsheet, git workflow |
| `plugins/memory` | `plugins/memory/README.md` — summaries, injection, cross-session search |

When working on a plugin, open *its* AGENTS.md/README first; this file only
covers the parent glue.

## setup.sh (bootstrap)

`setup.sh` is the single place that ties this repo to OpenCode. It is idempotent
and, for the plugins, it:

- `git submodule update --init plugins/memory` and `plugins/notes` (skipped if
  already present; warns if offline).
- Symlinks `plugins/memory` → `~/.config/opencode/plugins/memory` and
  `plugins/notes` → `~/.config/opencode/plugins/notes`.
- Symlinks the notes skill: `plugins/notes/skills/notes/SKILL.md` →
  `~/.config/opencode/skills/notes/SKILL.md`.
- Runs `npm install --legacy-peer-deps` inside each plugin (fresh clones have
  no `node_modules`).
- Places `notes.db` under `~/.local/share/opencode/memory/` (never in the repo)
  and checks the runtime's built-in `node:sqlite`.

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
- **Never read OpenCode's `opencode.db` directly** — GUI/app data comes from the
  official `ctx.client.*` APIs only.
- **No `*.db` in the repo.** Databases live on disk under
  `~/.local/share/opencode/…` and are gitignored; override the notes DB with
  `$NOTES_DB` for isolated work.
- Respect each submodule's own AGENTS.md/README — they are the authoritative
  guides for their code.

## Quick checklist for a change

- **Change inside a submodule** (`plugins/*`): edit → submodule typecheck/test
  → build (if GUI) → commit + push the submodule → bump + commit + push the
  parent pointer.
- **Change in `tools/`, `skills/`, `sandbox/`, or `setup.sh`**: edit →
  `bun run typecheck` (and `bun run test`) at the root → commit + push the
  parent only.
- **Fresh machine**: `git clone --recurse-submodules …`, then `bun install`,
  then `./setup.sh`.
