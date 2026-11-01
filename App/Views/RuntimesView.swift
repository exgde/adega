import AdegaCore
import SwiftUI
import UniformTypeIdentifiers

struct RuntimesView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingImporter = false
    @State private var copyOnImport = true

    private static let homebrewWine = URL(fileURLWithPath: "/Applications/Wine Crossover.app")

    var body: some View {
        Form {
            Section("Instalados") {
                if model.runtimes.isEmpty {
                    Text("Nenhum runtime ainda. Adicione um Wine já instalado ou baixe um do catálogo.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.runtimes) { runtime in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(runtime.displayName)
                                .bold()
                            Text("\(runtime.version) · \(runtime.isExternal ? "externo (somente leitura)" : "gerenciado pelo Adega")")
                                .font(.caption)
                            if !runtime.runtimeComponents.isEmpty {
                                Text("Componentes: " + runtime.runtimeComponents.values.sorted().joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(runtime.wineRootPath)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Button("Mostrar") { model.reveal(runtime.wineRoot) }
                        Button("Remover", role: .destructive) { model.removeRuntime(runtime) }
                            .disabled(model.isBusy)
                    }
                }
            }

            Section("Adicionar um Wine já instalado") {
                Text("Por exemplo, o Wine Crossover instalado pelo Homebrew: brew install --cask gcenx/wine/wine-crossover")
                    .font(.caption)
                    .textSelection(.enabled)
                Toggle("Copiar para dentro do Adega (necessário para DXMT e D3DMetal)", isOn: $copyOnImport)
                HStack {
                    Button("Escolher pasta ou .app…") { showingImporter = true }
                    Button("Usar /Applications/Wine Crossover.app") {
                        model.addExternalRuntime(location: Self.homebrewWine, copy: copyOnImport)
                    }
                    .disabled(!FileManager.default.fileExists(atPath: Self.homebrewWine.path))
                }
                .disabled(model.isBusy)
            }

            Section("Catálogo") {
                if model.settings.manifestURL.isEmpty {
                    Text("Configure a URL do catálogo (runtimes.json) nos Ajustes (⌘,).")
                        .foregroundStyle(.secondary)
                } else {
                    HStack {
                        Text(model.settings.manifestURL)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Atualizar") { model.fetchManifest() }
                            .disabled(model.isBusy)
                    }
                    ForEach(model.manifest?.runtimes ?? []) { descriptor in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(descriptor.displayName)
                                Text(descriptor.notes ?? descriptor.version)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if model.runtimes.contains(where: { $0.id == descriptor.id }) {
                                Text("Instalado")
                                    .foregroundStyle(.secondary)
                            } else {
                                Button("Baixar") { model.installRuntime(descriptor) }
                                    .disabled(model.isBusy)
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Runtimes do Wine")
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.folder, .application]) { result in
            if case .success(let url) = result {
                model.addExternalRuntime(location: url, copy: copyOnImport)
            }
        }
        .task {
            if model.manifest == nil, !model.settings.manifestURL.isEmpty {
                model.fetchManifest()
            }
        }
    }
}
