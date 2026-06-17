import AppKit
import SwiftUI
import ZeroFSManagerDomain
import ZeroFSManagerHelperClient
import ZeroFSPerformance
import ZeroFSManagerSecrets

public struct ZeroFSManagerRootView: View {
    @StateObject private var model = ZeroFSManagerViewModel()

    public init() {}

    public var body: some View {
        NavigationSplitView {
            List(selection: $model.selectedProfileID) {
                Section {
                    ForEach(model.profiles) { profile in
                        MountRow(profile: profile)
                            .tag(profile.id)
                    }
                } header: {
                    Label("Mounts", systemImage: "externaldrive.fill")
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("ZeroFS")
            .toolbar {
                Button {
                    model.addProfile()
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add mount profile")
            }
        } detail: {
            if let binding = model.selectedProfileBinding {
                ProfileDetailView(profile: binding, model: model)
            } else {
                EmptyMountSelectionView()
            }
        }
        .frame(minWidth: 980, minHeight: 680)
        .sheet(item: $model.mountFailure) { failure in
            MountFailurePanel(
                failure: failure,
                retry: {
                    Task { await model.retryMount(failure.profileID) }
                },
                openSettings: {
                    model.openLoginItemsSettings()
                },
                showLogs: {
                    Task { await model.showLogs(failure.profileID) }
                },
                disableAutoMount: {
                    model.disableAutoMount(failure.profileID)
                },
                dismiss: {
                    model.mountFailure = nil
                }
            )
        }
        .sheet(item: $model.devModeGuidance) { guidance in
            DevModeGuidancePanel(
                guidance: guidance,
                runManualMountTest: {
                    Task { await model.runManualMountTest(guidance.profileID) }
                },
                openTroubleshooting: {
                    model.openTroubleshooting()
                },
                copyCLICommand: {
                    Task { await model.copyManualMountCommand(guidance.profileID) }
                },
                dismiss: {
                    model.devModeGuidance = nil
                }
            )
        }
        .alert(item: $model.performanceConfirmation) { confirmation in
            Alert(
                title: Text("Run Performance Test?"),
                message: Text("This writes and reads \(confirmation.sizeMegabytes) MB through the mounted filesystem, then removes the test files."),
                primaryButton: .default(Text("Run Test")) {
                    Task { await model.runPerformanceTest(confirmation.profileID) }
                },
                secondaryButton: .cancel()
            )
        }
        .task {
            await model.runStartupChecks()
        }
    }
}

private struct EmptyMountSelectionView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "externaldrive.badge.questionmark")
                .font(.system(size: 42, weight: .regular))
                .foregroundStyle(.secondary)
            Text("No Mount")
                .font(.title3)
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct MountRow: View {
    var profile: EditableMountProfile

    var body: some View {
        HStack(spacing: 11) {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.accentColor.opacity(0.14))
                    .frame(width: 30, height: 30)
                Image(systemName: "externaldrive.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Circle()
                    .fill(profile.status.color)
                    .frame(width: 9, height: 9)
                    .overlay(Circle().stroke(.background, lineWidth: 1.5))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.displayName)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(profile.mountPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            Image(systemName: profile.autoMount == .afterLogin ? "bolt.circle.fill" : "circle")
                .font(.caption)
                .foregroundStyle(profile.autoMount == .afterLogin ? Color.yellow : Color.secondary.opacity(0.45))
                .help(profile.autoMount == .afterLogin ? "Auto mount after login" : "Auto mount off")
        }
        .padding(.vertical, 5)
    }
}

private struct ProfileDetailView: View {
    @Binding var profile: EditableMountProfile
    @ObservedObject var model: ZeroFSManagerViewModel

    var body: some View {
        VStack(spacing: 0) {
            Header(profile: profile, model: model)
            Divider()
            Form {
                Section("Distribution") {
                    DistributionModeBanner(
                        mode: model.distributionMode,
                        teamIdentifier: model.currentTeamIdentifier
                    )
                }

                Section("ZeroFS CLI") {
                    ZeroFSDependencyView(
                        binary: model.zeroFSBinary,
                        installCommand: ZeroFSInstallGuidance.recommendedShellCommand,
                        redetect: model.detectZeroFS,
                        copyInstallCommand: model.copyZeroFSInstallCommand
                    )
                }

                Section("Object Storage") {
                    TextField("Display Name", text: $profile.displayName)
                    TextField("Endpoint", text: $profile.endpoint)
                    TextField("Bucket", text: $profile.bucket)
                    TextField("Prefix", text: $profile.prefix)
                    SecureField("Access Key", text: $profile.accessKey)
                    SecureField("Secret Key", text: $profile.secretKey)
                    SecureField("ZeroFS Password", text: $profile.encryptionPassword)
                }

                Section("Mount") {
                    HStack {
                        TextField("Mount Directory", text: $profile.mountPath)
                        Button {
                            model.chooseMountDirectory(for: profile.id)
                        } label: {
                            Image(systemName: "folder")
                        }
                        .help("Choose mount directory")
                    }
                    if model.distributionMode.allowsLoginAutoMount {
                        Picker("Auto Mount", selection: $profile.autoMount) {
                            Text("Off").tag(AutoMountPolicy.disabled)
                            Text("After Login").tag(AutoMountPolicy.afterLogin)
                        }
                    } else {
                        LabeledContent("Auto Mount") {
                            HStack(spacing: 8) {
                                Text("Release-only")
                                    .foregroundStyle(.secondary)
                                Button {
                                    model.showDevModeGuidance(for: profile.id)
                                } label: {
                                    Label("Enable Auto Mount", systemImage: "bolt.fill")
                                }
                            }
                        }
                        Text("Auto Mount is disabled in GitHub-style dev mode so launch does not trigger SMAppService or privileged helper registration.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Stepper(value: $profile.quotaGigabytes, in: 1...1_048_576, step: 1) {
                        LabeledContent("Quota") {
                            Text("\(Int(profile.quotaGigabytes)) GB")
                                .monospacedDigit()
                        }
                    }
                    Stepper(value: $profile.performanceTestMegabytes, in: 1...1_048_576, step: 64) {
                        LabeledContent("Performance Test") {
                            Text("\(Int(profile.performanceTestMegabytes)) MB")
                                .monospacedDigit()
                        }
                    }
                }

                Section("Cache") {
                    Stepper(value: $profile.diskCacheGigabytes, in: 0...4096, step: 1) {
                        LabeledContent("Disk Cache") {
                            Text("\(Int(profile.diskCacheGigabytes)) GB")
                                .monospacedDigit()
                        }
                    }
                    Stepper(value: $profile.memoryCacheGigabytes, in: 0...512, step: 0.5) {
                        LabeledContent("Memory Cache") {
                            Text(profile.memoryCacheGigabytes, format: .number.precision(.fractionLength(1)))
                                .monospacedDigit()
                        }
                    }
                }

                Section("Ports") {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                        GridRow {
                            Text("NFS")
                            TextField("NFS", value: $profile.nfsPort, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 140)
                            Text("RPC")
                            TextField("RPC", value: $profile.rpcPort, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 140)
                            Text("Metrics")
                            TextField("Metrics", value: $profile.metricsPort, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 140)
                        }
                    }
                }

                Section("Validation") {
                    ValidationList(issues: model.validationIssues(for: profile))
                }

                Section("Status") {
                    StatusGrid(profile: profile, endpointReachability: model.endpointReachability)
                }
            }
            .formStyle(.grouped)
        }
    }
}

private struct DistributionModeBanner: View {
    var mode: AppDistributionMode
    var teamIdentifier: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: mode == .githubDev ? "hammer.fill" : "checkmark.seal.fill")
                .font(.title2)
                .foregroundStyle(mode == .githubDev ? .orange : .green)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 8) {
                Text(mode.title)
                    .font(.headline)
                Text(mode.warningText)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(teamIdentifier.map { "Apple TeamIdentifier: \($0)" } ?? "No Apple TeamIdentifier. Expected for GitHub-style dev builds; not valid for official release.")
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ZeroFSDependencyView: View {
    var binary: ZeroFSBinary?
    var installCommand: String
    var redetect: () -> Void
    var copyInstallCommand: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if binary != nil {
                Image(systemName: "checkmark.seal.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
                    .frame(width: 32)
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                    .frame(width: 32)
            }

            VStack(alignment: .leading, spacing: 8) {
                if let binary {
                    Text("ZeroFS CLI Ready")
                        .font(.headline)
                    Text(binary.path)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(binary.version ?? "Version unavailable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                } else {
                    Text("ZeroFS CLI Missing")
                        .font(.headline)
                    Text(installCommand)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                HStack {
                    Button {
                        redetect()
                    } label: {
                        Label("Re-detect", systemImage: "arrow.clockwise")
                    }
                    if binary == nil {
                        Button {
                            copyInstallCommand()
                        } label: {
                            Label("Copy Install Command", systemImage: "doc.on.doc")
                        }
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct StatusGrid: View {
    var profile: EditableMountProfile
    var endpointReachability: EndpointReachabilityState

    private let columns = [
        GridItem(.adaptive(minimum: 180), spacing: 8, alignment: .top)
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            StatusPill(
                title: "Helper",
                value: profile.helperRegistration.title,
                symbol: profile.helperRegistration.symbol,
                tint: profile.helperRegistration.color
            )
            StatusPill(
                title: "ZeroFS Process",
                value: profile.serviceState.title,
                symbol: profile.serviceState.symbol,
                tint: profile.serviceState.color
            )
            StatusPill(
                title: "Mount",
                value: profile.status.title,
                symbol: profile.status.symbol,
                tint: profile.status.color
            )
            StatusPill(
                title: "Metrics",
                value: profile.metricsReachable ? "Reachable" : "Unavailable",
                symbol: profile.metricsReachable ? "chart.line.uptrend.xyaxis" : "chart.line.flattrend.xyaxis",
                tint: profile.metricsReachable ? .green : .orange
            )
            StatusPill(
                title: "Endpoint",
                value: endpointReachability.title,
                symbol: endpointReachability.symbol,
                tint: endpointReachability.color
            )
            StatusPill(
                title: "Quota",
                value: "\(Int(profile.quotaGigabytes)) GB configured",
                symbol: "internaldrive",
                tint: .blue
            )
            StatusPill(
                title: "Last Error",
                value: profile.lastError.isEmpty ? "None" : profile.lastError,
                symbol: profile.lastError.isEmpty ? "checkmark.circle" : "text.bubble",
                tint: profile.lastError.isEmpty ? .secondary : .orange
            )
        }
    }
}

private struct StatusPill: View {
    var title: String
    var value: String
    var symbol: String
    var tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 18, height: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.callout)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(tint.opacity(0.18), lineWidth: 1)
        )
    }
}

private struct MountFailurePanel: View {
    var failure: MountFailure
    var retry: () -> Void
    var openSettings: () -> Void
    var showLogs: () -> Void
    var disableAutoMount: () -> Void
    var dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                Text("Mount Failed")
                    .font(.title2)
                    .fontWeight(.semibold)
            }

            Text(failure.message)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            if let logExcerpt = failure.logExcerpt, !logExcerpt.isEmpty {
                Text(logExcerpt)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            Text(failure.recovery.guidance)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                if failure.recovery.showsHelperActions {
                    HStack {
                        Button {
                            retry()
                        } label: {
                            Label("Retry", systemImage: "arrow.clockwise")
                        }
                        .keyboardShortcut(.defaultAction)
                        .accessibilityLabel("Retry mount")

                        Button {
                            openSettings()
                        } label: {
                            Label("Settings", systemImage: "gearshape")
                        }
                        .accessibilityLabel("Open System Settings")

                        Button {
                            showLogs()
                        } label: {
                            Label("Logs", systemImage: "doc.text")
                        }
                        .accessibilityLabel("Show helper logs")
                    }
                    HStack {
                        Button {
                            disableAutoMount()
                        } label: {
                            Label("Disable Auto Mount", systemImage: "bolt.slash")
                        }
                        .accessibilityLabel("Disable automatic mount")

                        Spacer()

                        Button {
                            dismiss()
                        } label: {
                            Label("Close", systemImage: "xmark")
                        }
                        .accessibilityLabel("Close mount failure dialog")
                    }
                } else {
                    HStack {
                        Spacer()
                        Button {
                            dismiss()
                        } label: {
                            Label("Close", systemImage: "xmark")
                        }
                        .keyboardShortcut(.defaultAction)
                        .accessibilityLabel("Close mount failure dialog")
                    }
                }
            }
            .controlSize(.regular)
        }
        .padding(24)
        .frame(minWidth: 640)
    }
}

private struct DevModeGuidancePanel: View {
    var guidance: DevModeGuidance
    var runManualMountTest: () -> Void
    var openTroubleshooting: () -> Void
    var copyCLICommand: () -> Void
    var dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "hammer.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                Text("GitHub-style Dev Mode")
                    .font(.title2)
                    .fontWeight(.semibold)
            }

            Text(guidance.message)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            Text("Manual CLI and debug launchd paths are only for lower-level S3/ZeroFS testing. They are not the official SMAppService authorization path.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button {
                    runManualMountTest()
                } label: {
                    Label("Run Manual Mount Test", systemImage: "terminal")
                }
                .keyboardShortcut(.defaultAction)

                Button {
                    openTroubleshooting()
                } label: {
                    Label("Open Troubleshooting", systemImage: "questionmark.circle")
                }

                Button {
                    copyCLICommand()
                } label: {
                    Label("Copy CLI Command", systemImage: "doc.on.doc")
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Label("Later", systemImage: "clock")
                }
            }
            .controlSize(.regular)
        }
        .padding(24)
        .frame(minWidth: 680)
    }
}

