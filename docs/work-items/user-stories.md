# Work items — user stories

> Feature: **work items (necessidade) + planos (execução)** no `opencode-plans`.
> Requisitos: [`requirements.md`](requirements.md) — a necessidade e o que o sistema deve fazer.
> Este documento registra as histórias e o aceite; o plano de execução (10 passos) vive no `plans.db`.
> Status: rascunho para revisão — 2026-11-16.
> Convenção: `[ ]` todo · `[~]` doing · `[x]` done. Prioridade: Must (F1/F2), Should (F2), Could (v1.1).

## Glossário

| Termo | Significado |
|---|---|
| **Projeto (usuário)** | Contêiner do usuário que agrupa **N workspaces/repos**. É a unidade de produto. |
| **Workspace / location** | Um diretório com sessão (o que o OpenCode chama de projeto). Um projeto tem vários. |
| **Projeto OpenCode** | `plans.project_id` — derivado do remote git. Não muda; é onde a sessão roda. |
| **Work item (US)** | Uma **necessidade**: problema, contexto, resultado esperado. Nunca a implementação. |
| **Plano** | Uma **tentativa de execução** de um work item, presa ao workspace da sessão. |
| **Planner / Executor** | Agentes de planejamento e execução do fluxo dedicado (`plan`/`build` no nativo). |

Atores: **usuário**, **planner** (agente), **executor** (agente), **mantenedor**.

## Fases

- **F1 — núcleo sem GUI (s1–s5):** schema, projeto/resolução, tools, contrato do agente, e2e de agente.
- **F2 — superfícies (s6–s8):** RPC, superfície global do Trabalho, continuidade.
- **F3 — fechamento (s9–s10):** docs, commits, stress.
- **F4 — execução de projeto (e1–e8):** grafo, worktrees/branches, dependências implícitas, fila de merge, monitor. Plano próprio, depende de F1–F3.

---

## Projeto (contêiner)

- [ ] **US-01 (Must · s1)** — Como usuário, quero que cada work item pertença a um projeto que agrupa vários repos/workspaces, para acompanhar uma iniciativa que atravessa mais de um repo.
  - Aceite: `work_items.project_id` aponta para `projects.id`; um projeto tem ≥1 location; um diretório pertence a um único projeto (`UNIQUE(directory)`).
  - Aceite: um item nunca fica órfão de projeto.

- [ ] **US-02 (Must · s1/s2)** — Como usuário, quero que o plugin descubra o projeto pelo workspace da sessão, para não escolher manualmente a cada chamada.
  - Aceite: match exato em `project_locations.directory`; senão o maior ancestral da sessão; senão “sem projeto”.
  - Aceite: projetos aninhados (um dentro do outro) resolvem pelo mais específico.
  - Aceite: `work.list` sem argumento devolve só os itens do projeto resolvido.

- [ ] **US-03 (Must · s2)** — Como usuário, quero que um projeto seja criado automaticamente na primeira vez que uso um workspace sem projeto, para o fluxo não travar.
  - Aceite: `work.save`/`/work` cria o projeto com o basename do workspace e registra a location.
  - Aceite: a criação é idempotente — duas chamadas no mesmo diretório não criam dois projetos.

- [ ] **US-04 (Should · s6/s7)** — Como usuário, quero renomear o projeto e adicionar/remover workspaces, para corrigir o agrupamento.
  - Aceite: renomear mantém ids e vínculos; remover uma location com itens vinculados pede confirmação.
  - Aceite: a primeira location adicionada é a `primary` até eu escolher outra.

- [ ] **US-05 (Should · s8)** — Como usuário, quero ver todos os itens na superfície global, agrupados por projeto, para navegar entre iniciativas.
  - Aceite: o overlay lista por projeto, depois por status, com filtro de projeto; o **painel da sessão é só de planos** (Sessão -> Planos; Global -> Trabalho e/ou Planos).

- [ ] **US-32 (Should · s7)** — Como usuário, quero ver os itens como um **quadro por status** (kanban), para triar e mover trabalho com uma olhada.
  - Aceite: alternância **Lista | Quadro** no overlay; colunas `backlog`, `ready`, `doing`, `blocked`, `done` (`dropped` só por filtro).
  - Aceite: arrastar um card entre colunas muda status **e** posição (rank no índice de destino); o caminho por teclado é abrir o card (Enter) e usar o menu de status do detalhe.
  - Aceite: no modo quadro o overlay alarga (até ~1280px); busca, pai e origem continuam valendo.
  - Aceite: o quadro é **por projeto** (seletor no overlay); sem swimlanes de todos os projetos.
  - Aceite: cada coluna mostra no máximo 20 cards (por rank) e oferece “ver todos”, que abre a lista filtrada por aquele status.

