import Foundation

/// Gerencia componentes gráficos (DXVK, DXMT, MoltenVK, D3DMetal) e os aplica
/// em runtimes e bottles conforme o `FileMapping` de cada um.
public final class ComponentManager: @unchecked Sendable {
    public static let metadataFileName = "component.json"

    public let paths: AdegaPaths
    let downloader: Downloading
    let runner: ProcessRunning
    let fileManager: FileManager

    public init(paths: AdegaPaths, downloader: Downloading = URLSessionDownloader(), runner: ProcessRunning = SystemProcessRunner(), fileManager: FileManager = .default) {
        self.paths = paths
        self.downloader = downloader
        self.runner = runner
        self.fileManager = fileManager
    }

    func directory(for id: String) -> URL {
        paths.components.appendingPathComponent(id, isDirectory: true)
    }

    public func installedComponents() -> [InstalledComponent] {
        guard let entries = try? fileManager.contentsOfDirectory(at: paths.components, includingPropertiesForKeys: nil) else { return [] }
        return entries
            .compactMap { try? JSONStore.read(InstalledComponent.self, from: $0.appendingPathComponent(Self.metadataFileName)) }
            .sorted { ($0.kind.rawValue, $1.installedAt) < ($1.kind.rawValue, $0.installedAt) }
    }

    /// O componente mais recente instalado de um tipo.
    public func latest(_ kind: ComponentKind) -> InstalledComponent? {
        Self.latest(kind, in: installedComponents())
    }

    public static func latest(_ kind: ComponentKind, in installed: [InstalledComponent]) -> InstalledComponent? {
        installed
            .filter { $0.kind == kind }
            .max { $0.installedAt < $1.installedAt }
    }

    public func install(_ descriptor: ComponentDescriptor, progress: (@Sendable (Double) -> Void)? = nil) async throws -> InstalledComponent {
        guard let url = descriptor.url else { throw AdegaError.downloadFailed("o componente \(descriptor.id) não tem URL") }
        let id = try NameSanitizer.identifier(from: descriptor.id)
        try paths.ensureDirectories(fileManager: fileManager)
        let finalDir = directory(for: id)
        let staging = paths.components.appendingPathComponent(".\(id).partial", isDirectory: true)
        try FileOps.removeIfPresent(staging, fileManager: fileManager)
        do {
            try await PackageInstaller(paths: paths, downloader: downloader, runner: runner)
                .downloadVerifyExtract(url: url, sha256: descriptor.sha256, into: staging.appendingPathComponent("files"), progress: progress)
            try FileOps.removeIfPresent(finalDir, fileManager: fileManager)
            try fileManager.moveItem(at: staging, to: finalDir)
            let component = InstalledComponent(descriptor: descriptor, filesPath: finalDir.appendingPathComponent("files").path)
            try validateSources(of: component)
            try JSONStore.write(component, to: finalDir.appendingPathComponent(Self.metadataFileName))
            return component
        } catch {
            try? FileOps.removeIfPresent(staging, fileManager: fileManager)
            throw error
        }
    }

    /// Importa o D3DMetal de uma cópia local do Game Porting Toolkit.
    /// Aceita a raiz do DMG montado, a pasta `redist` ou a pasta `redist/lib`.
    public func importD3DMetal(from location: URL, version: String = "gptk") throws -> InstalledComponent {
        guard let libDir = Self.locateGPTKLib(location, fileManager: fileManager) else {
            throw AdegaError.invalidD3DMetalFolder(location.path)
        }
        let descriptor = ComponentDescriptor.d3dMetal(version: version)
        let id = try NameSanitizer.identifier(from: descriptor.id)
        try paths.ensureDirectories(fileManager: fileManager)
        let finalDir = directory(for: id)
        try FileOps.removeIfPresent(finalDir, fileManager: fileManager)
        let files = finalDir.appendingPathComponent("files", isDirectory: true)
        try FileOps.copyMerging(from: libDir, to: files, fileManager: fileManager)
        let component = InstalledComponent(descriptor: descriptor, filesPath: files.path)
        try JSONStore.write(component, to: finalDir.appendingPathComponent(Self.metadataFileName))
        return component
    }

    static func locateGPTKLib(_ location: URL, fileManager: FileManager) -> URL? {
        let candidates = [
            location,
            location.appendingPathComponent("lib"),
            location.appendingPathComponent("redist/lib"),
        ]
        return candidates.first { fileManager.fileExists(atPath: $0.appendingPathComponent("external/D3DMetal.framework").path) }
    }

    public func remove(id: String) throws {
        try FileOps.removeIfPresent(directory(for: id), fileManager: fileManager)
    }

