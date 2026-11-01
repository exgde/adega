import Foundation

/// Leitura/escrita de JSON com formato estável (chaves ordenadas, datas ISO 8601).
enum JSONStore {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static func read<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        try decoder().decode(type, from: Data(contentsOf: url))
    }

    static func write<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder().encode(value).write(to: url, options: .atomic)
    }
}

extension Date {
    /// Datas são gravadas em ISO 8601 (precisão de segundos). Arredondar na criação
    /// mantém o valor em memória igual ao lido do disco.
    var truncatedToSeconds: Date {
        Date(timeIntervalSince1970: timeIntervalSince1970.rounded(.down))
    }
}

/// Converte um nome dado pelo usuário em um identificador seguro para nome de pasta.
public enum NameSanitizer {
    public static func identifier(from name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_."))
        var result = ""
        for scalar in trimmed.unicodeScalars {
            result.unicodeScalars.append(allowed.contains(scalar) ? scalar : "-")
        }
        // Evita nomes como "." / ".." ou ocultos.
        while result.hasPrefix(".") { result.removeFirst() }
        result = result.trimmingCharacters(in: .whitespaces)
        guard !result.isEmpty, result.count <= 64 else {
            throw AdegaError.invalidName(name)
        }
        return result
    }
}
