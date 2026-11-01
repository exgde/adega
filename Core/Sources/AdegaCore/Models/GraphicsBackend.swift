import Foundation

/// Como o DirectX do programa Windows é traduzido para a GPU do Mac.
public enum GraphicsBackend: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Embutido no Wine: DirectX → OpenGL. Sempre disponível, mais lento.
    case wined3d
    /// DXVK (DX9–11 → Vulkan) + MoltenVK (Vulkan → Metal).
    case dxvk
    /// DXMT (DX10/11 → Metal direto).
    case dxmt
    /// D3DMetal da Apple (DX11/12 → Metal). Vem do Game Porting Toolkit, fornecido pelo usuário.
    case d3dmetal

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .wined3d: return "WineD3D (OpenGL)"
        case .dxvk: return "DXVK + MoltenVK"
        case .dxmt: return "DXMT (Metal)"
        case .d3dmetal: return "D3DMetal (Apple GPTK)"
        }
    }

    public var summary: String {
        switch self {
        case .wined3d: return "Compatível com tudo, desempenho baixo. Bom para apps e jogos antigos."
        case .dxvk: return "DirectX 9–11 via Vulkan. Requer o componente DXVK."
        case .dxmt: return "DirectX 10/11 direto em Metal. Requer o componente DXMT."
        case .d3dmetal: return "DirectX 11/12 em Metal (o melhor para jogos modernos). Requer o GPTK da Apple."
        }
    }

    /// O componente que precisa estar instalado para este backend (nil = embutido).
    public var requiredComponent: ComponentKind? {
        switch self {
        case .wined3d: return nil
        case .dxvk: return .dxvk
        case .dxmt: return .dxmt
        case .d3dmetal: return .d3dmetal
        }
    }

    /// Overrides de DLL aplicados na execução (via `WINEDLLOVERRIDES`).
    /// Como são definidos a cada execução, trocar de backend não exige mexer no registro
    /// e DLLs de outro backend que sobraram em system32 são ignoradas.
    public var dllOverrides: [String: String] {
        switch self {
        case .wined3d:
            return ["d3d9": "b", "d3d10core": "b", "d3d11": "b", "dxgi": "b"]
        case .dxvk:
            return ["d3d9": "n,b", "d3d10core": "n,b", "d3d11": "n,b", "dxgi": "n,b"]
        case .dxmt:
            return ["d3d10core": "n,b", "d3d11": "n,b", "dxgi": "n,b"]
        case .d3dmetal:
            return ["d3d10core": "b", "d3d11": "b", "d3d12": "b", "dxgi": "b"]
        }
    }
}

public enum WindowsVersion: String, Codable, CaseIterable, Identifiable, Sendable {
    case win11, win10, win81, win8, win7

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .win11: return "Windows 11"
        case .win10: return "Windows 10"
        case .win81: return "Windows 8.1"
        case .win8: return "Windows 8"
        case .win7: return "Windows 7"
        }
    }
}
