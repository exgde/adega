import AdegaCore
import SwiftUI
import UniformTypeIdentifiers

struct ComponentsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingGPTKImporter = false

    var body: some View {
        Form {
            Section("Instalados") {
                if model.components.isEmpty {
                    Text("Nenhum componente. Sem eles, só o backend WineD3D (OpenGL) fica disponível.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.components) { component in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(component.kind.displayName) \(component.descriptor.version)")
                                .bold()
                            if let license = component.descriptor.license {
                                Text("Licença: \(license)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button("Remover", role: .destructive) { model.removeComponent(component) }
                            .disabled(model.isBusy)
                    }
                }
            }

            Section("D3DMetal (Game Porting Toolkit da Apple)") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("O D3DMetal tem licença da Apple e não vem com o Adega. Para usar:")
                    Text("1. Baixe o Game Porting Toolkit em developer.apple.com/games (conta gratuita).")
                    Text("2. Abra o DMG \"Evaluation environment for Windows games\".")
                    Text("3. Clique em Importar e escolha o volume montado (ou a pasta redist/lib).")
                }
                .font(.callout)
                Button("Importar do GPTK…") { showingGPTKImporter = true }
                    .disabled(model.isBusy)
            }

            Section("Catálogo") {
                if model.settings.manifestURL.isEmpty {
                    Text("Configure a URL do catálogo nos Ajustes (⌘,) para baixar DXVK, DXMT e MoltenVK.")
                        .foregroundStyle(.secondary)
                } else if let catalog = model.manifest?.components, !catalog.isEmpty {
                    ForEach(catalog) { descriptor in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(descriptor.kind.displayName) \(descriptor.version)")
                                Text(descriptor.notes ?? descriptor.license ?? "")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if model.components.contains(where: { $0.id == descriptor.id }) {
                                Text("Instalado")
                                    .foregroundStyle(.secondary)
                            } else {
                                Button("Baixar") { model.installComponent(descriptor) }
                                    .disabled(model.isBusy)
                            }
                        }
                    }
                } else {
                    Button("Carregar catálogo") { model.fetchManifest() }
                        .disabled(model.isBusy)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Componentes gráficos")
        .fileImporter(isPresented: $showingGPTKImporter, allowedContentTypes: [.folder, .volume]) { result in
            if case .success(let url) = result {
                model.importD3DMetal(from: url)
            }
        }
    }
}
