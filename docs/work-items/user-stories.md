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
- **F2 — superfícies (s6–s8):** RPC, painel Trabalho, continuidade.
- **F3 — fechamento (s9–s10):** docs, commits, stress.

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

- [ ] **US-05 (Should · s8)** — Como usuário, quero ver todos os itens agrupados por projeto na visão global, para navegar entre iniciativas.
  - Aceite: o overlay (sem sessão) lista por projeto, depois por status; o painel mostra só o projeto resolvido.

- [ ] **US-06 (Could · v1.1)** — Como usuário, quero mover um item para outro projeto, para reclassificar sem recriar.
  - Fora do v1: mover exige revisar dependências e planos vinculados.

## Item (necessidade)

- [ ] **US-07 (Must · s6)** — Como usuário, quero capturar uma necessidade em uma frase com `/work <título>`, para não perder a ideia no meio de outra tarefa.
  - Aceite: cria sem turno de modelo, `origin=user`, status `backlog`, no projeto resolvido.
  - Aceite: título vazio falha com mensagem clara; nada é criado.

- [ ] **US-08 (Must · s7)** — Como usuário, quero escrever e editar a necessidade em markdown no detalhe do item, para o planejador entender o que precisa existir.
  - Aceite: criar pelo cabeçalho (“Novo item”, só título) e editar corpo/dependências no detalhe.
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
  - Aceite: planos vinculados não são apagados.

## Planejar

- [ ] **US-16 (Must · s7)** — Como usuário, quero um botão **Planejar** em cada item que abre uma sessão nova com o planejador no workspace certo, para decidir o como com contexto limpo.
  - Aceite: sessão criada no diretório da `location_id` do item (ou `primary`), com o agente de planejamento do fluxo (`plan`/`planner`).
  - Aceite: o chat da sessão criada abre focado (o app navega para ela) — **sem modal, diálogo ou overlay intermediário**.
  - Aceite: o título é `Planejar: <título do item>`.
  - Aceite: funciona no painel e no overlay (sem sessão roteada).
  - Aceite: sempre habilitado; replanejar é permitido.

- [ ] **US-17 (Must · s7)** — Como usuário, quero que a sessão de planejamento já nasça sabendo qual item planejar, para não repetir o contexto.
  - Aceite: prompt-semente (i18n PT/EN) com id + título, “o corpo é a necessidade”, “salve com `plans.save({workItemID})`”, “não implemente”.
  - Aceite: o prompt não presume a implementação.

- [ ] **US-18 (Must · s3/s7)** — Como usuário, quero que o plano fique vinculado ao item e que o item liste todos os planos, para ver as tentativas.
  - Aceite: `plans.save` aceita `workItemID`; `plans.get`/`plans.list` expõem o vínculo.
  - Aceite: o detalhe do item lista os planos com status e data, mais recente primeiro.

- [ ] **US-19 (Should · s3)** — Como usuário, quero replanejar sem perder o plano anterior, para mudar de abordagem com histórico.
  - Aceite: um plano novo para o item supersede o ativo anterior; o antigo fica como `superseded`.
  - Aceite: nunca há dois planos ativos para o mesmo item.

- [ ] **US-20 (Must · s7)** — Como usuário, quero que **Executar** fique desabilitado sem plano, para o fluxo ser óbvio.
  - Aceite: sem plano ativo, “Planeje primeiro”; com plano ativo, executa esse plano.
  - Aceite: com execução em andamento, o botão vira Pausar (comportamento atual).

## Executar e fechar

- [ ] **US-21 (Must · s7/s8)** — Como usuário, quero executar o plano do item e ver o progresso refletido nele, para saber o que está acontecendo.
  - Aceite: o card mostra progresso do plano ativo (done/total, doing).
  - Aceite: a execução usa o fluxo atual (executor no dedicado, build no nativo).

