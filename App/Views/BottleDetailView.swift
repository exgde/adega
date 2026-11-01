import AdegaCore
import SwiftUI
import UniformTypeIdentifiers

struct BottleDetailView: View {
    @EnvironmentObject private var model: AppModel
    let bottle: Bottle

    private enum Tab: Hashable {
        case programs, settings, dependencies, logs
    }

    @State private var tab: Tab = .programs
    @State private var showingImporter = false
    @State private var confirmingDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding()
            Divider()
            TabView(selection: $tab) {
                ProgramsTab(bottle: bottle)
                    .tabItem { Text("Programas") }
                    .tag(Tab.programs)
                BottleSettingsTab(bottle: bottle)
                    .tabItem { Text("Configurações") }
                    .tag(Tab.settings)
                DependenciesTab(bottle: bottle)
                    .tabItem { Text("Dependências") }
                    .tag(Tab.dependencies)
                LogsTab(bottle: bottle)
                    .tabItem { Text("Logs") }
                    .tag(Tab.logs)
            }
            .padding()
        }
        .navigationTitle(bottle.config.displayName)
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.item]) { result in
            if case .success(let url) = result {
                model.run(url, in: bottle)
            }
        }
        .confirmationDialog(
            "Apagar a bottle \"\(bottle.config.displayName)\"?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Mover para a Lixeira", role: .destructive) { model.delete(bottle) }
        } message: {
            Text("Todos os programas e saves dentro dela vão junto.")
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "wineglass")
                .font(.system(size: 28))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(bottle.config.displayName)
                    .font(.title2.bold())
                Text("\(bottle.config.windowsVersion.displayName) · \(bottle.config.graphicsBackend.displayName) · \(bottle.config.runtimeID)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            let count = model.runningCount(in: bottle)
            if count > 0 {
                Label("\(count) em execução", systemImage: "circle.fill")
                    .font(.callout)
                    .foregroundStyle(.green)
            }
            Button {
                showingImporter = true
            } label: {
                Label("Executar…", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .help("Abrir um .exe, .msi, .bat ou .lnk nesta bottle")
            Menu {
                Button("Abrir o disco C: no Finder") { model.reveal(bottle.driveC) }
                Button("Encerrar todos os processos") { model.killAll(in: bottle) }
                Divider()
                Button("Apagar bottle…", role: .destructive) { confirmingDelete = true }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .fixedSize()
        }
    }
}

// MARK: - Programas

struct ProgramsTab: View {
    @EnvironmentObject private var model: AppModel
    let bottle: Bottle
    @State private var discovered: [DiscoveredProgram] = []

    var body: some View {
        VStack(alignment: .leading) {
            List {
                if !bottle.config.pinnedPrograms.isEmpty {
                    Section("Favoritos") {
                        ForEach(bottle.config.pinnedPrograms) { pinned in
                            ProgramRow(name: pinned.name, url: URL(fileURLWithPath: pinned.path), bottle: bottle, isPinned: true)
                        }
                    }
                }
                Section("Instalados") {
                    if discovered.isEmpty {
                        Text("Nenhum programa encontrado. Use \"Executar…\" para rodar um instalador (setup.exe).")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(discovered) { program in
                        ProgramRow(
                            name: program.name,
                            url: program.url,
                            bottle: bottle,
                            isPinned: bottle.config.pinnedPrograms.contains { $0.path == program.url.path }
                        )
                    }
                }
            }
            HStack {
                Spacer()
                Button("Atualizar lista") {
                    Task { await refresh() }
                }
            }
        }
        .task(id: bottle.id) { await refresh() }
        // Quando um instalador termina, a lista muda.
        .onChange(of: model.runningCount(in: bottle)) {
            Task { await refresh() }
        }
    }

    private func refresh() async {
        let bottle = bottle
        discovered = await Task.detached { ProgramDiscovery.discover(in: bottle) }.value
    }
}

struct ProgramRow: View {
    @EnvironmentObject private var model: AppModel
    let name: String
    let url: URL
    let bottle: Bottle
    let isPinned: Bool

    var body: some View {
        HStack {
            Image(systemName: url.pathExtension.lowercased() == "lnk" ? "arrow.up.forward.app" : "app")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading) {
                Text(name)
                Text(url.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if let preset = model.presets.match(executable: url) {
                Button("Aplicar receita") { model.applyPreset(preset, to: bottle) }
                    .help(preset.notes ?? preset.name)
                    .disabled(model.isBusy)
            }
            Button {
                model.togglePin(name: name, url: url, in: bottle)
            } label: {
                Image(systemName: isPinned ? "star.fill" : "star")
            }
            .buttonStyle(.borderless)
            .help(isPinned ? "Remover dos favoritos" : "Favoritar")
            Button {
                model.createShortcut(name: name, program: url, bottle: bottle)
            } label: {
                Image(systemName: "square.and.arrow.down")
            }
            .buttonStyle(.borderless)
            .help("Criar atalho em ~/Applications/Adega")
            Button("Abrir") { model.run(url, in: bottle) }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Configurações

struct BottleSettingsTab: View {
    @EnvironmentObject private var model: AppModel
    let bottle: Bottle
    @State private var draft: BottleConfig

    init(bottle: Bottle) {
        self.bottle = bottle
        _draft = State(initialValue: bottle.config)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Sistema") {
                    Picker("Runtime do Wine", selection: $draft.runtimeID) {
                        ForEach(model.runtimes) { runtime in
                            Text(runtime.displayName).tag(runtime.id)
                        }
                    }
                    Picker("Versão do Windows", selection: $draft.windowsVersion) {
                        ForEach(WindowsVersion.allCases) { version in
                            Text(version.displayName).tag(version)
                        }
                    }
                }
                Section("Gráficos") {
                    Picker("Backend", selection: $draft.graphicsBackend) {
                        ForEach(GraphicsBackend.allCases) { backend in
                            Text(backend.displayName).tag(backend)
                        }
                    }
                    Text(draft.graphicsBackend.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let warning = model.availability(of: draft.graphicsBackend, runtimeID: draft.runtimeID).message {
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                    Toggle("Modo Retina (resolução nativa)", isOn: $draft.retinaMode)
                    Toggle("HUD de desempenho", isOn: $draft.performanceHUD)
                }
                Section("Desempenho") {
                    Toggle("MSync (sincronização rápida)", isOn: $draft.msync)
                    Toggle("Anunciar AVX ao Rosetta (macOS 15+)", isOn: $draft.advertiseAVX)
                }
                Section("Variáveis de ambiente") {
                    KeyValueEditor(values: $draft.environment, keyPlaceholder: "CHAVE", valuePlaceholder: "valor")
                }
                Section("Overrides de DLL") {
                    KeyValueEditor(values: $draft.dllOverrides, keyPlaceholder: "dll (ex.: d3d11)", valuePlaceholder: "modo (n,b / b / vazio)")
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Descartar") { draft = bottle.config }
                    .disabled(draft == bottle.config)
                Button("Salvar") {
                    var updated = bottle
                    updated.config = draft
                    model.save(updated, previous: bottle.config)
                }
                .keyboardShortcut("s", modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(draft == bottle.config || model.isBusy || model.availability(of: draft.graphicsBackend, runtimeID: draft.runtimeID) != .ready)
            }
            .padding(.top, 8)
        }
    }
}

struct KeyValueEditor: View {
    @Binding var values: [String: String]
    let keyPlaceholder: String
    let valuePlaceholder: String
    @State private var newKey = ""
    @State private var newValue = ""

    var body: some View {
        ForEach(values.keys.sorted(), id: \.self) { key in
            HStack {
                Text(key)
                    .font(.body.monospaced())
                Spacer()
                Text(values[key] ?? "")
                    .font(.body.monospaced())
                    .foregroundStyle(.secondary)
                Button {
                    values.removeValue(forKey: key)
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
            }
        }
        HStack {
            TextField(keyPlaceholder, text: $newKey)
            TextField(valuePlaceholder, text: $newValue)
            Button("Adicionar") {
                let key = newKey.trimmingCharacters(in: .whitespaces)
                guard !key.isEmpty else { return }
                values[key] = newValue.trimmingCharacters(in: .whitespaces)
                newKey = ""
                newValue = ""
            }
            .disabled(newKey.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }
}

// MARK: - Dependências

struct DependenciesTab: View {
    @EnvironmentObject private var model: AppModel
    let bottle: Bottle
    @State private var selected: Set<String> = []
    @State private var custom = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Instala componentes do Windows com o winetricks. Os arquivos são baixados das fontes oficiais (Microsoft etc.).")
                .foregroundStyle(.secondary)
            List(Winetricks.curatedVerbs) { verb in
                Toggle(isOn: binding(for: verb.id)) {
                    VStack(alignment: .leading) {
                        Text(verb.title)
                        Text("\(verb.id) — \(verb.detail)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            HStack {
                TextField("Outros verbos, separados por espaço", text: $custom)
                Button("Instalar") {
                    model.installWinetricks(verbs, in: bottle)
                    selected = []
                    custom = ""
                }
                .buttonStyle(.borderedProminent)
                .disabled(verbs.isEmpty || model.isBusy)
            }
            Text("O winetricks precisa do cabextract no Mac: brew install cabextract")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var verbs: [String] {
        selected.sorted() + custom.split(separator: " ").map(String.init)
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { selected.contains(id) },
            set: { isOn in
                if isOn { selected.insert(id) } else { selected.remove(id) }
            }
        )
    }
}

// MARK: - Logs

struct LogsTab: View {
    @EnvironmentObject private var model: AppModel
    let bottle: Bottle
    @State private var files: [URL] = []
    @State private var selectedFile: URL?
    @State private var content = ""

    var body: some View {
        VStack(alignment: .leading) {
            HSplitView {
                List(files, id: \.self, selection: $selectedFile) { url in
                    Text(url.lastPathComponent)
                        .font(.caption.monospaced())
                }
                .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)
                ScrollView {
                    Text(content.isEmpty ? "Selecione um log." : content)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
            }
            HStack {
                Text("Um arquivo por execução, com o comando e as variáveis usadas.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Atualizar") { refresh() }
                Button("Mostrar no Finder") {
                    model.reveal(selectedFile ?? model.launcher.logDirectory(for: bottle))
                }
            }
        }
        .onAppear { refresh() }
        .onChange(of: selectedFile) { load() }
    }

    private func refresh() {
        files = model.logFiles(for: bottle)
        if selectedFile == nil || !files.contains(where: { $0 == selectedFile }) {
            selectedFile = files.first
        }
        load()
    }

    private func load() {
        content = selectedFile.map { model.readLog($0) } ?? ""
    }
}