private struct Header: View {
    var profile: EditableMountProfile
    @ObservedObject var model: ZeroFSManagerViewModel

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(profile.status.color.opacity(0.12))
                    .frame(width: 46, height: 46)
                Image(systemName: "externaldrive.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(profile.status.color)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(profile.displayName)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    StatusBadge(status: profile.status)
                }
                Text(profile.mountPath)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }

            Spacer()
            Button {
                model.requestPerformanceTest(profile.id)
            } label: {
                Label("Test", systemImage: "speedometer")
            }
            Button {
                Task { await model.toggleMount(profile.id) }
            } label: {
                Label(
                    profile.status == .mounted ? "Unmount" : "Mount",
                    systemImage: profile.status == .mounted ? "eject.fill" : "play.fill"
                )
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(.regularMaterial)
    }
}

enum EndpointReachabilityState: Equatable {
    case notChecked
    case checking
    case reachable(String)
    case failed(String)

    var title: String {
        switch self {
        case .notChecked:
            "Not checked"
        case .checking:
            "Checking"
        case .reachable(let note):
            note
        case .failed(let message):
            message
        }
    }

    var symbol: String {
        switch self {
        case .notChecked:
            "network"
        case .checking:
            "arrow.clockwise"
        case .reachable:
            "checkmark.circle.fill"
        case .failed:
            "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .notChecked, .checking:
            .secondary
        case .reachable:
            .green
        case .failed:
            .orange
        }
    }
}

