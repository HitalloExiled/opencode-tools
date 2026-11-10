# Guideline de GUI dos plugins

Contrato visual e comportamental dos painéis laterais do OpenCode neste
repositório: `memory`, `notes`, `plans` e `stats`. Código comum vive em
[`shared/`](../shared) (`opencode-shared/gui`); o layout, os
dados e o texto de cada painel continuam no plugin.

> Regra de ouro: **parecer o app**. Controles do host (`ctx.ui.*`), tokens do
> tema (`--v2-*`), mesma tipografia, mesma densidade. Identidade de um painel é
> o layout, não a cor.

## 1. Princípios

1. **Host primeiro.** Botão, ícone, tooltip, menu, loader, diálogo e campo vêm
   de `ctx.ui.*`. O tema, a fonte e o idioma do usuário valem de graça.
2. **Um padrão por problema.** Um cabeçalho, um cartão, um chip, um vazio, um
   erro, um loading, um jeito de rolar.
3. **Só tokens que existem.** A lista canônica é
   `packages/ui/src/styles/tokens/theme.css` do OpenCode. Token inexistente cai
   no fallback e quebra um dos temas.
4. **Sem `!important`**, sem estilo inline (exceto geometria de gráfico), sem
   classe global sem prefixo.
5. **Código comum vai para `shared/`.** Nunca copie componente entre plugins.

## 2. Tokens

| Uso | Token |
|---|---|
| Texto principal / secundário / dica | `--v2-text-text-base` / `-muted` / `-faint` |
| Superfície de cartão | `--v2-background-bg-layer-02` |
| Superfície interna (dentro do cartão) | `--v2-background-bg-layer-01` |
| Trilho / barra vazia | `--v2-background-bg-layer-03` |
| Borda fina / hover / foco | `--v2-border-border-muted` / `-strong` / `-focus` |
| Hover de linha / pressionado | `--v2-overlay-simple-overlay-hover` / `-pressed` |
| Flutuante (popover, botões de scroll) | `--v2-elevation-raised` |
| Backdrop de overlay | `--v2-overlay-simple-overlay-scrim` |
| Destaque | `--v2-icon-icon-accent` / `--v2-text-text-accent` |
| Sucesso / info / alerta / erro | `--v2-state-{fg,bg,border}-{success,info,warning,danger}` |
| Fonte | `--font-family-sans` / `--font-family-code` |

Mapa semântico fixo: `info` = ativo/rodando · `success` = concluído/verificado ·
`warning` = pausado/arquivado · `danger` = erro/retratado · `pressed + muted` =
neutro/substituído.

**Proibido:** `--v2-text-text-danger/success/warning/info`,
`--v2-background-bg-danger/warning`, `--v2-border-border-danger` (não existem);
hex cru fora das séries de gráfico declaradas no root do painel.

## 3. Escala

| Item | Valor |
|---|---|
| Fonte raiz | `12.5px / 1.5`, `--font-family-sans` |
| Título do painel (h2) | `13px / 600` |
| Título de seção/cartão (h3) | `12px / 600` |
| Corpo | `12.5px` |
| Meta | `11px` muted |
| Micro/rótulo caps | `10px / 600`, `letter-spacing .05em`, faint |
| Espaço | 4 / 6 / 8 / 10 / 12 (cartão 8, ações 6, seções 10–12) |
| Raio | cartão 8 · controle 6 · interno 4 · pill 999 · overlay 8 |
| Altura de controle | 24 small · 28 normal · 32 large |
| Padding de cartão | `9–10px 10–12px` |
| Foco | `outline: 2px solid var(--v2-border-border-focus)`; offset `2.5px` em botões, `0`/`-2px` em linhas e no container |
| Transição | `120–150ms ease` |

## 4. Estrutura do painel

```
.<prefixo>-root          flex column, height 100%, padding 12, gap 8
├── header                fixo (título + contagem + spacer + ações)
├── .<prefixo>-body       position: relative, flex: 1, min-height: 0
│   ├── .<prefixo>-scroll flex: 1, overflow-y: auto, class "os-scroll"
│   │   └── conteúdo…
│   └── <ScrollNav />     botões flutuantes (shared)
```

- A raiz **não rola**; só o container interno.
- `box-sizing: border-box` em tudo que tem padding.
- Nunca pinte o fundo do painel: o host fornece a superfície.
- Scrollbar fina e foco visível vêm de `.os-scroll` (shared).

## 5. Cabeçalho

Uma forma só: `[ícone] título (13/600) · contagem/meta (11 muted) → spacer →
ações (ghost small)`. Sem título duplicado no corpo.

## 6. Cartões e listas

```css
.<p>-card {
  border: 1px solid var(--v2-border-border-muted);
  background: var(--v2-background-bg-layer-02);
  border-radius: 8px;
  padding: 9px 10px;
  display: flex; flex-direction: column; gap: 4px;
}
.<p>-card:hover { border-color: var(--v2-border-border-strong); } /* só se clicável */
```

