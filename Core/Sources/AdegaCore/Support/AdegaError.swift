import Foundation

public enum AdegaError: Error, LocalizedError, Equatable {
    case invalidName(String)
    case bottleAlreadyExists(String)
    case bottleNotFound(String)
    case runtimeAlreadyInstalled(String)
    case runtimeNotFound(String)
    case wineBinaryNotFound(String)
    case externalRuntimeIsReadOnly(String)
    case componentNotInstalled(String)
    case componentFileMissing(String)
    case invalidD3DMetalFolder(String)
    case checksumMismatch(expected: String, actual: String)
    case httpStatus(Int)
    case downloadFailed(String)
    case unsupportedArchive(String)
    case unsupportedFileType(String)
    case invalidVerb(String)
    case processFailed(command: String, exitCode: Int32, outputTail: String)

    public var errorDescription: String? {
        switch self {
        case .invalidName(let name):
            return "Nome inválido: \"\(name)\". Use letras, números, espaço, '-' ou '_'."
        case .bottleAlreadyExists(let id):
            return "Já existe uma bottle chamada \"\(id)\"."
        case .bottleNotFound(let id):
            return "Bottle \"\(id)\" não encontrada."
        case .runtimeAlreadyInstalled(let id):
            return "O runtime \"\(id)\" já está instalado."
        case .runtimeNotFound(let id):
            return "Runtime \"\(id)\" não encontrado. Instale ou registre um runtime do Wine primeiro."
        case .wineBinaryNotFound(let path):
            return "Não encontrei o executável do Wine (bin/wine ou bin/wine64) em \(path)."
        case .externalRuntimeIsReadOnly(let id):
            return "O runtime \"\(id)\" é externo (fora do Adega) e não é modificado. Registre-o com cópia para poder instalar componentes nele."
        case .componentNotInstalled(let kind):
            return "O componente \"\(kind)\" não está instalado."
        case .componentFileMissing(let path):
            return "Arquivo do componente não encontrado: \(path)"
        case .invalidD3DMetalFolder(let path):
            return "A pasta \(path) não parece conter o D3DMetal (esperado: redist/lib/external/D3DMetal.framework)."
        case .checksumMismatch(let expected, let actual):
            return "O SHA-256 do download não confere (esperado \(expected), obtido \(actual))."
        case .httpStatus(let code):
            return "O servidor respondeu com HTTP \(code)."
        case .downloadFailed(let reason):
            return "Falha no download: \(reason)"
        case .unsupportedArchive(let name):
            return "Formato de arquivo não suportado: \(name)"
        case .unsupportedFileType(let name):
            return "Tipo de arquivo não suportado para execução: \(name) (use .exe, .msi, .bat ou .lnk)."
        case .invalidVerb(let verb):
            return "Verbo do winetricks inválido: \(verb)"
        case .processFailed(let command, let exitCode, let outputTail):
            return "O comando \"\(command)\" falhou (código \(exitCode)).\n\(outputTail)"
        }
    }
}