struct DevModeGuidance: Identifiable, Equatable {
    var id: ProfileID { profileID }
    var profileID: ProfileID
    var message: String
}

private struct StatusBadge: View {
    var status: EditableMountStatus

    var body: some View {
        Label(status.title, systemImage: status.symbol)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(status.color)
            .background(status.color.opacity(0.12), in: Capsule())
    }
}

private struct ValidationList: View {
    var issues: [ValidationIssue]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if issues.isEmpty {
                Label("Ready", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                ForEach(issues, id: \.self) { issue in
                    Label(issue.description, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

@MainActor
final class ZeroFSManagerViewModel: ObservableObject {
    @Published var profiles: [EditableMountProfile]
    @Published var selectedProfileID: ProfileID?
    @Published var mountFailure: MountFailure?
    @Published var devModeGuidance: DevModeGuidance?
    @Published var performanceConfirmation: PerformanceConfirmation?
    @Published var notifications: [MountNotification] = []
    @Published var zeroFSBinary: ZeroFSBinary?
    @Published var endpointReachability: EndpointReachabilityState = .notChecked

    private let helper: PrivilegedHelperClient
    private let secrets: SecretStore
    private let profileStore: FileMountProfileStore
    let distributionMode: AppDistributionMode
    let currentTeamIdentifier: String?

    init(
        helper: PrivilegedHelperClient = XPCPrivilegedHelperClient(),
        secrets: SecretStore = KeychainSecretStore(),
        profileStore: FileMountProfileStore = .applicationSupport(),
        distributionMode: AppDistributionMode = .resolve(),
        currentTeamIdentifier: String? = CodeSigningHelperClientAuthorizer.currentProcessTeamIdentifier()
    ) {
        self.helper = helper
        self.secrets = secrets
        self.profileStore = profileStore
        self.distributionMode = distributionMode
        self.currentTeamIdentifier = currentTeamIdentifier
        let migrationKey = "com.zerofs.manager.didRequireExplicitAutoMountOptIn"
        var storedProfiles = (try? profileStore.load()) ?? []
        if !storedProfiles.isEmpty && !UserDefaults.standard.bool(forKey: migrationKey) {
            storedProfiles = FirstRunProfilePolicy.requireExplicitAutoMountOptIn(storedProfiles)
            try? profileStore.save(storedProfiles)
            UserDefaults.standard.set(true, forKey: migrationKey)
        }
        let initialProfiles = storedProfiles.isEmpty
            ? [EditableMountProfile.lingyuzeng()]
            : storedProfiles.map(EditableMountProfile.init(mountProfile:))
        self.profiles = initialProfiles
        self.selectedProfileID = initialProfiles.first?.id
        self.zeroFSBinary = ZeroFSBinaryLocator().locate()
    }

    var selectedProfileBinding: Binding<EditableMountProfile>? {
        guard let selectedProfileID,
              let index = profiles.firstIndex(where: { $0.id == selectedProfileID }) else {
            return nil
        }
        return Binding(
            get: { self.profiles[index] },
            set: {
                self.profiles[index] = $0
                self.persistProfiles()
            }
        )
    }

    func addProfile() {
        let next = EditableMountProfile.empty()
        guard OneActiveProfilePolicy.canAdd(next.mountProfile, to: profiles.map(\.mountProfile)) else {
            recordMountFailure(
                profileID: selectedProfileID ?? next.id,
                message: "Version 1 allows one active profile. The UI is structured for multiple mounts so the data model can expand without redesign."
            )
            return
        }
        profiles.append(next)
        selectedProfileID = next.id
        persistProfiles()
    }

    func chooseMountDirectory(for id: ProfileID) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK,
              let url = panel.url,
              let index = profiles.firstIndex(where: { $0.id == id }) else {
            return
        }
        profiles[index].mountPath = url.path
        persistProfiles()
    }

    func detectZeroFS() {
        zeroFSBinary = ZeroFSBinaryLocator().locate()
        if zeroFSBinary == nil {
            notifications.append(MountNotification(
                profileID: selectedProfileID ?? (try! ProfileID("lingyuzeng")),
                title: "ZeroFS Missing",
                body: "Install ZeroFS with: \(ZeroFSInstallGuidance.recommendedShellCommand)"
            ))
        }
    }

    func copyZeroFSInstallCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ZeroFSInstallGuidance.recommendedShellCommand, forType: .string)
    }

    func showDevModeGuidance(for id: ProfileID) {
        devModeGuidance = DevModeGuidance(
            profileID: id,
            message: distributionMode.helperRegistrationUnavailableMessage
        )
    }

    func validationIssues(for profile: EditableMountProfile) -> [ValidationIssue] {
        ProfileValidator.validate(profile.mountProfile)
    }

    func toggleMount(_ id: ProfileID) async {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        var profile = profiles[index]
        let issues = validationIssues(for: profile)
        guard issues.isEmpty else {
            recordMountFailure(profileID: id, message: "Profile validation failed: \(issues.map(\.description).joined(separator: ", "))")
            return
        }

        do {
            guard let binary = zeroFSBinary else {
                recordMountFailure(profileID: id, message: "ZeroFS CLI is missing. Install it with: \(ZeroFSInstallGuidance.recommendedShellCommand)")
                return
            }
            guard distributionMode.allowsAutomaticHelperRegistration else {
                if applyLocalMountState(for: id) {
                    return
                }
                showDevModeGuidance(for: id)
                profile.lastError = "GitHub-style dev mode: use manual CLI/debug launchd testing instead of SMAppService helper registration."
                profiles[index] = profile
                return
            }
            if profile.status == .mounted {
                try await helper.unmount(profileID: id)
                profile.status = .unmounted
            } else {
                let missingSecrets = try missingRuntimeSecrets(for: profile)
                guard missingSecrets.isEmpty else {
                    recordMountFailure(
                        profileID: id,
                        message: "Missing required secrets: \(missingSecrets.joined(separator: ", ")). Enter them before mounting."
                    )
                    return
                }
                try ensureHelperRegistration()
                try saveRuntimeSecrets(for: profile)
                try await helper.installOrUpdate(profile.mountProfile)
                try await helper.syncRuntimeSecrets(profileID: id, secrets: resolvedRuntimeSecretPayload(for: profile))
                try await helper.start(profileID: id)
                profile.lastError = "Using external ZeroFS at \(binary.path)"
                try await helper.mount(profile.mountProfile)
                let status = try await helper.status(profileID: id)
                profile.status = status.mount.editableStatus
                profile.serviceState = status.service
                profile.helperRegistration = status.registration
                profile.metricsReachable = status.metricsReachable
                profile.lastError = status.lastError ?? profile.lastError
            }
            profiles[index] = profile
        } catch {
            recordMountFailure(profileID: id, message: redacted(String(describing: error), for: profile))
        }
    }

    func retryMount(_ id: ProfileID) async {
        mountFailure = nil
        await toggleMount(id)
    }

    func openLoginItemsSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func showLogs(_ id: ProfileID) async {
        guard let profile = profiles.first(where: { $0.id == id }) else { return }
        do {
            let logs = try await helper.logs(profileID: id, limitBytes: 4096)
            mountFailure = MountFailure(
                profileID: id,
                message: mountFailure?.message ?? "Recent helper logs",
                logExcerpt: logs.isEmpty ? "No recent helper logs were returned." : redacted(logs, for: profile)
            )
        } catch {
            recordMountFailure(profileID: id, message: redacted(String(describing: error), for: profile))
        }
    }

    func disableAutoMount(_ id: ProfileID) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[index].autoMount = .disabled
        persistProfiles()
        mountFailure = nil
    }

    func runStartupChecks() async {
        detectZeroFS()
        if let selected = selectedProfileBinding?.wrappedValue {
            await checkEndpointReachability(for: selected)
            _ = applyLocalMountState(for: selected.id)
        }
        guard distributionMode.allowsLoginAutoMount else {
            return
        }
        await runLoginAutoMountIfNeeded()
    }

    private func runLoginAutoMountIfNeeded() async {
        detectZeroFS()
        guard let selected = selectedProfileBinding?.wrappedValue else { return }
        guard selected.autoMount == .afterLogin else { return }
        guard zeroFSBinary != nil else {
            if selected.autoMount == .afterLogin {
                recordMountFailure(
                    profileID: selected.id,
                    message: "ZeroFS CLI is missing. Install it with: \(ZeroFSInstallGuidance.recommendedShellCommand)"
                )
            }
            return
        }

        do {
            let missingSecrets = try missingRuntimeSecrets(for: selected)
            guard missingSecrets.isEmpty else {
                recordMountFailure(
                    profileID: selected.id,
                    message: "Auto mount is missing required secrets: \(missingSecrets.joined(separator: ", ")). Enter them before mounting."
                )
                return
            }
            try ensureHelperRegistration()
            try await helper.installOrUpdate(selected.mountProfile)
            try saveRuntimeSecrets(for: selected)
            try await helper.syncRuntimeSecrets(profileID: selected.id, secrets: resolvedRuntimeSecretPayload(for: selected))
        } catch {
            recordMountFailure(profileID: selected.id, message: redacted(String(describing: error), for: selected))
            return
        }

        let report = await LoginAutoMountCoordinator(helper: helper).run(activeProfile: selected.mountProfile)
        applyAutoMount(report)
    }

    func copyManualMountCommand(_ id: ProfileID) async {
        guard let profile = profiles.first(where: { $0.id == id }) else { return }
        do {
            let scriptURL = try manualScriptURL(named: "manual-mount-test.sh")
            let command = "\(shellQuote(scriptURL.path)) --env /path/to/.env.local --delete-env-on-exit"
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(command, forType: .string)
            notifications.append(MountNotification(
                profileID: id,
                title: "CLI Command Copied",
                body: "Copied a safe template command. Create the env file outside the repo and keep it 0600."
            ))
        } catch {
            recordMountFailure(profileID: id, message: redacted(String(describing: error), for: profile))
        }
    }

    func runManualMountTest(_ id: ProfileID) async {
        guard let profile = profiles.first(where: { $0.id == id }) else { return }
        do {
            let envURL = try writeManualEnv(for: profile)
            let scriptURL = try manualScriptURL(named: "manual-mount-test.sh")
            let command = "cd \(shellQuote(scriptURL.deletingLastPathComponent().path)) && \(shellQuote(scriptURL.path)) --env \(shellQuote(envURL.path)) --delete-env-on-exit"
            let source = """
            tell application "Terminal"
              activate
              do script \(appleScriptString(command))
            end tell
            """
            var error: NSDictionary?
            guard NSAppleScript(source: source)?.executeAndReturnError(&error) != nil else {
                throw DevModeManualTestError.terminalLaunchFailed(error?.description ?? "unknown AppleScript error")
            }
            notifications.append(MountNotification(profileID: id, title: "Manual Mount Test", body: "Opened Terminal with a local env file. Script output redacts S3 secrets."))
        } catch {
            recordMountFailure(profileID: id, message: redacted(String(describing: error), for: profile))
        }
    }

    func openTroubleshooting() {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("docs/troubleshooting.md"),
            URL(fileURLWithPath: "/Users/lingyuzeng/project/zerofs-manager/docs/troubleshooting.md")
        ].compactMap { $0 }
        if let url = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            NSWorkspace.shared.open(url)
        }
    }

    private func checkEndpointReachability(for profile: EditableMountProfile) async {
        guard let url = URL(string: profile.endpoint), url.scheme == "https" || url.scheme == "http" else {
            endpointReachability = .failed("Invalid URL")
            return
        }
        endpointReachability = .checking
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 5
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse {
                endpointReachability = .reachable("HTTP \(http.statusCode)")
            } else {
                endpointReachability = .reachable("Reachable")
            }
        } catch {
            endpointReachability = .failed(error.localizedDescription)
        }
    }

    private func applyLocalMountState(for id: ProfileID) -> Bool {
        guard let index = profiles.firstIndex(where: { $0.id == id }),
              let mountOutput = LocalMountTable.currentOutput() else {
            return false
        }
        let mountPath = profiles[index].mountPath
        guard let mountLine = LocalMountTable.line(for: mountPath, mountOutput: mountOutput) else {
            profiles[index].status = .unmounted
            if profiles[index].lastError.contains("Detected existing mount") {
                profiles[index].lastError = ""
            }
            return false
        }
        profiles[index].status = .mounted
        profiles[index].serviceState = .running
        profiles[index].lastError = "Detected existing mount: \(mountLine)"
        return true
    }

    func requestPerformanceTest(_ id: ProfileID) {
        guard distributionMode.allowsAutomaticHelperRegistration else {
            if applyLocalMountState(for: id),
               let profile = profiles.first(where: { $0.id == id }) {
                performanceConfirmation = PerformanceConfirmation(
                    profileID: id,
                    sizeMegabytes: Int(profile.performanceTestMegabytes)
                )
                return
            }
            showDevModeGuidance(for: id)
            return
        }
        guard let profile = profiles.first(where: { $0.id == id }) else { return }
        performanceConfirmation = PerformanceConfirmation(
            profileID: id,
            sizeMegabytes: Int(profile.performanceTestMegabytes)
        )
    }

    func runPerformanceTest(_ id: ProfileID) async {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        let profile = profiles[index]
        profiles[index].status = .testing
        do {
            if !distributionMode.allowsAutomaticHelperRegistration {
                guard applyLocalMountState(for: id) else {
                    throw HelperClientError.operationFailed(
                        operation: .status,
                        message: "Local performance test requires an already mounted ZeroFS path.",
                        logExcerpt: nil
                    )
                }
                let report = try await runLocalPerformanceTest(profile: profile)
                applyPerformanceReport(report, to: index)
                return
            }
            let status = try await helper.status(profileID: id)
            guard status.mount == .mounted else {
                throw HelperClientError.operationFailed(
                    operation: .status,
                    message: "Performance test requires the profile to be mounted.",
                    logExcerpt: status.lastError
                )
            }
            let workDirectory = FileManager.default
                .homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/ZeroFSManager/PerformanceWork/\(id.rawValue)", isDirectory: true)
            let runner = PerformanceTestRunner(
                fileManager: .default,
                helper: PrivilegedPerformanceHelper(helper: helper),
                metrics: PrometheusMetricsProvider(url: URL(string: "http://127.0.0.1:\(profile.metricsPort)/metrics")!),
                byteGenerator: RepeatingByteGenerator(byte: 0x2A)
            )
            let report = try await runner.run(
                profileID: id,
                mountDirectory: URL(fileURLWithPath: profile.mountPath, isDirectory: true),
                workDirectory: workDirectory,
                sizeBytes: profile.mountProfile.performanceTestSize.bytes
            )
            applyPerformanceReport(report, to: index)
        } catch {
            profiles[index].status = .failed
            recordMountFailure(profileID: id, message: redacted(String(describing: error), for: profile))
        }
    }

    private func runLocalPerformanceTest(profile: EditableMountProfile) async throws -> PerformanceReport {
        let workDirectory = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ZeroFSManager/PerformanceWork/\(profile.id.rawValue)", isDirectory: true)
        let runner = PerformanceTestRunner(
            fileManager: .default,
            helper: LocalPerformanceHelper(),
            metrics: StaticMetricsProvider(metrics: "Metrics are unavailable in GitHub-style dev mode without the privileged helper."),
            byteGenerator: RepeatingByteGenerator(byte: 0x2A)
        )
        return try await runner.run(
            profileID: profile.id,
            mountDirectory: URL(fileURLWithPath: profile.mountPath, isDirectory: true),
            workDirectory: workDirectory,
            sizeBytes: profile.mountProfile.performanceTestSize.bytes
        )
    }

    private func applyPerformanceReport(_ report: PerformanceReport, to index: Int) {
        profiles[index].status = report.checksumStatus == .pass ? .mounted : .failed
        profiles[index].lastError = "Performance \(report.checksumStatus.rawValue): wrote \(report.sizeBytes) bytes in \(String(format: "%.2f", report.writeSeconds))s, read in \(String(format: "%.2f", report.readSeconds))s. \(report.capacityNote)"
        notifications.append(MountNotification(
            profileID: report.profileID,
            title: "Performance Test",
            body: profiles[index].lastError
        ))
    }

    private func recordMountFailure(profileID: ProfileID, message: String, logExcerpt: String? = nil) {
        if let index = profiles.firstIndex(where: { $0.id == profileID }) {
            profiles[index].status = .failed
            profiles[index].lastError = message
        }
        mountFailure = MountFailure(
            profileID: profileID,
            message: message,
            logExcerpt: logExcerpt,
            recovery: MountFailureRecovery.classify(message: message)
        )
        notifications.append(MountNotification(profileID: profileID, title: "Mount Failed", body: message))
    }

    private func ensureHelperRegistration() throws {
        switch HelperServiceRegistrar.registrationStatus() {
        case .enabled:
            return
        case .notRegistered, .notFound:
            try HelperServiceRegistrar.register()
        case .requiresApproval:
            throw HelperClientError.requiresApproval
        case .disabled:
            throw HelperClientError.operationFailed(
                operation: .installOrUpdate,
                message: "Privileged helper is disabled. Approve ZeroFS Manager in System Settings > General > Login Items & Extensions.",
                logExcerpt: nil
            )
        case .failed:
            throw HelperClientError.operationFailed(
                operation: .installOrUpdate,
                message: "Privileged helper registration failed.",
                logExcerpt: nil
            )
        }
    }

    private func saveRuntimeSecrets(for profile: EditableMountProfile) throws {
        if !profile.accessKey.isEmpty {
            try secrets.save(profile.accessKey, kind: .s3AccessKeyID, profileID: profile.id)
        }
        if !profile.secretKey.isEmpty {
            try secrets.save(profile.secretKey, kind: .s3SecretAccessKey, profileID: profile.id)
        }
        if !profile.encryptionPassword.isEmpty {
            try secrets.save(profile.encryptionPassword, kind: .zeroFSEncryptionPassword, profileID: profile.id)
        }
    }

    private func resolvedRuntimeSecretPayload(for profile: EditableMountProfile) throws -> RuntimeSecretPayload {
        RuntimeSecretPayload(
            accessKeyID: try resolvedSecret(profile.accessKey, kind: .s3AccessKeyID, profileID: profile.id),
            secretAccessKey: try resolvedSecret(profile.secretKey, kind: .s3SecretAccessKey, profileID: profile.id),
            zeroFSEncryptionPassword: try resolvedSecret(profile.encryptionPassword, kind: .zeroFSEncryptionPassword, profileID: profile.id)
        )
    }

    private func missingRuntimeSecrets(for profile: EditableMountProfile) throws -> [String] {
        var missing: [String] = []
        if try resolvedSecret(profile.accessKey, kind: .s3AccessKeyID, profileID: profile.id).isEmpty {
            missing.append("Access Key")
        }
        if try resolvedSecret(profile.secretKey, kind: .s3SecretAccessKey, profileID: profile.id).isEmpty {
            missing.append("Secret Key")
        }
        if try resolvedSecret(profile.encryptionPassword, kind: .zeroFSEncryptionPassword, profileID: profile.id).isEmpty {
            missing.append("ZeroFS Password")
        }
        return missing
    }

    private func resolvedSecret(_ visibleValue: String, kind: SecretKind, profileID: ProfileID) throws -> String {
        if !visibleValue.isEmpty {
            return visibleValue
        }
        return try secrets.read(kind: kind, profileID: profileID) ?? ""
    }

    private func redacted(_ text: String, for profile: EditableMountProfile) -> String {
        SecretRedactor.redact(text, secrets: redactionSecrets(for: profile))
    }

    private func redactionSecrets(for profile: EditableMountProfile) -> [String] {
        var values = [profile.accessKey, profile.secretKey, profile.encryptionPassword]
        for kind in [SecretKind.s3AccessKeyID, .s3SecretAccessKey, .zeroFSEncryptionPassword] {
            if let stored = try? secrets.read(kind: kind, profileID: profile.id), !stored.isEmpty {
                values.append(stored)
            }
        }
        return values
    }

    private func writeManualEnv(for profile: EditableMountProfile) throws -> URL {
        let accessKey = try resolvedSecret(profile.accessKey, kind: .s3AccessKeyID, profileID: profile.id)
        let secretKey = try resolvedSecret(profile.secretKey, kind: .s3SecretAccessKey, profileID: profile.id)
        let password = try resolvedSecret(profile.encryptionPassword, kind: .zeroFSEncryptionPassword, profileID: profile.id)
        guard !accessKey.isEmpty, !secretKey.isEmpty, !password.isEmpty else {
            throw DevModeManualTestError.missingSecrets
        }
        let baseDirectory = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("ZeroFSManager/ManualTests", isDirectory: true)
        try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        let envURL = baseDirectory.appendingPathComponent("\(profile.id.rawValue)-\(UUID().uuidString).env")
        let manualNFS = profile.nfsPort < 1024 ? 12_049 : profile.nfsPort
        let contents = """
        ZEROFS_BIN=\(shellQuote(zeroFSBinary?.path ?? "/usr/local/bin/zerofs"))
        ZEROFS_MOUNT_POINT=\(shellQuote(profile.mountPath))
        ZEROFS_NFS_PORT=\(manualNFS)
        ZEROFS_RPC_PORT=\(profile.rpcPort)
        ZEROFS_METRICS_PORT=\(profile.metricsPort)
        S3_ENDPOINT=\(shellQuote(profile.endpoint))
        S3_BUCKET=\(shellQuote(profile.bucket))
        S3_PREFIX=\(shellQuote(profile.prefix))
        S3_REGION='us-east-1'
        S3_ACCESS_KEY=\(shellQuote(accessKey))
        S3_SECRET_KEY=\(shellQuote(secretKey))
        ZEROFS_PASSWORD=\(shellQuote(password))
        """
        try contents.write(to: envURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: envURL.path)
        return envURL
    }

    private func manualScriptURL(named scriptName: String) throws -> URL {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("Scripts/\(scriptName)"),
            URL(fileURLWithPath: "/Users/lingyuzeng/project/zerofs-manager/Scripts/\(scriptName)")
        ].compactMap { $0 }
        guard let scriptURL = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else {
            throw DevModeManualTestError.scriptNotFound(scriptName)
        }
        return scriptURL
    }

    private func persistProfiles() {
        do {
            try profileStore.save(profiles.map(\.mountProfile))
        } catch {
            notifications.append(MountNotification(
                profileID: selectedProfileID ?? (try! ProfileID("lingyuzeng")),
                title: "Profile Save Failed",
                body: String(describing: error)
            ))
        }
    }

    private func applyAutoMount(_ report: LoginAutoMountReport) {
        guard let profileID = report.profileID,
              let index = profiles.firstIndex(where: { $0.id == profileID }) else {
            return
        }

        if let status = report.initialStatus {
            profiles[index].helperRegistration = status.registration
            profiles[index].serviceState = status.service
            profiles[index].metricsReachable = status.metricsReachable
            profiles[index].status = status.mount.editableStatus
            profiles[index].lastError = status.lastError ?? profiles[index].lastError
        }

        switch report.outcome {
        case .skippedNoProfile, .skippedDisabled:
            break
        case .alreadyMounted:
            profiles[index].status = .mounted
        case .mounted:
            profiles[index].serviceState = .running
            profiles[index].status = .mounted
        case .failed(let failure):
            let current = profiles[index]
            recordMountFailure(
                profileID: failure.profileID,
                message: redacted("\(failure.operation.rawValue) failed for \(failure.profileName): \(failure.message)", for: current),
                logExcerpt: failure.logExcerpt.map { redacted($0, for: current) }
            )
        }
    }
}

