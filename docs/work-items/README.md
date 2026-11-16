# Work items

Camada de **intenção durável** do plugin de planos: work items (necessidade) ligados a planos (execução), atravessando sessões e vários repositórios.

## Como ler

```
necessidade ──► requisitos ──► user stories ──► plano (plans.db)
   por quê        o que deve      quem quer         como
                  acontecer       e por quê
```

- **`requirements.md`** — a necessidade e os requisitos (RF/RNF/restrições) que o sistema deve cumprir, com rastreabilidade para as histórias e os passos.
- **`user-stories.md`** — 31 histórias em três fases, com critérios de aceite, mapa US → passo, fora de escopo e perguntas abertas.

O plano de execução vive no `plans.db` (10 passos) — este diretório não duplica o plano, só a intenção e o aceite.

## Estado

- Requisitos: rascunho para revisão.
- Histórias: rascunho para revisão.
- Implementação: não iniciada.

## Decisões abertas

1. Auto-criação de projeto quando o workspace não tem um: automática ou erro com instrução?
2. Merge de projetos no v1: necessário ou basta renomear/remover workspaces?
3. `blocked` manual ou derivado de dependência aberta?
