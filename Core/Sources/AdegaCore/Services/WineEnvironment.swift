import Foundation

/// Monta as variáveis de ambiente de uma execução do Wine. Função pura (fácil de testar).
public enum WineEnvironment {
    /// Variáveis herdadas que nunca devem vazar para dentro da bottle.
    static let strippedKeys: Set<String> = [
        "WINEPREFIX", "WINEDLLOVERRIDES", "WINEDEBUG", "WINEARCH", "WINEESYNC", "WINEMSYNC",
        "WINELOADER", "WINESERVER", "WINEDLLPATH", "DXVK_HUD", "MTL_HUD_ENABLED", "ROSETTA_ADVERTISE_AVX",
    ]

    public static func build(
        config: BottleConfig,
        bottleURL: URL,
        runtime: InstalledRuntime,
        base: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        var env = base.filter { !strippedKeys.contains($0.key) }

        env["WINEPREFIX"] = bottleURL.path
        env["WINEDEBUG"] = "fixme-all"
        let inheritedPath = base["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = runtime.binDirectory.path + ":" + inheritedPath

        if config.msync {
            env["WINEMSYNC"] = "1"
        }

        var overrides = config.graphicsBackend.dllOverrides
        overrides.merge(config.dllOverrides) { _, user in user }
        if !overrides.isEmpty {
            env["WINEDLLOVERRIDES"] = formatOverrides(overrides)
        }

        if config.performanceHUD {
            if config.graphicsBackend == .dxvk {
                env["DXVK_HUD"] = "fps,devinfo,gpuload"
            } else {
                env["MTL_HUD_ENABLED"] = "1"
            }
        }

        if config.advertiseAVX {
            env["ROSETTA_ADVERTISE_AVX"] = "1"
        }

        // Variáveis do usuário por último: elas sempre vencem.
        env.merge(config.environment) { _, user in user }
        return env
    }

    /// `["d3d11": "n,b", "dxgi": "n,b"]` → `"d3d11=n,b;dxgi=n,b"` (ordem estável).
    public static func formatOverrides(_ overrides: [String: String]) -> String {
        overrides.keys.sorted().map { "\($0)=\(overrides[$0]!)" }.joined(separator: ";")
    }
}

/// Converte "abrir este arquivo" nos argumentos do `wine`.
public enum WineCommand {
    public static let supportedExtensions: Set<String> = ["exe", "com", "msi", "bat", "cmd", "lnk"]

    public static func arguments(forProgram program: URL, extraArguments: [String] = []) throws -> [String] {
        switch program.pathExtension.lowercased() {
        case "exe", "com":
            return [program.path] + extraArguments
        case "msi", "bat", "cmd", "lnk":
            // `start /unix` usa a associação de arquivos do próprio Wine
            // (msi → msiexec, bat → cmd, lnk → destino do atalho).
            return ["start", "/unix", program.path] + extraArguments
        default:
            throw AdegaError.unsupportedFileType(program.lastPathComponent)
        }
    }

    /// Pasta de trabalho: muitos jogos esperam rodar a partir da pasta do .exe.
    public static func workingDirectory(forProgram program: URL, bottle: Bottle) -> URL {
        switch program.pathExtension.lowercased() {
        case "exe", "com", "bat", "cmd":
            return program.deletingLastPathComponent()
        default:
            return bottle.driveC
        }
    }
}