private enum DevModeManualTestError: Error, CustomStringConvertible {
    case missingSecrets
    case scriptNotFound(String)
    case terminalLaunchFailed(String)

    var description: String {
        switch self {
        case .missingSecrets:
            "Manual mount test requires Access Key, Secret Key, and ZeroFS Password."
        case .scriptNotFound(let scriptName):
            "Manual test script not found or not executable: \(scriptName)"
        case .terminalLaunchFailed(let message):
            "Could not open Terminal for manual mount test: \(message)"
        }
    }
}

private func shellQuote(_ value: String) -> String {
    "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
}

private func appleScriptString(_ value: String) -> String {
    let escaped = value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "\n", with: "\\n")
        .replacingOccurrences(of: "\r", with: "\\r")
    return "\"\(escaped)\""
}

struct EditableMountProfile: Identifiable, Equatable {
    var id: ProfileID
    var displayName: String
    var endpoint: String
    var bucket: String
    var prefix: String
    var mountPath: String
    var accessKey: String
    var secretKey: String
    var encryptionPassword: String
    var quotaGigabytes: Double
    var diskCacheGigabytes: Double
    var memoryCacheGigabytes: Double
    var performanceTestMegabytes: Double
    var nfsPort: Int
    var rpcPort: Int
    var metricsPort: Int
    var autoMount: AutoMountPolicy
    var helperRegistration: HelperRegistrationState
    var serviceState: ZeroFSServiceState
    var metricsReachable: Bool
    var lastError: String
    var status: EditableMountStatus

