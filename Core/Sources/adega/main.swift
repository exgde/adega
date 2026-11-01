import AdegaCore
import Foundation

let usage = """
adega — gerenciador de bottles do Wine para macOS

USO
  adega <comando> [opções]

RUNTIMES (builds do Wine)
  runtime list
  runtime available [--manifest <url|arquivo>]
  runtime install <id> [--manifest <url|arquivo>]
  runtime add <nome> <caminho> [--copy] [--version <v>]
        <caminho>: pasta do Wine, a pasta bin/ ou um .app (ex.: "/Applications/Wine Crossover.app")
        --copy: copia para dentro do Adega (necessário para instalar DXMT/D3DMetal no runtime)
  runtime remove <id>

BOTTLES
  bottle list
  bottle create <nome> --runtime <id> [--windows win10] [--backend wined3d|dxvk|dxmt|d3dmetal] [--retina]
  bottle info <bottle>
  bottle set <bottle> [--backend X] [--windows X] [--msync on|off] [--retina on|off]
                      [--hud on|off] [--avx on|off] [--env CHAVE=VALOR]... [--unset-env CHAVE]...
                      [--dll nome=modo]... [--unset-dll nome]...
  bottle preset <bottle> <id-da-receita> [--presets <url|arquivo>]
  bottle delete <bottle> --yes

COMPONENTES GRÁFICOS
  component list
  component available [--manifest <url|arquivo>]
  component install <id> [--manifest <url|arquivo>]
  component add-d3dmetal <pasta-do-GPTK> [--version <v>]
  component remove <id>

PROGRAMAS
  run --bottle <bottle> [--wait] <programa.exe|.msi|.bat|.lnk> [argumentos...]
  programs --bottle <bottle>
  winetricks --bottle <bottle> <verbo>...        (ex.: vcrun2022 corefonts)
  shortcut --bottle <bottle> [--name <nome>] <programa>
  kill --bottle <bottle>
  logs --bottle <bottle> [--last]

OUTROS
  settings [--manifest <url>] [--presets <url>]
  doctor

Dados em: \(AdegaPaths.default.root.path)  (mude com ADEGA_HOME)
"""

let paths = AdegaPaths.default
let runner = SystemProcessRunner()
let downloader = URLSessionDownloader()
let runtimes = RuntimeManager(paths: paths, downloader: downloader, runner: runner)
let bottles = BottleManager(paths: paths, runner: runner)
let components = ComponentManager(paths: paths, downloader: downloader, runner: runner)
let launcher = Launcher(paths: paths, runner: runner)

func printError(_ message: String) {
    FileHandle.standardError.write(Data("erro: \(message)\n".utf8))
}

let progressPrinter: @Sendable (Double) -> Void = { fraction in
    let percent = Int((fraction * 100).rounded())
    FileHandle.standardOutput.write(Data("\r  baixando… \(percent)%   ".utf8))
    if fraction >= 1 { FileHandle.standardOutput.write(Data("\n".utf8)) }
}

func manifest(_ args: Arguments) async throws -> RuntimeManifest {
    let location = args.value("manifest") ?? AppSettings.load(paths: paths).manifestURL
    guard !location.isEmpty else {
        throw CLIError("informe --manifest <url|arquivo> ou configure com: adega settings --manifest <url>")
    }
    return try await ManifestLoader.loadRuntimeManifest(from: location, downloader: downloader, paths: paths)
}

func describe(_ runtime: InstalledRuntime) -> String {
    let kind = runtime.isExternal ? "externo" : "gerenciado"
    let extras = runtime.runtimeComponents.isEmpty ? "" : "  componentes: " + runtime.runtimeComponents.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
    return "\(runtime.id)  [\(runtime.version), \(kind)]  \(runtime.wineRootPath)\(extras)"
}

func describe(_ bottle: Bottle) -> String {
    let c = bottle.config
    return """
    \(c.displayName)  (id: \(bottle.id))
      pasta:     \(bottle.url.path)
      runtime:   \(c.runtimeID)
      windows:   \(c.windowsVersion.displayName)
      gráficos:  \(c.graphicsBackend.displayName)
      msync: \(c.msync ? "on" : "off")  retina: \(c.retinaMode ? "on" : "off")  hud: \(c.performanceHUD ? "on" : "off")  avx: \(c.advertiseAVX ? "on" : "off")
      env:       \(c.environment.isEmpty ? "—" : c.environment.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))
      dll:       \(c.dllOverrides.isEmpty ? "—" : WineEnvironment.formatOverrides(c.dllOverrides))
    """
}

