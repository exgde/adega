import AdegaCore
import AppKit
import Foundation

enum SidebarItem: Hashable {
    case bottle(String)
    case runtimes
    case components
}

struct RunningProgram: Identifiable {
    let id: UUID
    let bottleID: String
    let name: String
    let process: SpawnedProcess
    let startedAt: Date
}

/// Estado do app e ponte entre a interface e o AdegaCore.
@MainActor
final class AppModel: ObservableObject {
    let paths: AdegaPaths
    let runner: SystemProcessRunner
    let downloader: URLSessionDownloader
    let runtimeManager: RuntimeManager
    let bottleManager: BottleManager
    let componentManager: ComponentManager
    let launcher: Launcher

    @Published private(set) var bottles: [Bottle] = []
    @Published private(set) var runtimes: [InstalledRuntime] = []
    @Published private(set) var components: [InstalledComponent] = []
    @Published private(set) var manifest: RuntimeManifest?
    @Published private(set) var presets = PresetCatalog()
    @Published private(set) var running: [RunningProgram] = []
    @Published var settings = AppSettings()
    @Published var selection: SidebarItem?
    @Published var showingNewBottle = false
    @Published var busyMessage: String?
    @Published var progress: Double?
    @Published var errorMessage: String?

    init() {
        let paths = AdegaPaths.default
        let runner = SystemProcessRunner()
        let downloader = URLSessionDownloader()
        self.paths = paths
        self.runner = runner
        self.downloader = downloader
        self.runtimeManager = RuntimeManager(paths: paths, downloader: downloader, runner: runner)
        self.bottleManager = BottleManager(paths: paths, runner: runner)
        self.componentManager = ComponentManager(paths: paths, downloader: downloader, runner: runner)
        self.launcher = Launcher(paths: paths, runner: runner)
        self.settings = AppSettings.load(paths: paths)
        try? paths.ensureDirectories()
        reload()
        if !settings.presetsURL.isEmpty { fetchPresets() }
    }

    var isBusy: Bool { busyMessage != nil }

    func reload() {
        bottles = bottleManager.bottles()
        runtimes = runtimeManager.installedRuntimes()
        components = componentManager.installedComponents()
    }

    // MARK: - Infra

    /// Executa uma operação longa mostrando a barra de status e tratando erros.
    private func perform(_ message: String, _ work: @escaping () async throws -> Void) {
        Task {
            busyMessage = message
            progress = nil
            do {
                try await work()
            } catch {
                errorMessage = error.localizedDescription
            }
            busyMessage = nil
            progress = nil
            reload()
        }
    }

    /// Trabalho síncrono pesado (cópia de arquivos) fora da main thread.
    private func background<T: Sendable>(_ body: @escaping @Sendable () throws -> T) async throws -> T {
        try await Task.detached(priority: .userInitiated) { try body() }.value
    }

    private var progressHandler: @Sendable (Double) -> Void {
        { [weak self] value in
            Task { @MainActor in self?.progress = value }
        }
    }

    func availability(of backend: GraphicsBackend, runtimeID: String) -> BackendAvailability {
        ComponentManager.availability(of: backend, runtime: runtimes.first { $0.id == runtimeID }, installed: components)
    }

    func runningCount(in bottle: Bottle) -> Int {
        running.filter { $0.bottleID == bottle.id }.count
    }

    // MARK: - Bottles

    func createBottle(name: String, runtimeID: String, windows: WindowsVersion, backend: GraphicsBackend, retina: Bool) {
        perform("Criando a bottle \"\(name)\"…") { [self] in
            let runtime = try runtimeManager.runtime(id: runtimeID)
            let config = BottleConfig(displayName: name, runtimeID: runtimeID, windowsVersion: windows, graphicsBackend: backend, retinaMode: retina)
            let bottle = try await bottleManager.create(name: name, config: config, runtime: runtime)
            selection = .bottle(bottle.id)
            try await prepareBackend(for: bottle)
        }
    }

    /// Salva a configuração e aplica no prefixo o que mudou.
    func save(_ bottle: Bottle, previous: BottleConfig) {
        perform("Aplicando configurações…") { [self] in
            let runtime = try runtimeManager.runtime(id: bottle.config.runtimeID)
            try await bottleManager.applyChanges(to: bottle, previous: previous, runtime: runtime)
            if bottle.config.graphicsBackend != previous.graphicsBackend || bottle.config.runtimeID != previous.runtimeID {
                try await prepareBackend(for: bottle)
            }
        }
    }

    private func prepareBackend(for bottle: Bottle) async throws {
        guard bottle.config.graphicsBackend.requiredComponent != nil else { return }
        let runtime = try runtimeManager.runtime(id: bottle.config.runtimeID)
        let components = componentManager
        let runtimes = runtimeManager
        _ = try await background {
            try components.prepareBackend(bottle.config.graphicsBackend, bottle: bottle, runtime: runtime, runtimeManager: runtimes)
        }
    }

    func applyPreset(_ preset: Preset, to bottle: Bottle) {
        var updated = bottle
        updated.config = preset.applied(to: bottle.config)
        let previous = bottle.config
        perform("Aplicando a receita \"\(preset.name)\"…") { [self] in
            let runtime = try runtimeManager.runtime(id: updated.config.runtimeID)
            try await bottleManager.applyChanges(to: updated, previous: previous, runtime: runtime)
            if updated.config.graphicsBackend != previous.graphicsBackend {
                try await prepareBackend(for: updated)
            }
            if !preset.winetricks.isEmpty {
                busyMessage = "Instalando dependências da receita (\(preset.winetricks.joined(separator: " ")))…"
                _ = try await Winetricks(paths: paths, downloader: downloader, runner: runner)
                    .install(verbs: preset.winetricks, in: updated, runtime: runtime)
            }
        }
    }

