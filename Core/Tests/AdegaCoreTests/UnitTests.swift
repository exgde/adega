import Foundation
import XCTest
@testable import AdegaCore

final class SHA256Tests: XCTestCase {
    func testKnownVectors() {
        XCTAssertEqual(FileHasher.sha256Hex(of: Data()), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(FileHasher.sha256Hex(of: Data("abc".utf8)), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(
            FileHasher.sha256Hex(of: Data("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".utf8)),
            "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"
        )
    }

    func testSoftwareImplementationMatchesAcrossChunkBoundaries() throws {
        // 1.000.000 x "a" — vetor oficial do NIST.
        let million = Data(repeating: UInt8(ascii: "a"), count: 1_000_000)
        var soft = SoftwareSHA256()
        var offset = 0
        for size in [1, 63, 64, 65, 1000, 4096] where offset < million.count {
            soft.update(data: million.subdata(in: offset..<min(offset + size, million.count)))
            offset += size
        }
        soft.update(data: million.subdata(in: offset..<million.count))
        let hex = soft.finalize().map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(hex, "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0")

        let temp = try TempDir()
        let file = temp.path("million.bin")
        try million.write(to: file)
        XCTAssertEqual(try FileHasher.sha256Hex(of: file, chunkSize: 4099), hex)
    }
}

final class WineEnvironmentTests: XCTestCase {
    let runtime = InstalledRuntime(id: "rt", displayName: "RT", version: "1", wineRootPath: "/opt/wine", isExternal: true)
    let bottleURL = URL(fileURLWithPath: "/tmp/bottles/Steam")

    func testDefaultsAndOverrides() {
        var config = BottleConfig(displayName: "Steam", runtimeID: "rt", graphicsBackend: .dxmt)
        config.dllOverrides = ["dxgi": "b", "mscoree": ""]
        let env = WineEnvironment.build(config: config, bottleURL: bottleURL, runtime: runtime, base: [
            "PATH": "/usr/bin",
            "WINEPREFIX": "/vazou",
            "WINEDLLOVERRIDES": "vazou=n",
            "HOME": "/Users/x",
        ])
        XCTAssertEqual(env["WINEPREFIX"], "/tmp/bottles/Steam")
        XCTAssertEqual(env["PATH"], "/opt/wine/bin:/usr/bin")
        XCTAssertEqual(env["HOME"], "/Users/x")
        XCTAssertEqual(env["WINEMSYNC"], "1")
        XCTAssertEqual(env["WINEDEBUG"], "fixme-all")
        // Override do usuário (dxgi=b) vence o do backend (dxgi=n,b); ordem alfabética.
        XCTAssertEqual(env["WINEDLLOVERRIDES"], "d3d10core=n,b;d3d11=n,b;dxgi=b;mscoree=")
        XCTAssertNil(env["MTL_HUD_ENABLED"])
        XCTAssertNil(env["ROSETTA_ADVERTISE_AVX"])
    }

    func testHUDAVXAndUserEnvironmentPrecedence() {
        var config = BottleConfig(displayName: "Jogo", runtimeID: "rt", graphicsBackend: .dxvk, msync: false, performanceHUD: true, advertiseAVX: true)
        config.environment = ["WINEDEBUG": "+loaddll", "DXVK_HUD": "full"]
        let env = WineEnvironment.build(config: config, bottleURL: bottleURL, runtime: runtime, base: [:])
        XCTAssertNil(env["WINEMSYNC"])
        XCTAssertEqual(env["DXVK_HUD"], "full")
        XCTAssertEqual(env["WINEDEBUG"], "+loaddll")
        XCTAssertEqual(env["ROSETTA_ADVERTISE_AVX"], "1")
        XCTAssertEqual(env["PATH"], "/opt/wine/bin:/usr/bin:/bin:/usr/sbin:/sbin")

        config.graphicsBackend = .d3dmetal
        config.environment = [:]
        let metal = WineEnvironment.build(config: config, bottleURL: bottleURL, runtime: runtime, base: [:])
        XCTAssertEqual(metal["MTL_HUD_ENABLED"], "1")
        XCTAssertNil(metal["DXVK_HUD"])
        XCTAssertEqual(metal["WINEDLLOVERRIDES"], "d3d10core=b;d3d11=b;d3d12=b;dxgi=b")
    }

    func testWineCommandArguments() throws {
        XCTAssertEqual(try WineCommand.arguments(forProgram: URL(fileURLWithPath: "/a/Game.EXE"), extraArguments: ["-dx11"]), ["/a/Game.EXE", "-dx11"])
        XCTAssertEqual(try WineCommand.arguments(forProgram: URL(fileURLWithPath: "/a/setup.msi")), ["start", "/unix", "/a/setup.msi"])
        XCTAssertEqual(try WineCommand.arguments(forProgram: URL(fileURLWithPath: "/a/Steam.lnk")), ["start", "/unix", "/a/Steam.lnk"])
        XCTAssertThrowsError(try WineCommand.arguments(forProgram: URL(fileURLWithPath: "/a/readme.txt")))

        let bottle = Bottle(id: "b", url: URL(fileURLWithPath: "/tmp/b"), config: BottleConfig(displayName: "b", runtimeID: "rt"))
        XCTAssertEqual(WineCommand.workingDirectory(forProgram: URL(fileURLWithPath: "/games/x/x.exe"), bottle: bottle).path, "/games/x")
        XCTAssertEqual(WineCommand.workingDirectory(forProgram: URL(fileURLWithPath: "/games/x.lnk"), bottle: bottle), bottle.driveC)
    }
}

final class ModelTests: XCTestCase {
    func testBottleConfigDecodesOldFilesWithDefaults() throws {
        let json = #"{"displayName":"Antiga","runtimeID":"wine-7"}"#
        let config = try JSONStore.decoder().decode(BottleConfig.self, from: Data(json.utf8))
        XCTAssertEqual(config.displayName, "Antiga")
        XCTAssertEqual(config.windowsVersion, .win10)
        XCTAssertEqual(config.graphicsBackend, .wined3d)
        XCTAssertTrue(config.msync)
        XCTAssertEqual(config.schemaVersion, BottleConfig.currentSchemaVersion)
    }

    func testBottleConfigRoundTrip() throws {
        var config = BottleConfig(displayName: "X", runtimeID: "rt", windowsVersion: .win11, graphicsBackend: .d3dmetal, retinaMode: true)
        config.pinnedPrograms = [PinnedProgram(name: "Jogo", path: "/c/jogo.exe", arguments: ["-a"])]
        config.createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let data = try JSONStore.encoder().encode(config)
        XCTAssertEqual(try JSONStore.decoder().decode(BottleConfig.self, from: data), config)
    }

    func testNameSanitizer() throws {
        XCTAssertEqual(try NameSanitizer.identifier(from: "  Steam  "), "Steam")
        XCTAssertEqual(try NameSanitizer.identifier(from: "Jogos/Antigos:2"), "Jogos-Antigos-2")
        XCTAssertEqual(try NameSanitizer.identifier(from: "..oculto"), "oculto")
        XCTAssertEqual(try NameSanitizer.identifier(from: "Ação"), "Ação")
        XCTAssertThrowsError(try NameSanitizer.identifier(from: "   "))
        XCTAssertThrowsError(try NameSanitizer.identifier(from: ".."))
        XCTAssertThrowsError(try NameSanitizer.identifier(from: String(repeating: "a", count: 65)))
    }

    func testManifestDecoding() throws {
        let json = """
        {"schemaVersion":1,
         "runtimes":[{"id":"wine-11","displayName":"Wine 11","version":"11.0","url":"https://example.com/w.tar.xz","sha256":"ab","wineRoot":"wine"}],
         "components":[{"id":"dxmt-0.72","kind":"dxmt","version":"0.72","url":"https://example.com/d.tar.gz",
           "files":[{"source":"x86_64-unix/winemetal.so","destination":"lib/wine/x86_64-unix/winemetal.so","scope":"runtime"}]}]}
        """
        let manifest = try JSONStore.decoder().decode(RuntimeManifest.self, from: Data(json.utf8))
        XCTAssertEqual(manifest.runtimes.first?.wineRoot, "wine")
        XCTAssertEqual(manifest.components.first?.kind, .dxmt)
        XCTAssertTrue(manifest.components.first?.hasRuntimeFiles == true)
        XCTAssertFalse(manifest.components.first?.hasBottleFiles == true)
    }

    /// Os exemplos do repositório precisam continuar compatíveis com os modelos.
    func testRepositoryExamplesDecode() throws {
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let manifest = try JSONStore.read(RuntimeManifest.self, from: repo.appendingPathComponent("manifests/runtimes.example.json"))
        XCTAssertFalse(manifest.runtimes.isEmpty)
        XCTAssertEqual(Set(manifest.components.map(\.kind)), [.dxmt, .dxvk])
        let presets = try PresetCatalog.decode(from: Data(contentsOf: repo.appendingPathComponent("presets/presets.example.json")))
        XCTAssertEqual(presets.match(executable: URL(fileURLWithPath: "/x/STEAM.exe"))?.id, "steam")
    }

    func testPresetMatchAndApply() {
        let preset = Preset(id: "p", name: "Jogo", executables: ["Game.exe"], graphicsBackend: .d3dmetal, windowsVersion: .win11, advertiseAVX: true, environment: ["A": "1"], dllOverrides: ["x": "n"])
        let catalog = PresetCatalog(presets: [preset])
        XCTAssertEqual(catalog.match(executable: URL(fileURLWithPath: "/c/GAME.EXE"))?.id, "p")
        XCTAssertNil(catalog.match(executable: URL(fileURLWithPath: "/c/outro.exe")))

        var config = BottleConfig(displayName: "b", runtimeID: "rt")
        config.environment = ["A": "0", "B": "2"]
        let applied = preset.applied(to: config)
        XCTAssertEqual(applied.graphicsBackend, .d3dmetal)
        XCTAssertEqual(applied.windowsVersion, .win11)
        XCTAssertTrue(applied.advertiseAVX)
        XCTAssertTrue(applied.msync, "campos ausentes na receita não mudam")
        XCTAssertEqual(applied.environment, ["A": "1", "B": "2"])
        XCTAssertEqual(applied.dllOverrides, ["x": "n"])
    }

    func testRuntimeRootNormalization() {
        XCTAssertEqual(InstalledRuntime.normalizeWineRoot(URL(fileURLWithPath: "/Applications/Wine Crossover.app")).path, "/Applications/Wine Crossover.app/Contents/Resources/wine")
        XCTAssertEqual(InstalledRuntime.normalizeWineRoot(URL(fileURLWithPath: "/opt/wine/bin")).path, "/opt/wine")
        XCTAssertEqual(InstalledRuntime.normalizeWineRoot(URL(fileURLWithPath: "/opt/wine")).path, "/opt/wine")
    }
}

final class HeadlessAndShortcutTests: XCTestCase {
    func testHeadlessRoundTrip() {
        let request = HeadlessLaunch.Request(bottleID: "Minha Bottle", program: "/c/Program Files/Jogo/jogo.exe", arguments: ["--", "-windowed"])
        let args = ["/Applications/Adega.app/Contents/MacOS/Adega"] + HeadlessLaunch.arguments(for: request)
        XCTAssertEqual(HeadlessLaunch.parse(Array(args.dropFirst())), request)
        XCTAssertNil(HeadlessLaunch.parse(["-NSDocumentRevisionsDebugMode", "YES"]))
        XCTAssertNil(HeadlessLaunch.parse(["--adega-run", "--bottle", "x"]))
        // Sem o separador "--" também funciona.
        XCTAssertEqual(HeadlessLaunch.parse(["--adega-run", "--bottle", "x", "/a.exe", "-b"]), .init(bottleID: "x", program: "/a.exe", arguments: ["-b"]))
    }

    func testShellQuote() {
        XCTAssertEqual(ShortcutBuilder.shellQuote("simples"), "'simples'")
        XCTAssertEqual(ShortcutBuilder.shellQuote("it's $HOME"), "'it'\\''s $HOME'")
    }

    func testCreatesAppBundle() throws {
        let temp = try TempDir()
        let bottle = Bottle(id: "Steam", url: temp.path("Steam"), config: BottleConfig(displayName: "Steam", runtimeID: "rt"))
        let app = try ShortcutBuilder().create(
            name: "Steam's Launcher",
            bottle: bottle,
            program: URL(fileURLWithPath: "/c/Steam/steam.exe"),
            launcherExecutable: URL(fileURLWithPath: "/Applications/Adega.app/Contents/MacOS/Adega"),
            in: temp.url
        )
        XCTAssertEqual(app.lastPathComponent, "Steam-s Launcher.app")
        let script = try String(contentsOf: app.appendingPathComponent("Contents/MacOS/launch"), encoding: .utf8)
        XCTAssertTrue(script.hasPrefix("#!/bin/sh"))
        XCTAssertTrue(script.contains("exec '/Applications/Adega.app/Contents/MacOS/Adega' '--adega-run' '--bottle' 'Steam' '--' '/c/Steam/steam.exe'"))
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: app.appendingPathComponent("Contents/MacOS/launch").path))
        let plistData = try Data(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
        let plist = try PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]
        XCTAssertEqual(plist?["CFBundleExecutable"] as? String, "launch")
        XCTAssertEqual(plist?["CFBundleName"] as? String, "Steam's Launcher")
    }
}