func parseBackend(_ raw: String?) throws -> GraphicsBackend? {
    guard let raw else { return nil }
    guard let backend = GraphicsBackend(rawValue: raw.lowercased()) else {
        throw CLIError("backend inválido: \(raw) (use \(GraphicsBackend.allCases.map(\.rawValue).joined(separator: ", ")))")
    }
    return backend
}

func parseWindows(_ raw: String?) throws -> WindowsVersion? {
    guard let raw else { return nil }
    guard let version = WindowsVersion(rawValue: raw.lowercased()) else {
        throw CLIError("versão do Windows inválida: \(raw) (use \(WindowsVersion.allCases.map(\.rawValue).joined(separator: ", ")))")
    }
    return version
}

func keyValue(_ raw: String) throws -> (String, String) {
    guard let eq = raw.firstIndex(of: "="), eq != raw.startIndex else { throw CLIError("esperado CHAVE=VALOR, recebido: \(raw)") }
    return (String(raw[..<eq]), String(raw[raw.index(after: eq)...]))
}

/// Instala os arquivos do backend escolhido (se precisar) e avisa quando falta componente.
func prepareBackend(for bottle: Bottle) throws {
    let runtime = try runtimes.runtime(id: bottle.config.runtimeID)
    try components.prepareBackend(bottle.config.graphicsBackend, bottle: bottle, runtime: runtime, runtimeManager: runtimes)
}

// MARK: - Comandos

func runtimeCommand(_ argv: [String]) async throws {
    let args = try Arguments(argv, valueOptions: ["manifest", "version"])
    switch args.positional.first {
    case "list", nil:
        let list = runtimes.installedRuntimes()
        if list.isEmpty { print("Nenhum runtime. Use 'adega runtime add' ou 'adega runtime install'.") }
        list.forEach { print(describe($0)) }
    case "available":
        for r in try await manifest(args).runtimes {
            print("\(r.id)  \(r.displayName) [\(r.version)]\(r.notes.map { " — \($0)" } ?? "")")
        }
    case "install":
        let id = try args.positional(1, "id")
        guard let descriptor = try await manifest(args).runtimes.first(where: { $0.id == id }) else {
            throw CLIError("runtime \(id) não está no manifesto")
        }
        let runtime = try await runtimes.install(descriptor, progress: progressPrinter)
        print("Instalado: \(describe(runtime))")
    case "add":
        let name = try args.positional(1, "nome")
        let location = URL(fileURLWithPath: (try args.positional(2, "caminho") as NSString).expandingTildeInPath)
        var runtime = try await runtimes.registerExternal(name: name, location: location, version: args.value("version") ?? "externo", copy: args.has("copy"))
        if args.value("version") == nil, let detected = await runtimes.detectVersion(of: runtime) {
            runtime.version = detected
            try runtimes.save(runtime)
        }
        print("Registrado: \(describe(runtime))")
    case "remove":
        let id = try args.positional(1, "id")
        let users = bottles.bottles(using: id)
        if !users.isEmpty, !args.has("force") {
            throw CLIError("o runtime é usado por: \(users.map(\.config.displayName).joined(separator: ", ")). Use --force para remover mesmo assim.")
        }
        try runtimes.remove(id: id)
        print("Removido: \(id)")
    case let other?:
        throw CLIError("subcomando desconhecido: runtime \(other)")
    }
}