    init(
        id: ProfileID,
        displayName: String,
        endpoint: String,
        bucket: String,
        prefix: String,
        mountPath: String,
        accessKey: String,
        secretKey: String,
        encryptionPassword: String,
        quotaGigabytes: Double,
        diskCacheGigabytes: Double,
        memoryCacheGigabytes: Double,
        performanceTestMegabytes: Double,
        nfsPort: Int,
        rpcPort: Int,
        metricsPort: Int,
        autoMount: AutoMountPolicy,
        helperRegistration: HelperRegistrationState,
        serviceState: ZeroFSServiceState,
        metricsReachable: Bool,
        lastError: String,
        status: EditableMountStatus
    ) {
        self.id = id
        self.displayName = displayName
        self.endpoint = endpoint
        self.bucket = bucket
        self.prefix = prefix
        self.mountPath = mountPath
        self.accessKey = accessKey
        self.secretKey = secretKey
        self.encryptionPassword = encryptionPassword
        self.quotaGigabytes = quotaGigabytes
        self.diskCacheGigabytes = diskCacheGigabytes
        self.memoryCacheGigabytes = memoryCacheGigabytes
        self.performanceTestMegabytes = performanceTestMegabytes
        self.nfsPort = nfsPort
        self.rpcPort = rpcPort
        self.metricsPort = metricsPort
        self.autoMount = autoMount
        self.helperRegistration = helperRegistration
        self.serviceState = serviceState
        self.metricsReachable = metricsReachable
        self.lastError = lastError
        self.status = status
    }