final class FileOpsAndDiscoveryTests: XCTestCase {
    func testCopyMergingPreservesSymlinksAndMerges() throws {
        let temp = try TempDir()
        let fm = FileManager.default
        let src = temp.path("src")
        try fm.createDirectory(at: src.appendingPathComponent("Fw.framework/Versions/A"), withIntermediateDirectories: true)
        try Data("bin".utf8).write(to: src.appendingPathComponent("Fw.framework/Versions/A/Fw"))
        try fm.createSymbolicLink(atPath: src.appendingPathComponent("Fw.framework/Versions/Current").path, withDestinationPath: "A")
        try Data("novo".utf8).write(to: src.appendingPathComponent("d3d11.dll"))

        let dst = temp.path("dst")
        try fm.createDirectory(at: dst, withIntermediateDirectories: true)
        try Data("antigo".utf8).write(to: dst.appendingPathComponent("d3d11.dll"))
        try Data("fica".utf8).write(to: dst.appendingPathComponent("outro.dll"))

        try FileOps.copyMerging(from: src, to: dst)
        XCTAssertEqual(try String(contentsOf: dst.appendingPathComponent("d3d11.dll"), encoding: .utf8), "novo")
        XCTAssertEqual(try String(contentsOf: dst.appendingPathComponent("outro.dll"), encoding: .utf8), "fica")
        XCTAssertEqual(try fm.destinationOfSymbolicLink(atPath: dst.appendingPathComponent("Fw.framework/Versions/Current").path), "A")
        // Copiar de novo (com o link já existente) não falha.
        XCTAssertNoThrow(try FileOps.copyMerging(from: src, to: dst))
    }

