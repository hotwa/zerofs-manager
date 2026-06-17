import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case japanese = "ja"
    case korean = "ko"

    static let storageKey = "com.zerofs.manager.ui.language"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english: "English"
        case .simplifiedChinese: "简体中文"
        case .traditionalChinese: "繁體中文"
        case .japanese: "日本語"
        case .korean: "한국어"
        }
    }

    var localeIdentifier: String {
        switch self {
        case .english: "en"
        case .simplifiedChinese: "zh-Hans"
        case .traditionalChinese: "zh-Hant"
        case .japanese: "ja"
        case .korean: "ko"
        }
    }

    static func preferred(locale: Locale = .current) -> AppLanguage {
        let candidates = Locale.preferredLanguages + [locale.identifier]
        for candidate in candidates {
            if candidate.hasPrefix("zh-Hant") || candidate.hasPrefix("zh-TW") || candidate.hasPrefix("zh-HK") {
                return .traditionalChinese
            }
            if candidate.hasPrefix("zh") {
                return .simplifiedChinese
            }
            if candidate.hasPrefix("ja") {
                return .japanese
            }
            if candidate.hasPrefix("ko") {
                return .korean
            }
            if candidate.hasPrefix("en") {
                return .english
            }
        }
        return .english
    }

    static func resolved(rawValue: String) -> AppLanguage {
        AppLanguage(rawValue: rawValue) ?? .preferred()
    }

    func text(_ key: AppTextKey) -> String {
        Self.translations[self]?[key] ?? Self.translations[.english]?[key] ?? key.rawValue
    }

    func quotaConfigured(_ gigabytes: Int) -> String {
        switch self {
        case .english:
            "\(gigabytes) GB configured"
        case .simplifiedChinese:
            "已配置 \(gigabytes) GB"
        case .traditionalChinese:
            "已設定 \(gigabytes) GB"
        case .japanese:
            "\(gigabytes) GB 設定済み"
        case .korean:
            "\(gigabytes) GB 설정됨"
        }
    }

    func runPerformanceTestMessage(sizeMegabytes: Int) -> String {
        switch self {
        case .english:
            "This writes and reads \(sizeMegabytes) MB through the mounted filesystem, then removes the test files."
        case .simplifiedChinese:
            "这会通过已挂载文件系统写入并读取 \(sizeMegabytes) MB，然后删除测试文件。"
        case .traditionalChinese:
            "這會透過已掛載檔案系統寫入並讀取 \(sizeMegabytes) MB，然後刪除測試檔案。"
        case .japanese:
            "マウント済みファイルシステム経由で \(sizeMegabytes) MB を書き込み・読み取り、その後テストファイルを削除します。"
        case .korean:
            "마운트된 파일 시스템을 통해 \(sizeMegabytes) MB를 쓰고 읽은 뒤 테스트 파일을 삭제합니다."
        }
    }

    func appleTeamIdentifier(_ value: String?) -> String {
        if let value, !value.isEmpty {
            return switch self {
            case .english:
                "Apple TeamIdentifier: \(value)"
            case .simplifiedChinese:
                "Apple TeamIdentifier：\(value)"
            case .traditionalChinese:
                "Apple TeamIdentifier：\(value)"
            case .japanese:
                "Apple TeamIdentifier: \(value)"
            case .korean:
                "Apple TeamIdentifier: \(value)"
            }
        } else {
            return text(.noAppleTeamIdentifier)
        }
    }

    func zeroFSMissingInstallBody(command: String) -> String {
        switch self {
        case .english:
            "Install ZeroFS with: \(command)"
        case .simplifiedChinese:
            "使用以下命令安装 ZeroFS：\(command)"
        case .traditionalChinese:
            "使用以下命令安裝 ZeroFS：\(command)"
        case .japanese:
            "次のコマンドで ZeroFS をインストールしてください: \(command)"
        case .korean:
            "다음 명령으로 ZeroFS를 설치하세요: \(command)"
        }
    }

    func missingRequiredSecrets(_ names: [String], autoMount: Bool = false) -> String {
        let joined = names.joined(separator: ", ")
        switch self {
        case .english:
            return autoMount
                ? "Auto mount is missing required secrets: \(joined). Enter them before mounting."
                : "Missing required secrets: \(joined). Enter them before mounting."
        case .simplifiedChinese:
            return autoMount
                ? "自动挂载缺少必要密钥：\(joined)。请先填写后再挂载。"
                : "缺少必要密钥：\(joined)。请先填写后再挂载。"
        case .traditionalChinese:
            return autoMount
                ? "自動掛載缺少必要密鑰：\(joined)。請先填寫後再掛載。"
                : "缺少必要密鑰：\(joined)。請先填寫後再掛載。"
        case .japanese:
            return autoMount
                ? "自動マウントに必要なシークレットがありません: \(joined)。入力してからマウントしてください。"
                : "必要なシークレットがありません: \(joined)。入力してからマウントしてください。"
        case .korean:
            return autoMount
                ? "자동 마운트에 필요한 시크릿이 없습니다: \(joined). 입력 후 마운트하세요."
                : "필수 시크릿이 없습니다: \(joined). 입력 후 마운트하세요."
        }
    }

    func profileValidationFailed(_ issues: [String]) -> String {
        switch self {
        case .english:
            "Profile validation failed: \(issues.joined(separator: ", "))"
        case .simplifiedChinese:
            "配置校验失败：\(issues.joined(separator: ", "))"
        case .traditionalChinese:
            "設定檔驗證失敗：\(issues.joined(separator: ", "))"
        case .japanese:
            "プロファイル検証に失敗しました: \(issues.joined(separator: ", "))"
        case .korean:
            "프로필 검증 실패: \(issues.joined(separator: ", "))"
        }
    }

    func performanceSummary(bytes: Int64, writeSeconds: Double, readSeconds: Double, capacityNote: String, status: String) -> String {
        let write = String(format: "%.2f", writeSeconds)
        let read = String(format: "%.2f", readSeconds)
        return switch self {
        case .english:
            "Performance \(status): wrote \(bytes) bytes in \(write)s, read in \(read)s. \(capacityNote)"
        case .simplifiedChinese:
            "性能测试 \(status)：写入 \(bytes) 字节耗时 \(write)s，读取耗时 \(read)s。\(capacityNote)"
        case .traditionalChinese:
            "效能測試 \(status)：寫入 \(bytes) 位元組耗時 \(write)s，讀取耗時 \(read)s。\(capacityNote)"
        case .japanese:
            "性能テスト \(status): \(bytes) バイトを書き込み \(write)s、読み取り \(read)s。\(capacityNote)"
        case .korean:
            "성능 테스트 \(status): \(bytes) 바이트 쓰기 \(write)s, 읽기 \(read)s. \(capacityNote)"
        }
    }

    func manualScriptNotFound(_ scriptName: String) -> String {
        "\(text(.manualScriptNotFound)): \(scriptName)"
    }

    func terminalLaunchFailed(_ message: String) -> String {
        "\(text(.terminalLaunchFailed)): \(message)"
    }

    private static let translations: [AppLanguage: [AppTextKey: String]] = [
        .english: [
            .language: "Language",
            .chooseLanguage: "Choose language",
            .mounts: "Mounts",
            .addMountProfile: "Add mount profile",
            .autoMountAfterLoginHelp: "Auto mount after login",
            .autoMountOffHelp: "Auto mount off",
            .noMount: "No Mount",
            .runPerformanceTestTitle: "Run Performance Test?",
            .runTest: "Run Test",
            .distribution: "Distribution",
            .zeroFSCLI: "ZeroFS CLI",
            .objectStorage: "Object Storage",
            .displayName: "Display Name",
            .endpoint: "Endpoint",
            .bucket: "Bucket",
            .prefix: "Prefix",
            .accessKey: "Access Key",
            .secretKey: "Secret Key",
            .zeroFSPassword: "ZeroFS Password",
            .mountSection: "Mount",
            .mountDirectory: "Mount Directory",
            .chooseMountDirectory: "Choose mount directory",
            .autoMount: "Auto Mount",
            .off: "Off",
            .afterLogin: "After Login",
            .releaseOnly: "Release-only",
            .enableAutoMount: "Enable Auto Mount",
            .devAutoMountDisabled: "Auto Mount is disabled in GitHub-style dev mode so launch does not trigger SMAppService or privileged helper registration.",
            .sudoLaunchDaemon: "sudo LaunchDaemon",
            .applyRestartLaunchDaemon: "Apply & Restart LaunchDaemon",
            .removeLaunchDaemon: "Remove LaunchDaemon",
            .githubDevLaunchDaemonNote: "GitHub builds use reviewed sudo scripts. Current profile parameters are written to root-owned config/env files, then the matching LaunchDaemon is restarted.",
            .quota: "Quota",
            .performanceTest: "Performance Test",
            .cache: "Cache",
            .diskCache: "Disk Cache",
            .memoryCache: "Memory Cache",
            .ports: "Ports",
            .validation: "Validation",
            .status: "Status",
            .githubDevBuildTitle: "GitHub-style development build",
            .officialReleaseTitle: "Official Developer ID release",
            .githubDevWarning: "Current build is a GitHub-style development build and is not signed with Apple Developer ID. It is suitable for development testing and technical users running manual workflows; it does not represent the official macOS distribution experience.",
            .officialReleaseWarning: "Official release mode expects Developer ID signing, hardened runtime, notarization, stapling, and the formal SMAppService helper registration path.",
            .noAppleTeamIdentifier: "No Apple TeamIdentifier. Expected for GitHub-style dev builds; not valid for official release.",
            .zeroFSCLIReady: "ZeroFS CLI Ready",
            .zeroFSCLIMissing: "ZeroFS CLI Missing",
            .versionUnavailable: "Version unavailable",
            .redetect: "Re-detect",
            .copyInstallCommand: "Copy Install Command",
            .helper: "Helper",
            .zeroFSProcess: "ZeroFS Process",
            .metrics: "Metrics",
            .endpointStatus: "Endpoint",
            .quotaStatus: "Quota",
            .lastError: "Last Error",
            .reachable: "Reachable",
            .unavailable: "Unavailable",
            .none: "None",
            .notChecked: "Not checked",
            .checking: "Checking",
            .invalidURL: "Invalid URL",
            .mountFailed: "Mount Failed",
            .retry: "Retry",
            .settings: "Settings",
            .logs: "Logs",
            .disableAutoMount: "Disable Auto Mount",
            .close: "Close",
            .retryMountAccessibility: "Retry mount",
            .openSystemSettingsAccessibility: "Open System Settings",
            .showHelperLogsAccessibility: "Show helper logs",
            .disableAutoMountAccessibility: "Disable automatic mount",
            .closeMountFailureDialogAccessibility: "Close mount failure dialog",
            .helperGuidance: "If macOS shows the helper as disabled, approve it in System Settings > General > Login Items & Extensions.",
            .credentialsGuidance: "Enter Access Key, Secret Key, and ZeroFS Password in this profile, then run the mount or manual test again.",
            .dependencyGuidance: "Install ZeroFS, then click Re-detect in the ZeroFS CLI section.",
            .generalGuidance: "Review the message above, fix the profile or runtime state, then try again.",
            .githubDevMode: "GitHub-style Dev Mode",
            .devModeNote: "Manual CLI and debug launchd paths are only for lower-level S3/ZeroFS testing. They are not the official SMAppService authorization path.",
            .runManualMountTest: "Run Manual Mount Test",
            .openTroubleshooting: "Open Troubleshooting",
            .copyCLICommand: "Copy CLI Command",
            .later: "Later",
            .test: "Test",
            .mountAction: "Mount",
            .unmountAction: "Unmount",
            .ready: "Ready",
            .helperNotRegistered: "Not Registered",
            .helperRequiresApproval: "Requires Approval",
            .helperEnabled: "Enabled",
            .helperDisabled: "Disabled",
            .helperNotFound: "Not Found",
            .helperFailed: "Failed",
            .serviceRunning: "Running",
            .serviceStopped: "Stopped",
            .serviceFailed: "Failed",
            .serviceUnknown: "Unknown",
            .mounted: "Mounted",
            .unmounted: "Unmounted",
            .testing: "Testing",
            .failed: "Failed",
            .invalidProfileID: "Invalid profile ID",
            .invalidEndpoint: "Invalid endpoint",
            .invalidBucket: "Invalid bucket",
            .invalidPrefix: "Invalid prefix",
            .invalidMountPath: "Invalid mount path",
            .unsafeMountPath: "Unsafe mount path",
            .invalidQuota: "Invalid quota",
            .invalidCache: "Invalid cache",
            .invalidPort: "Invalid port",
            .duplicatePorts: "Duplicate ports",
            .zeroFSMissingTitle: "ZeroFS Missing",
            .cliCommandCopiedTitle: "CLI Command Copied",
            .cliCommandCopiedBody: "Copied a safe template command. Create the env file outside the repo and keep it 0600.",
            .manualMountTestTitle: "Manual Mount Test",
            .manualMountTestBody: "Opened Terminal with a local env file. Script output redacts S3 secrets.",
            .launchDaemonInstallTitle: "LaunchDaemon Update Started",
            .launchDaemonInstallBody: "Terminal opened the sudo installer. Approve it to write root-owned config and restart this profile.",
            .launchDaemonUninstallTitle: "LaunchDaemon Removal Started",
            .launchDaemonUninstallBody: "Terminal opened the sudo uninstaller for this profile.",
            .profileSaveFailedTitle: "Profile Save Failed",
            .performanceTestTitle: "Performance Test",
            .recentHelperLogs: "Recent helper logs",
            .noRecentHelperLogs: "No recent helper logs were returned.",
            .oneActiveProfileMessage: "Version 1 allows one active profile. The UI is structured for multiple mounts so the data model can expand without redesign.",
            .githubDevManualTestingLastError: "GitHub-style dev mode: use manual CLI/debug launchd testing instead of SMAppService helper registration.",
            .localPerformanceRequiresMounted: "Local performance test requires an already mounted ZeroFS path.",
            .performanceRequiresMounted: "Performance test requires the profile to be mounted.",
            .metricsUnavailableDev: "Metrics are unavailable in GitHub-style dev mode without the privileged helper.",
            .helperDisabledMessage: "Privileged helper is disabled. Approve ZeroFS Manager in System Settings > General > Login Items & Extensions.",
            .helperRegistrationFailedMessage: "Privileged helper registration failed.",
            .manualMissingSecrets: "Manual mount test requires Access Key, Secret Key, and ZeroFS Password.",
            .manualScriptNotFound: "Manual test script not found or not executable",
            .terminalLaunchFailed: "Could not open Terminal for manual mount test"
        ],
        .simplifiedChinese: [
            .language: "语言",
            .chooseLanguage: "选择语言",
            .mounts: "挂载",
            .addMountProfile: "新增挂载配置",
            .autoMountAfterLoginHelp: "登录后自动挂载",
            .autoMountOffHelp: "自动挂载关闭",
            .noMount: "未选择挂载",
            .runPerformanceTestTitle: "运行性能测试？",
            .runTest: "运行测试",
            .distribution: "分发",
            .zeroFSCLI: "ZeroFS CLI",
            .objectStorage: "对象存储",
            .displayName: "显示名称",
            .endpoint: "Endpoint",
            .bucket: "Bucket",
            .prefix: "Prefix",
            .accessKey: "Access Key",
            .secretKey: "Secret Key",
            .zeroFSPassword: "ZeroFS 密码",
            .mountSection: "挂载",
            .mountDirectory: "挂载目录",
            .chooseMountDirectory: "选择挂载目录",
            .autoMount: "自动挂载",
            .off: "关闭",
            .afterLogin: "登录后",
            .releaseOnly: "仅正式版",
            .enableAutoMount: "启用自动挂载",
            .devAutoMountDisabled: "GitHub 开发版禁用自动挂载，避免启动时触发 SMAppService 或特权 helper 注册。",
            .sudoLaunchDaemon: "sudo LaunchDaemon",
            .applyRestartLaunchDaemon: "应用并重启 LaunchDaemon",
            .removeLaunchDaemon: "移除 LaunchDaemon",
            .githubDevLaunchDaemonNote: "GitHub 版使用已审查的 sudo 脚本。当前配置参数会写入 root 拥有的 config/env 文件，然后重启对应的 LaunchDaemon。",
            .quota: "配额",
            .performanceTest: "性能测试",
            .cache: "缓存",
            .diskCache: "磁盘缓存",
            .memoryCache: "内存缓存",
            .ports: "端口",
            .validation: "校验",
            .status: "状态",
            .githubDevBuildTitle: "GitHub 风格开发版",
            .officialReleaseTitle: "正式 Developer ID 版本",
            .githubDevWarning: "当前构建是 GitHub 风格开发版，未使用 Apple Developer ID 签名。它适合开发测试和技术用户手动流程，不代表正式 macOS 分发体验。",
            .officialReleaseWarning: "正式发布模式需要 Developer ID 签名、hardened runtime、notarization、stapling，以及正式 SMAppService helper 注册流程。",
            .noAppleTeamIdentifier: "没有 Apple TeamIdentifier。GitHub 开发版符合预期，但不适合正式发布。",
            .zeroFSCLIReady: "ZeroFS CLI 已就绪",
            .zeroFSCLIMissing: "缺少 ZeroFS CLI",
            .versionUnavailable: "版本不可用",
            .redetect: "重新检测",
            .copyInstallCommand: "复制安装命令",
            .helper: "Helper",
            .zeroFSProcess: "ZeroFS 进程",
            .metrics: "指标",
            .endpointStatus: "Endpoint",
            .quotaStatus: "配额",
            .lastError: "最后错误",
            .reachable: "可访问",
            .unavailable: "不可用",
            .none: "无",
            .notChecked: "未检查",
            .checking: "检查中",
            .invalidURL: "URL 无效",
            .mountFailed: "挂载失败",
            .retry: "重试",
            .settings: "设置",
            .logs: "日志",
            .disableAutoMount: "禁用自动挂载",
            .close: "关闭",
            .retryMountAccessibility: "重试挂载",
            .openSystemSettingsAccessibility: "打开系统设置",
            .showHelperLogsAccessibility: "显示 helper 日志",
            .disableAutoMountAccessibility: "禁用自动挂载",
            .closeMountFailureDialogAccessibility: "关闭挂载失败对话框",
            .helperGuidance: "如果 macOS 显示 helper 已禁用，请在“系统设置 > 通用 > 登录项与扩展”中批准它。",
            .credentialsGuidance: "请在此配置中填写 Access Key、Secret Key 和 ZeroFS 密码，然后重新挂载或运行手动测试。",
            .dependencyGuidance: "安装 ZeroFS 后，在 ZeroFS CLI 区域点击“重新检测”。",
            .generalGuidance: "查看上方信息，修复配置或运行状态后再重试。",
            .githubDevMode: "GitHub 风格开发模式",
            .devModeNote: "手动 CLI 和 debug launchd 路径只用于底层 S3/ZeroFS 测试，不是正式 SMAppService 授权流程。",
            .runManualMountTest: "运行手动挂载测试",
            .openTroubleshooting: "打开故障排查",
            .copyCLICommand: "复制 CLI 命令",
            .later: "稍后",
            .test: "测试",
            .mountAction: "挂载",
            .unmountAction: "卸载",
            .ready: "就绪",
            .helperNotRegistered: "未注册",
            .helperRequiresApproval: "需要批准",
            .helperEnabled: "已启用",
            .helperDisabled: "已禁用",
            .helperNotFound: "未找到",
            .helperFailed: "失败",
            .serviceRunning: "运行中",
            .serviceStopped: "已停止",
            .serviceFailed: "失败",
            .serviceUnknown: "未知",
            .mounted: "已挂载",
            .unmounted: "未挂载",
            .testing: "测试中",
            .failed: "失败",
            .invalidProfileID: "Profile ID 无效",
            .invalidEndpoint: "Endpoint 无效",
            .invalidBucket: "Bucket 无效",
            .invalidPrefix: "Prefix 无效",
            .invalidMountPath: "挂载路径无效",
            .unsafeMountPath: "挂载路径不安全",
            .invalidQuota: "配额无效",
            .invalidCache: "缓存无效",
            .invalidPort: "端口无效",
            .duplicatePorts: "端口重复",
            .zeroFSMissingTitle: "缺少 ZeroFS",
            .cliCommandCopiedTitle: "CLI 命令已复制",
            .cliCommandCopiedBody: "已复制安全模板命令。请在仓库外创建 env 文件并保持 0600 权限。",
            .manualMountTestTitle: "手动挂载测试",
            .manualMountTestBody: "已用本地 env 文件打开 Terminal。脚本输出会隐藏 S3 密钥。",
            .launchDaemonInstallTitle: "LaunchDaemon 更新已开始",
            .launchDaemonInstallBody: "已在 Terminal 打开 sudo 安装器。授权后会写入 root 配置并重启此 profile。",
            .launchDaemonUninstallTitle: "LaunchDaemon 移除已开始",
            .launchDaemonUninstallBody: "已在 Terminal 为此 profile 打开 sudo 卸载器。",
            .profileSaveFailedTitle: "配置保存失败",
            .performanceTestTitle: "性能测试",
            .recentHelperLogs: "最近 helper 日志",
            .noRecentHelperLogs: "没有返回最近 helper 日志。",
            .oneActiveProfileMessage: "版本 1 只允许一个活跃配置。界面已经按多挂载结构设计，后续可扩展数据模型而无需重做界面。",
            .githubDevManualTestingLastError: "GitHub 开发版：请使用手动 CLI/debug launchd 测试，而不是 SMAppService helper 注册。",
            .localPerformanceRequiresMounted: "本地性能测试需要一个已经挂载的 ZeroFS 路径。",
            .performanceRequiresMounted: "性能测试要求此配置已挂载。",
            .metricsUnavailableDev: "GitHub 开发版未启用特权 helper 时无法获取指标。",
            .helperDisabledMessage: "特权 helper 已禁用。请在“系统设置 > 通用 > 登录项与扩展”中批准 ZeroFS Manager。",
            .helperRegistrationFailedMessage: "特权 helper 注册失败。",
            .manualMissingSecrets: "手动挂载测试需要 Access Key、Secret Key 和 ZeroFS 密码。",
            .manualScriptNotFound: "手动测试脚本不存在或不可执行",
            .terminalLaunchFailed: "无法为手动挂载测试打开 Terminal"
        ],
        .traditionalChinese: [
            .language: "語言",
            .chooseLanguage: "選擇語言",
            .mounts: "掛載",
            .addMountProfile: "新增掛載設定",
            .autoMountAfterLoginHelp: "登入後自動掛載",
            .autoMountOffHelp: "自動掛載關閉",
            .noMount: "未選擇掛載",
            .runPerformanceTestTitle: "執行效能測試？",
            .runTest: "執行測試",
            .distribution: "分發",
            .zeroFSCLI: "ZeroFS CLI",
            .objectStorage: "物件儲存",
            .displayName: "顯示名稱",
            .endpoint: "Endpoint",
            .bucket: "Bucket",
            .prefix: "Prefix",
            .accessKey: "Access Key",
            .secretKey: "Secret Key",
            .zeroFSPassword: "ZeroFS 密碼",
            .mountSection: "掛載",
            .mountDirectory: "掛載目錄",
            .chooseMountDirectory: "選擇掛載目錄",
            .autoMount: "自動掛載",
            .off: "關閉",
            .afterLogin: "登入後",
            .releaseOnly: "僅正式版",
            .enableAutoMount: "啟用自動掛載",
            .devAutoMountDisabled: "GitHub 開發版停用自動掛載，避免啟動時觸發 SMAppService 或特權 helper 註冊。",
            .sudoLaunchDaemon: "sudo LaunchDaemon",
            .applyRestartLaunchDaemon: "套用並重啟 LaunchDaemon",
            .removeLaunchDaemon: "移除 LaunchDaemon",
            .githubDevLaunchDaemonNote: "GitHub 版使用已審查的 sudo 腳本。目前設定參數會寫入 root 擁有的 config/env 檔案，然後重啟對應的 LaunchDaemon。",
            .quota: "配額",
            .performanceTest: "效能測試",
            .cache: "快取",
            .diskCache: "磁碟快取",
            .memoryCache: "記憶體快取",
            .ports: "連接埠",
            .validation: "驗證",
            .status: "狀態",
            .githubDevBuildTitle: "GitHub 風格開發版",
            .officialReleaseTitle: "正式 Developer ID 版本",
            .githubDevWarning: "目前建置是 GitHub 風格開發版，未使用 Apple Developer ID 簽名。它適合開發測試和技術使用者手動流程，不代表正式 macOS 分發體驗。",
            .officialReleaseWarning: "正式發布模式需要 Developer ID 簽名、hardened runtime、notarization、stapling，以及正式 SMAppService helper 註冊流程。",
            .noAppleTeamIdentifier: "沒有 Apple TeamIdentifier。GitHub 開發版符合預期，但不適合正式發布。",
            .zeroFSCLIReady: "ZeroFS CLI 已就緒",
            .zeroFSCLIMissing: "缺少 ZeroFS CLI",
            .versionUnavailable: "版本不可用",
            .redetect: "重新偵測",
            .copyInstallCommand: "複製安裝命令",
            .helper: "Helper",
            .zeroFSProcess: "ZeroFS 行程",
            .metrics: "指標",
            .endpointStatus: "Endpoint",
            .quotaStatus: "配額",
            .lastError: "最後錯誤",
            .reachable: "可存取",
            .unavailable: "不可用",
            .none: "無",
            .notChecked: "未檢查",
            .checking: "檢查中",
            .invalidURL: "URL 無效",
            .mountFailed: "掛載失敗",
            .retry: "重試",
            .settings: "設定",
            .logs: "日誌",
            .disableAutoMount: "停用自動掛載",
            .close: "關閉",
            .retryMountAccessibility: "重試掛載",
            .openSystemSettingsAccessibility: "開啟系統設定",
            .showHelperLogsAccessibility: "顯示 helper 日誌",
            .disableAutoMountAccessibility: "停用自動掛載",
            .closeMountFailureDialogAccessibility: "關閉掛載失敗對話框",
            .helperGuidance: "如果 macOS 顯示 helper 已停用，請在「系統設定 > 一般 > 登入項目與延伸功能」中批准它。",
            .credentialsGuidance: "請在此設定中填寫 Access Key、Secret Key 和 ZeroFS 密碼，然後重新掛載或執行手動測試。",
            .dependencyGuidance: "安裝 ZeroFS 後，在 ZeroFS CLI 區域點選「重新偵測」。",
            .generalGuidance: "查看上方資訊，修復設定或執行狀態後再重試。",
            .githubDevMode: "GitHub 風格開發模式",
            .devModeNote: "手動 CLI 和 debug launchd 路徑只用於底層 S3/ZeroFS 測試，不是正式 SMAppService 授權流程。",
            .runManualMountTest: "執行手動掛載測試",
            .openTroubleshooting: "開啟故障排查",
            .copyCLICommand: "複製 CLI 命令",
            .later: "稍後",
            .test: "測試",
            .mountAction: "掛載",
            .unmountAction: "卸載",
            .ready: "就緒",
            .helperNotRegistered: "未註冊",
            .helperRequiresApproval: "需要批准",
            .helperEnabled: "已啟用",
            .helperDisabled: "已停用",
            .helperNotFound: "未找到",
            .helperFailed: "失敗",
            .serviceRunning: "執行中",
            .serviceStopped: "已停止",
            .serviceFailed: "失敗",
            .serviceUnknown: "未知",
            .mounted: "已掛載",
            .unmounted: "未掛載",
            .testing: "測試中",
            .failed: "失敗",
            .invalidProfileID: "Profile ID 無效",
            .invalidEndpoint: "Endpoint 無效",
            .invalidBucket: "Bucket 無效",
            .invalidPrefix: "Prefix 無效",
            .invalidMountPath: "掛載路徑無效",
            .unsafeMountPath: "掛載路徑不安全",
            .invalidQuota: "配額無效",
            .invalidCache: "快取無效",
            .invalidPort: "連接埠無效",
            .duplicatePorts: "連接埠重複",
            .zeroFSMissingTitle: "缺少 ZeroFS",
            .cliCommandCopiedTitle: "CLI 命令已複製",
            .cliCommandCopiedBody: "已複製安全模板命令。請在倉庫外建立 env 檔案並保持 0600 權限。",
            .manualMountTestTitle: "手動掛載測試",
            .manualMountTestBody: "已用本機 env 檔案開啟 Terminal。腳本輸出會遮蔽 S3 密鑰。",
            .launchDaemonInstallTitle: "LaunchDaemon 更新已開始",
            .launchDaemonInstallBody: "已在 Terminal 開啟 sudo 安裝器。授權後會寫入 root 設定並重啟此 profile。",
            .launchDaemonUninstallTitle: "LaunchDaemon 移除已開始",
            .launchDaemonUninstallBody: "已在 Terminal 為此 profile 開啟 sudo 解除安裝器。",
            .profileSaveFailedTitle: "設定儲存失敗",
            .performanceTestTitle: "效能測試",
            .recentHelperLogs: "最近 helper 日誌",
            .noRecentHelperLogs: "沒有返回最近 helper 日誌。",
            .oneActiveProfileMessage: "版本 1 只允許一個活躍設定。介面已按多掛載結構設計，後續可擴充資料模型而無需重做介面。",
            .githubDevManualTestingLastError: "GitHub 開發版：請使用手動 CLI/debug launchd 測試，而不是 SMAppService helper 註冊。",
            .localPerformanceRequiresMounted: "本機效能測試需要一個已掛載的 ZeroFS 路徑。",
            .performanceRequiresMounted: "效能測試要求此設定已掛載。",
            .metricsUnavailableDev: "GitHub 開發版未啟用特權 helper 時無法取得指標。",
            .helperDisabledMessage: "特權 helper 已停用。請在「系統設定 > 一般 > 登入項目與延伸功能」中批准 ZeroFS Manager。",
            .helperRegistrationFailedMessage: "特權 helper 註冊失敗。",
            .manualMissingSecrets: "手動掛載測試需要 Access Key、Secret Key 和 ZeroFS 密碼。",
            .manualScriptNotFound: "手動測試腳本不存在或不可執行",
            .terminalLaunchFailed: "無法為手動掛載測試開啟 Terminal"
        ],
        .japanese: [
            .language: "言語",
            .chooseLanguage: "言語を選択",
            .mounts: "マウント",
            .addMountProfile: "マウントプロファイルを追加",
            .autoMountAfterLoginHelp: "ログイン後に自動マウント",
            .autoMountOffHelp: "自動マウントはオフ",
            .noMount: "マウント未選択",
            .runPerformanceTestTitle: "性能テストを実行しますか？",
            .runTest: "テストを実行",
            .distribution: "配布",
            .zeroFSCLI: "ZeroFS CLI",
            .objectStorage: "オブジェクトストレージ",
            .displayName: "表示名",
            .endpoint: "Endpoint",
            .bucket: "Bucket",
            .prefix: "Prefix",
            .accessKey: "Access Key",
            .secretKey: "Secret Key",
            .zeroFSPassword: "ZeroFS パスワード",
            .mountSection: "マウント",
            .mountDirectory: "マウント先ディレクトリ",
            .chooseMountDirectory: "マウント先を選択",
            .autoMount: "自動マウント",
            .off: "オフ",
            .afterLogin: "ログイン後",
            .releaseOnly: "正式版のみ",
            .enableAutoMount: "自動マウントを有効化",
            .devAutoMountDisabled: "GitHub 開発版では、起動時に SMAppService や特権 helper 登録を起動しないよう自動マウントを無効化しています。",
            .sudoLaunchDaemon: "sudo LaunchDaemon",
            .applyRestartLaunchDaemon: "適用して LaunchDaemon を再起動",
            .removeLaunchDaemon: "LaunchDaemon を削除",
            .githubDevLaunchDaemonNote: "GitHub ビルドではレビュー済みの sudo スクリプトを使います。現在のプロファイル設定を root 所有の config/env に書き込み、対応する LaunchDaemon を再起動します。",
            .quota: "クォータ",
            .performanceTest: "性能テスト",
            .cache: "キャッシュ",
            .diskCache: "ディスクキャッシュ",
            .memoryCache: "メモリキャッシュ",
            .ports: "ポート",
            .validation: "検証",
            .status: "状態",
            .githubDevBuildTitle: "GitHub 形式の開発ビルド",
            .officialReleaseTitle: "正式 Developer ID リリース",
            .githubDevWarning: "現在のビルドは GitHub 形式の開発ビルドで、Apple Developer ID 署名はありません。開発テストや技術ユーザーの手動ワークフロー向けであり、正式な macOS 配布体験ではありません。",
            .officialReleaseWarning: "正式リリースでは Developer ID 署名、hardened runtime、notarization、stapling、正式な SMAppService helper 登録経路が必要です。",
            .noAppleTeamIdentifier: "Apple TeamIdentifier がありません。GitHub 開発版では想定内ですが、正式リリースには無効です。",
            .zeroFSCLIReady: "ZeroFS CLI 準備完了",
            .zeroFSCLIMissing: "ZeroFS CLI がありません",
            .versionUnavailable: "バージョン不明",
            .redetect: "再検出",
            .copyInstallCommand: "インストールコマンドをコピー",
            .helper: "Helper",
            .zeroFSProcess: "ZeroFS プロセス",
            .metrics: "メトリクス",
            .endpointStatus: "Endpoint",
            .quotaStatus: "クォータ",
            .lastError: "直近のエラー",
            .reachable: "到達可能",
            .unavailable: "利用不可",
            .none: "なし",
            .notChecked: "未確認",
            .checking: "確認中",
            .invalidURL: "URL が無効です",
            .mountFailed: "マウント失敗",
            .retry: "再試行",
            .settings: "設定",
            .logs: "ログ",
            .disableAutoMount: "自動マウントを無効化",
            .close: "閉じる",
            .retryMountAccessibility: "マウントを再試行",
            .openSystemSettingsAccessibility: "システム設定を開く",
            .showHelperLogsAccessibility: "helper ログを表示",
            .disableAutoMountAccessibility: "自動マウントを無効化",
            .closeMountFailureDialogAccessibility: "マウント失敗ダイアログを閉じる",
            .helperGuidance: "macOS で helper が無効と表示される場合は、システム設定 > 一般 > ログイン項目と拡張機能で承認してください。",
            .credentialsGuidance: "このプロファイルに Access Key、Secret Key、ZeroFS パスワードを入力し、マウントまたは手動テストを再実行してください。",
            .dependencyGuidance: "ZeroFS をインストールしてから、ZeroFS CLI セクションで「再検出」をクリックしてください。",
            .generalGuidance: "上のメッセージを確認し、プロファイルまたは実行状態を修正してから再試行してください。",
            .githubDevMode: "GitHub 形式の開発モード",
            .devModeNote: "手動 CLI と debug launchd 経路は低レベルの S3/ZeroFS テスト専用で、正式な SMAppService 認可経路ではありません。",
            .runManualMountTest: "手動マウントテストを実行",
            .openTroubleshooting: "トラブルシューティングを開く",
            .copyCLICommand: "CLI コマンドをコピー",
            .later: "後で",
            .test: "テスト",
            .mountAction: "マウント",
            .unmountAction: "アンマウント",
            .ready: "準備完了",
            .helperNotRegistered: "未登録",
            .helperRequiresApproval: "承認が必要",
            .helperEnabled: "有効",
            .helperDisabled: "無効",
            .helperNotFound: "見つかりません",
            .helperFailed: "失敗",
            .serviceRunning: "実行中",
            .serviceStopped: "停止中",
            .serviceFailed: "失敗",
            .serviceUnknown: "不明",
            .mounted: "マウント済み",
            .unmounted: "未マウント",
            .testing: "テスト中",
            .failed: "失敗",
            .invalidProfileID: "Profile ID が無効です",
            .invalidEndpoint: "Endpoint が無効です",
            .invalidBucket: "Bucket が無効です",
            .invalidPrefix: "Prefix が無効です",
            .invalidMountPath: "マウントパスが無効です",
            .unsafeMountPath: "マウントパスが安全ではありません",
            .invalidQuota: "クォータが無効です",
            .invalidCache: "キャッシュが無効です",
            .invalidPort: "ポートが無効です",
            .duplicatePorts: "ポートが重複しています",
            .zeroFSMissingTitle: "ZeroFS がありません",
            .cliCommandCopiedTitle: "CLI コマンドをコピーしました",
            .cliCommandCopiedBody: "安全なテンプレートコマンドをコピーしました。repo 外に env ファイルを作成し、0600 を維持してください。",
            .manualMountTestTitle: "手動マウントテスト",
            .manualMountTestBody: "ローカル env ファイルで Terminal を開きました。スクリプト出力では S3 シークレットがマスクされます。",
            .launchDaemonInstallTitle: "LaunchDaemon 更新を開始",
            .launchDaemonInstallBody: "Terminal で sudo インストーラを開きました。承認すると root 所有の設定を書き込み、このプロファイルを再起動します。",
            .launchDaemonUninstallTitle: "LaunchDaemon 削除を開始",
            .launchDaemonUninstallBody: "このプロファイル用の sudo アンインストーラを Terminal で開きました。",
            .profileSaveFailedTitle: "プロファイル保存失敗",
            .performanceTestTitle: "性能テスト",
            .recentHelperLogs: "最近の helper ログ",
            .noRecentHelperLogs: "最近の helper ログは返されませんでした。",
            .oneActiveProfileMessage: "バージョン 1 ではアクティブプロファイルは 1 つだけです。UI は複数マウント構造にしているため、後からデータモデルを拡張できます。",
            .githubDevManualTestingLastError: "GitHub 開発版: SMAppService helper 登録ではなく、手動 CLI/debug launchd テストを使用してください。",
            .localPerformanceRequiresMounted: "ローカル性能テストには、すでにマウント済みの ZeroFS パスが必要です。",
            .performanceRequiresMounted: "性能テストにはプロファイルがマウント済みである必要があります。",
            .metricsUnavailableDev: "特権 helper なしの GitHub 開発版ではメトリクスを利用できません。",
            .helperDisabledMessage: "特権 helper が無効です。システム設定 > 一般 > ログイン項目と拡張機能で ZeroFS Manager を承認してください。",
            .helperRegistrationFailedMessage: "特権 helper 登録に失敗しました。",
            .manualMissingSecrets: "手動マウントテストには Access Key、Secret Key、ZeroFS パスワードが必要です。",
            .manualScriptNotFound: "手動テストスクリプトが見つからないか実行できません",
            .terminalLaunchFailed: "手動マウントテスト用に Terminal を開けませんでした"
        ],
        .korean: [
            .language: "언어",
            .chooseLanguage: "언어 선택",
            .mounts: "마운트",
            .addMountProfile: "마운트 프로필 추가",
            .autoMountAfterLoginHelp: "로그인 후 자동 마운트",
            .autoMountOffHelp: "자동 마운트 꺼짐",
            .noMount: "선택한 마운트 없음",
            .runPerformanceTestTitle: "성능 테스트를 실행할까요?",
            .runTest: "테스트 실행",
            .distribution: "배포",
            .zeroFSCLI: "ZeroFS CLI",
            .objectStorage: "오브젝트 스토리지",
            .displayName: "표시 이름",
            .endpoint: "Endpoint",
            .bucket: "Bucket",
            .prefix: "Prefix",
            .accessKey: "Access Key",
            .secretKey: "Secret Key",
            .zeroFSPassword: "ZeroFS 암호",
            .mountSection: "마운트",
            .mountDirectory: "마운트 디렉터리",
            .chooseMountDirectory: "마운트 디렉터리 선택",
            .autoMount: "자동 마운트",
            .off: "꺼짐",
            .afterLogin: "로그인 후",
            .releaseOnly: "정식 릴리스 전용",
            .enableAutoMount: "자동 마운트 활성화",
            .devAutoMountDisabled: "GitHub 개발 빌드에서는 시작 시 SMAppService 또는 권한 helper 등록을 트리거하지 않도록 자동 마운트를 비활성화합니다.",
            .sudoLaunchDaemon: "sudo LaunchDaemon",
            .applyRestartLaunchDaemon: "적용 후 LaunchDaemon 재시작",
            .removeLaunchDaemon: "LaunchDaemon 제거",
            .githubDevLaunchDaemonNote: "GitHub 빌드는 검토된 sudo 스크립트를 사용합니다. 현재 프로필 매개변수를 root 소유 config/env 파일에 쓴 뒤 해당 LaunchDaemon을 재시작합니다.",
            .quota: "할당량",
            .performanceTest: "성능 테스트",
            .cache: "캐시",
            .diskCache: "디스크 캐시",
            .memoryCache: "메모리 캐시",
            .ports: "포트",
            .validation: "검증",
            .status: "상태",
            .githubDevBuildTitle: "GitHub 스타일 개발 빌드",
            .officialReleaseTitle: "공식 Developer ID 릴리스",
            .githubDevWarning: "현재 빌드는 Apple Developer ID로 서명되지 않은 GitHub 스타일 개발 빌드입니다. 개발 테스트와 기술 사용자의 수동 워크플로에 적합하며, 공식 macOS 배포 경험을 의미하지 않습니다.",
            .officialReleaseWarning: "공식 릴리스 모드는 Developer ID 서명, hardened runtime, notarization, stapling, 공식 SMAppService helper 등록 경로가 필요합니다.",
            .noAppleTeamIdentifier: "Apple TeamIdentifier가 없습니다. GitHub 개발 빌드에서는 예상된 상태지만 공식 릴리스에는 유효하지 않습니다.",
            .zeroFSCLIReady: "ZeroFS CLI 준비됨",
            .zeroFSCLIMissing: "ZeroFS CLI 없음",
            .versionUnavailable: "버전 확인 불가",
            .redetect: "다시 감지",
            .copyInstallCommand: "설치 명령 복사",
            .helper: "Helper",
            .zeroFSProcess: "ZeroFS 프로세스",
            .metrics: "메트릭",
            .endpointStatus: "Endpoint",
            .quotaStatus: "할당량",
            .lastError: "마지막 오류",
            .reachable: "연결 가능",
            .unavailable: "사용 불가",
            .none: "없음",
            .notChecked: "확인 안 됨",
            .checking: "확인 중",
            .invalidURL: "잘못된 URL",
            .mountFailed: "마운트 실패",
            .retry: "재시도",
            .settings: "설정",
            .logs: "로그",
            .disableAutoMount: "자동 마운트 비활성화",
            .close: "닫기",
            .retryMountAccessibility: "마운트 재시도",
            .openSystemSettingsAccessibility: "시스템 설정 열기",
            .showHelperLogsAccessibility: "helper 로그 보기",
            .disableAutoMountAccessibility: "자동 마운트 비활성화",
            .closeMountFailureDialogAccessibility: "마운트 실패 대화상자 닫기",
            .helperGuidance: "macOS에서 helper가 비활성화된 것으로 표시되면 시스템 설정 > 일반 > 로그인 항목 및 확장 프로그램에서 승인하세요.",
            .credentialsGuidance: "이 프로필에 Access Key, Secret Key, ZeroFS 암호를 입력한 뒤 마운트 또는 수동 테스트를 다시 실행하세요.",
            .dependencyGuidance: "ZeroFS를 설치한 뒤 ZeroFS CLI 섹션에서 다시 감지를 클릭하세요.",
            .generalGuidance: "위 메시지를 검토하고 프로필 또는 런타임 상태를 수정한 뒤 다시 시도하세요.",
            .githubDevMode: "GitHub 스타일 개발 모드",
            .devModeNote: "수동 CLI와 debug launchd 경로는 낮은 수준의 S3/ZeroFS 테스트 전용이며 공식 SMAppService 승인 경로가 아닙니다.",
            .runManualMountTest: "수동 마운트 테스트 실행",
            .openTroubleshooting: "문제 해결 열기",
            .copyCLICommand: "CLI 명령 복사",
            .later: "나중에",
            .test: "테스트",
            .mountAction: "마운트",
            .unmountAction: "언마운트",
            .ready: "준비됨",
            .helperNotRegistered: "등록되지 않음",
            .helperRequiresApproval: "승인 필요",
            .helperEnabled: "활성화됨",
            .helperDisabled: "비활성화됨",
            .helperNotFound: "찾을 수 없음",
            .helperFailed: "실패",
            .serviceRunning: "실행 중",
            .serviceStopped: "중지됨",
            .serviceFailed: "실패",
            .serviceUnknown: "알 수 없음",
            .mounted: "마운트됨",
            .unmounted: "마운트 안 됨",
            .testing: "테스트 중",
            .failed: "실패",
            .invalidProfileID: "잘못된 Profile ID",
            .invalidEndpoint: "잘못된 Endpoint",
            .invalidBucket: "잘못된 Bucket",
            .invalidPrefix: "잘못된 Prefix",
            .invalidMountPath: "잘못된 마운트 경로",
            .unsafeMountPath: "안전하지 않은 마운트 경로",
            .invalidQuota: "잘못된 할당량",
            .invalidCache: "잘못된 캐시",
            .invalidPort: "잘못된 포트",
            .duplicatePorts: "중복 포트",
            .zeroFSMissingTitle: "ZeroFS 없음",
            .cliCommandCopiedTitle: "CLI 명령 복사됨",
            .cliCommandCopiedBody: "안전한 템플릿 명령을 복사했습니다. repo 밖에 env 파일을 만들고 0600 권한을 유지하세요.",
            .manualMountTestTitle: "수동 마운트 테스트",
            .manualMountTestBody: "로컬 env 파일로 Terminal을 열었습니다. 스크립트 출력은 S3 시크릿을 마스킹합니다.",
            .launchDaemonInstallTitle: "LaunchDaemon 업데이트 시작됨",
            .launchDaemonInstallBody: "Terminal에서 sudo 설치 스크립트를 열었습니다. 승인하면 root 소유 설정을 쓰고 이 프로필을 재시작합니다.",
            .launchDaemonUninstallTitle: "LaunchDaemon 제거 시작됨",
            .launchDaemonUninstallBody: "이 프로필의 sudo 제거 스크립트를 Terminal에서 열었습니다.",
            .profileSaveFailedTitle: "프로필 저장 실패",
            .performanceTestTitle: "성능 테스트",
            .recentHelperLogs: "최근 helper 로그",
            .noRecentHelperLogs: "최근 helper 로그가 반환되지 않았습니다.",
            .oneActiveProfileMessage: "버전 1은 활성 프로필 하나만 허용합니다. UI는 다중 마운트 구조로 되어 있어 향후 데이터 모델을 확장할 수 있습니다.",
            .githubDevManualTestingLastError: "GitHub 개발 빌드: SMAppService helper 등록 대신 수동 CLI/debug launchd 테스트를 사용하세요.",
            .localPerformanceRequiresMounted: "로컬 성능 테스트에는 이미 마운트된 ZeroFS 경로가 필요합니다.",
            .performanceRequiresMounted: "성능 테스트를 하려면 프로필이 마운트되어 있어야 합니다.",
            .metricsUnavailableDev: "권한 helper가 없는 GitHub 개발 빌드에서는 메트릭을 사용할 수 없습니다.",
            .helperDisabledMessage: "권한 helper가 비활성화되었습니다. 시스템 설정 > 일반 > 로그인 항목 및 확장 프로그램에서 ZeroFS Manager를 승인하세요.",
            .helperRegistrationFailedMessage: "권한 helper 등록에 실패했습니다.",
            .manualMissingSecrets: "수동 마운트 테스트에는 Access Key, Secret Key, ZeroFS 암호가 필요합니다.",
            .manualScriptNotFound: "수동 테스트 스크립트를 찾을 수 없거나 실행할 수 없습니다",
            .terminalLaunchFailed: "수동 마운트 테스트용 Terminal을 열 수 없습니다"
        ]
    ]
}

