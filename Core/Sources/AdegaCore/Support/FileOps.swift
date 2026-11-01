import Foundation

enum FileOps {
    /// Copia `source` para `destination`, mesclando diretórios e substituindo arquivos.
    /// Links simbólicos são recriados como links (necessário para `.framework`).
    static func copyMerging(from source: URL, to destination: URL, fileManager fm: FileManager = .default) throws {
        let sourcePath = source.path
        if let linkTarget = try? fm.destinationOfSymbolicLink(atPath: sourcePath) {
            try removeIfPresent(destination, fileManager: fm)
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.createSymbolicLink(atPath: destination.path, withDestinationPath: linkTarget)
            return
        }

        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: sourcePath, isDirectory: &isDirectory) else {
            throw AdegaError.componentFileMissing(sourcePath)
        }

        if isDirectory.boolValue {
            if isSymlink(destination, fileManager: fm) { try fm.removeItem(at: destination) }
            try fm.createDirectory(at: destination, withIntermediateDirectories: true)
            for child in try fm.contentsOfDirectory(atPath: sourcePath) {
                try copyMerging(
                    from: source.appendingPathComponent(child),
                    to: destination.appendingPathComponent(child),
                    fileManager: fm
                )
            }
        } else {
            try removeIfPresent(destination, fileManager: fm)
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: source, to: destination)
        }
    }

    static func removeIfPresent(_ url: URL, fileManager fm: FileManager = .default) throws {
        if isSymlink(url, fileManager: fm) || fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
    }

    static func isSymlink(_ url: URL, fileManager fm: FileManager = .default) -> Bool {
        (try? fm.destinationOfSymbolicLink(atPath: url.path)) != nil
    }

    static func isExecutable(_ url: URL, fileManager fm: FileManager = .default) -> Bool {
        fm.isExecutableFile(atPath: url.path)
    }

    /// Lê no máximo os últimos `maxBytes` de um arquivo de texto (logs podem ficar enormes).
    static func readTail(of url: URL, maxBytes: Int) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        let size = handle.seekToEndOfFile()
        let start = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
        handle.seek(toFileOffset: start)
        return String(decoding: handle.readDataToEndOfFile(), as: UTF8.self)
    }
}

/// Extrai .tar.gz/.tar.xz/.tar.bz2/.tgz/.txz/.zip usando ferramentas do sistema.
struct ArchiveExtractor {
    let runner: ProcessRunning

    static func isSupported(_ fileName: String) -> Bool {
        let lower = fileName.lowercased()
        return [".tar.gz", ".tgz", ".tar.xz", ".txz", ".tar.bz2", ".tbz2", ".tar", ".zip"].contains { lower.hasSuffix($0) }
    }

    func extract(_ archive: URL, to destination: URL) async throws {
        let name = archive.lastPathComponent
        guard Self.isSupported(name) else { throw AdegaError.unsupportedArchive(name) }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let env = ProcessInfo.processInfo.environment
        let usrBinEnv = URL(fileURLWithPath: "/usr/bin/env")
        if name.lowercased().hasSuffix(".zip") {
            #if os(macOS)
            try await runner.runChecked(executable: URL(fileURLWithPath: "/usr/bin/ditto"), arguments: ["-x", "-k", archive.path, destination.path], environment: env)
            #else
            try await runner.runChecked(executable: usrBinEnv, arguments: ["unzip", "-q", "-o", archive.path, "-d", destination.path], environment: env)
            #endif
        } else {
            try await runner.runChecked(executable: usrBinEnv, arguments: ["tar", "-xf", archive.path, "-C", destination.path], environment: env)
        }
    }
}