func bottleCommand(_ argv: [String]) async throws {
    let args = try Arguments(argv, valueOptions: ["runtime", "windows", "backend", "msync", "retina", "hud", "avx", "env", "unset-env", "dll", "unset-dll", "presets"])
    switch args.positional.first {
    case "list", nil:
        let list = bottles.bottles()
        if list.isEmpty { print("Nenhuma bottle. Crie com: adega bottle create <nome> --runtime <id>") }
        for b in list {
            print("\(b.config.displayName)  [\(b.config.graphicsBackend.rawValue), \(b.config.windowsVersion.rawValue), runtime: \(b.config.runtimeID)]")
        }
    case "create":
        let name = try args.positional(1, "nome")
        guard let runtimeID = args.value("runtime") ?? runtimes.installedRuntimes().first?.id else {
            throw AdegaError.runtimeNotFound("(nenhum)")
        }
        let runtime = try runtimes.runtime(id: runtimeID)
        var config = BottleConfig(displayName: name, runtimeID: runtime.id)
        if let windows = try parseWindows(args.value("windows")) { config.windowsVersion = windows }
        if let backend = try parseBackend(args.value("backend")) { config.graphicsBackend = backend }
        config.retinaMode = args.has("retina")
        print("Criando bottle \"\(name)\" (wineboot pode levar alguns segundos)…")
        let bottle = try await bottles.create(name: name, config: config, runtime: runtime)
        do {
            try prepareBackend(for: bottle)
        } catch {
            printError("bottle criada, mas o backend \(config.graphicsBackend.displayName) não pôde ser preparado: \(error.localizedDescription)")
        }
        print(describe(bottle))
    case "info":
        print(describe(try bottles.find(try args.positional(1, "bottle"))))
    case "set":
        var bottle = try bottles.find(try args.positional(1, "bottle"))
        let previous = bottle.config
        if let backend = try parseBackend(args.value("backend")) { bottle.config.graphicsBackend = backend }
        if let windows = try parseWindows(args.value("windows")) { bottle.config.windowsVersion = windows }
        if let msync = try args.bool("msync") { bottle.config.msync = msync }
        if let retina = try args.bool("retina") { bottle.config.retinaMode = retina }
        if let hud = try args.bool("hud") { bottle.config.performanceHUD = hud }
        if let avx = try args.bool("avx") { bottle.config.advertiseAVX = avx }
        for pair in args.values("env") { let (k, v) = try keyValue(pair); bottle.config.environment[k] = v }
        for key in args.values("unset-env") { bottle.config.environment.removeValue(forKey: key) }
        for pair in args.values("dll") { let (k, v) = try keyValue(pair); bottle.config.dllOverrides[k] = v }
        for key in args.values("unset-dll") { bottle.config.dllOverrides.removeValue(forKey: key) }
        try await apply(bottle, previous: previous)
        print(describe(bottle))
    case "preset":
        var bottle = try bottles.find(try args.positional(1, "bottle"))
        let presetID = try args.positional(2, "id-da-receita")
        let location = args.value("presets") ?? AppSettings.load(paths: paths).presetsURL
        guard !location.isEmpty else { throw CLIError("informe --presets <url|arquivo> ou configure com: adega settings --presets <url>") }
        let catalog = try await ManifestLoader.loadPresets(from: location, downloader: downloader, paths: paths)
        guard let preset = catalog.presets.first(where: { $0.id == presetID }) else { throw CLIError("receita \(presetID) não encontrada") }
        let previous = bottle.config
        bottle.config = preset.applied(to: bottle.config)
        try await apply(bottle, previous: previous)
        if !preset.winetricks.isEmpty {
            print("Instalando dependências da receita: \(preset.winetricks.joined(separator: " "))…")
            _ = try await Winetricks(paths: paths, downloader: downloader, runner: runner)
                .install(verbs: preset.winetricks, in: bottle, runtime: try runtimes.runtime(id: bottle.config.runtimeID))
        }
        if let notes = preset.notes { print("Notas: \(notes)") }
        print(describe(bottle))
    case "delete":
        let bottle = try bottles.find(try args.positional(1, "bottle"))
        guard args.has("yes") else { throw CLIError("isso apaga \(bottle.url.path). Repita com --yes para confirmar.") }
        if let runtime = try? runtimes.runtime(id: bottle.config.runtimeID) {
            try? await Wine(runtime: runtime, runner: runner).killAll(in: bottle)
        }
        try bottles.delete(bottle)
        print("Bottle \"\(bottle.config.displayName)\" removida.")
    case let other?:
        throw CLIError("subcomando desconhecido: bottle \(other)")
    }
}

func apply(_ bottle: Bottle, previous: BottleConfig) async throws {
    let runtime = try runtimes.runtime(id: bottle.config.runtimeID)
    try await bottles.applyChanges(to: bottle, previous: previous, runtime: runtime)
    if bottle.config.graphicsBackend != previous.graphicsBackend {
        try prepareBackend(for: bottle)
    }
}

