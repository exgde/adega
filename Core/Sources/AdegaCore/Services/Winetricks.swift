import Foundation

/// Wrapper do winetricks (script baixado na primeira utilização, nunca empacotado).
/// Ele baixa os redistribuíveis da Microsoft direto das fontes oficiais.
/// No macOS o winetricks precisa do `cabextract` (ex.: `brew install cabextract`).
public struct Winetricks: Sendable {
    public static let scriptURL = URL(string: "https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks")!

    public struct Verb: Identifiable, Hashable, Sendable {
        public let id: String
        public let title: String
        public let detail: String
    }

    /// Lista curta e curada; o usuário pode digitar qualquer outro verbo.
    public static let curatedVerbs: [Verb] = [
        Verb(id: "vcrun2022", title: "Visual C++ 2015–2022", detail: "Exigido pela maioria dos jogos e apps modernos."),
        Verb(id: "dotnet48", title: ".NET Framework 4.8", detail: "Apps e launchers feitos em .NET (instalação demorada)."),
        Verb(id: "corefonts", title: "Fontes Microsoft", detail: "Arial, Times New Roman etc. Corrige textos quebrados."),
        Verb(id: "d3dcompiler_47", title: "D3DCompiler 47", detail: "Compilador de shaders usado por muitos jogos."),
        Verb(id: "xact", title: "XACT", detail: "Áudio de jogos antigos (DirectX)."),
        Verb(id: "dxvk", title: "DXVK (via winetricks)", detail: "Alternativa ao componente DXVK do Adega."),
    ]

    public let paths: AdegaPaths
    let downloader: Downloading
    let runner: ProcessRunning

    public init(paths: AdegaPaths, downloader: Downloading = URLSessionDownloader(), runner: ProcessRunning = SystemProcessRunner()) {
        self.paths = paths
        self.downloader = downloader
        self.runner = runner
    }

    public var scriptPath: URL { paths.cache.appendingPathComponent("winetricks") }

    public func ensureScript(forceUpdate: Bool = false) async throws -> URL {
        let fm = FileManager.default
        if forceUpdate || !fm.fileExists(atPath: scriptPath.path) {
            try paths.ensureDirectories()
            try await downloader.download(from: Self.scriptURL, to: scriptPath, progress: nil)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath.path)
        }
        return scriptPath
    }

    static func validate(_ verbs: [String]) throws -> [String] {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789_=.-")
        return try verbs.map { verb in
            let v = verb.trimmingCharacters(in: .whitespaces).lowercased()
            guard !v.isEmpty, !v.hasPrefix("-"), v.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
                throw AdegaError.invalidVerb(verb)
            }
            return v
        }
    }

    public func install(verbs: [String], in bottle: Bottle, runtime: InstalledRuntime) async throws -> ProcessResult {
        let verbs = try Self.validate(verbs)
        guard !verbs.isEmpty else { return ProcessResult(exitCode: 0, output: "") }
        let script = try await ensureScript()
        let wine = Wine(runtime: runtime, runner: runner)
        let env = wine.environment(for: bottle, extra: [
            "WINE": try runtime.wineBinary().path,
            "WINESERVER": runtime.wineserver.path,
            "WINETRICKS_LATEST_VERSION_CHECK": "disabled",
        ])
        return try await runner.runChecked(
            executable: URL(fileURLWithPath: "/bin/bash"),
            arguments: [script.path, "-q"] + verbs,
            environment: env,
            currentDirectory: bottle.url
        )
    }
}