    func validateSources(of component: InstalledComponent) throws {
        for mapping in component.descriptor.files {
            let source = mapping.source.isEmpty ? component.sourceRoot : component.sourceRoot.appendingPathComponent(mapping.source)
            guard fileManager.fileExists(atPath: source.path) else {
                throw AdegaError.componentFileMissing(source.path)
            }
        }
    }

    // MARK: - Aplicação

    /// Copia os arquivos de escopo `runtime` para dentro do runtime e registra no `runtime.json`.
    public func applyRuntimeFiles(of component: InstalledComponent, to runtime: InstalledRuntime, runtimeManager: RuntimeManager) throws -> InstalledRuntime {
        guard component.descriptor.hasRuntimeFiles else { return runtime }
        guard !runtime.isExternal else { throw AdegaError.externalRuntimeIsReadOnly(runtime.id) }
        try copy(component, scope: .runtime, into: runtime.wineRoot)
        var updated = runtime
        updated.runtimeComponents[component.kind.rawValue] = component.id
        try runtimeManager.save(updated)
        return updated
    }

    /// Copia os arquivos de escopo `bottle` (ex.: DLLs em system32).
    public func applyBottleFiles(of component: InstalledComponent, to bottle: Bottle) throws {
        guard component.descriptor.hasBottleFiles else { return }
        try copy(component, scope: .bottle, into: bottle.url)
    }

    /// Garante que o backend escolhido tem seus arquivos instalados no runtime e na bottle.
    /// Deve ser chamado quando a bottle é criada ou o backend muda.
    @discardableResult
    public func prepareBackend(_ backend: GraphicsBackend, bottle: Bottle, runtime: InstalledRuntime, runtimeManager: RuntimeManager) throws -> InstalledRuntime {
        guard let kind = backend.requiredComponent else { return runtime }
        guard let component = latest(kind) else { throw AdegaError.componentNotInstalled(kind.displayName) }

        var runtime = runtime
        if component.descriptor.hasRuntimeFiles, runtime.runtimeComponents[kind.rawValue] != component.id {
            runtime = try applyRuntimeFiles(of: component, to: runtime, runtimeManager: runtimeManager)
        }
        // DXVK no macOS depende do MoltenVK; se houver um componente MoltenVK, aplica junto.
        if backend == .dxvk, let moltenVK = latest(.moltenvk), runtime.runtimeComponents[ComponentKind.moltenvk.rawValue] != moltenVK.id {
            runtime = try applyRuntimeFiles(of: moltenVK, to: runtime, runtimeManager: runtimeManager)
        }
        // Arquivos da bottle são sempre recopiados: outro backend pode ter sobrescrito d3d11.dll etc.
        try applyBottleFiles(of: component, to: bottle)
        return runtime
    }

    /// Indica se o backend pode ser usado agora (componente presente e runtime gravável quando necessário).
    public func availability(of backend: GraphicsBackend, runtime: InstalledRuntime?) -> BackendAvailability {
        Self.availability(of: backend, runtime: runtime, installed: installedComponents())
    }

    /// Versão sem acesso a disco, para a interface (usa a lista já carregada).
    public static func availability(of backend: GraphicsBackend, runtime: InstalledRuntime?, installed: [InstalledComponent]) -> BackendAvailability {
        guard let kind = backend.requiredComponent else { return .ready }
        guard let component = latest(kind, in: installed) else { return .missingComponent(kind) }
        if component.descriptor.hasRuntimeFiles, let runtime, runtime.isExternal,
           runtime.runtimeComponents[kind.rawValue] != component.id {
            return .runtimeReadOnly
        }
        return .ready
    }

    private func copy(_ component: InstalledComponent, scope: InstallScope, into root: URL) throws {
        for mapping in component.descriptor.files where mapping.scope == scope {
            let source = mapping.source.isEmpty ? component.sourceRoot : component.sourceRoot.appendingPathComponent(mapping.source)
            guard fileManager.fileExists(atPath: source.path) || FileOps.isSymlink(source, fileManager: fileManager) else {
                throw AdegaError.componentFileMissing(source.path)
            }
            let destination = mapping.destination.isEmpty ? root : root.appendingPathComponent(mapping.destination)
            try FileOps.copyMerging(from: source, to: destination, fileManager: fileManager)
        }
    }
}

public enum BackendAvailability: Equatable, Sendable {
    case ready
    case missingComponent(ComponentKind)
    case runtimeReadOnly

    public var message: String? {
        switch self {
        case .ready: return nil
        case .missingComponent(let kind): return "Instale o componente \(kind.displayName) em Componentes."
        case .runtimeReadOnly: return "Este backend precisa modificar o runtime, mas ele é externo. Registre o Wine com cópia."
        }
    }
}
