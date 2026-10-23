import AuthenticationServices
import SwiftData
import SwiftUI

/// Trello connection: sign in, pick board, warmups list, and lesson package card, then sync.
/// Shown inside a Form, both in Settings and during onboarding.
struct TrelloSections: View {
    @Environment(\.webAuthenticationSession) private var webAuth
    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var context

    @AppStorage(Prefs.trelloMember) private var memberName = ""
    @AppStorage(Prefs.trelloBoardID) private var boardID = ""
    @AppStorage(Prefs.trelloBoardName) private var boardName = ""
    @AppStorage(Prefs.trelloListID) private var listID = ""
    @AppStorage(Prefs.trelloPackageCardID) private var packageCardID = ""
    @AppStorage(Prefs.trelloLastSync) private var lastSync: Double = 0

    @State private var boards: [TrelloBoard] = []
    @State private var lists: [TrelloList] = []
    @State private var cards: [TrelloCard] = []
    @State private var loadedBoardID: String?
    @State private var busy = false
    @State private var message: String?
    @State private var showPaste = false
    @State private var pasted = ""

    private var connected: Bool { !memberName.isEmpty && TrelloSync.isConnected }

    var body: some View {
        if !TrelloConfig.isConfigured {
            Section("Trello") {
                Text("This build has no Trello API key, so lesson sync is off. Warmup tracks can still be imported from Files.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        } else if !connected {
            signInSection
        } else {
            connectedSections
        }
    }

    // MARK: Signed out

    private var signInSection: some View {
        Section {
            Text("Connect the Trello account your teacher shares your lesson board with. The app only reads: it pulls warmup tracks and lesson dates, and never changes your board.")
                .font(.footnote).foregroundStyle(.secondary)
            Button {
                Task { await connect() }
            } label: {
                Label("Connect Trello", systemImage: "link")
            }
            .disabled(busy)
            if showPaste {
                Text("Trello opened in Safari. Tap Allow, copy the token it shows, then come back and paste it here.")
                    .font(.footnote).foregroundStyle(.secondary)
                TextField("Paste token", text: $pasted)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .font(.system(.footnote, design: .monospaced))
                Button("Use token") {
                    Task {
                        guard let token = TrelloMapping.cleanToken(pasted) else {
                            message = "That doesn't look like a Trello token. Copy the whole line Trello shows."
                            return
                        }
                        await finishConnect(token)
                    }
                }
                .disabled(pasted.isEmpty || busy)
            }
            status
        } header: { Text("Trello") }
    }

    private func connect() async {
        guard let url = TrelloConfig.authorizeURL() else { return }
        message = nil
        guard !TrelloConfig.returnURL.isEmpty else {
            showPaste = true
            openURL(url)
            return
        }
        do {
            let callback = try await webAuth.authenticate(using: url, callbackURLScheme: TrelloConfig.callbackScheme)
            guard let token = TrelloMapping.token(fromCallback: callback) else {
                message = "Trello didn't grant access."
                return
            }
            await finishConnect(token)
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            return
        } catch {
            message = error.localizedDescription
        }
    }

    private func finishConnect(_ token: String) async {
        busy = true
        defer { busy = false }
        do {
            let client = TrelloClient(key: TrelloConfig.apiKey, token: token)
            let me = try await client.me()
            Keychain.set(token, for: TrelloConfig.tokenAccount)
            memberName = me.fullName ?? me.username ?? "Trello"
            showPaste = false
            pasted = ""
            await loadBoards()
        } catch {
            message = error.localizedDescription
        }
    }

    // MARK: Signed in

    @ViewBuilder
    private var connectedSections: some View {
        Section {
            LabeledContent("Signed in as", value: memberName)
            Picker("Lesson board", selection: $boardID) {
                if boardID.isEmpty { Text("Choose").tag("") }
                ForEach(boardChoices) { Text($0.name).tag($0.id) }
            }
            if !boardID.isEmpty {
                Picker("Warmups list", selection: $listID) {
                    if listID.isEmpty { Text("Choose").tag("") }
                    ForEach(lists) { Text($0.name).tag($0.id) }
                }
                Picker("Lesson package card", selection: $packageCardID) {
                    Text("None").tag("")
                    ForEach(cards) { Text($0.name).tag($0.id) }
                }
            }
        } header: {
            Text("Trello")
        } footer: {
            Text("Warmup tracks come from the cards in the warmups list. Lesson dates come from the package card's numbered lines, like \"4. 10/16\".")
        }
        .task { if boards.isEmpty { await loadBoards() } }
        .task(id: boardID) {
            boardName = boardChoices.first { $0.id == boardID }?.name ?? boardName
            await loadBoardContents()
        }

        Section {
            Button {
                Task { await sync() }
            } label: {
                Label(busy ? "Syncing..." : "Sync now", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(busy || listID.isEmpty)
            if lastSync > 0 {
                LabeledContent("Last synced",
                               value: Date(timeIntervalSince1970: lastSync).formatted(.relative(presentation: .named)))
            }
            status
            Button("Disconnect Trello", role: .destructive, action: disconnect)
        } footer: {
            Text("Disconnecting keeps the warmups and tracks already on this phone.")
        }
    }

    /// Keep the saved board visible even before the board list loads.
    private var boardChoices: [TrelloBoard] {
        if boards.isEmpty, !boardID.isEmpty { return [TrelloBoard(id: boardID, name: boardName)] }
        return boards
    }

    @ViewBuilder
    private var status: some View {
        if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
    }

    private func loadBoards() async {
        guard let client = TrelloClient.current() else { return }
        do {
            boards = try await client.boards().sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            if boardID.isEmpty {
                // One board, or one that looks like a lesson board: pick it.
                let named = boards.first { board in
                    let n = board.name.lowercased()
                    return n.contains("lesson") || n.contains("vocal")
                }
                let guess: TrelloBoard? = boards.count == 1 ? boards.first : named
                if let guess {
                    boardID = guess.id
                    boardName = guess.name
                }
            }
        } catch {
            message = error.localizedDescription
        }
    }

    /// Loads lists and cards for the chosen board. When the board changes (or nothing is picked yet),
    /// picks the list named like "Warmups" and the card that looks like a lesson package.
    private func loadBoardContents() async {
        guard let client = TrelloClient.current(), !boardID.isEmpty else { return }
        let boardChanged = loadedBoardID != nil && loadedBoardID != boardID
        if boardChanged {
            listID = ""
            packageCardID = ""
        }
        let autoPick = listID.isEmpty
        let board = boardID
        do {
            async let fetchedLists = client.lists(board: board)
            async let fetchedCards = client.cards(board: board)
            lists = try await fetchedLists
            cards = try await fetchedCards
            loadedBoardID = board
            if autoPick {
                listID = lists.first { $0.name.lowercased().contains("warm") }?.id ?? ""
                packageCardID = cards.first {
                    TrelloMapping.looksLikePackage(name: $0.name, description: $0.desc ?? "")
                }?.id ?? ""
            }
        } catch {
            message = error.localizedDescription
        }
    }

    private func sync() async {
        busy = true
        defer { busy = false }
        do {
            message = try await TrelloSync.run(context: context).summary
        } catch {
            message = error.localizedDescription
        }
    }

    private func disconnect() {
        Keychain.delete(TrelloConfig.tokenAccount)
        memberName = ""
        boardID = ""
        boardName = ""
        listID = ""
        packageCardID = ""
        boards = []
        lists = []
        cards = []
        loadedBoardID = nil
        message = nil
    }
}

/// First launch: connect Trello (or skip), then sync once so the Warmups tab is filled.
struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @AppStorage(Prefs.trelloListID) private var listID = ""
    var onDone: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Vocal Practice turns your lessons into a daily routine: it builds each session from your teacher's warmups and your songs, reminds you on practice days, and records a take of everything so you can hear progress.")
                } header: { Text("Welcome") }

                TrelloSections()

                Section {
                    Button(listID.isEmpty ? "Skip for now" : "Done") {
                        Task {
                            if !listID.isEmpty { _ = try? await TrelloSync.run(context: context) }
                            onDone()
                        }
                    }
                } footer: {
                    Text("You can connect or change Trello any time in Settings.")
                }
            }
            .navigationTitle("Get started")
        }
        .interactiveDismissDisabled()
    }
}