    init(mountProfile: MountProfile) {
        self.init(
            id: mountProfile.id,
            displayName: mountProfile.displayName,
            endpoint: mountProfile.endpoint,
            bucket: mountProfile.bucket,
            prefix: mountProfile.prefix,
            mountPath: mountProfile.mountPath.rawValue,
            accessKey: "",
            secretKey: "",
            encryptionPassword: "",
            quotaGigabytes: mountProfile.quota.gigabytes,
            diskCacheGigabytes: mountProfile.cache.diskGigabytes,
            memoryCacheGigabytes: mountProfile.cache.memoryGigabytes,
            performanceTestMegabytes: Double(mountProfile.performanceTestSize.megabytesValue),
            nfsPort: mountProfile.ports.nfs,
            rpcPort: mountProfile.ports.rpc,
            metricsPort: mountProfile.ports.metrics,
            autoMount: mountProfile.autoMount,
            helperRegistration: .notRegistered,
            serviceState: .unknown,
            metricsReachable: false,
            lastError: "",
            status: .unmounted
        )
    }

    var mountProfile: MountProfile {
        MountProfile(
            id: id,
            displayName: displayName,
            endpoint: endpoint,
            bucket: bucket,
            prefix: prefix,
            mountPath: MountPath(rawValue: mountPath),
            quota: Quota(gigabytes: quotaGigabytes),
            cache: CacheSettings(diskGigabytes: diskCacheGigabytes, memoryGigabytes: memoryCacheGigabytes),
            ports: PortSet(nfs: nfsPort, rpc: rpcPort, metrics: metricsPort),
            autoMount: autoMount,
            performanceTestSize: .megabytes(Int(performanceTestMegabytes))
        )
    }

