# Work items

Camada de **intenção durável** do plugin de planos: work items (necessidade) ligados a planos (execução), agrupados em **iniciativas** (N repositórios), atravessando sessões.

## Como ler

```
necessidade ──► requisitos ──► user stories ──► plano (plans.db)
   por quê        o que deve      quem quer         como
                  acontecer       e por quê
```

- **`requirements.md`** — a necessidade e os requisitos (RF/RNF/restrições) que o sistema deve cumprir, com rastreabilidade para as histórias e os passos.
- **`user-stories.md`** — 31 histórias em três fases, com critérios de aceite, mapa US → passo, fora de escopo e perguntas abertas.

O plano de execução vive no `plans.db` (10 passos) — este diretório não duplica o plano, só a intenção e o aceite.

## Fases

- **F1–F3 (work items):** projeto, necessidade, planejar/executar um item, superfície global e quadro. Plano no `plans.db` (10 passos).
- **F4 (execução de projeto):** grafo, worktrees/branches, paralelismo, dependências implícitas, monitor. Plano próprio no `plans.db` (8 passos), depende de F1–F3: fila de merge drenada por uma sessão única.

## Estado

- Requisitos: implementados (F1–F4).
- Histórias: implementadas; ver o mapa US → código abaixo.
- Implementação: F1–F3 (work items, superfícies, quadro) e **F4** (execução de
  projeto) no `opencode-plans`; o plano de cada entrega está no `plans.db`.

### F4 — rastreabilidade

| Requisito | Onde |
|---|---|
| RF-30 grafo/paralelismo | `src/run-scheduler.ts`, `src/run-engine.ts` (`pump`) |
| RF-31 worktree/branch por item | `src/git.ts`, `src/run-paths.ts`, `run-engine.executeItem` |
| RF-32 footprint/dependência implícita | `src/work-footprint.ts`, `store.recomputeImplicitDeps`, `plans.save(touches)` |
| RF-33 integração `run/<id>` + fila | `src/run-engine.ts`, `src/merge-session.ts`, tabelas `runs/run_items/merge_queue` |
| RF-34 planejar pendentes | modo quadro/superfície (US-36), sessões de planner por item |
| RF-35 cancelar/retry/restart | `cancelProjectRun`, `retryRunItem`, `recoverRuns` |
| RF-36 UI de pré-voo/monitor/fila | `src/gui/work.tsx` (run bar, painéis) + RPC `run*` |
| RF-37 merge único com claim | `store.claimNextMerge`, `merge.next` |
| RF-38 merge verificado | `merge.done` (`merge-base --is-ancestor`), `verify_command` |

Testes: `test/run-scheduler.test.ts`, `test/work-footprint.test.ts`,
`test/run-footprint.test.ts`, `test/runs.test.ts`,
`test/run-preflight.test.ts`, `test/merge-tools.test.ts`,
`test/run-e2e.test.ts`.

## Decisões abertas

1. Auto-criação de projeto quando o workspace não tem um: automática ou erro com instrução?
2. Merge de projetos no v1: necessário ou basta renomear/remover workspaces?
3. `blocked` manual ou derivado de dependência aberta?