    func testProgramDiscovery() throws {
        let temp = try TempDir()
        let bottle = Bottle(id: "b", url: temp.path("b"), config: BottleConfig(displayName: "b", runtimeID: "rt"))
        let fm = FileManager.default
        func touch(_ relative: String) throws {
            let url = bottle.driveC.appendingPathComponent(relative)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: url)
        }
        try touch("Program Files (x86)/Steam/steam.exe")
        try touch("Program Files (x86)/Steam/uninstall.exe")
        try touch("Program Files/Internet Explorer/iexplore.exe")
        try touch("Program Files/Jogo/bin/win64/Jogo.exe")
        try touch("Program Files/Jogo/bin/win64/CrashReporter.exe")
        try touch("Program Files/Fundo/a/b/c/d/escondido.exe")
        try touch("ProgramData/Microsoft/Windows/Start Menu/Programs/Steam/Steam.lnk")
        try touch("ProgramData/Microsoft/Windows/Start Menu/Programs/Steam/Uninstall Steam.lnk")
        try touch("users/steamuser/AppData/Roaming/Microsoft/Windows/Start Menu/Programs/Editor.lnk")

        let names = ProgramDiscovery.discover(in: bottle).map { "\($0.name)|\($0.source.rawValue)" }
        XCTAssertEqual(Set(names), ["Editor|startMenu", "Jogo|programFiles", "Steam|startMenu", "steam|programFiles"])
        XCTAssertEqual(names.count, 4)
        XCTAssertEqual(names.first, "Editor|startMenu")
    }
}
