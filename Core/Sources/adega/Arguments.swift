import Foundation

/// Parser mínimo de argumentos (sem dependências externas).
struct Arguments {
    var positional: [String] = []
    var options: [String: [String]] = [:]
    var flags: Set<String> = []
    /// Tudo depois do primeiro posicional quando `stopAtFirstPositional` está ativo
    /// (ex.: argumentos repassados ao programa Windows).
    var rest: [String] = []

    /// - Parameters:
    ///   - valueOptions: opções que recebem valor (`--bottle X`).
    ///   - stopAtFirstPositional: para de interpretar opções no primeiro posicional.
    init(_ args: [String], valueOptions: Set<String> = [], stopAtFirstPositional: Bool = false) throws {
        var queue = args[...]
        while let arg = queue.popFirst() {
            if arg == "--" {
                if stopAtFirstPositional, let program = queue.popFirst() {
                    positional.append(program)
                }
                rest.append(contentsOf: queue)
                break
            }
            if arg.hasPrefix("--") {
                let name = String(arg.dropFirst(2))
                if let eq = name.firstIndex(of: "=") {
                    options[String(name[..<eq]), default: []].append(String(name[name.index(after: eq)...]))
                } else if valueOptions.contains(name) {
                    guard let value = queue.popFirst() else { throw CLIError("a opção --\(name) precisa de um valor") }
                    options[name, default: []].append(value)
                } else {
                    flags.insert(name)
                }
                continue
            }
            positional.append(arg)
            if stopAtFirstPositional {
                rest.append(contentsOf: queue)
                break
            }
        }
    }

    func value(_ name: String) -> String? { options[name]?.last }
    func values(_ name: String) -> [String] { options[name] ?? [] }
    func has(_ flag: String) -> Bool { flags.contains(flag) }

    func required(_ name: String) throws -> String {
        guard let value = value(name) else { throw CLIError("falta a opção --\(name)") }
        return value
    }

    func positional(_ index: Int, _ what: String) throws -> String {
        guard positional.indices.contains(index) else { throw CLIError("falta o argumento <\(what)>") }
        return positional[index]
    }

    /// "on"/"off", "sim"/"nao", "true"/"false", "1"/"0".
    func bool(_ name: String) throws -> Bool? {
        guard let raw = value(name)?.lowercased() else { return nil }
        switch raw {
        case "on", "sim", "true", "1", "yes": return true
        case "off", "nao", "não", "false", "0", "no": return false
        default: throw CLIError("valor inválido para --\(name): \(raw) (use on/off)")
        }
    }
}

struct CLIError: Error, LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
