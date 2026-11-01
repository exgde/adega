import AdegaCore
import SwiftUI

struct NewBottleSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var runtimeID = ""
    @State private var windows: WindowsVersion = .win10
    @State private var backend: GraphicsBackend = .wined3d
    @State private var retina = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Nova bottle")
                .font(.title2.bold())
            Text("Cada bottle é um \"PC Windows\" separado, com seu próprio disco C: e configurações.")
                .foregroundStyle(.secondary)
            Form {
                TextField("Nome", text: $name, prompt: Text("ex.: Steam, Office, Jogos antigos"))
                Picker("Runtime do Wine", selection: $runtimeID) {
                    ForEach(model.runtimes) { runtime in
                        Text(runtime.displayName).tag(runtime.id)
                    }
                }
                Picker("Versão do Windows", selection: $windows) {
                    ForEach(WindowsVersion.allCases) { version in
                        Text(version.displayName).tag(version)
                    }
                }
                Picker("Gráficos", selection: $backend) {
                    ForEach(GraphicsBackend.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                Text(backend.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let warning = model.availability(of: backend, runtimeID: runtimeID).message {
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Toggle("Modo Retina", isOn: $retina)
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancelar", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Criar") {
                    model.createBottle(name: name, runtimeID: runtimeID, windows: windows, backend: backend, retina: retina)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear {
            if runtimeID.isEmpty { runtimeID = model.runtimes.first?.id ?? "" }
        }
    }

    private var isValid: Bool {
        guard let id = try? NameSanitizer.identifier(from: name) else { return false }
        let nameTaken = model.bottles.contains { $0.id == id }
        return !nameTaken
            && !runtimeID.isEmpty
            && !model.isBusy
            && model.availability(of: backend, runtimeID: runtimeID) == .ready
    }
}
