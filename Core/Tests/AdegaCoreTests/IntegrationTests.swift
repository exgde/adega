import Foundation
import XCTest
@testable import AdegaCore

/// Fluxos completos usando um Wine falso (scripts shell) — rodam em Linux e macOS.
final class IntegrationTests: XCTestCase {
    var temp: TempDir!
    var paths: AdegaPaths!

    override func setUpWithError() throws {
        temp = try TempDir()
        paths = AdegaPaths(root: temp.path("home"))
        try paths.ensureDirectories()
    }

    override func tearDown() {
        temp = nil
    }

    func testRegisterExternalWithAndWithoutCopy() async throws {
        let wineRoot = try Fixtures.makeFakeWine(at: temp.path("ext/wine"), binaryName: "wine64")
        let manager = RuntimeManager(paths: paths)

        let linked = try await manager.registerExternal(name: "Wine Externo", location: wineRoot.appendingPathComponent("bin"), copy: false)
        XCTAssertTrue(linked.isExternal)
        XCTAssertEqual(linked.wineRootPath, wineRoot.standardizedFileURL.path)
        XCTAssertEqual(try linked.wineBinary().lastPathComponent, "wine64")
        let version = await manager.detectVersion(of: linked)
        XCTAssertEqual(version, "wine-fake-9.9")

        let copied = try await manager.registerExternal(name: "Wine Copiado", location: wineRoot, copy: true)
        XCTAssertFalse(copied.isExternal)
        XCTAssertTrue(copied.wineRootPath.hasPrefix(paths.runtimes.path))
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: copied.wineRoot.appendingPathComponent("bin/wine64").path))

        XCTAssertEqual(manager.installedRuntimes().map(\.id), ["Wine Copiado", "Wine Externo"])

        // Remover o runtime externo não apaga a instalação original.
        try manager.remove(id: linked.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: wineRoot.appendingPathComponent("bin/wine64").path))
        XCTAssertEqual(manager.installedRuntimes().map(\.id), ["Wine Copiado"])

        do {
            _ = try await manager.registerExternal(name: "Sem Wine", location: temp.path("vazio"), copy: false)
            XCTFail("deveria falhar")
        } catch {
            XCTAssertTrue(error is AdegaError)
        }
    }

    func testInstallRuntimeFromManifestVerifiesChecksum() async throws {
        // Empacota um Wine falso como faria o pipeline de build.
        let staging = temp.path("pkg")
        try Fixtures.makeFakeWine(at: staging.appendingPathComponent("wine-test/wine"))
        let archive = temp.path("wine-test.tar.gz")
        try Fixtures.makeTarGz(of: staging, contentsNamed: "wine-test", output: archive)
        let sha = try FileHasher.sha256Hex(of: archive)

        let manager = RuntimeManager(paths: paths)
        let bad = RuntimeDescriptor(id: "wine-bad", displayName: "Ruim", version: "1", url: archive, sha256: String(repeating: "0", count: 64), wineRoot: "wine-test/wine")
        do {
            _ = try await manager.install(bad)
            XCTFail("checksum errado deveria falhar")
        } catch AdegaError.checksumMismatch(_, let actual) {
            XCTAssertEqual(actual, sha)
        }
        XCTAssertTrue(manager.installedRuntimes().isEmpty, "instalação falha não deixa lixo")

        let good = RuntimeDescriptor(id: "wine-test", displayName: "Wine Teste", version: "9.9", url: archive, sha256: sha.uppercased(), wineRoot: "wine-test/wine")
        let runtime = try await manager.install(good)
        XCTAssertEqual(try runtime.wineBinary().lastPathComponent, "wine")
        XCTAssertEqual(try manager.runtime(id: "wine-test"), runtime)
        do {
            _ = try await manager.install(good)
            XCTFail("instalar duas vezes deveria falhar")
        } catch AdegaError.runtimeAlreadyInstalled {}
    }

    func testCreateBottleRunsWinebootAndSettings() async throws {
        let runtime = Fixtures.runtime(at: try Fixtures.makeFakeWine(at: temp.path("wine")))
        let manager = BottleManager(paths: paths)
        let config = BottleConfig(displayName: "", runtimeID: runtime.id, windowsVersion: .win11, retinaMode: true)
        let bottle = try await manager.create(name: "Meus Jogos", config: config, runtime: runtime)

        XCTAssertTrue(bottle.isInitialized())
        XCTAssertEqual(bottle.config.displayName, "Meus Jogos")
        let calls = Fixtures.calls(in: bottle)
        XCTAssertTrue(calls[0].hasPrefix("wine wineboot --init"))
        XCTAssertTrue(calls[1].hasPrefix("wine winecfg -v win11"))
        XCTAssertTrue(calls[2].hasPrefix(#"wine reg add HKCU\Software\Wine\Mac Driver /v RetinaMode /t REG_SZ /d y /f"#))
        XCTAssertTrue(calls[0].contains("MSYNC=1"))

        // O id devolvido é sempre o nome real da pasta, digitado de qualquer jeito.
        XCTAssertEqual(try manager.find("meus jogos").id, "Meus Jogos")
        XCTAssertEqual(try manager.bottle(id: "MEUS JOGOS").id, "Meus Jogos")
        for duplicate in ["Meus Jogos", "meus jogos"] {
            do {
                _ = try await manager.create(name: duplicate, config: config, runtime: runtime)
                XCTFail("nome duplicado deveria falhar: \(duplicate)")
            } catch AdegaError.bottleAlreadyExists(let existing) {
                XCTAssertEqual(existing, "Meus Jogos")
            }
        }

        // Mudanças: só roda o que mudou.
        var updated = bottle
        updated.config.windowsVersion = .win7
        try await manager.applyChanges(to: updated, previous: bottle.config, runtime: runtime)
        XCTAssertTrue(Fixtures.calls(in: bottle).last?.hasPrefix("wine winecfg -v win7") == true)
        XCTAssertEqual(try manager.bottle(id: bottle.id).config.windowsVersion, .win7)

        try manager.delete(updated)
        XCTAssertTrue(manager.bottles().isEmpty)
    }

    func testFailedWinebootCleansUp() async throws {
        let runtime = Fixtures.runtime(at: try Fixtures.makeFakeWine(at: temp.path("wine"), failWineboot: true))
        let manager = BottleManager(paths: paths)
        do {
            _ = try await manager.create(name: "Quebrada", config: BottleConfig(displayName: "", runtimeID: runtime.id), runtime: runtime)
            XCTFail("deveria falhar")
        } catch AdegaError.processFailed(let command, let code, let output) {
            XCTAssertEqual(command, "wine wineboot --init")
            XCTAssertEqual(code, 3)
            XCTAssertTrue(output.contains("falha simulada"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.bottles.appendingPathComponent("Quebrada").path))
    }

    func testComponentInstallAndBackendPreparation() async throws {
        // Pacote "DXMT" falso: um .so para o runtime e DLLs para a bottle.
        let pkg = temp.path("dxmt-pkg/dxmt")
        let fm = FileManager.default
        try fm.createDirectory(at: pkg.appendingPathComponent("x86_64-unix"), withIntermediateDirectories: true)
        try fm.createDirectory(at: pkg.appendingPathComponent("x86_64-windows"), withIntermediateDirectories: true)
        try Data("so".utf8).write(to: pkg.appendingPathComponent("x86_64-unix/winemetal.so"))
        try Data("d3d11-dxmt".utf8).write(to: pkg.appendingPathComponent("x86_64-windows/d3d11.dll"))
        let archive = temp.path("dxmt.tar.gz")
        try Fixtures.makeTarGz(of: temp.path("dxmt-pkg"), contentsNamed: "dxmt", output: archive)

        let descriptor = ComponentDescriptor(
            id: "dxmt-test", kind: .dxmt, version: "0.1", url: archive, sha256: try FileHasher.sha256Hex(of: archive), root: "dxmt",
            files: [
                FileMapping(source: "x86_64-unix/winemetal.so", destination: "lib/wine/x86_64-unix/winemetal.so", scope: .runtime),
                FileMapping(source: "x86_64-windows/d3d11.dll", destination: "drive_c/windows/system32/d3d11.dll", scope: .bottle),
            ]
        )

        let runtimes = RuntimeManager(paths: paths)
        let components = ComponentManager(paths: paths)
        let wineRoot = try Fixtures.makeFakeWine(at: temp.path("ext-wine"))
        var runtime = try await runtimes.registerExternal(name: "Gravavel", location: wineRoot, copy: true)
        let bottle = try await BottleManager(paths: paths).create(name: "DX11", config: BottleConfig(displayName: "", runtimeID: runtime.id, graphicsBackend: .dxmt), runtime: runtime)

        XCTAssertEqual(components.availability(of: .dxmt, runtime: runtime), .missingComponent(.dxmt))
        XCTAssertThrowsError(try components.prepareBackend(.dxmt, bottle: bottle, runtime: runtime, runtimeManager: runtimes))
        XCTAssertEqual(components.availability(of: .wined3d, runtime: runtime), .ready)

        let installed = try await components.install(descriptor)
        XCTAssertEqual(components.latest(.dxmt)?.id, installed.id)

        runtime = try components.prepareBackend(.dxmt, bottle: bottle, runtime: runtime, runtimeManager: runtimes)
        XCTAssertEqual(runtime.runtimeComponents["dxmt"], "dxmt-test")
        XCTAssertEqual(try runtimes.runtime(id: runtime.id).runtimeComponents["dxmt"], "dxmt-test")
        XCTAssertEqual(try String(contentsOf: runtime.wineRoot.appendingPathComponent("lib/wine/x86_64-unix/winemetal.so"), encoding: .utf8), "so")
        XCTAssertEqual(try String(contentsOf: bottle.system32.appendingPathComponent("d3d11.dll"), encoding: .utf8), "d3d11-dxmt")

        // Runtime externo (sem cópia) não pode receber arquivos.
        let readOnly = try await runtimes.registerExternal(name: "SoLeitura", location: try Fixtures.makeFakeWine(at: temp.path("ro-wine")), copy: false)
        XCTAssertEqual(components.availability(of: .dxmt, runtime: readOnly), .runtimeReadOnly)
        XCTAssertThrowsError(try components.prepareBackend(.dxmt, bottle: bottle, runtime: readOnly, runtimeManager: runtimes)) { error in
            XCTAssertEqual(error as? AdegaError, .externalRuntimeIsReadOnly("SoLeitura"))
        }
    }

    func testImportD3DMetalFromGPTKFolder() throws {
        let gptk = temp.path("Evaluation environment for Windows games 3.0")
        let fm = FileManager.default
        let lib = gptk.appendingPathComponent("redist/lib")
        try fm.createDirectory(at: lib.appendingPathComponent("external/D3DMetal.framework/Versions/A"), withIntermediateDirectories: true)
        try fm.createSymbolicLink(atPath: lib.appendingPathComponent("external/D3DMetal.framework/Versions/Current").path, withDestinationPath: "A")
        try fm.createDirectory(at: lib.appendingPathComponent("wine/x86_64-windows"), withIntermediateDirectories: true)
        try Data("gptk-d3d12".utf8).write(to: lib.appendingPathComponent("wine/x86_64-windows/d3d12.dll"))

        let components = ComponentManager(paths: paths)
        XCTAssertThrowsError(try components.importD3DMetal(from: temp.url))
        let component = try components.importD3DMetal(from: gptk, version: "3.0")
        XCTAssertEqual(component.kind, .d3dmetal)

        let runtimeRoot = try Fixtures.makeFakeWine(at: temp.path("rt"))
        let runtimes = RuntimeManager(paths: paths)
        let runtime = Fixtures.runtime(at: runtimeRoot)
        try runtimes.save(runtime)
        let bottle = Bottle(id: "x", url: temp.path("x"), config: BottleConfig(displayName: "x", runtimeID: runtime.id, graphicsBackend: .d3dmetal))
        let updated = try components.prepareBackend(.d3dmetal, bottle: bottle, runtime: runtime, runtimeManager: runtimes)
        XCTAssertEqual(updated.runtimeComponents["d3dmetal"], "d3dmetal-3.0")
        XCTAssertEqual(try String(contentsOf: runtimeRoot.appendingPathComponent("lib/wine/x86_64-windows/d3d12.dll"), encoding: .utf8), "gptk-d3d12")
        XCTAssertEqual(try fm.destinationOfSymbolicLink(atPath: runtimeRoot.appendingPathComponent("lib/external/D3DMetal.framework/Versions/Current").path), "A")
    }

    func testLauncherWritesLogAndRunsFromProgramFolder() async throws {
        let runtime = Fixtures.runtime(at: try Fixtures.makeFakeWine(at: temp.path("wine")))
        let bottle = try await BottleManager(paths: paths).create(name: "Run", config: BottleConfig(displayName: "", runtimeID: runtime.id, graphicsBackend: .dxvk), runtime: runtime)
        let exe = bottle.driveC.appendingPathComponent("Jogo/Jogo.exe")
        try FileManager.default.createDirectory(at: exe.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: exe)

        let launcher = Launcher(paths: paths)
        let process = try launcher.launch(program: exe, arguments: ["-windowed"], in: bottle, runtime: runtime)
        process.waitUntilExit()
        XCTAssertEqual(process.exitCode, 0)

        let last = try XCTUnwrap(Fixtures.calls(in: bottle).last)
        XCTAssertTrue(last.hasPrefix("wine \(exe.path) -windowed"))
        XCTAssertTrue(last.contains("OVERRIDES=d3d10core=n,b;d3d11=n,b;d3d9=n,b;dxgi=n,b"))
        // Só o final do caminho: no macOS o /var do temporário é link para /private/var.
        XCTAssertTrue(last.hasSuffix("/drive_c/Jogo"), last)

        let logs = launcher.logFiles(for: bottle)
        XCTAssertEqual(logs.count, 1)
        let log = launcher.readLog(logs[0])
        XCTAssertTrue(log.contains("Backend:  DXVK + MoltenVK"))
        XCTAssertTrue(log.contains("WINEPREFIX=\(bottle.url.path)"))

        // Atalhos usam o mesmo caminho via HeadlessLaunch (que lê o runtime do disco).
        try RuntimeManager(paths: paths).save(runtime)
        let headless = try HeadlessLaunch.perform(.init(bottleID: bottle.id, program: exe.path), paths: paths)
        headless.waitUntilExit()
        XCTAssertEqual(Fixtures.calls(in: bottle).last?.hasPrefix("wine \(exe.path) |"), true)
    }

    func testWinetricksVerbValidation() throws {
        XCTAssertEqual(try Winetricks.validate([" VCRUN2022 ", "d3dcompiler_47", "win10"]), ["vcrun2022", "d3dcompiler_47", "win10"])
        XCTAssertThrowsError(try Winetricks.validate(["--force"]))
        XCTAssertThrowsError(try Winetricks.validate(["a;rm -rf /"]))
        XCTAssertThrowsError(try Winetricks.validate([""]))
    }

    func testSettingsPersistence() throws {
        XCTAssertEqual(AppSettings.load(paths: paths), AppSettings())
        let settings = AppSettings(manifestURL: "https://example.com/runtimes.json", presetsURL: "~/presets.json")
        try settings.save(paths: paths)
        XCTAssertEqual(AppSettings.load(paths: paths), settings)
        XCTAssertEqual(ManifestLoader.resolve("~/presets.json").path, NSHomeDirectory() + "/presets.json")
        XCTAssertEqual(ManifestLoader.resolve(" https://example.com/a.json ").absoluteString, "https://example.com/a.json")
    }
}
