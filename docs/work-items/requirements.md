# Work items — requisitos

> Feature: **work items (necessidade) + planos (execução)** no `opencode-plans`.
> Camada: este documento deriva da necessidade e define **o que o sistema deve fazer**. As histórias (`user-stories.md`) dizem quem quer e por quê; o plano (`plans.db`) diz como.
> Status: rascunho para revisão — 2026-11-16.

## Necessidade

Projetos duram semanas e atravessam vários repositórios. O plano atual cobre **uma execução**: nasce com um pedido, morre quando os passos acabam, e a próxima sessão recomeça sem memória do que já foi decidido e do que falta. Falta uma camada durável de **intenção** — o que precisa existir, por quê, em que ordem e o que depende do quê — ligada à execução e independente da sessão.

## Escopo

**Dentro:** iniciativa do usuário (N repositórios), work item (necessidade), vínculo plano↔item, planejar/executar, ferramentas e contexto do agente, superfície global do Trabalho.

**Fases:** F1–F3 (work items) e **F4 (execução da iniciativa: grafo, branches, paralelismo)** — plano próprio, depende das fases anteriores.

**Fora (v1):** swimlanes, WIP limits, drag de colunas, assignees, labels, sprints, milestones, comentários/feed, sync com GitHub/Jira, merge de projetos, dependências entre projetos, auto-merge na base. Ver `user-stories.md` → “Fora de escopo”.

---

## Requisitos funcionais

### Projeto (contêiner do usuário)

- **RF-01** — O plugin deve manter **iniciativas** que agrupam N repositórios, independentes do projeto derivado do git pelo OpenCode.
- **RF-02** — Um work item pertence a exatamente uma iniciativa; um repositório (diretório) pertence a no máximo uma iniciativa.
- **RF-03** — O plugin deve resolver o projeto de uma sessão pelo diretório: match exato; senão o ancestral mais próximo; senão “sem projeto”.
- **RF-04** — Sem projeto resolvido, a primeira escrita deve criar o projeto a partir do workspace (idempotente) ou falhar com instrução explícita, conforme a decisão registrada.
- **RF-05** — O usuário deve poder renomear o projeto e adicionar/remover workspaces, mantendo ids e vínculos.
- **RF-06** — O **Trabalho é global** (overlay): lista os itens agrupados por projeto, com filtro de projeto. O **painel da sessão é só de planos** (Sessão -> Planos). O plano é alcançável pelo item (Global -> Trabalho -> Plano) e pela aba Planos global.

### Work item (necessidade)

- **RF-07** — O item deve registrar: título, corpo, status, rank, origem, pai e dependências, com timestamps.
- **RF-08** — O corpo é markdown livre que descreve a **necessidade**; o sistema não deve extrair passos, checklist ou estrutura de execução dele.
- **RF-09** — O status deve seguir transições válidas; `done`/`dropped` são terminais e gravam `closed_at`; `doing` é setado quando um plano do item começa; `done` nunca é automático.
- **RF-10** — O usuário deve poder ordenar itens manualmente (rank) dentro do status.
- **RF-11** — O usuário deve poder declarar dependências entre itens; o sistema rejeita ciclos e indica os bloqueadores.
- **RF-12** — O usuário deve poder agrupar itens sob um pai (profundidade 1), sem transformar o pai em plano.
- **RF-13** — A origem (`user`/`agent`) deve ser inferida pelo canal (tool × RPC/comando), nunca declarada pelo agente.
- **RF-14** — Deve existir captura rápida de um item por comando, sem turno de modelo.
- **RF-15** — O usuário deve criar (título, no projeto selecionado) e editar (corpo, pai, deps) na superfície global do Trabalho.
- **RF-16** — Descartar deve pedir confirmação e preservar o plano vinculado.

### Planejar