- [ ] **US-06 (Could · v1.1)** — Como usuário, quero mover um item para outro projeto, para reclassificar sem recriar.
  - Fora do v1: mover exige revisar dependências e o plano vinculado.

## Item (necessidade)

- [ ] **US-07 (Must · s6)** — Como usuário, quero capturar uma necessidade em uma frase com `/work <título>`, para não perder a ideia no meio de outra tarefa.
  - Aceite: cria sem turno de modelo, `origin=user`, status `backlog`, no projeto resolvido.
  - Aceite: título vazio falha com mensagem clara; nada é criado.

- [ ] **US-08 (Must · s7)** — Como usuário, quero escrever e editar a necessidade em markdown no detalhe do item, para o planejador entender o que precisa existir.
  - Aceite: criar pelo cabeçalho da superfície global, com um projeto selecionado (“Novo item”, só título), e editar corpo/dependências no detalhe.
  - Aceite: o editor não tem checklist de execução nem extração de passos.

- [ ] **US-09 (Must · s1/s2/s4)** — Como usuário, quero que o item guarde a necessidade e **nunca** a implementação, para o plano decidir o como.
  - Aceite: nenhuma tabela de passos para item; nada de `step_id`/`position` em `work_items`.
  - Aceite: o contrato (system) diz “necessidade, não solução”; a semente do Planejar repete isso.
  - Aceite: um checklist no corpo é texto, não vira execução.

- [ ] **US-10 (Must · s1/s7)** — Como usuário, quero estados claros (`backlog`, `ready`, `doing`, `blocked`, `done`, `dropped`), para saber o que vem agora.
  - Aceite: transições válidas impostas no store/RPC; `done`/`dropped` gravam `closed_at`.
  - Aceite: `doing` é setado quando um plano do item começa; `done` nunca é automático.
  - Aceite: `blocked` mostra os itens que o bloqueiam.

- [ ] **US-11 (Must · s1/s7)** — Como usuário, quero ordenar os itens manualmente dentro do status, para definir prioridade.
  - Aceite: subir/descer troca a posição e persiste `rank`; a lista respeita o `rank`.

- [ ] **US-12 (Should · s1/s7)** — Como usuário, quero declarar dependências entre itens, para não começar o que não pode começar.
  - Aceite: `addDep`/`removeDep`; ciclo (A→B→A) é rejeitado com erro claro.
  - Aceite: o item mostra “bloqueado por X, Y”; o detalhe permite navegar para o bloqueador.

- [ ] **US-13 (Should · s1/s7)** — Como usuário, quero agrupar itens sob um pai, para organizar uma necessidade grande sem criar passos.
  - Aceite: `parent_id` com profundidade 1; o detalhe mostra o pai e os filhos.
  - Aceite: excluir/descartar o pai não apaga os filhos.

- [ ] **US-14 (Should · s2/s7)** — Como usuário, quero ver o que o agente propôs, para triar o que ele inventou.
  - Aceite: `origin=agent` exibido como chip e filtrável; itens criados por ferramenta nunca saem como `user`.
  - Aceite: máximo 3 itens por pedido, com dedupe por título normalizado.

- [ ] **US-15 (Must · s6/s7)** — Como usuário, quero descartar um item com confirmação, para limpar o backlog sem perder o histórico.
  - Aceite: `dropped` pede confirmação; o item some das listas padrão e continua acessível por filtro.
  - Aceite: o plano vinculado não é apagado.

## Planejar

- [ ] **US-16 (Must · s7)** — Como usuário, quero um botão **Planejar** em cada item que abre uma sessão nova com o planejador no workspace certo, para decidir o como com contexto limpo.
  - Aceite: sessão criada no diretório da `location_id` do item (ou `primary`), com o agente de planejamento do fluxo (`plan`/`planner`).
  - Aceite: o chat da sessão criada abre focado (o app navega para ela) — **sem modal, diálogo ou overlay intermediário**.
  - Aceite: o título é `Planejar: <título do item>`.
  - Aceite: funciona na superfície global do Trabalho (overlay), sem sessão roteada.
  - Aceite: sempre habilitado; replanejar é permitido.

