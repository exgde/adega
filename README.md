# Adega

Gerenciador de **bottles** do Wine para macOS: roda programas do Windows em ambientes isolados, usando Wine e as camadas gráficas DXMT, DXVK+MoltenVK ou D3DMetal. É a mesma ideia do CrossOver, mas o Adega **não** reimplementa o Wine: ele é o app que baixa, configura e executa builds open source do Wine.

> "Adega" é um nome provisório. Troque à vontade (não use "CrossOver" nem nomes parecidos).

## Status

| Parte | Estado |
|---|---|
| `Core/` — biblioteca `AdegaCore` (runtimes, bottles, componentes, execução, winetricks, atalhos, receitas) | ✅ compila; 26 testes passando (unitários + integração com um Wine falso) |
| `Core/` — CLI `adega` | ✅ testada de ponta a ponta com o Wine falso |
| `App/` — app SwiftUI (macOS 14+) | ⚠️ escrito, mas ainda **não compilado**. Foi feito num ambiente Linux sem Xcode. O CI do GitHub Actions (macOS) compila; o primeiro build no Mac pode exigir pequenos ajustes |
| Teste com o Wine real | ⏳ falta — ver [docs/FASE0.md](docs/FASE0.md) |

## Estrutura

```
Core/                       Swift Package (compila em macOS e Linux)
  Sources/AdegaCore/
    Models/                 Bottle, runtime, componente, receita, backend gráfico
    Services/               RuntimeManager, BottleManager, ComponentManager, Launcher,
                            Wine, WineEnvironment, Winetricks, ProgramDiscovery,
                            ShortcutBuilder, ManifestLoader
    Support/                ProcessRunner, Downloader, SHA-256, operações de arquivo
  Sources/adega/            CLI
  Tests/AdegaCoreTests/
App/                        App SwiftUI (só macOS)
project.yml                 Projeto Xcode via XcodeGen
manifests/                  Exemplo de catálogo de runtimes/componentes
presets/                    Exemplo de receitas por jogo/app
scripts/manifest-entry.sh   Gera entradas do catálogo (sha256 + tamanho)
docs/FASE0.md               Prova de conceito no seu Mac
```

## Como funciona

- **Runtime**: um build do Wine, guardado em `~/Library/Application Support/Adega/Runtimes/<id>/`. Há dois jeitos de obter um:
  - baixar do catálogo (`runtimes.json`), com o SHA-256 conferido;
  - registrar um Wine já instalado, como o `Wine Crossover.app` do Homebrew. Com `--copy` ele é copiado para dentro do Adega.
- **Bottle**: um `WINEPREFIX`, com o próprio `drive_c` e registro, mais um `bottle.json`. Ficam em `Bottles/<nome>/`.
- **Backend gráfico**: definido a cada execução via `WINEDLLOVERRIDES`. Por isso trocar de backend é instantâneo e DLLs que sobram de outro backend não atrapalham.
  - `wined3d`: embutido no Wine (OpenGL).
  - `dxvk`: DXVK + MoltenVK.
  - `dxmt`: DX10/11 → Metal.
  - `d3dmetal`: Apple GPTK, DX11/12 → Metal.
- **Componentes**: pacotes descritos no catálogo, com um mapa `origem → destino` para o runtime ou para a bottle. Quando o layout de um release mudar, basta atualizar o JSON, sem mexer no código.
- **D3DMetal**: o usuário importa da **própria** cópia do Game Porting Toolkit. O Adega nunca redistribui esses arquivos, porque a licença da Apple é restritiva.
- **Logs**: um arquivo por execução em `Logs/<bottle>/`, com o comando e as variáveis usadas.
- **Atalhos**: gera um `.app` em `~/Applications/Adega/`. Ele chama o próprio Adega com `--adega-run`, então mudanças na bottle valem também para atalhos antigos.
- **Receitas**: JSON por executável, com backend, versão do Windows, variáveis e dependências do winetricks. **É aqui que fica o valor do produto**: um catálogo curado e testado.

## Compilar no Mac

Requisitos: macOS 14+, Xcode 15+ e Homebrew.

```bash
brew install xcodegen cabextract
```

```bash
swift test --package-path Core
```

```bash
xcodegen generate && open Adega.xcodeproj
```

No Xcode: escolha o esquema **Adega** e dê Run (⌘R). A assinatura padrão é ad-hoc ("-"), que roda localmente sem conta da Apple.

## CLI

```bash
swift build -c release --package-path Core && cp Core/.build/release/adega /usr/local/bin/
```

```bash
adega runtime add "Wine Crossover" "/Applications/Wine Crossover.app" --copy
```

```bash
adega bottle create Steam --windows win10
```

```bash
adega run --bottle Steam ~/Downloads/SteamSetup.exe
```

```bash
adega programs --bottle Steam
```

```bash
adega bottle set Steam --backend dxmt --hud on
```

```bash
adega logs --bottle Steam --last
```

Use `adega help` para ver todos os comandos. A variável `ADEGA_HOME` muda a pasta de dados, útil para testes.

## Catálogo próprio (sem servidor)

1. Gere ou baixe os builds do Wine e os componentes, e publique os `.tar.xz` em **GitHub Releases** (grátis).
2. Gere cada entrada com `scripts/manifest-entry.sh` e monte o `runtimes.json` seguindo `manifests/runtimes.example.json`.
3. Publique o `runtimes.json` e o `presets.json` no **GitHub Pages** (ou use os links "raw").
4. No app, em Ajustes (⌘,), aponte para essas URLs. Na CLI: `adega settings --manifest <url> --presets <url>`.

## Checklist legal antes de vender

- [ ] Nome e ícone próprios (sem "CrossOver" ou marcas parecidas, sem logos do Windows).
- [ ] Wine é LGPL 2.1: publique o código-fonte de qualquer build ou modificação do Wine que você distribuir. O app Swift pode continuar fechado.
- [ ] Inclua a tela e o arquivo de licenças de terceiros (Wine, DXVK, DXMT, MoltenVK, winetricks).
- [ ] **Não** empacote o D3DMetal (fica como está: importação pelo usuário).
- [ ] **Não** empacote redistribuíveis da Microsoft (o winetricks baixa das fontes oficiais).
- [ ] Deixe claro que jogos com anti-cheat (EAC, BattlEye, Vanguard etc.) normalmente não funcionam.

## Próximos passos

1. **Fase 0** ([docs/FASE0.md](docs/FASE0.md)): validar no seu Mac com o Wine real e os seus jogos.
2. Primeiro build do app no Xcode e correção do que o compilador apontar.
3. Assinatura com Developer ID, notarização (`notarytool`) e Sparkle para atualizações.
4. Licenciamento: trial + chave (Lemon Squeezy ou Paddle), com validação offline em cache.
5. Pipeline próprio de build do Wine (GitHub Actions macOS) a partir do código-fonte do CrossOver ou do Wine.
6. Ícones dos programas (extrair do .exe), empacotar o `cabextract`, tela de licenças de terceiros.
7. Acompanhar o Rosetta 2: a Apple anunciou que o Rosetta completo vai até o macOS 27.