enum AppTextKey: String, CaseIterable {
    case language
    case chooseLanguage
    case mounts
    case addMountProfile
    case autoMountAfterLoginHelp
    case autoMountOffHelp
    case noMount
    case runPerformanceTestTitle
    case runTest
    case distribution
    case zeroFSCLI
    case objectStorage
    case displayName
    case endpoint
    case bucket
    case prefix
    case accessKey
    case secretKey
    case zeroFSPassword
    case mountSection
    case mountDirectory
    case chooseMountDirectory
    case autoMount
    case off
    case afterLogin
    case releaseOnly
    case enableAutoMount
    case devAutoMountDisabled
    case sudoLaunchDaemon
    case applyRestartLaunchDaemon
    case removeLaunchDaemon
    case githubDevLaunchDaemonNote
    case quota
    case performanceTest
    case cache
    case diskCache
    case memoryCache
    case ports
    case validation
    case status
    case githubDevBuildTitle
    case officialReleaseTitle
    case githubDevWarning
    case officialReleaseWarning
    case noAppleTeamIdentifier
    case zeroFSCLIReady
    case zeroFSCLIMissing
    case versionUnavailable
    case redetect
    case copyInstallCommand
    case helper
    case zeroFSProcess
    case metrics
    case endpointStatus
    case quotaStatus
    case lastError
    case reachable
    case unavailable
    case none
    case notChecked
    case checking
    case invalidURL
    case mountFailed
    case retry
    case settings
    case logs
    case disableAutoMount
    case close
    case retryMountAccessibility
    case openSystemSettingsAccessibility
    case showHelperLogsAccessibility
    case disableAutoMountAccessibility
    case closeMountFailureDialogAccessibility
    case helperGuidance
    case credentialsGuidance
    case dependencyGuidance
    case generalGuidance
    case githubDevMode
    case devModeNote
    case runManualMountTest
    case openTroubleshooting
    case copyCLICommand
    case later
    case test
    case mountAction
    case unmountAction
    case ready
    case helperNotRegistered
    case helperRequiresApproval
    case helperEnabled
    case helperDisabled
    case helperNotFound
    case helperFailed
    case serviceRunning
    case serviceStopped
    case serviceFailed
    case serviceUnknown
    case mounted
    case unmounted
    case testing
    case failed
    case invalidProfileID
    case invalidEndpoint
    case invalidBucket
    case invalidPrefix
    case invalidMountPath
    case unsafeMountPath
    case invalidQuota
    case invalidCache
    case invalidPort
    case duplicatePorts
    case zeroFSMissingTitle
    case cliCommandCopiedTitle
    case cliCommandCopiedBody
    case manualMountTestTitle
    case manualMountTestBody
    case launchDaemonInstallTitle
    case launchDaemonInstallBody
    case launchDaemonUninstallTitle
    case launchDaemonUninstallBody
    case profileSaveFailedTitle
    case performanceTestTitle
    case recentHelperLogs
    case noRecentHelperLogs
    case oneActiveProfileMessage
    case githubDevManualTestingLastError
    case localPerformanceRequiresMounted
    case performanceRequiresMounted
    case metricsUnavailableDev
    case helperDisabledMessage
    case helperRegistrationFailedMessage
    case manualMissingSecrets
    case manualScriptNotFound
    case terminalLaunchFailed
}
