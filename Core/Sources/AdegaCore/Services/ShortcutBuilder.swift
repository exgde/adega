import Foundation

/// Gera um `.app` mínimo (Info.plist + script) que abre um programa numa bottle.
/// O script chama o executável do Adega em modo headless, então mudanças na
/// configuração da bottle valem também para atalhos já criados.
public struct ShortcutBuilder: Sendable {
    public init() {}

    public static var defaultDirectory: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Applications/Adega", isDirectory: true)
    }

    @discardableResult
    public func create(name: String, bottle: Bottle, program: URL, arguments: [String] = [], launcherExecutable: URL, in directory: URL = ShortcutBuilder.defaultDirectory) throws -> URL {
        let fm = FileManager.default
        let safeName = try NameSanitizer.identifier(from: name)
        let app = directory.appendingPathComponent("\(safeName).app", isDirectory: true)
        try FileOps.removeIfPresent(app, fileManager: fm)

        let macOS = app.appendingPathComponent("Contents/MacOS", isDirectory: true)
        try fm.createDirectory(at: macOS, withIntermediateDirectories: true)

        let request = HeadlessLaunch.Request(bottleID: bottle.id, program: program.path, arguments: arguments)
        let script = Self.script(launcherExecutable: launcherExecutable, request: request)
        let scriptURL = macOS.appendingPathComponent("launch")
        try Data(script.utf8).write(to: scriptURL)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let bundleSuffix = safeName.lowercased().unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? String($0) : "-" }
            .joined()
        let plist: [String: Any] = [
            "CFBundleExecutable": "launch",
            "CFBundleIdentifier": "app.adega.shortcut.\(bundleSuffix)",
            "CFBundleName": name,
            "CFBundleDisplayName": name,
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": "1",
            "CFBundleInfoDictionaryVersion": "6.0",
            "LSMinimumSystemVersion": "14.0",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: app.appendingPathComponent("Contents/Info.plist"))
        return app
    }

    static func script(launcherExecutable: URL, request: HeadlessLaunch.Request) -> String {
        let command = ([launcherExecutable.path] + HeadlessLaunch.arguments(for: request)).map(shellQuote).joined(separator: " ")
        return "#!/bin/sh\n# Gerado pelo Adega.\nexec \(command)\n"
    }

    /// Aspas simples para shell POSIX: `it's` → `'it'\''s'`.
    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

/// Verificações do sistema que afetam o Wine.
public enum SystemCheck {
    /// No Apple Silicon o Wine (x86_64) depende do Rosetta 2.
    public static var needsRosetta: Bool {
        #if os(macOS) && arch(arm64)
        return true
        #else
        return false
        #endif
    }

    public static var isRosettaInstalled: Bool {
        guard needsRosetta else { return true }
        return FileManager.default.fileExists(atPath: "/Library/Apple/usr/libexec/oah/libRosettaRuntime")
    }

    public static let rosettaInstallCommand = "softwareupdate --install-rosetta --agree-to-license"
}