    static func lingyuzeng() -> EditableMountProfile {
        EditableMountProfile(
            id: try! ProfileID("lingyuzeng"),
            displayName: "lingyuzeng",
            endpoint: "https://amiaps3.hzau.edu.cn",
            bucket: "user-123456789",
            prefix: "lingyuzeng",
            mountPath: "/Volumes/ZeroFS-lingyuzeng",
            accessKey: "",
            secretKey: "",
            encryptionPassword: "",
            quotaGigabytes: 1024,
            diskCacheGigabytes: 10,
            memoryCacheGigabytes: 0.5,
            performanceTestMegabytes: Double(ProductDefaults.defaultPerformanceTestMegabytes),
            nfsPort: 2049,
            rpcPort: 17000,
            metricsPort: 9091,
            autoMount: ProductDefaults.firstRunAutoMountPolicy,
            helperRegistration: .notRegistered,
            serviceState: .unknown,
            metricsReachable: false,
            lastError: "",
            status: .unmounted
        )
    }

    static func empty() -> EditableMountProfile {
        EditableMountProfile(
            id: try! ProfileID("new-profile"),
            displayName: "New Profile",
            endpoint: "https://",
            bucket: "",
            prefix: "",
            mountPath: MountPath.defaultPath(displayName: "New Profile").rawValue,
            accessKey: "",
            secretKey: "",
            encryptionPassword: "",
            quotaGigabytes: 1024,
            diskCacheGigabytes: 10,
            memoryCacheGigabytes: 0.5,
            performanceTestMegabytes: Double(ProductDefaults.defaultPerformanceTestMegabytes),
            nfsPort: 2049,
            rpcPort: 17000,
            metricsPort: 9091,
            autoMount: .disabled,
            helperRegistration: .notRegistered,
            serviceState: .unknown,
            metricsReachable: false,
            lastError: "",
            status: .unmounted
        )
    }
}

