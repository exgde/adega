import AdegaCore
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationSplitView {
            List(selection: $model.selection) {
                Section("Bottles") {
                    ForEach(model.bottles) { bottle in
                        Label(bottle.config.displayName, systemImage: "wineglass")
                            .badge(model.runningCount(in: bottle))
                            .tag(SidebarItem.bottle(bottle.id))
                    }
                }
                Section("Sistema") {
                    Label("Runtimes do Wine", systemImage: "shippingbox")
                        .tag(SidebarItem.runtimes)
                    Label("Componentes gráficos", systemImage: "cpu")
                        .tag(SidebarItem.components)
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 230)
            .toolbar {
                ToolbarItem {
                    Button {
                        model.showingNewBottle = true
                    } label: {
                        Label("Nova bottle", systemImage: "plus")
                    }
                    .disabled(model.runtimes.isEmpty)
                    .help(model.runtimes.isEmpty ? "Adicione um runtime do Wine primeiro" : "Nova bottle")
                }
            }
        } detail: {
            VStack(spacing: 0) {
                if !SystemCheck.isRosettaInstalled {
                    RosettaBanner()
                }
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if let message = model.busyMessage {
                    StatusBar(message: message, progress: model.progress)
                }
            }
        }
        .sheet(isPresented: $model.showingNewBottle) {
            NewBottleSheet()
                .environmentObject(model)
        }
        .alert("Algo deu errado", isPresented: errorBinding) {
            Button("OK") {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch model.selection {
        case .bottle(let id):
            if let bottle = model.bottles.first(where: { $0.id == id }) {
                BottleDetailView(bottle: bottle)
                    .id(bottle.id)
            } else {
                ContentUnavailableView("Selecione uma bottle", systemImage: "wineglass")
            }
        case .runtimes:
            RuntimesView()
        case .components:
            ComponentsView()
        case nil:
            WelcomeView()
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )
    }
}

struct WelcomeView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "wineglass")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Bem-vindo ao Adega")
                .font(.largeTitle.bold())
            Text("Rode programas do Windows no seu Mac em bottles isoladas.")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                step(1, "Adicione um runtime do Wine", done: !model.runtimes.isEmpty)
                step(2, "Crie uma bottle", done: !model.bottles.isEmpty)
                step(3, "Rode um instalador (setup.exe) dentro dela", done: false)
            }
            .padding()
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            HStack {
                Button("Runtimes do Wine") { model.selection = .runtimes }
                Button("Nova bottle") { model.showingNewBottle = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.runtimes.isEmpty)
            }
        }
        .padding(40)
    }

    private func step(_ number: Int, _ text: String, done: Bool) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: done ? "checkmark.circle.fill" : "\(number).circle")
                .foregroundStyle(done ? Color.green : Color.secondary)
        }
    }
}

struct StatusBar: View {
    let message: String
    let progress: Double?

    var body: some View {
        HStack(spacing: 10) {
            if let progress {
                ProgressView(value: progress)
                    .frame(width: 140)
                Text("\(Int(progress * 100))%")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
            Text(message)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

struct RosettaBanner: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("O Rosetta 2 não está instalado. O Wine precisa dele no Apple Silicon. Rode no Terminal:")
            Text(SystemCheck.rosettaInstallCommand)
                .font(.body.monospaced())
                .textSelection(.enabled)
            Spacer()
            Button("Copiar") { model.copyToPasteboard(SystemCheck.rosettaInstallCommand) }
        }
        .padding(10)
        .background(Color.orange.opacity(0.12))
    }
}