- [ ] **US-17 (Must · s7)** — Como usuário, quero que a sessão de planejamento já nasça sabendo qual item planejar, para não repetir o contexto.
  - Aceite: prompt-semente (i18n PT/EN) com id + título, “o corpo é a necessidade”, “salve com `plans.save({workItemID})`”, “não implemente”.
  - Aceite: o prompt não presume a implementação.

- [ ] **US-18 (Must · s3/s7)** — Como usuário, quero que o plano fique vinculado ao item e que o item mostre esse plano, para saber o que será executado.
  - Aceite: `plans.save` aceita `workItemID`; `plans.get`/`plans.list` expõem o vínculo; **um item tem no máximo um plano** (índice único parcial em `plans.work_item_id`).
  - Aceite: o detalhe do item mostra o plano com status, progresso e data — sem lista de tentativas.

- [ ] **US-19 (Should · s3)** — Como usuário, quero replanejar **editando o plano existente**, para a estratégia atual ser o único registro — histórico de planos não é relevante.
  - Aceite: `plans.save` com `id` substitui texto/estrutura do mesmo plano; criar um segundo plano para o item é rejeitado com o id do existente.
  - Aceite: `Planejar` num item que já tem plano abre a sessão desse plano (ou cria uma nova, se ela não existir) e manda **editar** o plano, não criar outro.
  - Aceite: editar um plano `done` o reabre como `active`; num item `done`, a UI pede para reabrir o item antes.
  - Aceite: `superseded` não é produzido por este fluxo.

- [ ] **US-20 (Must · s7)** — Como usuário, quero que **Executar** fique desabilitado sem plano, para o fluxo ser óbvio.
  - Aceite: sem plano ativo, “Planeje primeiro”; com plano ativo, executa esse plano.
  - Aceite: com execução em andamento, o botão vira Pausar (comportamento atual).

## Executar e fechar

- [ ] **US-21 (Must · s7/s8)** — Como usuário, quero executar o plano do item e ver o progresso refletido nele, para saber o que está acontecendo.
  - Aceite: o card mostra progresso do plano ativo (done/total, doing).
  - Aceite: a execução usa o fluxo atual (executor no dedicado, build no nativo).

- [ ] **US-22 (Must · s4/s7)** — Como usuário, quero que o executor **proponha** o aceite em vez de fechar sozinho, para “done” significar algo.
  - Aceite: ao concluir sem bloqueios, o agente propõe o aceite; o status continua `doing`.
  - Aceite: `done`/`dropped` só por ação humana (superfície global) ou decisão do planner.

## Agente

- [ ] **US-23 (Must · s2)** — Como planner, quero listar e ler os itens do projeto e o corpo da necessidade, para planejar com continuidade.
  - Aceite: `work.list` devolve id, título, status, rank, bloqueios e plano ativo; `work.get` devolve corpo, deps e planos.
  - Aceite: o corpo é tratado como dado, não como instrução.

- [ ] **US-24 (Must · s2)** — Como planner, quero criar e atualizar itens sem duplicar, para transformar necessidades soltas em backlog.
  - Aceite: `work.save`/`work.update` com os limites de validação; `existing: true` no dedupe.
  - Aceite: `origin` é inferido; o agente não consegue gravar como `user`.

- [ ] **US-25 (Must · s4)** — Como agente, quero receber as regras de autoria sempre e a lista de itens no contexto, sem inflar o prompt.
  - Aceite: regras no `PLANS_ROUTING_RULE` (system, os dois fluxos); lista no `<work-items>` da cauda, cap 12, sem corpo.
  - Aceite: planner/Plan recebem a lista a cada request; executor só após compactação.

- [ ] **US-26 (Must · s4)** — Como agente, quero que a lista de itens sobreviva à compactação, para não perder o fio em sessões longas.
  - Aceite: após compactação forçada, o `<work-items>` volta com o estado atual.

- [ ] **US-27 (Must · s7)** — Como executor, quero saber qual item estou executando, para marcar progresso e propor o aceite no lugar certo.
  - Aceite: o prompt de execução e o contexto nomeiam o item e o plano.

## Continuidade