Lista em coluna com `gap: 8px`. Grupo com cabeçalho em caps 10.5/600 muted.

## 7. Chips

Use `StatusChip` do shared (`neutral | info | success | warning | danger`).
Pill 999, `padding: 1px 6px`, `10.5px / 600`, cores de `--v2-state-*`. Nunca use
o mesmo token do fundo do cartão para a tag.

## 8. Botões e ações

| Situação | Componente |
|---|---|
| Ação principal / submit | `ctx.ui.Button variant="contrast"` |
| Ação comum | `ctx.ui.Button variant="neutral"` |
| Toolbar / inline | `ctx.ui.Button variant="ghost" size="small"` |
| Secundária / densa | `variant="ghost-muted"` |
| Destrutiva | `variant="danger"` + `ctx.dialogs.confirm({ danger: true })` |
| Só ícone | `ctx.ui.IconButton` + `Tooltip` + `label` |
| 3+ ações de linha | `ctx.ui.Menu` ("…") com itens icônicos |

- Ícone destrutivo isolado: `IconButton` + classe `is-danger` (hover com
  `--v2-state-fg-danger`) definida uma vez no CSS do painel.
- `<button>` cru só para estrutura (linha/cartão, segmented control, step
  toggle); nunca para uma ação com texto.

## 9. Inputs

`ctx.ui.TextInput` para uma linha. `textarea`/`select` crus seguem a métrica:
raio 6, `bg-layer-01`, borda muted, `--font-family-code` para conteúdo técnico,
foco de 2px. `select option` precisa de `background`/`color` (Linux pinta
branco).

## 10. Estados

Use os componentes do shared:

- `EmptyState` — ícone opcional + título + dica; centralizado, `24px 10px`.
- `ErrorBanner` — `role="alert"`, tokens `danger`, `retry` opcional.
- `LoadingRow` — `ctx.ui.Loader size="small"` + texto.
- `EndMarker` — "Fim", 10px faint.

Erro da primeira carga = banner no lugar da lista. Erro ao carregar mais = banner
inline no fim, **sem** descartar o que já carregou.

## 11. Scroll e listas

### 11.1 Scroll infinito (todas as listas)

| Superfície | Chunk |
|---|---|
| Notas, planos, sessões | 20 |
| Conversa (memory) | 40 |

- `createScrollNav({ hasMore, loadingMore, loadMore, visible, items })` do
  shared; `nav.ref` no container, `nav.sentinelRef` no sentinel, `nav.onKeyDown`
  no container.
- Sentinela + `IntersectionObserver` (`root` = container, `rootMargin` 200px) +
  safety net em `requestAnimationFrame` para listas menores que a viewport.
- Não carregar com o painel invisível (`usePanel().visible()`) ou o documento
  oculto.
- Se um chunk não adicionar itens, pare e mostre o fim (sem loop).
- Filtro/query/escopo/sessão mudou → limpa, volta ao topo e busca o chunk 0.
- Atualização comum de dados não mexe na posição do scroll.
- Fim da lista: `LoadingRow` ao anexar, `ErrorBanner` + retry no erro, `EndMarker`
  quando acabou.

### 11.2 Navegação

- `ScrollNav` renderiza o par "ao topo"/"ao fim" no canto inferior direito, com
  Tooltip mostrando `Home`/`End`.
- Container: `tabIndex={nav.scrollable() ? 0 : undefined}`, `role="region"`,
  `aria-label` traduzido, classe `os-scroll`.
- Teclado: `Home` topo · `End` fim (+ próximo chunk) · `PageUp`/`PageDown` uma
  tela menos 48px. Ignorar eventos com `alt/ctrl/meta`, com `defaultPrevented`
  ou com alvo editável (`input`, `textarea`, `select`, `contenteditable`,
  `role=textbox`). `preventDefault` só quando o container rola.
- Botões com `smooth`; teclas instantâneas; `prefers-reduced-motion: reduce`
  desliga a animação.

## 12. Overlays e feedback

| Necessidade | Mecanismo |
|---|---|
| Confirmar destrutivo | `ctx.dialogs.confirm` com `danger: true` |
| Pedir texto | `ctx.dialogs.prompt` |
| Formulário simples | `ctx.dialogs.open` + `ctx.ui.Dialog` |
| Formulário complexo | overlay próprio: scrim token, raio 8, `--v2-elevation-raised`, `max-height: calc(100% - 28px)` |
| Resultado de ação | `ctx.toast.show({ title, description, variant })` |
| Trabalho > 2s | toast `loading` + `persistent`, dismiss ao terminar |

Nunca `alert()`.

## 13. Ícones

| Plugin | Ícone (menu/mobile) |
|---|---|
| Memory | `brain` |
| Notes | `pencil-line` |
| Plans | `checklist` |
| Stats | `window-analytics` |
| System prompt | `prompt` |

- Só nomes do catálogo (`icon-name.d.ts`); tamanho via `ctx.ui.Icon`.
- `<svg>` à mão só em gauge/chart.
- Aba no strip é texto puro; ícone vai em menu/mobile.

