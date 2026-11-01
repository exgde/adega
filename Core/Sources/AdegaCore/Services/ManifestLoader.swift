import Foundation

public enum ManifestLoader {
    /// Lê um JSON de `https://` ou `file://` (ou um caminho local simples).
    public static func data(from location: String, downloader: Downloading, paths: AdegaPaths) async throws -> Data {
        let url = resolve(location)
        if url.isFileURL {
            return try Data(contentsOf: url)
        }
        let temp = paths.cache.appendingPathComponent("manifest-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: temp) }
        try await downloader.download(from: url, to: temp, progress: nil)
        return try Data(contentsOf: temp)
    }

    public static func loadRuntimeManifest(from location: String, downloader: Downloading, paths: AdegaPaths) async throws -> RuntimeManifest {
        try await JSONStore.decoder().decode(RuntimeManifest.self, from: data(from: location, downloader: downloader, paths: paths))
    }

    public static func loadPresets(from location: String, downloader: Downloading, paths: AdegaPaths) async throws -> PresetCatalog {
        try await PresetCatalog.decode(from: data(from: location, downloader: downloader, paths: paths))
    }

    static func resolve(_ location: String) -> URL {
        let trimmed = location.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), let scheme = url.scheme, ["http", "https", "file"].contains(scheme.lowercased()) {
            return url
        }
        return URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath)
    }
}

/// Baixa um arquivo, confere o SHA-256 e extrai. Usado por runtimes e componentes.
struct PackageInstaller {
    let paths: AdegaPaths
    let downloader: Downloading
    let runner: ProcessRunning

    func downloadVerifyExtract(url: URL, sha256: String?, into destination: URL, progress: (@Sendable (Double) -> Void)?) async throws {
        let fileName = url.lastPathComponent
        guard ArchiveExtractor.isSupported(fileName) else { throw AdegaError.unsupportedArchive(fileName) }
        let archive = paths.cache.appendingPathComponent("\(UUID().uuidString)-\(fileName)")
        defer { try? FileManager.default.removeItem(at: archive) }

        try await downloader.download(from: url, to: archive, progress: progress)

        if let expected = sha256?.lowercased(), !expected.isEmpty {
            let actual = try FileHasher.sha256Hex(of: archive)
            guard actual == expected else {
                throw AdegaError.checksumMismatch(expected: expected, actual: actual)
            }
        }
        try await ArchiveExtractor(runner: runner).extract(archive, to: destination)
    }
}