- **RF-17** — Cada item deve ter a ação **Planejar**, que cria uma sessão nova no workspace do item (não no diretório da sessão atual) e **abre o chat nela**, sem modal, diálogo ou overlay intermediário.
- **RF-18** — A sessão de planejamento deve usar o agente de planejamento do fluxo ativo (`plan` no nativo, `planner` no dedicado).
- **RF-19** — A sessão deve nascer com um prompt-semente que identifica o item, afirma que o corpo é a necessidade (não a implementação) e exige o vínculo do plano.
- **RF-20** — O plano salvo com `workItemID` fica vinculado ao item; o item mostra esse plano (status, progresso, data). Um item tem no máximo um plano.
- **RF-21** — Replanejar **edita** o plano existente (texto/estrutura, reabrindo como `active` se estava `done`); criar um segundo plano para o item é rejeitado com o id do existente. `superseded` não é produzido por este fluxo.

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
- **RF-29** — O overlay deve oferecer uma visão de **quadro (kanban)** por status, por projeto, com arrastar-e-soltar para mudar status/posição e um caminho acessível equivalente (menu “Mover para…”).

---

### Execução de projeto (F4)

- **RF-30** — O plugin deve executar o projeto inteiro pelo **grafo de dependências**: paralelizar itens sem dependência pendente (até o limite configurado) e encadear os dependentes.
- **RF-31** — Cada item deve rodar em **worktree + branch dedicada** (`wi/<item>`), criada a partir do tip atual da branch de integração.
- **RF-32** — O plano deve declarar o **footprint** (`touches`: arquivos/globs) e o sistema deve **criar dependências implícitas** quando dois itens se sobrepõem, com direção determinística (rank/created_at) e detecção de ciclo; footprint desconhecido serializa.
- **RF-33** — A execução deve acumular os itens concluídos numa branch de integração `run/<id>`; a base **nunca** é alterada automaticamente. A integração é feita por uma **fila de merge** drenada por uma sessão dedicada, não pelo engine.
- **RF-34** — Deve existir **Planejar pendentes**: uma sessão de planner por item sem plano, sequencial, antes da execução.
- **RF-35** — Deve ser possível **cancelar** uma execução (parar lançamentos, interromper sessões) e **retry** de um item; falha propaga para os dependentes e não bloqueia ramos independentes; restart marca a run como interrompida sem retomada automática.
- **RF-36** — A UI deve mostrar o **pré-voo** (bloqueios), o **monitor** por item (estado, branch, sessão, duração), a **fila de merge** e um badge da run no card.
- **RF-37** — Ao concluir, o item entra na **fila de merge** do run; uma **única sessão de merge** (agente executor, no worktree de integração) puxa um item por vez, mergeia `wi/<item>` em `run/<id>`, resolve conflitos e marca `merged` ou `merge_failed`.
- **RF-38** — A fila é serializada por **claim transacional** (um item `merging` por vez); um merge que falha para a fila e falha o run; restart devolve `merging` para `queued`/`interrupted`; o agente roda a verificação do projeto antes de marcar `merged`.

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
- **RNF-11 (concorrência)** — Limite de sessões simultâneas (`maxParallel`, padrão 2) por projeto; merges serializados.
- **RNF-12 (segurança git)** — A base nunca é alterada pelo plugin; conflito aborta o merge e falha com relatório, sem auto-resolução.
- **RNF-13 (determinismo)** — Mesmo grafo + mesmo footprint produz a mesma ordem; dependências implícitas são recalculadas a cada plano salvo.
- **RNF-14 (resiliência)** — Restart não retoma sozinho; worktrees órfãos são listáveis e removíveis.
- **RNF-15 (escritor único)** — Só a sessão de merge escreve em `run/<id>`; claims são transacionais e serializados, nunca dois merges ao mesmo tempo.

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
| RF-29 | US-32 | s7 |
| RF-28 | todas | s9/s10 |
| RNF-01…10 | US-30, US-31 | s1–s4, s9 |
| RF-30…38 (F4) | US-33…42 | e1–e8 (plano de execução) |
| RNF-11…15 (F4) | US-33…42 | e1–e8 (plano de execução) |

## Decisões abertas (mesmas do doc de USs)

1. **Auto-criação de projeto** (RF-04): automática ou erro com instrução?
2. **Merge de projetos**: necessário no v1?
3. **`blocked` manual vs derivado**: uma dependência aberta force o status?

Qualquer resposta muda o RF correspondente e o passo; nada aqui depende delas para começar o s1.
