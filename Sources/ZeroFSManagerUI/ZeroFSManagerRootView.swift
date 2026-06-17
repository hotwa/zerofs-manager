import AppKit
import SwiftUI
import ZeroFSManagerDomain
import ZeroFSManagerHelperClient
import ZeroFSPerformance
import ZeroFSManagerSecrets

public struct ZeroFSManagerRootView: View {
    @StateObject private var model = ZeroFSManagerViewModel()
    @AppStorage(AppLanguage.storageKey) private var languageID = AppLanguage.preferred().rawValue

    public init() {}

    public var body: some View {
        let language = AppLanguage.resolved(rawValue: languageID)
        NavigationSplitView {
            List(selection: $model.selectedProfileID) {
                Section {
                    ForEach(model.profiles) { profile in
                        MountRow(profile: profile, language: language)
                            .tag(profile.id)
                    }
                } header: {
                    Label(language.text(.mounts), systemImage: "externaldrive.fill")
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("ZeroFS")
            .toolbar {
                LanguageMenu(selection: $languageID, language: language)
                Button {
                    model.addProfile()
                } label: {
                    Image(systemName: "plus")
                }
                .help(language.text(.addMountProfile))
            }
        } detail: {
            if let binding = model.selectedProfileBinding {
                ProfileDetailView(profile: binding, model: model, language: language)
            } else {
                EmptyMountSelectionView(language: language)
            }
        }
        .frame(minWidth: 980, minHeight: 680)
        .sheet(item: $model.mountFailure) { failure in
            MountFailurePanel(
                failure: failure,
                language: language,
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
                language: language,
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
                title: Text(language.text(.runPerformanceTestTitle)),
                message: Text(language.runPerformanceTestMessage(sizeMegabytes: confirmation.sizeMegabytes)),
                primaryButton: .default(Text(language.text(.runTest))) {
                    Task { await model.runPerformanceTest(confirmation.profileID) }
                },
                secondaryButton: .cancel()
            )
        }
        .environment(\.locale, Locale(identifier: language.localeIdentifier))
        .onAppear {
            model.language = language
        }
        .onChange(of: languageID) { newValue in
            model.language = AppLanguage.resolved(rawValue: newValue)
        }
        .task {
            await model.runStartupChecks()
        }
    }
}

private struct LanguageMenu: View {
    @Binding var selection: String
    var language: AppLanguage

    var body: some View {
        Menu {
            ForEach(AppLanguage.allCases) { option in
                Button {
                    selection = option.rawValue
                } label: {
                    if option == language {
                        Label(option.displayName, systemImage: "checkmark")
                    } else {
                        Text(option.displayName)
                    }
                }
            }
        } label: {
            Label(language.text(.language), systemImage: "globe")
        }
        .help(language.text(.chooseLanguage))
    }
}

private struct EmptyMountSelectionView: View {
    var language: AppLanguage

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "externaldrive.badge.questionmark")
                .font(.system(size: 42, weight: .regular))
                .foregroundStyle(.secondary)
            Text(language.text(.noMount))
                .font(.title3)
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct MountRow: View {
    var profile: EditableMountProfile
    var language: AppLanguage

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
                .help(profile.autoMount == .afterLogin ? language.text(.autoMountAfterLoginHelp) : language.text(.autoMountOffHelp))
        }
        .padding(.vertical, 5)
    }
}

private struct ProfileDetailView: View {
    @Binding var profile: EditableMountProfile
    @ObservedObject var model: ZeroFSManagerViewModel
    var language: AppLanguage