func componentCommand(_ argv: [String]) async throws {
    let args = try Arguments(argv, valueOptions: ["manifest", "version"])
    switch args.positional.first {
    case "list", nil:
        let list = components.installedComponents()
        if list.isEmpty { print("Nenhum componente instalado.") }
        list.forEach { print("\($0.id)  [\($0.kind.displayName) \($0.descriptor.version)]  \($0.filesPath)") }
    case "available":
        for c in try await manifest(args).components {
            print("\(c.id)  \(c.kind.displayName) \(c.version)\(c.license.map { " — licença: \($0)" } ?? "")")
        }
    case "install":
        let id = try args.positional(1, "id")
        guard let descriptor = try await manifest(args).components.first(where: { $0.id == id }) else {
            throw CLIError("componente \(id) não está no manifesto")
        }
        let installed = try await components.install(descriptor, progress: progressPrinter)
        print("Instalado: \(installed.id)")
    case "add-d3dmetal":
        let location = URL(fileURLWithPath: (try args.positional(1, "pasta-do-GPTK") as NSString).expandingTildeInPath)
        let installed = try components.importD3DMetal(from: location, version: args.value("version") ?? "gptk")
        print("D3DMetal importado: \(installed.id). Ele é aplicado no runtime quando uma bottle usa o backend d3dmetal.")
    case "remove":
        try components.remove(id: try args.positional(1, "id"))
        print("Removido.")
    case let other?:
        throw CLIError("subcomando desconhecido: component \(other)")
    }
}

func runCommand(_ argv: [String]) async throws {
    let args = try Arguments(argv, valueOptions: ["bottle"], stopAtFirstPositional: true)
    let bottle = try bottles.find(try args.required("bottle"))
    let program = URL(fileURLWithPath: (try args.positional(0, "programa") as NSString).expandingTildeInPath).standardizedFileURL
    guard FileManager.default.fileExists(atPath: program.path) else { throw CLIError("arquivo não encontrado: \(program.path)") }
    let runtime = try runtimes.runtime(id: bottle.config.runtimeID)
    let process = try launcher.launch(program: program, arguments: args.rest, in: bottle, runtime: runtime)
    print("Iniciado (pid \(process.pid)). Log: \(process.logURL?.path ?? "—")")
    if args.has("wait") {
        process.waitUntilExit()
        print("Terminou com código \(process.exitCode ?? -1).")
    }
}

func programsCommand(_ argv: [String]) throws {
    let args = try Arguments(argv, valueOptions: ["bottle"])
    let bottle = try bottles.find(try args.required("bottle"))
    for pinned in bottle.config.pinnedPrograms { print("★ \(pinned.name)  \(pinned.path)") }
    let found = ProgramDiscovery.discover(in: bottle)
    if found.isEmpty && bottle.config.pinnedPrograms.isEmpty { print("Nenhum programa encontrado. Rode um instalador com: adega run --bottle \(bottle.id) <setup.exe>") }
    for program in found { print("\(program.name)  \(program.url.path)") }
}

func winetricksCommand(_ argv: [String]) async throws {
    let args = try Arguments(argv, valueOptions: ["bottle"])
    let bottle = try bottles.find(try args.required("bottle"))
    guard !args.positional.isEmpty else {
        print("Verbos sugeridos:")
        Winetricks.curatedVerbs.forEach { print("  \($0.id) — \($0.title): \($0.detail)") }
        return
    }
    print("Rodando winetricks \(args.positional.joined(separator: " ")) (pode demorar)…")
    let result = try await Winetricks(paths: paths, downloader: downloader, runner: runner)
        .install(verbs: args.positional, in: bottle, runtime: try runtimes.runtime(id: bottle.config.runtimeID))
    print(result.tail(lines: 10))
}

func shortcutCommand(_ argv: [String]) throws {
    let args = try Arguments(argv, valueOptions: ["bottle", "name"])
    let bottle = try bottles.find(try args.required("bottle"))
    let program = URL(fileURLWithPath: (try args.positional(0, "programa") as NSString).expandingTildeInPath).standardizedFileURL
    let executable = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
    let name = args.value("name") ?? program.deletingPathExtension().lastPathComponent
    let app = try ShortcutBuilder().create(name: name, bottle: bottle, program: program, launcherExecutable: executable)
    print("Atalho criado: \(app.path)")
}

