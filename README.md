# opencode-tools

Tools e skills do agente, mais o **bootstrap de máquina** que os liga ao
OpenCode.

Cinco subsistemas:

- **`notes`** — memória de longa duração (SQLite + FTS5 opcional), exposta
  pelo plugin `plugins/notes` (tools `notes.*` no Code Mode; nomes efetivos
  `notes_*` em sessões regulares) e por um painel lateral no app desktop.
  Não há CLI externa: tools e painel leem/gravam o SQLite diretamente.
- **`plans`** — planos persistidos do modo Plan (SQLite dedicado), expostos
  pelas tools `plans.*` e por um painel lateral **Planos**. O agente salva com
  `plans.save` (ou o usuário com `/save-plan`) e marca o progresso com
  `plans.update`; não há captura heurística.
- **`stats`** — painel **Estatísticas** (gauge de tok/s, histórico, reasoning,
  tool calls e totais da sessão) e aba **System prompt** com o prompt fixo,
  adicionado e dinâmico. O prompt é capturado no servidor; não há banco novo.
- **`sandbox`** — delegação de trabalho com risco para um container Docker
  descartável, via as tools `sandbox_*` e o CLI `opencode-sb`.
- **`memory` (plugin)** — captura resumos de compactação, injeta o
  estado do repo e o handoff da sessão anterior, e permite busca cross-sessão
  em resumos e conversas passadas. Veja [Plugin: memory](#plugin-memory).

O conteúdo (`tools/`, `skills/`, `memory/`, `sandbox/`, `plugins/`) é genérico;
o acoplamento com o OpenCode vive só no `setup.sh`. Trocar de harness =
reescrever o `setup.sh`.

## Layout

```
opencode-tools/
├── setup.sh            # links + banco + sandbox (daemon, guard, imagens, smoke)
├── tools/
│   └── sandbox.ts
├── plugins/
│   ├── memory/          # plugin OpenCode V2 (SUBMODULE → opencode-memory): resumos, injeção, busca
│   ├── notes/           # plugin OpenCode V2 + skill + painel desktop (SUBMODULE → opencode-notes): tools notes.* direto no SQLite
│   ├── plans/           # plugin OpenCode V2 + painel Planos (SUBMODULE → opencode-plans): tools plans.* + plans.db
│   └── stats/           # plugin OpenCode V2 + painel Estatísticas/System prompt (SUBMODULE → opencode-stats)
├── sandbox/
│   ├── setup.sh        # expõe opencode-sb/opencode-sandboxed no PATH
│   ├── run.sh          # orquestrador (task/steer/watch/peek/status/up/down/…)
│   ├── opencode-sandboxed  # CLI global (opencode-sb)
│   ├── Dockerfile, proxy/, relay/
│   ├── host-firewall.sh    # guard container → serviços do host
│   ├── models.conf         # listas de preferência de modelo
│   └── README.md
└── skills/
    └── sandbox/SKILL.md   # (a skill notes mora no submodule plugins/notes)
```

## Setup

Os plugins `plugins/memory`, `plugins/notes`, `plugins/plans` e `plugins/stats` são **submodules** dos repos
standalone [**opencode-memory**](https://github.com/HitalloExiled/opencode-memory),
[**opencode-notes**](https://github.com/HitalloExiled/opencode-notes),
[**opencode-plans**](https://github.com/HitalloExiled/opencode-plans) e
[**opencode-stats**](https://github.com/HitalloExiled/opencode-stats),
respectivamente:

```bash
git clone --recurse-submodules git@github.com:HitalloExiled/opencode-tools.git
cd opencode-tools
```

(ou, num clone já feito: `git submodule update --init plugins/memory plugins/notes plugins/plans plugins/stats` — o
`./setup.sh` faz isso sozinho quando um submodule está vazio.)

```bash
./setup.sh                 # configura tudo (inclui build + smoke do sandbox)
./setup.sh --check         # só diagnostica (exit 1 se faltar algo)
./setup.sh --remove        # remove os links (nunca toca nos dados nem no firewall)
./setup.sh --prefix DIR    # configura sob DIR (teste/portátil; sem sandbox)
./setup.sh --no-sandbox    # só memória/skills/tools (sem docker/root)
./setup.sh --no-smoke      # prepara o sandbox sem chamar modelo nenhum
./setup.sh --rebuild       # reconstrói as imagens do sandbox
```

O que o `setup.sh` faz, em ordem:

| Passo | Efeito |
|---|---|
| plugin (`@opencode-ai/plugin`) | garante a dependência npm resolvível a partir do repo (npm, ou symlink do config do OpenCode) — usada pela tool legada `sandbox_*` |
| memória | migra o banco legado, se existir; remove o symlink antigo do CLI `notes` |
| skills | symlink `skills/<id>/SKILL.md` → `~/.config/opencode/skills/<id>/SKILL.md` (o skill `notes` vem do submodule `plugins/notes/skills/notes` e é linkado na etapa de plugins) |
| tools | symlink `tools/*.ts` → `~/.config/opencode/tools/` |
| plugins `memory` + `notes` + `plans` + `stats` | garante os submodules `plugins/memory`, `plugins/notes`, `plugins/plans` e `plugins/stats` inicializados (clones de `opencode-memory`, `opencode-notes`, `opencode-plans` e `opencode-stats`) + symlinks → `~/.config/opencode/plugins/{memory,notes,plans,stats}` + `npm install` dentro de cada plugin com `package.json`; compila o GUI de `plans`, `memory` e `stats`; remove o link legado `tools/notes.ts` (as tools `notes_*` viraram o plugin `notes`) |
| sandbox | daemon docker → CLI `opencode-sb` → guard de firewall → imagens/rede → self-test → tarefa de fumaça |
| verificação | `node:sqlite` (FTS5) no runtime, presença do banco, estado do sandbox, PATH |

É **idempotente**: rodar de novo só confere e repete o smoke. A primeira execução
pede `sudo` uma vez (subir o daemon e instalar o guard). Sem terminal/sudo, use
`--no-sandbox` e rode os comandos privilegiados manualmente — o script imprime
quais são.

Arquivos reais que estejam no caminho são **movidos para backup**
(`*.bak-<timestamp>`), nunca apagados.

## Máquina zerada: o que é criado, quando

O banco e o schema são criados sob demanda: o plugin aplica DDL + migrações
idempotentes (`PRAGMA user_version`) na primeira abertura.

```
$XDG_DATA_HOME/opencode/memory/notes.db     # notes (estado; nunca versionado)
$XDG_DATA_HOME/opencode/plans/plans.db      # planos persistidos (nunca versionado)
```

| Objeto | Origem |
|---|---|
| banco | `src/store.ts` (`initSchema`) |
| `notes` + índices | DDL embutido em `src/store.ts` |
| `notes_fts` + shadow tables + triggers | DDL embutido (só se houver FTS5) |
| `note_revisions` e migrações `≥ 2` | DDL embutido por `user_version` |
| imagens, rede e relay do sandbox | `sandbox/run.sh up` |
| unit do firewall | `sandbox/host-firewall.sh install-unit` |

**Degradação:** sem FTS5, a busca cai para `LIKE`. `notes.doctor` reporta isso.

### Backup

```bash
cp ~/.local/share/opencode/memory/notes.db ~/notes-backup.db   # app fechado
```

## Camadas de memória

O repositório expõe duas camadas complementares, **isoladas por design**
(nenhuma conhece a outra; cada uma define seu escopo por si):

| Camada | Papel | Onde vive |
|---|---|---|
| **notes** (plugin `notes.*` + painel) | conhecimento **curado e portátil**: fatos, decisões, problemas resolvidos, configs — com ciclo de confiança e histórico de versões; **via entre máquinas** (arquivo SQLite) | `notes.db` + `plugins/notes/` |
| **memory** (plugin) | **retrieval local** de conversas e compactações: índice derivado (FTS5 + busca semântica local), injeção de contexto e handoff; descartável e por projeto | `plugins/memory/` + `index.db`/`compactions/` |
| **memória persistente** (camada do plugin memory) | fatos duráveis do **mundo/usuário** que continuam verdadeiros após a sessão: quem é o usuário, preferências, trabalho em curso, fatos da máquina — injetada **no início de toda sessão** (com quota), escrita explícita do agente (`memory.profile`) ou do usuário (`/remember`/`/forget`); por máquina, sem portabilidade | `plugins/memory/` + `profile.json` |

Regra prática: "o que foi **dito/feito** na conversa X?" → `memory.search`;
"o que **sabemos com confiança** sobre X?" → `notes`; "quem é o usuário /
como esta máquina se comporta / no que estamos trabalhando?" → memória
persistente (injetada, um `memory.profile get` de distância). O que precisa
valer em outra máquina precisa ser nota.

## Tools

O contrato completo de cada subsistema está nas skills (`plugins/notes/skills/notes`
e `skills/sandbox`, expostas via symlinks em `~/.config/opencode/skills/`);
aqui vai só o mapa.

| Origem | O que oferece |
|---|---|
| `notes.*` (plugin; `notes_*` em sessões regulares) | memória: `add`, `update`, `confirm`, `dispute`, `retract`, `history`, `restore`, `view`, `pin`, `unpin`, `search`, `doctor` — leitura/escrita direta no SQLite; `notes.add` **recusa** `#problem` sem Sintoma/Causa/Solução e aceita `author` (exibido como `(by <author>)`) |
| `plans.*` (plugin; `plans_*` em sessões regulares) | planos: `save`, `list`, `get`, `update`, `delete`, `doctor` — leitura/escrita direta no `plans.db`; a gravação é sempre explícita (`plans.save` ou `/save-plan`) |
| `opencode-sb task/steer/peek/logs/status/…` | sandbox (detalhes em `skills/sandbox/SKILL.md`) |
| `sandbox_run/steer/peek/logs/status` | tools tipadas sobre o CLI; execução por `argv`, sem shell |

O canal de retorno do sandbox é a **resposta final** (texto). `/workspace/out` é
o drop de artefatos do **usuário** — o agente host nunca lê esse diretório.

### Permissões (opcional)

Se quiser uma allow-list de skills no config do OpenCode:

```jsonc
"permissions": [
  { "action": "skill", "resource": "*",        "effect": "deny"  },
  { "action": "skill", "resource": "notes",    "effect": "allow" },
  { "action": "skill", "resource": "sandbox",  "effect": "allow" }
]
```

## Plugin: memory

Plugin único (`plugins/memory/`, id `memory`; antes `agent-toolbelt`) para o
OpenCode V2.
Carregado automaticamente como pacote local em `~/.config/opencode/plugins/memory`
(link criado pelo `setup.sh`). Três funções:

1. **Captura resumos de compactação.** Toda vez que uma sessão é compactada, o
   corpo completo do resumo (Objective, Requirements, Decisions, Work State,
   Next Move, Relevant Files, Important Context) é salvo como um arquivo
   Markdown, um por compactação. Nenhuma transcript é guardada — só o resumo
   que o próprio OpenCode já produziu.
2. **Injeta contexto no início da sessão.** No primeiro turno de uma sessão
   (e de novo se o projeto mudar), o plugin injeta um bloco
   `<memory-context>` com: repositório, branch e último commit (o status do
   working tree fica **fora** do bloco, para não invalidar o cache de prefixo
   do servidor a cada edição — peça o estado atual sob demanda pela ferramenta
   `memory.summaries` com `action=repo`), a **memória persistente** (fatos
   duráveis do mundo/usuário em `profile.json` — quem é o usuário,
   preferências, trabalho em curso, fatos da máquina; fatos `machine` +
   fatos do projeto da sessão, mais recentes primeiro, com quota de
   `MEMORY_PROFILE_MAX` chars e teto de `MEMORY_PROFILE_INJECT` fatos; loja
   vazia → sem seção) e o handoff da sessão anterior do mesmo projeto —
   apenas as seções Objective/Next Move, marcadas como *dados não confiáveis*
   (o corpo completo do resumo nunca entra no system prompt; use
   `memory.summaries` para ler). A memória persistente é **raw e
   determinística**: o texto injetado é 1:1 com a loja, sem passo de modelo
   no caminho de injeção — os fatos são mastigados no write. Junto ao bloco,
   o plugin injeta também uma pequena regra de *memory routing* — orientativa
   e **aditiva** (nunca substitui as instruções originais): consulte a
   memória antes de agir no mundo quando a pergunta já pode estar respondida
   nela, e persista fatos duráveis novos via `memory.profile`. Isso nunca é
   persistido — é recalculado a cada injeção.
3. **Permite busca cross-sessão.** Um índice derivado (SQLite FTS5, com
   fallback `LIKE` e, por último, JSON) guarda apenas texto de usuário, texto
   de assistente e resumos — nunca reasoning, nunca chamadas de tool. A busca
   é **híbrida**: além das palavras-chave (FTS5), uma camada semântica local
   (modelos de embedding rodando em CPU, sem daemon nem serviço remoto)
   encontra documentos por intenção, mesmo sem sobreposição de termos — e os
   dois rankings são fundidos por RRF. O backfill é preguiçoso e incremental:
   só acontece quando alguém busca, e só processa sessões/mensagens novas
   desde a última vez. `scope=all` busca o que já está indexado + todos os
   resumos em disco; para indexar todos os projetos manualmente, use
   `action=index-all` (ou `/index-all`).

   Resumos acompanham a sessão: quando uma sessão muda de projeto, os resumos
   dela são movidos do bucket antigo para o novo (consolidação lazy, no
   próximo contato da sessão — injeção ou backfill) — o handoff e a busca do
   novo projeto passam a ver o histórico completo, e os vetores são
   re-bucketeados junto (sem re-embed).

### Onde os dados ficam

```
$XDG_DATA_HOME/opencode/memory/
├── compactions/<projectID>/<timestampUTC>-<messageID>.md   # resumos, um por compactação
├── index.db          # índice FTS5 derivado + tabela `embeddings` (ou index.json sem SQLite)
├── profile.json      # memória persistente: fatos duráveis do mundo/usuário
└── embed-models/<model>/   # pesos dos modelos de embedding locais (baixados uma vez, com checagem de tamanho)
```

O diretório vive dentro da data dir do próprio OpenCode
(`~/.local/share/opencode/`) para ficar no mesmo volume gravável — em
ambientes onde a raiz XDG é read-only, os caminhos antigos
(`$XDG_DATA_HOME/agent-toolbelt` e `$XDG_DATA_HOME/opencode/agent-toolbelt`)
não aceitam escrita. Dados criados antes do renome são migrados uma única vez
pelo plugin ao iniciar (rename, ou cópia quando o diretório antigo é somente
leitura). O diretório é compartilhado com o banco do plugin `notes`
(`notes.db`) — tudo que é memória durável do agente mora aqui.

`projectID` é o identificador de projeto do próprio OpenCode
(`session.projectID`); sessões sem projeto caem em `global`. Nada é
versionado no repo nem escrito dentro dele.

### Busca semântica local (híbrida com o FTS5)

A consulta de `memory.search` roda dois rankings em paralelo e funde-os por
Reciprocal Rank Fusion (RRF, k=60). Cada resultado carrega a tag `via:`
indicando a camada que o achou: `fts` (só palavras-chave), `vec`
(só semântica) ou `fts+vec` (as duas).

- **Tudo local.** Os embeddings rodam na CPU desta máquina via
  `onnxruntime-node` (modelos ONNX quantizados) — sem daemon, sem API, sem
  rede por consulta. Os pesos são baixados uma única vez, com checagem de
  tamanho, em `embed-models/<model>/`.
- **Modelo padrão: `minilm-qint8`** (384 dim, multilíngue, int8, 235 MB).
  Em teste com resumos reais de compactação e consultas em PT sem sobreposição
  de termos, acertou o top-3 com margem clara e indexou 83 documentos em ~16 s.
  `e5-large-qint8` (1024 dim, 562 MB) fica disponível via
  `MEMORY_EMBED_MODEL=e5-large-qint8`: funciona, mas o export ONNX dele tem o
  espaço de scores comprimido (margem menor entre relevantes e irrelevantes)
  e é ~3× mais lento.
- **Multi-vetor por documento.** O texto é cortado em 4096 caracteres e
  dividido em chunks que cabem na janela do modelo; a pontuação do documento
  é o máximo cosseno entre seus chunks.
- **Lazy e incremental.** Os vetores são gerados em segundo plano após cada
  upsert (nunca bloqueiam a busca por palavras). Documentos inalterados (mesmo
  hash de conteúdo + mesmo modelo) são pulados. Trocar de modelo invalida os
  vetores antigos: rode `action=embed` de novo e os obsoletos são podados.
- **Degradação graciosa.** Se o engine não iniciar (addon nativo ausente,
  pesos incompletos, `MEMORY_EMBED_DISABLED=1`), a busca volta a ser só por
  palavras-chave e o resultado informa isso.

### Tools (read-only, exceto `memory.profile`; escopo de projeto por padrão)

| Tool | Para quê |
|---|---|
| `memory.summaries` | listar/buscar/ler resumos de compactação (`detail=brief\|full\|sections`) + estado do repo (`action=repo`) |
| `memory.search` | busca híbrida (FTS5 + semântica local, fundida por RRF; cada hit tagueado `via: fts\|vec\|fts+vec` **e com atribuição** `by: <agente> (<modelo>)` / `by: user`) no índice derivado (resumos + texto de usuário/assistente); `scope=project\|all`; `action=index-all` indexa todos os projetos manualmente (`rebuild=true` para rebuild completo); `action=embed` (re)constrói os vetores do escopo |
| `memory.history` | inspecionar a timeline completa de uma sessão (listar sessões, ler página, buscar, buscar uma mensagem; mensagens de assistente mostram `agent:` e `model:`); tool calls e reasoning só entram com `includeTools`/`includeReasoning` explícitos; sessões de outro projeto exigem `scope=all` |
| `memory.profile` | **memória persistente** (a única com escrita): `get` lista os fatos (machine + projeto atual; `all=true` para tudo), `set {value, scope?, id?}` persiste um fato verbatim (≤500 chars; com `id`, atualiza in-place) e `remove {id}` apaga. Scope: `machine` (padrão), `project` (projeto atual) ou `project:<name>`. Fatos têm ids estáveis e são injetados no início de toda sessão |

### Comandos

`/summaries`, `/summary [id] [brief|full|sections]`, `/sessions`, `/index`
(força reindex do projeto), `/index-all` (indexa todos os projetos;
`/index-all rebuild` para rebuild completo), `/repo` (mostra só o estado do
git) e `/recall <algo>` (busca forçada nas superfícies de memória: notas via
tools `notes.*` + índice de conversas; cada hit com sua fonte — nota #N ou
sessão + timestamp). Cada um é um atalho que chama as tools acima.

**Memória persistente** (escrita explícita do usuário): `/remember <fato>`
persiste o fato verbatim (scope opcional `machine:`, `project:` ou
`project:<name>`, padrão `machine`; deduplica via update in-place) e
`/forget <texto ou id>` remove o fato correspondente (ambíguo → lista com ids
para escolher).

### Variáveis de ambiente

| Variável | Efeito | Default |
|---|---|---|
| `MEMORY_DATA_DIR` | raiz de dados do plugin (sobrepõe XDG) | `$XDG_DATA_HOME/opencode/memory` |
| `MEMORY_SUMMARY_KEEP` | quantos resumos manter por projeto (os mais antigos são podados, do disco e do índice, quando um novo resumo é capturado — nunca na path de leitura) | `20` |
| `MEMORY_INJECT_MAX` | teto de bytes do bloco `<memory-context>` injetado | `~6 KB` |
| `MEMORY_PROFILE_INJECT` | quantos fatos da memória persistente injetar no `<memory-context>` (`0` desliga a seção) | `12` |
| `MEMORY_PROFILE_MAX` | quota de chars da seção de memória persistente | `3000` |
| `MEMORY_INDEX_TEXT_MAX` | teto de caracteres de texto indexado por documento | — |
| `MEMORY_BACKFILL_SESSIONS` | teto de sessões processadas por backfill | — |
| `MEMORY_BACKFILL_MESSAGES` | teto de mensagens processadas por sessão no backfill | — |
| `MEMORY_EMBED_MODEL` | modelo de embedding local da camada semântica (`minilm-qint8` ou `e5-large-qint8`); trocar o modelo invalida os vetores antigos | `minilm-qint8` |
| `MEMORY_EMBED_DISABLED` | `1` desliga a camada semântica (busca só por palavras-chave) | — |

### Privacidade e remoção

Tudo fica fora do repo, em `$XDG_DATA_HOME/opencode/memory/`
(permissões `0700`/`0600`). `./setup.sh --remove` remove só o symlink do
plugin — nunca apaga resumos nem o índice. Para apagar os dados **do plugin**
de fato (o `notes.db` é do plugin `notes` e fica fora desta limpeza):

```bash
rm -rf "${XDG_DATA_HOME:-$HOME/.local/share}/opencode/memory/compactions" \
       "${XDG_DATA_HOME:-$HOME/.local/share}/opencode/memory"/index.db*
```

Para desativar sem remover nada, apague o link
`~/.config/opencode/plugins/memory` (ou rode `./setup.sh --remove`) e
reinicie o OpenCode. O `--remove` só desvincula os symlinks do repo — o
submodule `plugins/memory` é parte do opencode-tools e permanece (use
`git submodule deinit plugins/memory` para removê-lo do working tree).

## Plugin: notes

Plugin (`plugins/notes/`, id `notes`; vendored como **git submodule** do repo
[opencode-notes](https://github.com/HitalloExiled/opencode-notes)) que expõe
as operações de memória como tools tipadas no namespace `notes`,
no mesmo padrão do plugin `memory` (`memory.*` / `notes.*`). O repo
`opencode-notes` também traz o **skill `notes`** (`skills/notes/SKILL.md` —
o contrato de uso da camada para os agentes), exposto por este repo via
symlink `~/.config/opencode/skills/notes/SKILL.md` (feito pelo `setup.sh` na
etapa de plugins):

- **Code Mode:** `tools.notes.add`, `tools.notes.search`, `tools.notes.confirm`,
  ... (12 tools) — o agente enxerga o grupo `notes` no catálogo e chama
  direto, sem sondar nomes.
- **Sessões regulares:** nomes efetivos `notes_add`, `notes_search`, ...
  (mesmos de antes do refactor) — as regras de permissão existentes
  (`resource: "notes_add"` etc. no `opencode.jsonc`) continuam valendo.

Mecânica: `Plugin.define` + `ctx.tool.transform` com `editor.namespace({name:
"notes"})` (só rotula o grupo no catálogo) e, por tool,
`options: { namespace: "notes" }` (é isto que prefixa o nome qualificado no
Code Mode). Os schemas de entrada são zod (o `input` do SDK aceita
StandardSchemaV1); cada tool retorna `{content, metadata}`.

As tools e o painel lateral são wrappers finos sobre `plugins/notes/src/store.ts`,
a única camada de dados: schema/FTS5/migrações embutidos, validação do formato
`#problem` (Sintoma/Causa/Solução obrigatórios) e nenhum comando destrutivo —
`retract` esconde, `restore` recupera versões; nada é apagado. O acesso ao
SQLite é feito in-process com o `node:sqlite` embutido (síncrono, FTS5), o
mesmo backend no processo Bun das tools e no processo principal do Electron;
não há CLI, subprocesso nem addon nativo.

Isolamento por camadas: o plugin `notes` não conhece a camada `memory` (e
vice-versa); o `/recall` do `memory` orienta o agente a usar as tools
`notes.*`, mantendo cada plugin standalone.

## Plugin: plans

Plugin (`plugins/plans/`, id `plans`; vendored como **git submodule** do repo
[opencode-plans](https://github.com/HitalloExiled/opencode-plans)) que persiste
planos do modo Plan e os expõe ao agente e ao usuário:

- **Tools:** `tools.plans.save`, `tools.plans.list`, `tools.plans.get`,
  `tools.plans.update`, `tools.plans.delete`, `tools.plans.doctor` no Code
  Mode; nomes efetivos `plans_*` em sessões regulares. `list`/`get` são
  **session-scoped** por padrão; `update`/`delete` recusam plano de outra
  sessão. `scope: "project"` no `list`/`get` é o opt-in para outras sessões.
- **Captura explícita:** o agente Plan é instruído a chamar `plans.save` ao
  apresentar um plano final; o usuário também pode usar `/save-plan` ou o
  botão **Salvar último plano** no painel. Não há captura automática.
- **Progresso:** `plans.update` marca passos como concluídos; o painel
  **Planos** lista por padrão só a **sessão ativa**. O toggle **Projeto** traz
  todos os planos do projeto e o botão **Mover para esta sessão** move um
  plano de outra sessão para a ativa. Cada alteração gera uma mensagem
  sintética na sessão, para o agente saber o que mudou.
- **Injeção:** agentes fora do Plan recebem um bloco curto com os planos
  ativos **da sessão atual** e os passos pendentes, para retomar trabalho sem
  misturar sessões paralelas.
- **Banco:** `~/.local/share/opencode/plans/plans.db` (override `$PLANS_DB`),
  acessado in-process com `node:sqlite`; a GUI fala com o plugin servidor via
  RPC, nunca abre o banco no renderer.

## Plugin: stats

Plugin (`plugins/stats/`, id `stats`; vendored como **git submodule** do repo
[opencode-stats](https://github.com/HitalloExiled/opencode-stats)) com duas
abas no painel lateral e uma faixa no cabeçalho da sessão:

- **Estatísticas:** gauge radial de tok/s (valor ao vivo com `~` e exato ao
  concluir o passo, com a média da sessão marcada no arco), gráfico de linha
  com o histórico (turno de 60s ou sessão por passo), reasoning (tokens, tempo
  e participação no output), tool calls (status/duração/argumento) e totais da
  sessão: tempo médio por resposta e por turno, tok/s médio/máximo, tokens,
  custo, ferramentas e modelos.
- **System prompt:** o `system` final do request, separado em **Fixo** (prompt
  base + `core/*`), **Adicionado** (`core/instructions`, AGENTS.md) e
  **Dinâmico** (`api/*` + blocos de `notes`, `memory` e `plans`). Tem filtro,
  busca, visão por fonte ou texto completo, copiar por parte, copiar tudo e
  salvar `.md`.
- **Faixa do cabeçalho:** `⚡ ~27.4 tok/s · 🕐 18.6s · 🧠 1.2k · 🔧 7 tools`,
  com clique para abrir a aba.

Mecânica: o servidor registra `ctx.session.hook("context")`, captura o array
`system` (com `metadata.experimental.instructions`, que traz as chaves
`core/instructions`, `api/<key>` etc.), guarda a última captura por sessão **em
memória** e a serve pela RPC `systemPrompt`. A GUI calcula as métricas a partir
de `session.server.data` e de `session.context` e desenha gauge/gráfico em SVG,
sem biblioteca de charts. Não há banco novo nem escrita no repositório.

Atalhos: `mod+shift+s` (Estatísticas) e `mod+shift+i` (System prompt); entradas
também no menu do painel da sessão.

## Desenvolvimento

```bash
git submodule update --init plugins/memory plugins/notes plugins/plans plugins/stats   # se o clone veio sem os submodules
npm install        # devDeps: typescript, @types/node, @opencode-ai/plugin, @opencode/plugin, @opencode/client, @opencode/schema, zod
npm run typecheck  # typecheck da raiz (types do plugin resolvem do node_modules da raiz)
npm test           # suites dos plugins (bun test, plugins/{memory,notes,plans,stats}/test)
```

Os plugins também se desenvolvem standalone nos repos
[opencode-memory](https://github.com/HitalloExiled/opencode-memory),
[opencode-notes](https://github.com/HitalloExiled/opencode-notes),
[opencode-plans](https://github.com/HitalloExiled/opencode-plans) e
[opencode-stats](https://github.com/HitalloExiled/opencode-stats)
(`npm install && npm run typecheck` lá); mudanças neles voltam para o
opencode-tools via `git submodule update` (commit do submodule atualizado no
repo pai). O `setup.sh` roda `npm install` dentro de cada plugin com
`package.json`, então o clone fresco fica pronto sem passo manual.

Smoke do store de notas sem tocar no banco real:

```bash
cd plugins/notes
cp ~/.local/share/opencode/memory/notes.db /tmp/notes-test.db
NOTES_DB=/tmp/notes-test.db bun -e 'import("./notes.ts").then(async (m) => console.log((await m.doctor.execute({})).content))'
```

Teste do `setup.sh` sem tocar na máquina:

```bash
./setup.sh --prefix /tmp/atb-test
```

## Adicionando um componente

1. Tool: crie `tools/<nome>.ts` exportando `tool({...})` (SDK antigo
   `@opencode-ai/plugin`; export nomeado vira `<nome>_<export>`) — ou, para
   ferramentas com namespace, um plugin `plugins/<ns>/` com `Plugin.define`
   (SDK novo `@opencode/plugin`) e `options: { namespace: "<ns>" }` por tool
   (fica `tools.<ns>.*` no Code Mode e `<ns>_<tool>` em sessões regulares).
   Rode `npm run typecheck`.
2. Skill: crie `skills/<id>/SKILL.md` com frontmatter `name`/`description`.
3. `./setup.sh` já linka tudo que estiver nessas pastas.
