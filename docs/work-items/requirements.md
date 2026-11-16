# Work items — requisitos

> Feature: **work items (necessidade) + planos (execução)** no `opencode-plans`.
> Camada: este documento deriva da necessidade e define **o que o sistema deve fazer**. As histórias (`user-stories.md`) dizem quem quer e por quê; o plano (`plans.db`) diz como.
> Status: rascunho para revisão — 2026-11-16.

## Necessidade

Projetos duram semanas e atravessam vários repositórios. O plano atual cobre **uma execução**: nasce com um pedido, morre quando os passos acabam, e a próxima sessão recomeça sem memória do que já foi decidido e do que falta. Falta uma camada durável de **intenção** — o que precisa existir, por quê, em que ordem e o que depende do quê — ligada à execução e independente da sessão.

## Escopo

**Dentro:** projeto do usuário (N workspaces), work item (necessidade), vínculo plano↔item, planejar/executar, ferramentas e contexto do agente, painel.

**Fora (v1):** board com drag-and-drop, assignees, labels, sprints, milestones, comentários/feed, sync com GitHub/Jira, merge de projetos, dependências entre projetos. Ver `user-stories.md` → “Fora de escopo”.

---

## Requisitos funcionais

### Projeto (contêiner do usuário)

- **RF-01** — O plugin deve manter **projetos do usuário** que agrupam N workspaces, independentes do projeto derivado do git pelo OpenCode.
- **RF-02** — Um work item pertence a exatamente um projeto; um workspace (diretório) pertence a no máximo um projeto.
- **RF-03** — O plugin deve resolver o projeto de uma sessão pelo diretório: match exato; senão o ancestral mais próximo; senão “sem projeto”.
- **RF-04** — Sem projeto resolvido, a primeira escrita deve criar o projeto a partir do workspace (idempotente) ou falhar com instrução explícita, conforme a decisão registrada.
- **RF-05** — O usuário deve poder renomear o projeto e adicionar/remover workspaces, mantendo ids e vínculos.
- **RF-06** — A visão global deve agrupar itens por projeto; a visão do painel mostra só o projeto resolvido.

### Work item (necessidade)

- **RF-07** — O item deve registrar: título, corpo, status, rank, origem, pai e dependências, com timestamps.
- **RF-08** — O corpo é markdown livre que descreve a **necessidade**; o sistema não deve extrair passos, checklist ou estrutura de execução dele.
- **RF-09** — O status deve seguir transições válidas; `done`/`dropped` são terminais e gravam `closed_at`; `doing` é setado quando um plano do item começa; `done` nunca é automático.
- **RF-10** — O usuário deve poder ordenar itens manualmente (rank) dentro do status.
- **RF-11** — O usuário deve poder declarar dependências entre itens; o sistema rejeita ciclos e indica os bloqueadores.
- **RF-12** — O usuário deve poder agrupar itens sob um pai (profundidade 1), sem transformar o pai em plano.
- **RF-13** — A origem (`user`/`agent`) deve ser inferida pelo canal (tool × RPC/comando), nunca declarada pelo agente.
- **RF-14** — Deve existir captura rápida de um item por comando, sem turno de modelo.
- **RF-15** — O usuário deve criar (título) e editar (corpo, pai, deps) pelo painel.
- **RF-16** — Descartar deve pedir confirmação e preservar planos vinculados.

### Planejar

- **RF-17** — Cada item deve ter a ação **Planejar**, que cria uma sessão nova no workspace do item (não no diretório da sessão atual) e **abre o chat nela**, sem modal, diálogo ou overlay intermediário.
- **RF-18** — A sessão de planejamento deve usar o agente de planejamento do fluxo ativo (`plan` no nativo, `planner` no dedicado).
- **RF-19** — A sessão deve nascer com um prompt-semente que identifica o item, afirma que o corpo é a necessidade (não a implementação) e exige o vínculo do plano.
- **RF-20** — O plano salvo com `workItemID` fica vinculado ao item; o item lista todos os planos, mais recente primeiro.
- **RF-21** — Um novo plano ativo para o item deve superseder o anterior; nunca dois planos ativos para o mesmo item.

### Executar e fechar

- **RF-22** — **Executar** só deve estar disponível com plano ativo, e o progresso do plano deve aparecer no item.
- **RF-23** — O executor deve **propor** o aceite; `done`/`dropped` só por ação humana ou decisão do planner após revisão.

### Agente