private extension HelperRegistrationState {
    var title: String {
        switch self {
        case .notRegistered: "Not Registered"
        case .requiresApproval: "Requires Approval"
        case .enabled: "Enabled"
        case .disabled: "Disabled"
        case .notFound: "Not Found"
        case .failed: "Failed"
        }
    }

    var symbol: String {
        switch self {
        case .enabled: "checkmark.seal.fill"
        case .requiresApproval: "person.badge.key.fill"
        case .disabled, .failed: "xmark.octagon.fill"
        case .notRegistered, .notFound: "questionmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .enabled: .green
        case .requiresApproval: .orange
        case .disabled, .failed: .red
        case .notRegistered, .notFound: .secondary
        }
    }
}

private extension ZeroFSServiceState {
    var title: String {
        switch self {
        case .running: "Running"
        case .stopped: "Stopped"
        case .failed: "Failed"
        case .unknown: "Unknown"
        }
    }

    var symbol: String {
        switch self {
        case .running: "play.circle.fill"
        case .stopped: "stop.circle"
        case .failed: "xmark.octagon.fill"
        case .unknown: "questionmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .running: .green
        case .stopped: .secondary
        case .failed: .red
        case .unknown: .secondary
        }
    }
}

private extension MountState {
    var editableStatus: EditableMountStatus {
        switch self {
        case .mounted:
            .mounted
        case .failed, .stale:
            .failed
        case .unmounted, .unknown:
            .unmounted
        }
    }
}

enum EditableMountStatus: Equatable {
    case mounted
    case unmounted
    case testing
    case failed

    var title: String {
        switch self {
        case .mounted: "Mounted"
        case .unmounted: "Unmounted"
        case .testing: "Testing"
        case .failed: "Failed"
        }
    }

    var symbol: String {
        switch self {
        case .mounted: "checkmark.circle.fill"
        case .unmounted: "circle"
        case .testing: "speedometer"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .mounted: .green
        case .unmounted: .secondary
        case .testing: .blue
        case .failed: .orange
        }
    }
}

struct MountFailure: Identifiable {
    let id = UUID()
    var profileID: ProfileID
    var message: String
    var logExcerpt: String?
    var recovery: MountFailureRecovery = .helper
}

enum MountFailureRecovery {
    case helper
    case credentials
    case dependency
    case general

    static func classify(message: String) -> MountFailureRecovery {
        if message.contains("Access Key") ||
            message.contains("Secret Key") ||
            message.contains("ZeroFS Password") ||
            message.contains("Missing required secrets") ||
            message.contains("missing required secrets") {
            return .credentials
        }
        if message.contains("ZeroFS CLI is missing") {
            return .dependency
        }
        if message.contains("helper") ||
            message.contains("SMAppService") ||
            message.contains("launchd") ||
            message.contains("Login Items") {
            return .helper
        }
        return .general
    }

    var guidance: String {
        switch self {
        case .helper:
            "If macOS shows the helper as disabled, approve it in System Settings > General > Login Items & Extensions."
        case .credentials:
            "Enter Access Key, Secret Key, and ZeroFS Password in this profile, then run the mount or manual test again."
        case .dependency:
            "Install ZeroFS, then click Re-detect in the ZeroFS CLI section."
        case .general:
            "Review the message above, fix the profile or runtime state, then try again."
        }
    }

    var showsHelperActions: Bool {
        self == .helper
    }
}

struct PerformanceConfirmation: Identifiable {
    var profileID: ProfileID
    var sizeMegabytes: Int

    var id: ProfileID {
        profileID
    }
}

struct MountNotification: Identifiable, Equatable {
    let id = UUID()
    var profileID: ProfileID
    var title: String
    var body: String
}

private struct PrivilegedPerformanceHelper: PerformanceHelper {
    var helper: PrivilegedHelperClient

    func flush(profileID: ProfileID) async throws {
        try await helper.flush(profileID: profileID)
    }
}

private struct LocalPerformanceHelper: PerformanceHelper {
    func flush(profileID: ProfileID) async throws {}
}

private extension PerformanceTestSize {
    var megabytesValue: Int {
        switch self {
        case .megabytes(let value):
            value
        }
    }
}
