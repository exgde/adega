import Foundation

public struct DiscoveredProgram: Identifiable, Hashable, Sendable {
    public enum Source: String, Sendable {
        case startMenu
        case programFiles
    }

    public let name: String
    public let url: URL
    public let source: Source

    public var id: String { url.path }
}

/// Encontra programas instalados numa bottle: atalhos do Menu Iniciar e .exe em Program Files.
public enum ProgramDiscovery {
    /// Pastas que o próprio Wine cria e que não interessam ao usuário.
    static let ignoredFolders: Set<String> = [
        "common files", "internet explorer", "windows media player", "windows nt", "windows defender", "microsoft.net",
    ]

    /// Fragmentos de nome que indicam instaladores/utilitários, não o programa em si.
    static let ignoredNameFragments = [
        "unins", "uninstall", "setup", "install", "update", "crash", "report", "redist", "vcredist", "dxsetup", "helper",
    ]

    public static func discover(in bottle: Bottle, maxDepth: Int = 3, fileManager: FileManager = .default) -> [DiscoveredProgram] {
        var results: [DiscoveredProgram] = []
        var seen = Set<String>()

        func add(_ url: URL, _ source: DiscoveredProgram.Source) {
            let name = url.deletingPathExtension().lastPathComponent
            guard !isIgnored(name), seen.insert(url.path).inserted else { return }
            results.append(DiscoveredProgram(name: name, url: url, source: source))
        }

        for menu in startMenuFolders(in: bottle, fileManager: fileManager) {
            walk(menu, depth: 0, maxDepth: 6, fileManager: fileManager) { url in
                if url.pathExtension.lowercased() == "lnk" { add(url, .startMenu) }
            }
        }
        for folder in ["Program Files", "Program Files (x86)"] {
            let root = bottle.driveC.appendingPathComponent(folder, isDirectory: true)
            walk(root, depth: 0, maxDepth: maxDepth, fileManager: fileManager) { url in
                if url.pathExtension.lowercased() == "exe" { add(url, .programFiles) }
            }
        }
        return results.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func isIgnored(_ name: String) -> Bool {
        let lower = name.lowercased()
        return ignoredNameFragments.contains { lower.contains($0) }
    }

    static func startMenuFolders(in bottle: Bottle, fileManager: FileManager) -> [URL] {
        let suffix = "Microsoft/Windows/Start Menu/Programs"
        var folders = [bottle.driveC.appendingPathComponent("ProgramData/\(suffix)", isDirectory: true)]
        let users = bottle.driveC.appendingPathComponent("users", isDirectory: true)
        if let names = try? fileManager.contentsOfDirectory(atPath: users.path) {
            for user in names {
                folders.append(users.appendingPathComponent("\(user)/AppData/Roaming/\(suffix)", isDirectory: true))
            }
        }
        return folders.filter { fileManager.fileExists(atPath: $0.path) }
    }

    static func walk(_ directory: URL, depth: Int, maxDepth: Int, fileManager: FileManager, visit: (URL) -> Void) {
        guard depth <= maxDepth, let children = try? fileManager.contentsOfDirectory(atPath: directory.path) else { return }
        for child in children.sorted() {
            let url = directory.appendingPathComponent(child)
            // Não segue links simbólicos (dosdevices aponta para "/", por exemplo).
            if FileOps.isSymlink(url, fileManager: fileManager) { continue }
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                if ignoredFolders.contains(child.lowercased()) { continue }
                walk(url, depth: depth + 1, maxDepth: maxDepth, fileManager: fileManager, visit: visit)
            } else {
                visit(url)
            }
        }
    }
}