- **RF-24** — O agente deve ter quatro ferramentas: listar, ler, criar/atualizar a necessidade e atualizar estado/ordem/pai/deps — com validação e dedupe idempotente.
- **RF-25** — A escrita do agente deve ser limitada (máx. 3 itens por pedido); título normalizado + pai + status não-terminal devolve o existente.
- **RF-26** — As regras de autoria devem ser constantes e chegar a todos os agentes nos dois fluxos; a lista de itens deve ir na cauda, limitada e sem corpo, sobrevivendo à compactação.

### Dados e qualidade

- **RF-27** — Tudo vive no `plans.db` existente, com migração v3 idempotente (aditiva) e índices por projeto/status/rank.
- **RF-28** — O comportamento do fluxo nativo e o schema v2 existente não podem regredir.

---

## Requisitos não funcionais

- **RNF-01 (cache)** — Regras constantes no `system`; dados dinâmicos (lista de itens) na cauda. Nunca reescrever o `system` por request.
- **RNF-02 (catálogo)** — Descrições de tools ≤110 chars; parâmetros ≤6 palavras.
- **RNF-03 (tokens)** — Lista no contexto ≤12 itens, sem corpo; sem itens, nenhum bloco injetado.
- **RNF-04 (permissões)** — O planner continua read-only nas edições; `shell` inalterado; o plugin não concede diretórios automaticamente.
- **RNF-05 (isolamento)** — Itens e planos são escopados por projeto/sessão; nada vaza entre projetos.
- **RNF-06 (i18n)** — Toda cópia exibida existe em PT-BR e EN-US, com EN-US de fallback.
- **RNF-07 (compatibilidade)** — Migração aditiva; fluxo nativo byte a byte; nenhuma mudança em `plans.project_id`.
- **RNF-08 (testabilidade)** — Store, tools, contrato, resolução, dedupe e invariantes cobertos por teste; UI com checklist manual.
- **RNF-09 (desempenho)** — Listar o backlog é O(itens do projeto), com índice `(project_id, status, rank)`.
- **RNF-10 (observabilidade)** — Erros com prefixo `[plans]`; stress sem `ERROR`/`WARN` do plugin.

## Restrições

- **R-01** — Um único banco (`plans.db`); nada de segundo banco ou serviço.
- **R-02** — Sem board, assignees, labels, sprints, milestones, comentários ou sync de issues no v1.
- **R-03** — Uma execução acontece em um workspace por vez; cross-repo continua `external_directory` (ask).
- **R-04** — O item nunca carrega passos; o plano é a única unidade executável.
- **R-05** — O documento de USs é a fonte das histórias; o `plans.db` é a fonte da execução.

---

## Rastreabilidade

| Requisito | Histórias | Passo |
|---|---|---|
| RF-01, RF-02 | US-01 | s1 |
| RF-03 | US-02 | s1/s2 |
| RF-04 | US-03 | s2 |
| RF-05 | US-04 | s6/s7 |
| RF-06 | US-05 | s8 |
| RF-07 | US-07, 08, 10, 11, 12, 13 | s1 |
| RF-08 | US-09 | s1/s2/s4 |
| RF-09 | US-10 | s1/s7 |
| RF-10 | US-11 | s1/s7 |
| RF-11 | US-12 | s1/s7 |
| RF-12 | US-13 | s1/s7 |
| RF-13 | US-14 | s2 |
| RF-14 | US-07 | s6 |
| RF-15 | US-08 | s7 |
| RF-16 | US-15 | s6/s7 |
| RF-17, RF-18 | US-16 | s7 |
| RF-19 | US-17 | s7 |
| RF-20 | US-18 | s3/s7 |
| RF-21 | US-19 | s3 |
| RF-22 | US-20, US-21 | s7/s8 |
| RF-23 | US-22 | s4/s7 |
| RF-24, RF-25 | US-23, US-24 | s2 |
| RF-26 | US-25, US-26, US-31 | s4 |
| RF-27 | US-29 | s1 |
| RF-28 | todas | s9/s10 |
| RNF-01…10 | US-30, US-31 | s1–s4, s9 |

## Decisões abertas (mesmas do doc de USs)

1. **Auto-criação de projeto** (RF-04): automática ou erro com instrução?
2. **Merge de projetos**: necessário no v1?
3. **`blocked` manual vs derivado**: uma dependência aberta force o status?

Qualquer resposta muda o RF correspondente e o passo; nada aqui depende delas para começar o s1.