    func togglePin(name: String, url: URL, in bottle: Bottle) {
        var updated = bottle
        if let index = updated.config.pinnedPrograms.firstIndex(where: { $0.path == url.path }) {
            updated.config.pinnedPrograms.remove(at: index)
        } else {
            updated.config.pinnedPrograms.append(PinnedProgram(name: name, path: url.path))
        }
        do {
            try bottleManager.save(updated)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ bottle: Bottle) {
        perform("Apagando a bottle…") { [self] in
            if let runtime = try? runtimeManager.runtime(id: bottle.config.runtimeID) {
                try? await Wine(runtime: runtime, runner: runner).killAll(in: bottle)
            }
            try bottleManager.delete(bottle)
            selection = nil
        }
    }

    func killAll(in bottle: Bottle) {
        perform("Encerrando os processos da bottle…") { [self] in
            let runtime = try runtimeManager.runtime(id: bottle.config.runtimeID)
            try await Wine(runtime: runtime, runner: runner).killAll(in: bottle)
            running.removeAll { $0.bottleID == bottle.id }
        }
    }

    // MARK: - Programas

    func run(_ program: URL, arguments: [String] = [], in bottle: Bottle) {
        do {
            let runtime = try runtimeManager.runtime(id: bottle.config.runtimeID)
            let entryID = UUID()
            let process = try launcher.launch(program: program, arguments: arguments, in: bottle, runtime: runtime) { [weak self] _ in
                Task { @MainActor in self?.running.removeAll { $0.id == entryID } }
            }
            running.append(RunningProgram(
                id: entryID,
                bottleID: bottle.id,
                name: program.deletingPathExtension().lastPathComponent,
                process: process,
                startedAt: Date()
            ))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func installWinetricks(_ verbs: [String], in bottle: Bottle) {
        perform("winetricks \(verbs.joined(separator: " ")) — pode levar vários minutos…") { [self] in
            let runtime = try runtimeManager.runtime(id: bottle.config.runtimeID)
            _ = try await Winetricks(paths: paths, downloader: downloader, runner: runner)
                .install(verbs: verbs, in: bottle, runtime: runtime)
        }
    }

    func createShortcut(name: String, program: URL, bottle: Bottle) {
        guard let executable = Bundle.main.executableURL else { return }
        do {
            let app = try ShortcutBuilder().create(name: name, bottle: bottle, program: program, launcherExecutable: executable)
            NSWorkspace.shared.activateFileViewerSelecting([app])
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func logFiles(for bottle: Bottle) -> [URL] {
        launcher.logFiles(for: bottle)
    }

    func readLog(_ url: URL) -> String {
        launcher.readLog(url)
    }

    // MARK: - Runtimes

    func fetchManifest() {
        let location = settings.manifestURL
        guard !location.isEmpty else { return }
        perform("Buscando o catálogo…") { [self] in
            manifest = try await ManifestLoader.loadRuntimeManifest(from: location, downloader: downloader, paths: paths)
        }
    }

    func fetchPresets() {
        let location = settings.presetsURL
        guard !location.isEmpty else { return }
        Task {
            do {
                presets = try await ManifestLoader.loadPresets(from: location, downloader: downloader, paths: paths)
            } catch {
                errorMessage = "Não foi possível carregar as receitas: \(error.localizedDescription)"
            }
        }
    }

    func installRuntime(_ descriptor: RuntimeDescriptor) {
        perform("Baixando \(descriptor.displayName)…") { [self] in
            _ = try await runtimeManager.install(descriptor, progress: progressHandler)
        }
    }

    func addExternalRuntime(location: URL, copy: Bool) {
        let base = location.pathExtension == "app"
            ? location.deletingPathExtension().lastPathComponent
            : location.lastPathComponent
        let existing = Set(runtimes.map(\.id))
        var name = base
        var counter = 2
        while existing.contains((try? NameSanitizer.identifier(from: name)) ?? name) {
            name = "\(base) \(counter)"
            counter += 1
        }
        let finalName = name
        perform(copy ? "Copiando o Wine para o Adega…" : "Registrando o Wine…") { [self] in
            var runtime = try await runtimeManager.registerExternal(name: finalName, location: location, copy: copy)
            if let version = await runtimeManager.detectVersion(of: runtime) {
                runtime.version = version
                try runtimeManager.save(runtime)
            }
        }
    }

    func removeRuntime(_ runtime: InstalledRuntime) {
        let users = bottles.filter { $0.config.runtimeID == runtime.id }
        guard users.isEmpty else {
            errorMessage = "O runtime é usado por: \(users.map(\.config.displayName).joined(separator: ", ")). Mude ou apague essas bottles primeiro."
            return
        }
        perform("Removendo o runtime…") { [self] in
            try runtimeManager.remove(id: runtime.id)
        }
    }

    // MARK: - Componentes

    func installComponent(_ descriptor: ComponentDescriptor) {
        perform("Baixando \(descriptor.kind.displayName) \(descriptor.version)…") { [self] in
            _ = try await componentManager.install(descriptor, progress: progressHandler)
        }
    }

    func importD3DMetal(from location: URL) {
        let components = componentManager
        perform("Importando o D3DMetal…") { [self] in
            _ = try await background { try components.importD3DMetal(from: location) }
        }
    }

    func removeComponent(_ component: InstalledComponent) {
        perform("Removendo o componente…") { [self] in
            try componentManager.remove(id: component.id)
        }
    }

    // MARK: - Ajustes e utilidades

    func saveSettings() {
        do {
            try settings.save(paths: paths)
            fetchPresets()
            manifest = nil
            fetchManifest()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