func killCommand(_ argv: [String]) async throws {
    let args = try Arguments(argv, valueOptions: ["bottle"])
    let bottle = try bottles.find(try args.required("bottle"))
    try await Wine(runtime: try runtimes.runtime(id: bottle.config.runtimeID), runner: runner).killAll(in: bottle)
    print("Processos da bottle \"\(bottle.config.displayName)\" encerrados.")
}

func logsCommand(_ argv: [String]) throws {
    let args = try Arguments(argv, valueOptions: ["bottle"])
    let bottle = try bottles.find(try args.required("bottle"))
    let logs = launcher.logFiles(for: bottle)
    if args.has("last") {
        guard let last = logs.first else { print("Sem logs."); return }
        print(launcher.readLog(last, maxBytes: 64 * 1024))
    } else {
        if logs.isEmpty { print("Sem logs.") }
        logs.forEach { print($0.path) }
    }
}

func settingsCommand(_ argv: [String]) throws {
    let args = try Arguments(argv, valueOptions: ["manifest", "presets"])
    var settings = AppSettings.load(paths: paths)
    if let manifest = args.value("manifest") { settings.manifestURL = manifest }
    if let presets = args.value("presets") { settings.presetsURL = presets }
    if args.value("manifest") != nil || args.value("presets") != nil {
        try paths.ensureDirectories()
        try settings.save(paths: paths)
    }
    print("manifesto: \(settings.manifestURL.isEmpty ? "—" : settings.manifestURL)")
    print("receitas:  \(settings.presetsURL.isEmpty ? "—" : settings.presetsURL)")
}

func doctorCommand() async {
    print("Pasta de dados: \(paths.root.path)")
    if SystemCheck.needsRosetta {
        print(SystemCheck.isRosettaInstalled ? "✓ Rosetta 2 instalado" : "✗ Rosetta 2 ausente — instale com: \(SystemCheck.rosettaInstallCommand)")
    }
    let cabextract = try? await runner.run(executable: URL(fileURLWithPath: "/usr/bin/env"), arguments: ["which", "cabextract"], environment: ProcessInfo.processInfo.environment, currentDirectory: nil)
    print(cabextract?.succeeded == true ? "✓ cabextract encontrado (winetricks)" : "! cabextract não encontrado — o winetricks precisa dele (brew install cabextract)")
    let list = runtimes.installedRuntimes()
    print(list.isEmpty ? "! Nenhum runtime do Wine registrado" : "✓ \(list.count) runtime(s)")
    for runtime in list {
        let ok = (try? runtime.wineBinary()) != nil
        print("   \(ok ? "✓" : "✗") \(describe(runtime))")
    }
    print("✓ \(bottles.bottles().count) bottle(s), \(components.installedComponents().count) componente(s)")
}

// MARK: - Entrada

var argv = Array(CommandLine.arguments.dropFirst())

// Modo usado pelos atalhos .app.
if let request = HeadlessLaunch.parse(argv) {
    do {
        _ = try HeadlessLaunch.perform(request, paths: paths, runner: runner)
        exit(0)
    } catch {
        printError(error.localizedDescription)
        exit(1)
    }
}

guard let command = argv.first else {
    print(usage)
    exit(0)
}
argv.removeFirst()

do {
    switch command {
    case "runtime": try await runtimeCommand(argv)
    case "bottle": try await bottleCommand(argv)
    case "component": try await componentCommand(argv)
    case "run": try await runCommand(argv)
    case "programs": try programsCommand(argv)
    case "winetricks": try await winetricksCommand(argv)
    case "shortcut": try shortcutCommand(argv)
    case "kill": try await killCommand(argv)
    case "logs": try logsCommand(argv)
    case "settings": try settingsCommand(argv)
    case "doctor": await doctorCommand()
    case "help", "-h", "--help": print(usage)
    default:
        printError("comando desconhecido: \(command)\n")
        print(usage)
        exit(2)
    }
} catch {
    printError(error.localizedDescription)
    exit(1)
}