- [ ] **US-28 (Should · s8)** — Como usuário, quero abrir uma sessão nova semanas depois e ver o estado do projeto e do item, para retomar sem reler o histórico.
  - Aceite: a sessão resolve o projeto e mostra os itens `ready`/`doing`/`blocked` + o plano de cada item.
  - Aceite: não injeta corpo de itens (só título/status).

## Execução de projeto (F4)

- [ ] **US-33 (Must · e1/e4)** — Como usuário, quero **executar o projeto inteiro** seguindo o grafo, para o trabalho andar sem eu disparar item por item.
  - Aceite: só itens `ready` com plano; sem ciclo; até `maxParallel` em paralelo; um dependente só começa com as dependências concluídas.
  - Aceite: a ordem é determinística; a execução é cancelável e não toca a branch base.

- [ ] **US-34 (Must · e2/e4)** — Como usuário, quero que cada item seja desenvolvido numa **branch/worktree dedicada**, para execuções paralelas não pisarem umas nas outras.
  - Aceite: `git worktree` + branch `wi/<item>` a partir do tip atual da integração; a sessão do executor roda nesse diretório.
  - Aceite: o worktree é identificável e removível ao fim; nada é escrito na árvore principal.

- [ ] **US-35 (Must · e3)** — Como usuário, quero que itens que alteram **o mesmo código** ganhem automaticamente uma **dependência implícita**, para não rodarem em paralelo e conflitarem.
  - Aceite: footprint = `touches` declarado pelo plano ∪ diff real da branch; interseção sem caminho no grafo cria uma dep `implicit` com os caminhos no `reason`.
  - Aceite: direção determinística (rank/created_at); se a direção criar ciclo, o pré-voo falha com os itens envolvidos.
  - Aceite: plano sem `touches` é tratado como conflitante com tudo e serializa.

- [ ] **US-36 (Should · e5)** — Como usuário, quero **planejar os pendentes em lote**, para não abrir uma sessão por item antes de executar.
  - Aceite: uma sessão de planner por item `ready` sem plano, sequencial; para no primeiro erro e mantém o que já foi planejado.
  - Aceite: `backlog` não é planejado nem executado até ser promovido.

- [ ] **US-37 (Should · e5)** — Como usuário, quero um **monitor da execução**, para ver o que está rodando, o que espera e o que falhou.
  - Aceite: por item `queued | running | merging | done | failed | skipped`, com branch, sessão (link) e duração.
  - Aceite: **Cancelar** interrompe as sessões e para a fila; **Retry** recria a branch do item a partir do tip atual.

- [ ] **US-38 (Must · e4)** — Como usuário, quero que a execução produza uma **branch de integração revisável**, para eu juntar tudo de uma vez.
  - Aceite: `run/<id>` nasce na base e recebe os itens concluídos pela fila de merge, um por vez.
  - Aceite: a base **nunca** é alterada automaticamente; o resultado é uma branch única para revisão.

- [ ] **US-39 (Must · e4)** — Como usuário, quero que uma falha **propague só para os dependentes**, para os ramos independentes continuarem.
  - Aceite: dependentes do item falho são `skipped` transitivamente; a run termina `failed` com o resumo.
  - Aceite: a execução não entra em loop de retry automático.

- [ ] **US-40 (Should · e1)** — Como mantenedor, quero limitar a **concorrência** por projeto, para não estourar o provedor nem o disco.
  - Aceite: `maxParallel` por projeto (padrão 2), respeitado pelo engine e visível na UI.

- [ ] **US-41 (Must · e5)** — Como usuário, quero que cada item concluído entre numa **fila de merge** drenada por **uma única sessão**, para os merges nunca se atropelarem.
  - Aceite: fila por run, FIFO; um item `merging` por vez via **claim transacional**; a sessão de merge é única e roda no worktree de integração.
  - Aceite: um dependente só é liberado quando a dependência está `merged` (não apenas executada).
  - Aceite: novo item na fila **acorda** a sessão de merge; se ela estiver ocupada, o item espera a vez.

- [ ] **US-42 (Must · e5)** — Como usuário, quero que o agente de merge **resolva conflitos e valide** antes de marcar como mergeado, para a integração não quebrar em silêncio.
  - Aceite: o agente lê o item/plano, mergeia `wi/<item>` em `run/<id>` e resolve conflito no worktree de integração.
  - Aceite: roda a verificação do projeto (`verify_command`, quando configurada); falha → `git merge --abort`/reset e marca `merge_failed`.
  - Aceite: um merge que falha para a fila e falha o run; nunca há auto-merge na base.

