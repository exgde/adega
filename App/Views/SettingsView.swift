import AdegaCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section("Catálogos") {
                TextField("Runtimes e componentes", text: $model.settings.manifestURL, prompt: Text("https://…/runtimes.json"))
                TextField("Receitas por jogo/app", text: $model.settings.presetsURL, prompt: Text("https://…/presets.json"))
                Text("Aceita https:// ou um caminho de arquivo local. Exemplos em manifests/ e presets/ no repositório.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("Salvar") { model.saveSettings() }
                        .keyboardShortcut(.defaultAction)
                }
            }
            Section("Dados") {
                Text(model.paths.root.path)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                Button("Mostrar no Finder") { model.reveal(model.paths.root) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 540)
        .padding()
    }
}