- [ ] **US-22 (Must · s4/s7)** — Como usuário, quero que o executor **proponha** o aceite em vez de fechar sozinho, para “done” significar algo.
  - Aceite: ao concluir sem bloqueios, o agente propõe o aceite; o status continua `doing`.
  - Aceite: `done`/`dropped` só por ação humana (painel) ou decisão do planner.

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
  - Aceite: a sessão resolve o projeto e mostra os itens `ready`/`doing`/`blocked` + o último plano.
  - Aceite: não injeta corpo de itens (só título/status).

## Qualidade

- [ ] **US-29 (Must · s1)** — Como mantenedor, quero migração v3 idempotente, para atualizar sem perder dados.
  - Aceite: roda em `plans.db` v2 real; `user_version = 3`; reexecutar não duplica nem falha; `ALTER TABLE` guardado por `PRAGMA table_info`.

- [ ] **US-30 (Must · s1/s2/s3)** — Como mantenedor, quero testes de contrato, resolução, dedupe e invariantes, para não regredir.
  - Aceite: resolução (exato, ancestral, nenhum), `UNIQUE(directory)`, ciclo de deps, dedupe, supersede, um `doing` por plano.

- [ ] **US-31 (Must · s4)** — Como usuário que não usa work items, quero custo mínimo, para o plugin continuar leve.
  - Aceite: sem itens, nenhum bloco na cauda; só a regra constante no system.

---

## Fora de escopo (v1)

- Board com drag-and-drop, assignees, labels, sprints, milestones.
- Comentários/feed de atividade (o log é a sessão; o registro é o plano).
- Sync com GitHub Issues/Jira; importadores.
- Merge de projetos; dependências entre projetos; permissões automáticas para os outros repos do projeto (leitura continua `external_directory`/ask).
- Edição de item na timeline (só painel/overlay).

## Perguntas abertas

1. **Auto-criação de projeto** (US-03): aceitar o risco de projetos “lixo” ou exigir projeto explícito e falhar com “configure um projeto para este workspace”?
2. **Merge de projetos**: se duas sessões do mesmo repo criarem projetos diferentes por engano, o v1 precisa de “juntar” ou basta renomear/remover locations?
3. **`blocked` manual vs derivado**: hoje o status é explícito e as deps são informativas. Quer que uma dep aberta force `blocked` automaticamente?

## Mapa US → passo do plano

| Passo | USs |
|---|---|
| s1 schema + store + resolução | 01, 02, 09, 10, 11, 12, 13, 29, 30 |
| s2 tools + auto-criação | 02, 03, 09, 14, 23, 24, 30 |
| s3 vínculo com planos + supersede | 18, 19, 30 |
| s4 contrato do runtime | 09, 22, 25, 26, 31 |
| s5 e2e F1 | 01–03, 10, 18, 19, 23–26 |
| s6 RPC + `/work` | 03, 04, 07, 14, 15 |
| s7 painel + Planejar/Executar | 08, 10–13, 16–22, 27 |
| s8 continuidade + global | 05, 21, 28 |
| s9 docs + commits | todas (documentação) |
| s10 stress | 01–28 (regressão) |

## Associação plano ↔ US (depois do s10)

Cada US vira um **work item** quando a feature existir (dogfooding), e cada plano de implementação referencia a US que executa:

- No `plans.db`: `plans.work_item_id` aponta para o item da US; o plano é a execução, a US é a necessidade.
- **Até a feature existir**: o título ou o corpo do plano começa com `US-XX`, para a migração conseguir mapear sem adivinhação.
- **Um plano ativo por US.** Se uma execução cobrir duas USs, são dois itens separados — ou um item pai com dois filhos.
- **Não migrar as 31 de uma vez**: criar itens só para as Must/Should da fase corrente, planejar e executar; o doc continua sendo a fonte das histórias.
- O plano que constrói a própria feature (`plans.db`, 10 passos) fica **fora** do backlog de USs: ele é a obra, não uma necessidade do produto.

Ordem sugerida: s10 concluído → criar os itens da fase corrente a partir deste doc → `Planejar` cada um → vincular os planos → acompanhar pelo painel.
