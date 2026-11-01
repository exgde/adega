# Fase 0 — prova de conceito no seu Mac

Objetivo: descobrir, em 1–2 semanas e **antes** de investir no app, se os programas e jogos que você quer rodam bem com os builds open source do Wine no seu hardware. Se não rodarem aqui, não vão rodar no app.

## 1. Preparar o Mac

```bash
softwareupdate --install-rosetta --agree-to-license
```

```bash
brew install --cask gcenx/wine/wine-crossover
```

```bash
brew install cabextract winetricks
```

O build `wine-crossover` do Gcenx é feito a partir do código-fonte que a CodeWeavers publica. Se o macOS bloquear o app por ser de desenvolvedor não identificado, rode:

```bash
xattr -dr com.apple.quarantine "/Applications/Wine Crossover.app"
```

Confira as instruções atuais no repositório do Gcenx, porque os nomes dos pacotes podem mudar.

## 2. Testar só com o Wine (sem o Adega)

```bash
export PATH="/Applications/Wine Crossover.app/Contents/Resources/wine/bin:$PATH"
```

```bash
export WINEPREFIX="$HOME/wine-teste" WINEMSYNC=1
```

```bash
wine wineboot --init
```

```bash
wine ~/Downloads/SteamSetup.exe
```

No Wine 9 ou mais novo o executável é `wine`; em builds antigos pode ser `wine64`.

## 3. Testar com a CLI do Adega

```bash
swift build -c release --package-path Core
```

```bash
alias adega="$PWD/Core/.build/release/adega"
```

```bash
adega doctor
```

```bash
adega runtime add "Wine Crossover" "/Applications/Wine Crossover.app" --copy
```

```bash
adega bottle create Teste --windows win10
```

```bash
adega run --bottle Teste --wait ~/Downloads/SteamSetup.exe
```

```bash
adega programs --bottle Teste
```

```bash
adega logs --bottle Teste --last
```

## 4. Testar os backends gráficos

Rode um jogo DX11 com cada backend e anote FPS e estabilidade. Ligue o HUD com `--hud on`.

| Backend | Como preparar |
|---|---|
| WineD3D | nada a fazer: `adega bottle set Teste --backend wined3d` |
| DXMT | baixe o release do DXMT, ajuste a entrada em `manifests/runtimes.example.json`, depois `adega component install <id> --manifest <arquivo>` e `--backend dxmt` |
| DXVK | o mesmo processo, com o release do DXVK-macOS |
| D3DMetal | baixe o Game Porting Toolkit (developer.apple.com/games), monte o DMG, depois `adega component add-d3dmetal "/Volumes/Evaluation environment for Windows games…"` e `--backend d3dmetal` |

O D3DMetal funciona melhor com a versão do Wine para a qual o GPTK foi feito. Se der problema, teste o pacote `game-porting-toolkit` do Gcenx como runtime.

## 5. O que anotar

- Para cada jogo ou app: abriu? FPS médio? travou? qual backend foi melhor?
- O que precisou de winetricks (vcrun2022, dotnet48…).
- Essa planilha vira as suas primeiras **receitas** (`presets.json`), que são o diferencial do produto.

**Critério para seguir para a Fase 1:** a maioria dos programas da sua lista-alvo roda de forma aceitável.