## Qualidade

- [ ] **US-29 (Must · s1)** — Como mantenedor, quero migração v3 idempotente, para atualizar sem perder dados.
  - Aceite: roda em `plans.db` v2 real; `user_version = 3`; reexecutar não duplica nem falha; `ALTER TABLE` guardado por `PRAGMA table_info`.

- [ ] **US-30 (Must · s1/s2/s3)** — Como mantenedor, quero testes de contrato, resolução, dedupe e invariantes, para não regredir.
  - Aceite: resolução (exato, ancestral, nenhum), `UNIQUE(directory)`, ciclo de deps, dedupe, um plano por item, um `doing` por plano.

- [ ] **US-31 (Must · s4)** — Como usuário que não usa work items, quero custo mínimo, para o plugin continuar leve.
  - Aceite: sem itens, nenhum bloco na cauda; só a regra constante no system.

---

## Fora de escopo (v1)

- Swimlanes, WIP limits, drag de colunas, assignees, labels, sprints, milestones.
- Comentários/feed de atividade (o log é a sessão; o registro é o plano).
- Sync com GitHub Issues/Jira; importadores.
- Merge de projetos; dependências entre projetos; permissões automáticas para os outros repos do projeto (leitura continua `external_directory`/ask).
- Edição de item na timeline (só na superfície global).
- Auto-merge na base; retomada automática após restart; execução atravessando projetos; WIP por coluna.

## Perguntas abertas

1. **Auto-criação de projeto** (US-03): aceitar o risco de projetos “lixo” ou exigir projeto explícito e falhar com “configure um projeto para este workspace”?
2. **Merge de projetos**: se duas sessões do mesmo repo criarem projetos diferentes por engano, o v1 precisa de “juntar” ou basta renomear/remover locations?
3. **`blocked` manual vs derivado**: hoje o status é explícito e as deps são informativas. Quer que uma dep aberta force `blocked` automaticamente?

## Mapa US → passo do plano

| Passo | USs |
|---|---|
| s1 schema + store + resolução | 01, 02, 09, 10, 11, 12, 13, 29, 30 |
| s2 tools + auto-criação | 02, 03, 09, 14, 23, 24, 30 |
| s3 vínculo com planos + edição | 18, 19, 30 |
| s4 contrato do runtime | 09, 22, 25, 26, 31 |
| s5 e2e F1 | 01–03, 10, 18, 19, 23–26 |
| s6 RPC + `/work` | 03, 04, 07, 14, 15 |
| s7 superfície global + Planejar/Executar + quadro | 08, 10–13, 16–22, 27, 32 |
| s8 continuidade + global | 05, 21, 28 |
| s9 docs + commits | todas (documentação) |
| s10 stress | 01–28 (regressão) |
| e1 schema de runs + fila + settings | 33, 40, 41 |
| e2 git helper (worktree/branch/diff/ancestor) | 34 |
| e3 footprint + dependências implícitas | 35 |
| e4 engine (grafo, sessões, enfileirar) | 33, 34, 38, 39, 41 |
| e5 sessão de merge + tools + verificação | 41, 42 |
| e6 pré-voo + monitor + planejar pendentes | 36, 37, 41 |
| e7 e2e com repo real (inclui conflito) | 33–42 |
| e8 docs + stress | todas |

## Associação plano ↔ US (depois do s10)

Cada US vira um **work item** quando a feature existir (dogfooding), e cada plano de implementação referencia a US que executa:

- No `plans.db`: `plans.work_item_id` aponta para o item da US; o plano é a execução, a US é a necessidade.
- **Até a feature existir**: o título ou o corpo do plano começa com `US-XX`, para a migração conseguir mapear sem adivinhação.
- **Um plano por US.** Replanejar edita o mesmo plano (sem histórico); se uma execução cobrir duas USs, são dois itens separados — ou um item pai com dois filhos.
- **Não migrar as 31 de uma vez**: criar itens só para as Must/Should da fase corrente, planejar e executar; o doc continua sendo a fonte das histórias.
- O plano que constrói a própria feature (`plans.db`, 10 passos) fica **fora** do backlog de USs: ele é a obra, não uma necessidade do produto.

Ordem sugerida: s10 concluído → criar os itens da fase corrente a partir deste doc → `Planejar` cada um → vincular os planos → acompanhar pela superfície global do Trabalho.