## 14. Contrato da Panel

Registre com `registerSidePanel` do shared (ou `createPanelTab` para abas
extras):

- `list` filtra por `input.open` (nunca liste sempre);
- `mobile` no More menu; `closed` para "Reabrir aba fechada";
- `closable: "compact"` na aba;
- `render` keyed por `props.session.key`;
- **`fallback: false`** em todos (o app decide a aba padrão);
- command id `open-<id>`, getters para o locale; menu `session.panel` com
  `order` 40+.

| Plugin | Aba | Ordem no menu | Atalho |
|---|---|---|---|
| memory | `memory` | 40 | `mod+shift+m` |
| notes | `notes` | 41 | `mod+shift+n` |
| plans | `plans` | 42 | — (o `p` é da paleta) |
| stats | `stats` | 43 | `mod+shift+s` |
| stats (prompt) | `prompt` | 44 | `mod+shift+i` |

Plugin novo reserva a letra nesta tabela antes de usar.

## 15. i18n

- `createI18n(en, pt)` do shared; EN é a fonte e o fallback, PT é
  `Record<keyof typeof EN, string>` (chave faltando quebra o typecheck).
- Zero string visível fora da tabela, incluindo `por/by`, "nada/none" e
  mensagens de `throw`.
- Placeholders `{0}`, `{1}`.
- No `setup` não existe `usePlugin()`: use `ctx.locale.locale()` e getters, ou
  `registerSidePanel` (que já é reativo).
- Números/datas com `Intl` (`useI18nTag` + `formatNumber`/`formatDate`).

## 16. Acessibilidade

- Todo controle só-ícone tem `label`/`aria-label` + Tooltip.
- Todo interativo tem `:focus-visible`.
- Popover fecha com Escape e clique fora; listbox próprio segue
  combobox/listbox.
- Lista em `role="region"` com nome; mudança de estado em `aria-live` quando
  fizer sentido.
- Status nunca só por cor: sempre cor + rótulo/ícone.

## 17. CSS

- Uma `<style>` por plugin, todas as classes com o prefixo do painel
  (`memory-`, `notes-`, `plans-`, `stats-`, `prompt-`). Componentes do shared
  usam `os-`.
- Renderize `SHARED_CSS` uma vez no root do painel.
- Sem seletor genérico (`.form`, `.empty`, `.actions`, `.tag`): `<style>` é
  global e vaza para o app.
- Sem `!important`; sem inline, exceto geometria dinâmica.

## 18. Código compartilhado

```ts
import { SHARED_CSS, createScrollNav, ScrollNav, EmptyState, ErrorBanner,
         LoadingRow, EndMarker, StatusChip, createI18n, registerSidePanel }
  from "opencode-shared/gui";
```

- Declare no `package.json`:
  `"opencode-shared": "github:HitalloExiled/opencode-shared#<sha>"`.
- Proibido import relativo para `shared/`.
- `setup.sh` faz `npm link` do working tree em cada plugin.
- Dev loop: editar `shared/src` → `npm run build` (ou `npm run dev`) no shared →
  `npm run gui:build` no plugin.
- `dist/` do shared é versionado (install por git sem toolchain).

### Nomes de pacote (restrição do host)

Plugin local precisa de `name` **sem escopo** (`opencode-notes`, não
`@scope/opencode-notes`): o OpenCode 2.2.7 não descobre um diretório em
`plugins/` cujo `package.json` tenha nome escopado — o plugin some do
inventário do servidor e o GUI não carrega. Por isso o pacote compartilhado
também é `opencode-shared`. Revisar se o host passar a aceitar nomes escopados.

## 19. Protocolo de commit (três níveis)

1. `shared`: commit + push (+ tag quando a API muda).
2. Cada plugin afetado: bump do SHA + lock → commit + push.
3. `opencode-tools`: ponteiros (`shared` + plugins) + docs → commit + push.

O ponteiro `shared/` do pai e os SHAs dos plugins devem apontar para o mesmo
commit.

## 20. Checklist de PR

- [ ] Cores só de tokens existentes; status com `--v2-state-*`.
- [ ] Controles do host; nenhuma ação de texto em `<button>` cru.
- [ ] Raiz sem scroll; um container `os-scroll`; `ScrollNav` presente.
- [ ] Lista com scroll infinito, sentinela, fim/erro/retry.
- [ ] Teclado Home/End/PageUp/PageDown com guarda de editáveis.
- [ ] Vazio/erro/loading com os componentes do shared.
- [ ] Toda string em `i18n` (PT + EN).
- [ ] Classes prefixadas; `SHARED_CSS` renderizado uma vez.
- [ ] `Panel` com `mobile`, `closed`, `list(open)`, render keyed, sem `fallback`.
- [ ] `npm run typecheck:gui` + `npm run gui:build` limpos; reload sem erro no log.
- [ ] Commits na ordem shared → plugins → pai.