    var body: some View {
        VStack(spacing: 0) {
            Header(profile: profile, model: model, language: language)
            Divider()
            Form {
                Section(language.text(.distribution)) {
                    DistributionModeBanner(
                        mode: model.distributionMode,
                        teamIdentifier: model.currentTeamIdentifier,
                        language: language
                    )
                }

                Section(language.text(.zeroFSCLI)) {
                    ZeroFSDependencyView(
                        binary: model.zeroFSBinary,
                        installCommand: ZeroFSInstallGuidance.recommendedShellCommand,
                        language: language,
                        redetect: model.detectZeroFS,
                        copyInstallCommand: model.copyZeroFSInstallCommand
                    )
                }

                Section(language.text(.objectStorage)) {
                    TextField(language.text(.displayName), text: $profile.displayName)
                    TextField(language.text(.endpoint), text: $profile.endpoint)
                    TextField(language.text(.bucket), text: $profile.bucket)
                    TextField(language.text(.prefix), text: $profile.prefix)
                    SecureField(language.text(.accessKey), text: $profile.accessKey)
                    SecureField(language.text(.secretKey), text: $profile.secretKey)
                    SecureField(language.text(.zeroFSPassword), text: $profile.encryptionPassword)
                }

                Section(language.text(.mountSection)) {
                    HStack {
                        TextField(language.text(.mountDirectory), text: $profile.mountPath)
                        Button {
                            model.chooseMountDirectory(for: profile.id)
                        } label: {
                            Image(systemName: "folder")
                        }
                        .help(language.text(.chooseMountDirectory))
                    }
                    if model.distributionMode.allowsLoginAutoMount {
                        Picker(language.text(.autoMount), selection: $profile.autoMount) {
                            Text(language.text(.off)).tag(AutoMountPolicy.disabled)
                            Text(language.text(.afterLogin)).tag(AutoMountPolicy.afterLogin)
                        }
                    } else {
                        LabeledContent(language.text(.autoMount)) {
                            HStack(spacing: 8) {
                                Text(language.text(.sudoLaunchDaemon))
                                    .foregroundStyle(.secondary)
                                Button {
                                    Task { await model.installOrUpdateLaunchDaemon(profile.id) }
                                } label: {
                                    Label(language.text(.applyRestartLaunchDaemon), systemImage: "arrow.triangle.2.circlepath")
                                }
                                Button {
                                    Task { await model.uninstallLaunchDaemon(profile.id) }
                                } label: {
                                    Label(language.text(.removeLaunchDaemon), systemImage: "trash")
                                }
                            }
                        }
                        Text(language.text(.githubDevLaunchDaemonNote))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Stepper(value: $profile.quotaGigabytes, in: 1...1_048_576, step: 1) {
                        LabeledContent(language.text(.quota)) {
                            Text("\(Int(profile.quotaGigabytes)) GB")
                                .monospacedDigit()
                        }
                    }
                    Stepper(value: $profile.performanceTestMegabytes, in: 1...1_048_576, step: 64) {
                        LabeledContent(language.text(.performanceTest)) {
                            Text("\(Int(profile.performanceTestMegabytes)) MB")
                                .monospacedDigit()
                        }
                    }
                }

                Section(language.text(.cache)) {
                    Stepper(value: $profile.diskCacheGigabytes, in: 0...4096, step: 1) {
                        LabeledContent(language.text(.diskCache)) {
                            Text("\(Int(profile.diskCacheGigabytes)) GB")
                                .monospacedDigit()
                        }
                    }
                    Stepper(value: $profile.memoryCacheGigabytes, in: 0...512, step: 0.5) {
                        LabeledContent(language.text(.memoryCache)) {
                            Text(profile.memoryCacheGigabytes, format: .number.precision(.fractionLength(1)))
                                .monospacedDigit()
                        }
                    }
                }

                Section(language.text(.ports)) {
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

                Section(language.text(.validation)) {
                    ValidationList(issues: model.validationIssues(for: profile), language: language)
                }

                Section(language.text(.status)) {
                    StatusGrid(profile: profile, endpointReachability: model.endpointReachability, language: language)
                }
            }
            .formStyle(.grouped)
        }
    }
}

private struct DistributionModeBanner: View {
    var mode: AppDistributionMode
    var teamIdentifier: String?
    var language: AppLanguage

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: mode == .githubDev ? "hammer.fill" : "checkmark.seal.fill")
                .font(.title2)
                .foregroundStyle(mode == .githubDev ? .orange : .green)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 8) {
                Text(mode.title(language: language))
                    .font(.headline)
                Text(mode.warningText(language: language))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(language.appleTeamIdentifier(teamIdentifier))
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
    var language: AppLanguage
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
                    Text(language.text(.zeroFSCLIReady))
                        .font(.headline)
                    Text(binary.path)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(binary.version ?? language.text(.versionUnavailable))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                } else {
                    Text(language.text(.zeroFSCLIMissing))
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
                        Label(language.text(.redetect), systemImage: "arrow.clockwise")
                    }
                    if binary == nil {
                        Button {
                            copyInstallCommand()
                        } label: {
                            Label(language.text(.copyInstallCommand), systemImage: "doc.on.doc")
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
    var language: AppLanguage

    private let columns = [
        GridItem(.adaptive(minimum: 180), spacing: 8, alignment: .top)
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            StatusPill(
                title: language.text(.helper),
                value: profile.helperRegistration.title(language: language),
                symbol: profile.helperRegistration.symbol,
                tint: profile.helperRegistration.color
            )
            StatusPill(
                title: language.text(.zeroFSProcess),
                value: profile.serviceState.title(language: language),
                symbol: profile.serviceState.symbol,
                tint: profile.serviceState.color
            )
            StatusPill(
                title: language.text(.mountSection),
                value: profile.status.title(language: language),
                symbol: profile.status.symbol,
                tint: profile.status.color
            )
            StatusPill(
                title: language.text(.metrics),
                value: profile.metricsReachable ? language.text(.reachable) : language.text(.unavailable),
                symbol: profile.metricsReachable ? "chart.line.uptrend.xyaxis" : "chart.line.flattrend.xyaxis",
                tint: profile.metricsReachable ? .green : .orange
            )
            StatusPill(
                title: language.text(.endpointStatus),
                value: endpointReachability.title(language: language),
                symbol: endpointReachability.symbol,
                tint: endpointReachability.color
            )
            StatusPill(
                title: language.text(.quotaStatus),
                value: language.quotaConfigured(Int(profile.quotaGigabytes)),
                symbol: "internaldrive",
                tint: .blue
            )
            StatusPill(
                title: language.text(.lastError),
                value: profile.lastError.isEmpty ? language.text(.none) : profile.lastError,
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
    var language: AppLanguage
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
                Text(language.text(.mountFailed))
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

            Text(failure.recovery.guidance(language: language))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                if failure.recovery.showsHelperActions {
                    HStack {
                        Button {
                            retry()
                        } label: {
                            Label(language.text(.retry), systemImage: "arrow.clockwise")
                        }
                        .keyboardShortcut(.defaultAction)
                        .accessibilityLabel(language.text(.retryMountAccessibility))

                        Button {
                            openSettings()
                        } label: {
                            Label(language.text(.settings), systemImage: "gearshape")
                        }
                        .accessibilityLabel(language.text(.openSystemSettingsAccessibility))

                        Button {
                            showLogs()
                        } label: {
                            Label(language.text(.logs), systemImage: "doc.text")
                        }
                        .accessibilityLabel(language.text(.showHelperLogsAccessibility))
                    }
                    HStack {
                        Button {
                            disableAutoMount()
                        } label: {
                            Label(language.text(.disableAutoMount), systemImage: "bolt.slash")
                        }
                        .accessibilityLabel(language.text(.disableAutoMountAccessibility))

                        Spacer()

                        Button {
                            dismiss()
                        } label: {
                            Label(language.text(.close), systemImage: "xmark")
                        }
                        .accessibilityLabel(language.text(.closeMountFailureDialogAccessibility))
                    }
                } else {
                    HStack {
                        Spacer()
                        Button {
                            dismiss()
                        } label: {
                            Label(language.text(.close), systemImage: "xmark")
                        }
                        .keyboardShortcut(.defaultAction)
                        .accessibilityLabel(language.text(.closeMountFailureDialogAccessibility))
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
    var language: AppLanguage
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
                Text(language.text(.githubDevMode))
                    .font(.title2)
                    .fontWeight(.semibold)
            }

            Text(guidance.message)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            Text(language.text(.devModeNote))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button {
                    runManualMountTest()
                } label: {
                    Label(language.text(.runManualMountTest), systemImage: "terminal")
                }
                .keyboardShortcut(.defaultAction)

                Button {
                    openTroubleshooting()
                } label: {
                    Label(language.text(.openTroubleshooting), systemImage: "questionmark.circle")
                }

                Button {
                    copyCLICommand()
                } label: {
                    Label(language.text(.copyCLICommand), systemImage: "doc.on.doc")
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Label(language.text(.later), systemImage: "clock")
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
    var language: AppLanguage

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
                    StatusBadge(status: profile.status, language: language)
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
                Label(language.text(.test), systemImage: "speedometer")
            }
            Button {
                Task { await model.toggleMount(profile.id) }
            } label: {
                Label(
                    profile.status == .mounted ? language.text(.unmountAction) : language.text(.mountAction),
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

    func title(language: AppLanguage) -> String {
        switch self {
        case .notChecked:
            language.text(.notChecked)
        case .checking:
            language.text(.checking)
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
    var language: AppLanguage

    var body: some View {
        Label(status.title(language: language), systemImage: status.symbol)
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
    var language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if issues.isEmpty {
                Label(language.text(.ready), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                ForEach(issues, id: \.self) { issue in
                    Label(issue.description(language: language), systemImage: "exclamationmark.triangle.fill")
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
    @Published var language: AppLanguage = .preferred()

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
            ? [EditableMountProfile.empty()]
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
                message: language.text(.oneActiveProfileMessage)
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
                profileID: selectedProfileID ?? (try! ProfileID("new-profile")),
                title: language.text(.zeroFSMissingTitle),
                body: language.zeroFSMissingInstallBody(command: ZeroFSInstallGuidance.recommendedShellCommand)
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
            message: distributionMode.helperRegistrationUnavailableMessage(language: language)
        )
    }

    func validationIssues(for profile: EditableMountProfile) -> [ValidationIssue] {
        ProfileValidator.validate(profile.mountProfile)
    }

    func toggleMount(_ id: ProfileID) async {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        var profile = profiles[index]
        let baseIssues = validationIssues(for: profile)
        let privilegedIssues = PrivilegedMountPathPolicy()
            .issues(for: profile.mountProfile.mountPath)
            .filter { !baseIssues.contains($0) }
        let issues = baseIssues + privilegedIssues
        guard issues.isEmpty else {
            recordMountFailure(
                profileID: id,
                message: language.profileValidationFailed(issues.map { $0.description(language: language) }),
                recovery: .general
            )
            return
        }

        do {
            guard let binary = zeroFSBinary else {
                recordMountFailure(
                    profileID: id,
                    message: language.zeroFSMissingInstallBody(command: ZeroFSInstallGuidance.recommendedShellCommand),
                    recovery: .dependency
                )
                return
            }
            guard distributionMode.allowsAutomaticHelperRegistration else {
                if applyLocalMountState(for: id) {
                    return
                }
                showDevModeGuidance(for: id)
                profile.lastError = language.text(.githubDevManualTestingLastError)
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
                        message: language.missingRequiredSecrets(missingSecrets),
                        recovery: .credentials
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
                message: mountFailure?.message ?? language.text(.recentHelperLogs),
                logExcerpt: logs.isEmpty ? language.text(.noRecentHelperLogs) : redacted(logs, for: profile)
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
                    message: language.zeroFSMissingInstallBody(command: ZeroFSInstallGuidance.recommendedShellCommand),
                    recovery: .dependency
                )
            }
            return
        }

        do {
            let missingSecrets = try missingRuntimeSecrets(for: selected)
            guard missingSecrets.isEmpty else {
                recordMountFailure(
                    profileID: selected.id,
                    message: language.missingRequiredSecrets(missingSecrets, autoMount: true),
                    recovery: .credentials
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
                title: language.text(.cliCommandCopiedTitle),
                body: language.text(.cliCommandCopiedBody)
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
            try openTerminal(command: command)
            notifications.append(MountNotification(profileID: id, title: language.text(.manualMountTestTitle), body: language.text(.manualMountTestBody)))
        } catch let error as DevModeManualTestError {
            recordMountFailure(profileID: id, message: error.description(language: language), recovery: error.recovery)
        } catch {
            recordMountFailure(profileID: id, message: redacted(String(describing: error), for: profile))
        }
    }

    func installOrUpdateLaunchDaemon(_ id: ProfileID) async {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        let profile = profiles[index]
        let baseIssues = validationIssues(for: profile)
        let privilegedIssues = PrivilegedMountPathPolicy()
            .issues(for: profile.mountProfile.mountPath)
            .filter { !baseIssues.contains($0) }
        let issues = baseIssues + privilegedIssues
        guard issues.isEmpty else {
            recordMountFailure(
                profileID: id,
                message: language.profileValidationFailed(issues.map { $0.description(language: language) }),
                recovery: .general
            )
            return
        }

        do {
            guard zeroFSBinary != nil else {
                recordMountFailure(
                    profileID: id,
                    message: language.zeroFSMissingInstallBody(command: ZeroFSInstallGuidance.recommendedShellCommand),
                    recovery: .dependency
                )
                return
            }
            let missingSecrets = try missingRuntimeSecrets(for: profile)
            guard missingSecrets.isEmpty else {
                recordMountFailure(
                    profileID: id,
                    message: language.missingRequiredSecrets(missingSecrets, autoMount: true),
                    recovery: .credentials
                )
                return
            }
            try saveRuntimeSecrets(for: profile)
            let envURL = try writeLaunchDaemonEnv(for: profile)
            let scriptURL = try manualScriptURL(named: "manual-install-profile-launchdaemon.sh")
            let command = "cd \(shellQuote(scriptURL.deletingLastPathComponent().path)) && \(shellQuote(scriptURL.path)) --env \(shellQuote(envURL.path)) --delete-env-on-exit"
            try openTerminal(command: command)
            profiles[index].lastError = language.text(.launchDaemonInstallBody)
            notifications.append(MountNotification(
                profileID: id,
                title: language.text(.launchDaemonInstallTitle),
                body: language.text(.launchDaemonInstallBody)
            ))
        } catch let error as DevModeManualTestError {
            recordMountFailure(profileID: id, message: error.description(language: language), recovery: error.recovery)
        } catch {
            recordMountFailure(profileID: id, message: redacted(String(describing: error), for: profile))
        }
    }

    func uninstallLaunchDaemon(_ id: ProfileID) async {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        let profile = profiles[index]
        do {
            let scriptURL = try manualScriptURL(named: "manual-uninstall-profile-launchdaemon.sh")
            let command = "cd \(shellQuote(scriptURL.deletingLastPathComponent().path)) && \(shellQuote(scriptURL.path)) --profile-id \(shellQuote(profile.id.rawValue)) --mount-point \(shellQuote(profile.mountPath))"
            try openTerminal(command: command)
            profiles[index].status = .unmounted
            profiles[index].serviceState = .stopped
            profiles[index].lastError = language.text(.launchDaemonUninstallBody)
            notifications.append(MountNotification(
                profileID: id,
                title: language.text(.launchDaemonUninstallTitle),
                body: language.text(.launchDaemonUninstallBody)
            ))
        } catch let error as DevModeManualTestError {
            recordMountFailure(profileID: id, message: error.description(language: language), recovery: error.recovery)
        } catch {
            recordMountFailure(profileID: id, message: redacted(String(describing: error), for: profile))
        }
    }

    func openTroubleshooting() {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("docs/troubleshooting.md")
        ].compactMap { $0 }
        if let url = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            NSWorkspace.shared.open(url)
        }
    }

    private func checkEndpointReachability(for profile: EditableMountProfile) async {
        guard let url = URL(string: profile.endpoint), url.scheme == "https" || url.scheme == "http" else {
            endpointReachability = .failed(language.text(.invalidURL))
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
                        message: language.text(.localPerformanceRequiresMounted),
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
                    message: language.text(.performanceRequiresMounted),
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
            metrics: StaticMetricsProvider(metrics: language.text(.metricsUnavailableDev)),
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
        profiles[index].lastError = language.performanceSummary(
            bytes: report.sizeBytes,
            writeSeconds: report.writeSeconds,
            readSeconds: report.readSeconds,
            capacityNote: report.capacityNote,
            status: report.checksumStatus.rawValue
        )
        notifications.append(MountNotification(
            profileID: report.profileID,
            title: language.text(.performanceTestTitle),
            body: profiles[index].lastError
        ))
    }

    private func recordMountFailure(profileID: ProfileID, message: String, logExcerpt: String? = nil, recovery: MountFailureRecovery? = nil) {
        if let index = profiles.firstIndex(where: { $0.id == profileID }) {
            profiles[index].status = .failed
            profiles[index].lastError = message
        }
        mountFailure = MountFailure(
            profileID: profileID,
            message: message,
            logExcerpt: logExcerpt,
            recovery: recovery ?? MountFailureRecovery.classify(message: message)
        )
        notifications.append(MountNotification(profileID: profileID, title: language.text(.mountFailed), body: message))
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
                message: language.text(.helperDisabledMessage),
                logExcerpt: nil
            )
        case .failed:
            throw HelperClientError.operationFailed(
                operation: .installOrUpdate,
                message: language.text(.helperRegistrationFailedMessage),
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

    private func writeLaunchDaemonEnv(for profile: EditableMountProfile) throws -> URL {
        let accessKey = try resolvedSecret(profile.accessKey, kind: .s3AccessKeyID, profileID: profile.id)
        let secretKey = try resolvedSecret(profile.secretKey, kind: .s3SecretAccessKey, profileID: profile.id)
        let password = try resolvedSecret(profile.encryptionPassword, kind: .zeroFSEncryptionPassword, profileID: profile.id)
        guard !accessKey.isEmpty, !secretKey.isEmpty, !password.isEmpty else {
            throw DevModeManualTestError.missingSecrets
        }
        let baseDirectory = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("ZeroFSManager/LaunchDaemonProfiles", isDirectory: true)
        try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        let envURL = baseDirectory.appendingPathComponent("\(profile.id.rawValue)-\(UUID().uuidString).env")
        let contents = """
        ZEROFS_PROFILE_ID=\(shellQuote(profile.id.rawValue))
        ZEROFS_DISPLAY_NAME=\(shellQuote(profile.displayName))
        ZEROFS_BIN=\(shellQuote(zeroFSBinary?.path ?? "/usr/local/bin/zerofs"))
        ZEROFS_MOUNT_POINT=\(shellQuote(profile.mountPath))
        ZEROFS_NFS_PORT=\(profile.nfsPort)
        ZEROFS_RPC_PORT=\(profile.rpcPort)
        ZEROFS_METRICS_PORT=\(profile.metricsPort)
        ZEROFS_QUOTA_GB=\(Int(profile.quotaGigabytes))
        ZEROFS_DISK_CACHE_GB=\(Int(profile.diskCacheGigabytes))
        ZEROFS_MEMORY_CACHE_GB=\(profile.memoryCacheGigabytes)
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
        var candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("Scripts/\(scriptName)")
        ].compactMap { $0 }
        if let scriptDirectory = ProcessInfo.processInfo.environment["ZEROFS_MANAGER_SCRIPT_DIR"],
           !scriptDirectory.isEmpty {
            candidates.append(URL(fileURLWithPath: scriptDirectory, isDirectory: true).appendingPathComponent(scriptName))
        }
        guard let scriptURL = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else {
            throw DevModeManualTestError.scriptNotFound(scriptName)
        }
        return scriptURL
    }

    private func openTerminal(command: String) throws {
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
    }

    private func persistProfiles() {
        do {
            try profileStore.save(profiles.map(\.mountProfile))
        } catch {
            notifications.append(MountNotification(
                profileID: selectedProfileID ?? (try! ProfileID("new-profile")),
                title: language.text(.profileSaveFailedTitle),
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
        description(language: .english)
    }

    var recovery: MountFailureRecovery {
        switch self {
        case .missingSecrets:
            .credentials
        case .scriptNotFound, .terminalLaunchFailed:
            .general
        }
    }

    func description(language: AppLanguage) -> String {
        switch self {
        case .missingSecrets:
            language.text(.manualMissingSecrets)
        case .scriptNotFound(let scriptName):
            language.manualScriptNotFound(scriptName)
        case .terminalLaunchFailed(let message):
            language.terminalLaunchFailed(message)
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

private extension AppDistributionMode {
    func title(language: AppLanguage) -> String {
        switch self {
        case .githubDev:
            language.text(.githubDevBuildTitle)
        case .officialRelease:
            language.text(.officialReleaseTitle)
        }
    }

    func warningText(language: AppLanguage) -> String {
        switch self {
        case .githubDev:
            language.text(.githubDevWarning)
        case .officialRelease:
            language.text(.officialReleaseWarning)
        }
    }

    func helperRegistrationUnavailableMessage(language: AppLanguage) -> String {
        switch self {
        case .githubDev:
            switch language {
            case .english:
                "Current build is GitHub-style development mode, so the Apple official helper authorization path is disabled. Use the manual CLI or debug launchd path to test real S3 mounts; formal helper authorization will be enabled after Developer ID signing and notarization."
            case .simplifiedChinese:
                "当前构建是 GitHub 风格开发模式，因此 Apple 官方 helper 授权路径已禁用。请使用手动 CLI 或 debug launchd 路径测试真实 S3 挂载；正式 helper 授权会在 Developer ID 签名和 notarization 后启用。"
            case .traditionalChinese:
                "目前建置是 GitHub 風格開發模式，因此 Apple 官方 helper 授權路徑已停用。請使用手動 CLI 或 debug launchd 路徑測試真實 S3 掛載；正式 helper 授權會在 Developer ID 簽名和 notarization 後啟用。"
            case .japanese:
                "現在のビルドは GitHub 形式の開発モードのため、Apple 公式 helper 認可経路は無効です。実際の S3 マウントテストには手動 CLI または debug launchd 経路を使用してください。正式な helper 認可は Developer ID 署名と notarization 後に有効化します。"
            case .korean:
                "현재 빌드는 GitHub 스타일 개발 모드이므로 Apple 공식 helper 승인 경로가 비활성화되어 있습니다. 실제 S3 마운트 테스트에는 수동 CLI 또는 debug launchd 경로를 사용하세요. 정식 helper 승인은 Developer ID 서명과 notarization 이후 활성화됩니다."
            }
        case .officialRelease:
            switch language {
            case .english:
                "Official release helper registration is unavailable. Verify Developer ID signing, notarization, and Login Items approval."
            case .simplifiedChinese:
                "正式发布 helper 注册不可用。请检查 Developer ID 签名、notarization 和登录项批准状态。"
            case .traditionalChinese:
                "正式發布 helper 註冊不可用。請檢查 Developer ID 簽名、notarization 和登入項目批准狀態。"
            case .japanese:
                "正式リリースの helper 登録を利用できません。Developer ID 署名、notarization、ログイン項目の承認を確認してください。"
            case .korean:
                "공식 릴리스 helper 등록을 사용할 수 없습니다. Developer ID 서명, notarization, 로그인 항목 승인을 확인하세요."
            }
        }
    }
}

private extension ValidationIssue {
    func description(language: AppLanguage) -> String {
        switch self {
        case .invalidProfileID: language.text(.invalidProfileID)
        case .invalidEndpoint: language.text(.invalidEndpoint)
        case .invalidBucket: language.text(.invalidBucket)
        case .invalidPrefix: language.text(.invalidPrefix)
        case .invalidMountPath: language.text(.invalidMountPath)
        case .unsafeMountPath: language.text(.unsafeMountPath)
        case .invalidQuota: language.text(.invalidQuota)
        case .invalidCache: language.text(.invalidCache)
        case .invalidPort: language.text(.invalidPort)
        case .duplicatePorts: language.text(.duplicatePorts)
        }
    }
}

private extension HelperRegistrationState {
    func title(language: AppLanguage) -> String {
        switch self {
        case .notRegistered: language.text(.helperNotRegistered)
        case .requiresApproval: language.text(.helperRequiresApproval)
        case .enabled: language.text(.helperEnabled)
        case .disabled: language.text(.helperDisabled)
        case .notFound: language.text(.helperNotFound)
        case .failed: language.text(.helperFailed)
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
    func title(language: AppLanguage) -> String {
        switch self {
        case .running: language.text(.serviceRunning)
        case .stopped: language.text(.serviceStopped)
        case .failed: language.text(.serviceFailed)
        case .unknown: language.text(.serviceUnknown)
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

    func title(language: AppLanguage) -> String {
        switch self {
        case .mounted: language.text(.mounted)
        case .unmounted: language.text(.unmounted)
        case .testing: language.text(.testing)
        case .failed: language.text(.failed)
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

    func guidance(language: AppLanguage) -> String {
        switch self {
        case .helper:
            language.text(.helperGuidance)
        case .credentials:
            language.text(.credentialsGuidance)
        case .dependency:
            language.text(.dependencyGuidance)
        case .general:
            language.text(.generalGuidance)
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
