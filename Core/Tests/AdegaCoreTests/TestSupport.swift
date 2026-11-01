import Foundation
import XCTest
@testable import AdegaCore

/// Diretório temporário isolado por teste.
final class TempDir {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("adega-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    func path(_ component: String) -> URL { url.appendingPathComponent(component) }
}

enum Fixtures {
    /// Cria um "Wine" falso: scripts `bin/wine` e `bin/wineserver` que registram as chamadas
    /// em `$WINEPREFIX/fake-wine-calls.log` e simulam o `wineboot`.
    @discardableResult
    static func makeFakeWine(at root: URL, binaryName: String = "wine", failWineboot: Bool = false) throws -> URL {
        let bin = root.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("lib/wine/x86_64-unix"), withIntermediateDirectories: true)
        let wine = """
        #!/bin/sh
        if [ -n "$WINEPREFIX" ]; then
          echo "wine $* | OVERRIDES=$WINEDLLOVERRIDES | MSYNC=$WINEMSYNC | PWD=$(pwd)" >> "$WINEPREFIX/fake-wine-calls.log"
        fi
        if [ "$1" = "--version" ]; then echo "wine-fake-9.9"; fi
        if [ "$1" = "wineboot" ]; then
          \(failWineboot ? "echo 'falha simulada' >&2; exit 3" : "mkdir -p \"$WINEPREFIX/drive_c/windows/system32\" \"$WINEPREFIX/drive_c/windows/syswow64\"")
        fi
        exit 0
        """
        let server = "#!/bin/sh\nexit 0\n"
        let wineURL = bin.appendingPathComponent(binaryName)
        try Data(wine.utf8).write(to: wineURL)
        try Data(server.utf8).write(to: bin.appendingPathComponent("wineserver"))
        for file in [wineURL, bin.appendingPathComponent("wineserver")] {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        }
        return root
    }

    static func makeTarGz(of directory: URL, contentsNamed name: String, output: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["tar", "-czf", output.path, "-C", directory.path, name]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

    static func calls(in bottle: Bottle) -> [String] {
        let log = bottle.url.appendingPathComponent("fake-wine-calls.log")
        guard let text = try? String(contentsOf: log, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").map(String.init)
    }

    static func runtime(at root: URL, id: String = "fake") -> InstalledRuntime {
        InstalledRuntime(id: id, displayName: "Fake", version: "9.9", wineRootPath: root.path, isExternal: false)
    }
}
