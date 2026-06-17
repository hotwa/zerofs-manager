import Foundation
import ZeroFSManagerDomain
import ZeroFSManagerSecrets
import ZeroFSManagerHelperClient
import ZeroFSLaunchd
import ZeroFSPerformance
import ZeroFSPackagingSupport
import ZeroFSPrivilegedHelperCore

@main
struct ZeroFSManagerChecks {
    static func main() async throws {
        var checks = CheckSuite()
        try checkDomain(&checks)
        try checkSecrets(&checks)
        try checkZeroFSDependency(&checks)
        try checkProfilePersistence(&checks)
        try await checkHelperClient(&checks)
        try checkLaunchd(&checks)
        try checkHelperRuntime(&checks)
        try await checkHelperOperations(&checks)
        try await checkLoginAutoMount(&checks)
        try await checkPerformance(&checks)
        try await checkReliabilityProbes(&checks)
        try checkPackaging(&checks)
        checks.finish()
    }

    private static func checkDomain(_ checks: inout CheckSuite) throws {
        let profile = try MountProfile.example()
        checks.expect(ProfileValidator.validate(profile).isEmpty, "valid profile has no validation issues")

        let defaultPath = MountPath.defaultPath(displayName: "Lingyu Zeng")
        checks.expect(defaultPath.rawValue == "/Volumes/ZeroFS-Lingyu-Zeng", "default mount path uses display name")

        var relative = try MountProfile.example()
        relative.mountPath = MountPath(rawValue: "relative/path")
        checks.expect(ProfileValidator.validate(relative).contains(.invalidMountPath), "relative mount path is rejected")

        var traversal = try MountProfile.example()
        traversal.mountPath = MountPath(rawValue: "/Volumes/../etc")
        checks.expect(ProfileValidator.validate(traversal).contains(.unsafeMountPath), "path traversal is rejected")

        var invalidObjectStorage = try MountProfile.example()
        invalidObjectStorage.endpoint = "not a url"
        invalidObjectStorage.bucket = "Bad Bucket"
        invalidObjectStorage.prefix = "../escape"
        let storageIssues = ProfileValidator.validate(invalidObjectStorage)
        checks.expect(storageIssues.contains(.invalidEndpoint), "invalid endpoint is rejected")
        checks.expect(storageIssues.contains(.invalidBucket), "invalid bucket is rejected")
        checks.expect(storageIssues.contains(.invalidPrefix), "invalid prefix is rejected")

        var injectedPrefix = try MountProfile.example()
        injectedPrefix.prefix = "safe\"\n[aws]\nendpoint = \"evil"
        checks.expect(ProfileValidator.validate(injectedPrefix).contains(.invalidPrefix), "prefix TOML injection characters are rejected")

        var endpointWithPath = try MountProfile.example()
        endpointWithPath.endpoint = "https://s3.example.invalid/with/path"
        checks.expect(ProfileValidator.validate(endpointWithPath).contains(.invalidEndpoint), "endpoint path is rejected")

        var invalidID = try MountProfile.example()
        invalidID.id = ProfileID(rawValue: "../root")
        checks.expect(ProfileValidator.validate(invalidID).contains(.invalidProfileID), "raw decoded invalid profile id is rejected")

        var duplicatePorts = try MountProfile.example()
        duplicatePorts.ports = PortSet(nfs: 2049, rpc: 2049, metrics: 9091)
        checks.expect(ProfileValidator.validate(duplicatePorts).contains(.duplicatePorts), "duplicate ports are rejected")

        let id = try ProfileID("example-profile")
        let firstName = try MountProfile.example(id: id, displayName: "Example Profile")
        let renamed = try MountProfile.example(id: id, displayName: "Renamed")
        checks.expect(
            ProfileRuntimePaths(profile: firstName).configPath == ProfileRuntimePaths(profile: renamed).configPath,
            "runtime paths remain stable after display rename"
        )
        checks.expect(
            ServiceNames(profile: firstName).profileRuntimeLabel == ServiceNames(profile: renamed).profileRuntimeLabel,
            "service labels remain stable after display rename"
        )

        let other = try MountProfile.example(id: ProfileID("lab-minio"))
        checks.expect(
            ProfileRuntimePaths(profile: firstName).configPath != ProfileRuntimePaths(profile: other).configPath,
            "different profiles get different runtime paths"
        )
        checks.expect(
            ServiceNames(profile: firstName).profileRuntimeLabel != ServiceNames(profile: other).profileRuntimeLabel,
            "different profiles get different runtime service labels"
        )
        checks.expect(
            ServiceNames(profile: firstName).helperMachServiceName == ServiceNames(profile: other).helperMachServiceName,
            "different profiles share one stable helper mach service"
        )
        checks.expect(
            PrivilegedMountPathPolicy().issues(for: MountPath(rawValue: "/Volumes/ZeroFS-Example")).isEmpty,
            "privileged mount policy allows child Volumes mount"
        )
        checks.expect(
            PrivilegedMountPathPolicy().issues(for: MountPath(rawValue: "/Volumes")).contains(.unsafeMountPath),
            "privileged mount policy rejects Volumes root"
        )
        checks.expect(
            PrivilegedMountPathPolicy().issues(for: MountPath(rawValue: "/Library/ZeroFS")).contains(.unsafeMountPath),
            "privileged mount policy rejects system directories"
        )
        let mountOutput = """
        /dev/disk3s1 on / (apfs, local)
        127.0.0.1:/ on /Volumes/ZeroFS-Example (nfs, asynchronous)
        """
        checks.expect(
            LocalMountTable.isMounted(path: "/Volumes/ZeroFS-Example", mountOutput: mountOutput),
            "local mount table detects an externally mounted ZeroFS path"
        )
        checks.expect(
            !LocalMountTable.isMounted(path: "/Volumes/ZeroFS-missing", mountOutput: mountOutput),
            "local mount table reports missing mount path"
        )
        let nonZeroFSMountOutput = """
        /dev/disk9s1 on /Volumes/ZeroFS-Example (apfs, local, read-only)
        storage.example:/ on /Volumes/ZeroFS-remote (nfs, nodev, nosuid)
        """
        checks.expect(
            !LocalMountTable.isMounted(path: "/Volumes/ZeroFS-Example", mountOutput: nonZeroFSMountOutput),
            "local mount table rejects ordinary mounts at the ZeroFS path"
        )
        checks.expect(
            !LocalMountTable.isMounted(path: "/Volumes/ZeroFS-remote", mountOutput: nonZeroFSMountOutput),
            "local mount table rejects remote NFS mounts that are not local ZeroFS"
        )

        checks.expect(!OneActiveProfilePolicy.canAdd(other, to: [firstName]), "v1 rejects additional active profile")
        checks.expect(OneActiveProfilePolicy.canAdd(firstName, to: []), "v1 allows first active profile")
        checks.expect(ProductDefaults.firstRunAutoMountPolicy == .disabled, "first-run profile does not auto-mount before explicit user opt-in")
        checks.expect(ProductDefaults.defaultPerformanceTestMegabytes == 64, "default performance test size is conservative")
        checks.expect(AppDistributionMode.defaultMode == .githubDev, "default app distribution mode is GitHub-style dev")
        checks.expect(!AppDistributionMode.githubDev.allowsAutomaticHelperRegistration, "GitHub-style dev does not auto-register the privileged helper")
        checks.expect(!AppDistributionMode.githubDev.allowsLoginAutoMount, "GitHub-style dev does not auto-mount at login")
        checks.expect(!AppDistributionMode.githubDev.requiresAppleTeamIdentifier, "GitHub-style dev does not require an Apple TeamIdentifier")
        checks.expect(AppDistributionMode.officialRelease.allowsAutomaticHelperRegistration, "official release enables helper registration path")
        checks.expect(AppDistributionMode.officialRelease.requiresAppleTeamIdentifier, "official release requires an Apple TeamIdentifier")
        checks.expect(
            AppDistributionMode.resolve(environment: ["ZEROFS_MANAGER_DISTRIBUTION_MODE": "official-release"]) == .officialRelease,
            "distribution mode can be selected for release builds"
        )
        var legacyAutoMount = try MountProfile.example()
        legacyAutoMount.autoMount = .afterLogin
        checks.expect(
            FirstRunProfilePolicy.requireExplicitAutoMountOptIn([legacyAutoMount]).first?.autoMount == .disabled,
            "legacy profiles require a fresh explicit auto-mount opt-in"
        )
    }

    private static func checkSecrets(_ checks: inout CheckSuite) throws {
        let profileID = try ProfileID("example-profile")
        let store = InMemorySecretStore()
        try store.save("access-value", kind: .s3AccessKeyID, profileID: profileID)
        try store.save("secret-value", kind: .s3SecretAccessKey, profileID: profileID)

        checks.expect(try store.read(kind: .s3AccessKeyID, profileID: profileID) == "access-value", "in-memory store reads access key")
        checks.expect(try store.read(kind: .s3SecretAccessKey, profileID: profileID) == "secret-value", "in-memory store reads secret key")

        let redacted = SecretRedactor.redact(
            "endpoint ok access-value secret-value",
            secrets: ["access-value", "secret-value"]
        )
        checks.expect(!redacted.contains("access-value"), "redactor removes access key")
        checks.expect(!redacted.contains("secret-value"), "redactor removes secret key")
        checks.expect(redacted.contains("[REDACTED]"), "redactor marks redacted values")

        let profile = try MountProfile.example()
        let encodedProfile = String(decoding: try JSONEncoder().encode(profile), as: UTF8.self)
        checks.expect(!encodedProfile.contains("access-value"), "profile JSON does not contain access key")
        checks.expect(!encodedProfile.contains("secret-value"), "profile JSON does not contain secret key")

        let reportText = String(describing: PerformanceReport(
            profileID: profileID,
            sizeBytes: 4096,
            checksumStatus: .pass,
            writeSeconds: 0.1,
            readSeconds: 0.1,
            dfBeforeWrite: DiskUsageSnapshot(phase: .beforeWrite, path: "/Volumes/ZeroFS-Example", rawOutput: "df output"),
            dfAfterWrite: DiskUsageSnapshot(phase: .afterWrite, path: "/Volumes/ZeroFS-Example", rawOutput: "df output"),
            dfAfterCleanup: DiskUsageSnapshot(phase: .afterCleanup, path: "/Volumes/ZeroFS-Example", rawOutput: "df output"),
            metricsBeforeCleanup: "zerofs_used_bytes 0",
            metricsAfterCleanup: "zerofs_used_bytes 0",
            remoteCleanup: .removed,
            readbackCleanup: .removed,
            capacityNote: "configured ZeroFS quota"
        ))
        checks.expect(!reportText.contains("access-value"), "performance report text does not contain access key")
        checks.expect(!reportText.contains("secret-value"), "performance report text does not contain secret key")

        let redactedError = SecretRedactor.redact(
            HelperClientError.operationFailed(operation: .mount, message: "failed secret-value", logExcerpt: "access-value").description,
            secrets: ["access-value", "secret-value"]
        )
        checks.expect(!redactedError.contains("access-value"), "printable error redaction removes access key")
        checks.expect(!redactedError.contains("secret-value"), "printable error redaction removes secret key")
    }

    private static func checkZeroFSDependency(_ checks: inout CheckSuite) throws {
        checks.expect(
            ZeroFSInstallGuidance.recommendedShellCommand == "curl -sSfL https://sh.zerofs.net | sh",
            "ZeroFS install guidance uses official install script"
        )
        checks.expect(
            ZeroFSInstallGuidance.sourceURL.absoluteString == "https://github.com/Barre/zerofs",
            "ZeroFS install guidance links to upstream project"
        )

        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let binDirectory = tempRoot.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: binDirectory, withIntermediateDirectories: true)
        let fakeBinary = binDirectory.appendingPathComponent("zerofs")
        try "#!/bin/sh\nprintf 'zerofs 1.2.6\\n'\n".write(to: fakeBinary, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeBinary.path)

        let locator = ZeroFSBinaryLocator(pathEnvironment: binDirectory.path, additionalCandidatePaths: [])
        let detected = locator.locate()
        checks.expect(detected?.path == fakeBinary.path, "ZeroFS locator finds executable on PATH")
        checks.expect(detected?.version == "zerofs 1.2.6", "ZeroFS locator records version output")

        let slowBinary = binDirectory.appendingPathComponent("slow-zerofs")
        try "#!/bin/sh\nsleep 1\nprintf 'zerofs slow\\n'\n".write(to: slowBinary, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: slowBinary.path)
        let slowLocator = ZeroFSBinaryLocator(pathEnvironment: "", additionalCandidatePaths: [slowBinary.path], versionTimeoutSeconds: 0.05)
        checks.expect(slowLocator.locate()?.version == nil, "ZeroFS version detection times out instead of blocking startup")

        let missingLocator = ZeroFSBinaryLocator(pathEnvironment: tempRoot.appendingPathComponent("missing").path, additionalCandidatePaths: [])
        checks.expect(missingLocator.locate() == nil, "ZeroFS locator reports missing dependency")
    }

    private static func checkProfilePersistence(_ checks: inout CheckSuite) throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let store = FileMountProfileStore(fileURL: tempRoot.appendingPathComponent("profiles.json"))
        let profile = try MountProfile.example()
        try store.save([profile])

        checks.expect(try store.load() == [profile], "profile store persists non-secret mount metadata")
        let storedText = try String(contentsOf: store.fileURL, encoding: .utf8)
        checks.expect(!storedText.contains("access-value"), "profile store does not persist access key fixtures")
        checks.expect(!storedText.contains("secret-value"), "profile store does not persist secret key fixtures")
    }

    private static func checkHelperClient(_ checks: inout CheckSuite) async throws {
        let profile = try MountProfile.example()
        let client = MockPrivilegedHelperClient()
        client.statusResult = .init(
            registration: .enabled,
            service: .running,
            mount: .unmounted,
            metricsReachable: true,
            lastError: nil
        )

        let status = try await client.status(profileID: profile.id)
        checks.expect(status.registration == .enabled, "mock helper reports registration state")
        checks.expect(status.service == .running, "mock helper reports service state")
        checks.expect(status.mount == .unmounted, "mock helper reports mount state")

        let request = HelperRequest.mount(profile)
        let requestRoundTrip = try JSONDecoder().decode(
            HelperRequest.self,
            from: try JSONEncoder().encode(request)
        )
        checks.expect(requestRoundTrip == request, "helper request model codable round-trips")

        let response = HelperResponse.status(status)
        let responseRoundTrip = try JSONDecoder().decode(
            HelperResponse.self,
            from: try JSONEncoder().encode(response)
        )
        checks.expect(responseRoundTrip == response, "helper response model codable round-trips")

        checks.expect(
            ServiceManagementStatusMapper.map(.requiresApproval) == .requiresApproval,
            "ServiceManagement requires-approval maps to helper registration state"
        )
        checks.expect(
            XPCPrivilegedHelperClient.machServiceName == "com.zerofs.manager.helper",
            "XPC helper client uses bundled helper Mach service"
        )
        checks.expect(
            HelperServiceRegistrar.helperPlistName == "com.zerofs.manager.helper.plist",
            "ServiceManagement registrar uses bundled helper plist"
        )
        let helperMain = try String(
            contentsOf: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Sources/ZeroFSPrivilegedHelper/main.swift"),
            encoding: .utf8
        )
        checks.expect(
            helperMain.contains("ZEROFS_MANAGER_HELPER_MACH_SERVICE_NAME"),
            "privileged helper can use a debug Mach service name for manual launchd testing"
        )
        let authPolicy = HelperClientAuthorizationPolicy(
            allowedBundleIdentifier: "com.zerofs.manager",
            allowedTeamIdentifier: "TEAM12345"
        )
        checks.expect(
            authPolicy.accepts(ClientCodeSigningInfo(bundleIdentifier: "com.zerofs.manager", teamIdentifier: "TEAM12345")),
            "helper client authorization accepts matching signed app"
        )
        checks.expect(
            !authPolicy.accepts(ClientCodeSigningInfo(bundleIdentifier: "com.evil.manager", teamIdentifier: "TEAM12345")),
            "helper client authorization rejects wrong bundle id"
        )
        checks.expect(
            !authPolicy.accepts(ClientCodeSigningInfo(bundleIdentifier: "com.zerofs.manager", teamIdentifier: "OTHERTEAM")),
            "helper client authorization rejects wrong team id"
        )
        let encodedRequest = try HelperXPCMessageCodec.encodeRequest(.status(profile.id))
        checks.expect(
            try HelperXPCMessageCodec.decodeRequest(encodedRequest) == .status(profile.id),
            "XPC helper request codec round-trips"
        )
        let encodedResponse = try HelperXPCMessageCodec.encodeResponse(.accepted(.mount))
        checks.expect(
            try HelperXPCMessageCodec.decodeResponse(encodedResponse) == .accepted(.mount),
            "XPC helper response codec round-trips"
        )

        client.statusResult = .init(
            registration: .requiresApproval,
            service: .stopped,
            mount: .stale,
            metricsReachable: false,
            lastError: "approval required"
        )
        let approvalStatus = try await client.status(profileID: profile.id)
        checks.expect(approvalStatus.registration == .requiresApproval, "mock helper reports requires-approval state")
        checks.expect(approvalStatus.mount == .stale, "mock helper reports stale mount state")

        client.statusResult = .init(
            registration: .disabled,
            service: .failed,
            mount: .failed,
            metricsReachable: false,
            lastError: "disabled in System Settings"
        )
        let disabledStatus = try await client.status(profileID: profile.id)
        checks.expect(disabledStatus.registration == .disabled, "mock helper reports disabled state")
        checks.expect(disabledStatus.service == .failed, "mock helper reports failed service state")

        client.mountResult = .failure(.operationFailed(operation: .mount, message: "NFS failed", logExcerpt: "mount timeout"))
        do {
            try await client.mount(profile)
            checks.expect(false, "mock helper mount failure throws")
        } catch let error as HelperClientError {
            checks.expect(error.description.contains("NFS failed"), "helper error includes human message")
            checks.expect(error.description.contains("mount timeout"), "helper error includes bounded log excerpt")
        }

        client.mountResult = .failure(.requiresApproval)
        do {
            try await client.mount(profile)
            checks.expect(false, "mock helper approval failure throws")
        } catch HelperClientError.requiresApproval {
            checks.expect(true, "helper approval failure is typed")
        }

        client.statusResultOverride = .failure(.unavailable)
        do {
            _ = try await client.status(profileID: profile.id)
            checks.expect(false, "mock helper unavailable status throws")
        } catch HelperClientError.unavailable {
            checks.expect(true, "helper unavailable failure is typed")
        }
    }

    private static func checkLaunchd(_ checks: inout CheckSuite) throws {
        let profile = try MountProfile.example()
        let names = ServiceNames(profile: profile)
        let plist = LaunchDaemonPlist(
            label: names.helperLaunchDaemonLabel,
            bundleProgram: "Contents/MacOS/ZeroFSPrivilegedHelper",
            machServiceName: names.helperMachServiceName,
            associatedBundleIdentifier: "com.zerofs.manager",
            runAtLoad: true,
            keepAlive: false
        )
        let data = try plist.xmlData()
        let text = String(decoding: data, as: UTF8.self)

        checks.expect(names.helperLaunchDaemonPlistName == "com.zerofs.manager.helper.plist", "helper launchd plist name is stable")
        checks.expect(names.profileRuntimePlistName.hasSuffix(".plist"), "profile runtime plist name has suffix")
        checks.expect(text.contains("BundleProgram"), "launchd plist contains BundleProgram")
        checks.expect(text.contains("MachServices"), "launchd plist contains MachServices")
        checks.expect(text.contains("AssociatedBundleIdentifiers"), "launchd plist contains AssociatedBundleIdentifiers")
        checks.expect(!text.contains("secret-value"), "launchd plist contains no secrets from check fixture")
    }

    private static func checkHelperRuntime(_ checks: inout CheckSuite) throws {
        let profile = try MountProfile.example()
        let fileSet = try HelperRuntimeGenerator.makeFileSet(profile: profile)
        checks.expect(fileSet.configContents.contains("s3.example.invalid"), "helper runtime config contains endpoint")
        checks.expect(!fileSet.configContents.contains("secret-value"), "helper runtime config contains no secret")

        var unsafeProfile = profile
        unsafeProfile.mountPath = MountPath(rawValue: "/Library/ZeroFS")
        do {
            _ = try HelperRuntimeGenerator.makeFileSet(profile: unsafeProfile)
            checks.expect(false, "helper runtime rejects unsafe mount path")
        } catch HelperRuntimeValidationError.invalidPrivilegedMountPath {
            checks.expect(true, "helper runtime rejects unsafe mount path")
        }

        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let runtimeProfile = try MountProfile.example(id: ProfileID("runtime-test"))
        let runtimePaths = ProfileRuntimePaths(profile: runtimeProfile, baseRoot: tempRoot.appendingPathComponent("runtime").path)
        do {
            _ = try HelperRuntimeGenerator.makeFileSet(profile: runtimeProfile, paths: runtimePaths)
            checks.expect(false, "helper runtime rejects unapproved runtime root")
        } catch HelperRuntimeValidationError.invalidRuntimeRoot {
            checks.expect(true, "helper runtime rejects unapproved runtime root")
        }
        let approvedRuntimeSet = try HelperRuntimeGenerator.makeFileSet(
            profile: runtimeProfile,
            paths: runtimePaths,
            allowedRuntimeRoots: [tempRoot.appendingPathComponent("runtime").path]
        )
        checks.expect(approvedRuntimeSet.paths.runtimeRoot == runtimePaths.runtimeRoot, "helper runtime accepts explicit approved runtime root")

        let runtimeSet = HelperRuntimeFileSet(profile: runtimeProfile, paths: runtimePaths)
        let escapedProfile = MountProfile(
            id: try ProfileID("escape-test"),
            displayName: "escape",
            endpoint: "https://example.com",
            bucket: "example-bucket",
            prefix: "",
            mountPath: MountPath(rawValue: "/Volumes/ZeroFS-escape"),
            quota: Quota(gigabytes: 1),
            cache: CacheSettings(diskGigabytes: 0, memoryGigabytes: 0),
            ports: PortSet(nfs: 2049, rpc: 17000, metrics: 9091),
            autoMount: .disabled,
            performanceTestSize: .megabytes(1)
        )
        let escapedPaths = ProfileRuntimePaths(profile: escapedProfile, baseRoot: tempRoot.appendingPathComponent("runtime").path)
        let escapedFileSet = HelperRuntimeFileSet(profile: escapedProfile, paths: escapedPaths)
        checks.expect(escapedFileSet.configContents.contains("endpoint = \"https://example.com\""), "helper runtime TOML quotes endpoint")

        try HelperRuntimeWriter().write(
            fileSet: runtimeSet,
            envContents: runtimeSet.envContents(
                accessKeyVariable: "access-value",
                secretKeyVariable: "secret-value",
                encryptionPasswordVariable: "password-value"
            )
        )
        let envAttributes = try FileManager.default.attributesOfItem(atPath: runtimePaths.envPath)
        checks.expect((envAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o600, "helper runtime env file uses 0600 permissions")

        checks.expect(fileSet.configContents.contains("[storage]"), "helper runtime config uses ZeroFS storage section")
        checks.expect(fileSet.configContents.contains("s3://example-bucket/example-prefix"), "helper runtime config uses bucket and prefix URL")
        checks.expect(fileSet.configContents.contains("[aws]"), "helper runtime config uses ZeroFS aws section")
        checks.expect(fileSet.configContents.contains("127.0.0.1:2049"), "helper runtime config binds NFS to loopback port")
        checks.expect(
            runtimeSet.envContents(
                accessKeyVariable: "access-value",
                secretKeyVariable: "secret-value",
                encryptionPasswordVariable: "password-value"
            ).contains("ZEROFS_CACHE_DIR='\(runtimePaths.cachePath)'"),
            "helper runtime env exports cache directory"
        )

        let external = ExternalZeroFSRuntimeDependency(binary: ZeroFSBinary(path: "/usr/local/bin/zerofs"))
        checks.expect(
            external.runArguments(configPath: runtimePaths.configPath) == ["/usr/local/bin/zerofs", "run", "--config", runtimePaths.configPath],
            "helper runtime uses external zerofs binary"
        )
        checks.expect(
            external.flushArguments(configPath: runtimePaths.configPath) == ["/usr/local/bin/zerofs", "flush", "--config", runtimePaths.configPath],
            "helper runtime flush uses external zerofs binary"
        )

        let mountCommand = ExternalZeroFSCommandFactory.mountCommand(profile: profile)
        checks.expect(
            mountCommand == HelperCommand(
                executablePath: "/sbin/mount",
                arguments: [
                    "-t",
                    "nfs",
                    "-o",
                    "async,nolocks,vers=3,tcp,port=2049,mountport=2049,hard,rsize=1048576,wsize=1048576",
                    "127.0.0.1:/",
                    "/Volumes/ZeroFS-Example"
                ]
            ),
            "helper runtime builds proven NFSv3 mount command"
        )
        checks.expect(
            ExternalZeroFSCommandFactory.unmountCommand(profile: profile) == HelperCommand(
                executablePath: "/sbin/umount",
                arguments: ["/Volumes/ZeroFS-Example"]
            ),
            "helper runtime builds unmount command"
        )
        checks.expect(
            fileSet.runScriptContents(binary: ZeroFSBinary(path: "/usr/local/bin/zerofs")).contains("run --config"),
            "helper runtime run script invokes zerofs run with config"
        )
        checks.expect(
            fileSet.mountScriptContents.contains("NFS_OPTIONS=\"async,nolocks,vers=3,tcp,port=2049,mountport=2049,hard,rsize=1048576,wsize=1048576\""),
            "helper runtime mount script uses proven NFS options"
        )
    }

    private static func checkHelperOperations(_ checks: inout CheckSuite) async throws {
        let profile = try MountProfile.example()
        let recorder = RecordingHelperOperationEnvironment()
        let coordinator = HelperOperationCoordinator(environment: recorder)

        _ = await coordinator.handle(.installOrUpdate(profile))
        _ = await coordinator.handle(.syncRuntimeSecrets(
            profileID: profile.id,
            secrets: RuntimeSecretPayload(
                accessKeyID: "access-value",
                secretAccessKey: "secret-value",
                zeroFSEncryptionPassword: "password-value"
            )
        ))
        _ = await coordinator.handle(.start(profile.id))
        _ = await coordinator.handle(.stop(profile.id))
        _ = await coordinator.handle(.restart(profile.id))
        _ = await coordinator.handle(.mount(profile))
        _ = await coordinator.handle(.unmount(profile.id))
        _ = await coordinator.handle(.flush(profile.id))
        let statusResponse = await coordinator.handle(.status(profile.id))
        let logsResponse = await coordinator.handle(.logs(profileID: profile.id, limitBytes: 8))

        checks.expect(
            recorder.operations == [.installOrUpdate, .syncRuntimeSecrets, .start, .stop, .restart, .mount, .unmount, .flush, .status, .logs],
            "helper operation coordinator executes only supported operations"
        )
        checks.expect(statusResponse == .status(recorder.status), "helper operation coordinator returns typed status")
        checks.expect(logsResponse == .logs("bounded "), "helper operation coordinator returns bounded logs")

        let failing = RecordingHelperOperationEnvironment()
        failing.mountResult = .failure(HelperClientError.operationFailed(operation: .mount, message: "mount failed", logExcerpt: "nfs refused"))
        let failingCoordinator = HelperOperationCoordinator(environment: failing)
        let failure = await failingCoordinator.handle(.mount(profile))
        checks.expect(
            failure == .failure(HelperErrorPayload(operation: .mount, message: "mount failed", logExcerpt: "nfs refused")),
            "helper operation coordinator returns structured failure"
        )

        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let binDirectory = tempRoot.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: binDirectory, withIntermediateDirectories: true)
        let fakeBinary = binDirectory.appendingPathComponent("zerofs")
        try "#!/bin/sh\nprintf 'zerofs 1.2.6\\n'\n".write(to: fakeBinary, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeBinary.path)
        let commandRunner = RecordingHelperCommandRunner()
        let runtimeBaseRoot = tempRoot.appendingPathComponent("runtime").path
        let externalEnvironment = ExternalZeroFSOperationEnvironment(
            binaryLocator: ZeroFSBinaryLocator(pathEnvironment: binDirectory.path, additionalCandidatePaths: []),
            commandRunner: commandRunner,
            profileStore: InMemoryHelperProfileStore(),
            runtimeBaseRoot: runtimeBaseRoot,
            launchDaemonRoot: tempRoot.appendingPathComponent("launchdaemons").path,
            logRoot: tempRoot.appendingPathComponent("logs").path,
            mountTableReader: StaticMountTableReader(mountedPaths: []),
            portWaiter: ImmediatePortWaiter(),
            createMountDirectory: false
        )
        try await externalEnvironment.installOrUpdate(profile)
        try await externalEnvironment.syncRuntimeSecrets(
            profileID: profile.id,
            secrets: RuntimeSecretPayload(
                accessKeyID: "access-value",
                secretAccessKey: "secret-value",
                zeroFSEncryptionPassword: "password-value"
            )
        )
        try await externalEnvironment.start(profileID: profile.id)
        try await externalEnvironment.mount(profile)
        try await externalEnvironment.flush(profileID: profile.id)
        try await externalEnvironment.unmount(profileID: profile.id)
        commandRunner.queuedResults = [HelperCommandResult(exitCode: 0, standardOutput: "state = running\npid = 123\n")]
        let externalStatus = try await externalEnvironment.status(profileID: profile.id)
        let externalLogs = try await externalEnvironment.logs(profileID: profile.id, limitBytes: 16)
        checks.expect(commandRunner.commands.contains(ExternalZeroFSCommandFactory.mountCommand(profile: profile)), "external helper environment executes NFS mount command")
        checks.expect(
            commandRunner.commands.contains(ExternalZeroFSCommandFactory.flushCommand(
                binary: ZeroFSBinary(path: fakeBinary.path),
                configPath: ProfileRuntimePaths(profile: profile, baseRoot: runtimeBaseRoot).configPath
            )),
            "external helper environment executes zerofs flush"
        )
        checks.expect(externalStatus.registration == .enabled, "external helper environment reports helper enabled")
        checks.expect(externalStatus.service == .running, "external helper environment reports running service from launchctl")
        checks.expect(externalStatus.mount == .unmounted, "external helper environment reports unmounted path from mount table")
        checks.expect(externalStatus.metricsReachable, "external helper environment reports metrics reachability")
        checks.expect(externalLogs.count <= 16, "external helper environment returns bounded logs")
    }

    private static func checkLoginAutoMount(_ checks: inout CheckSuite) async throws {
        var disabled = try MountProfile.example()
        disabled.autoMount = .disabled
        let disabledClient = MockPrivilegedHelperClient()
        let disabledReport = await LoginAutoMountCoordinator(helper: disabledClient).run(activeProfile: disabled)
        checks.expect(disabledReport.outcome == .skippedDisabled, "auto-mount skips disabled profile")
        checks.expect(disabledClient.recordedOperations.isEmpty, "auto-mount disabled does not contact helper")

        let unmountedClient = MockPrivilegedHelperClient()
        unmountedClient.statusResult = HelperStatus(
            registration: .enabled,
            service: .running,
            mount: .unmounted,
            metricsReachable: true,
            lastError: nil
        )
        let mountedReport = await LoginAutoMountCoordinator(helper: unmountedClient).run(activeProfile: try MountProfile.example())
        checks.expect(mountedReport.outcome == .mounted, "auto-mount mounts service running but unmounted profile")
        checks.expect(unmountedClient.recordedOperations == [.status, .mount], "auto-mount checks status before mount")

        let stoppedClient = MockPrivilegedHelperClient()
        stoppedClient.statusResult = HelperStatus(
            registration: .enabled,
            service: .stopped,
            mount: .unmounted,
            metricsReachable: false,
            lastError: nil
        )
        let startedReport = await LoginAutoMountCoordinator(helper: stoppedClient).run(activeProfile: try MountProfile.example())
        checks.expect(startedReport.outcome == .mounted, "auto-mount starts stopped service before mounting")
        checks.expect(stoppedClient.recordedOperations == [.status, .start, .mount], "auto-mount starts then mounts")

        let unavailableClient = MockPrivilegedHelperClient()
        unavailableClient.statusResultOverride = .failure(.unavailable)
        let unavailableReport = await LoginAutoMountCoordinator(helper: unavailableClient).run(activeProfile: try MountProfile.example())
        checks.expect(unavailableReport.outcome.isFailure, "auto-mount reports helper unavailable failure")
        checks.expect(unavailableReport.failure?.operation == .status, "auto-mount helper unavailable failure names status operation")

        let failingMountClient = MockPrivilegedHelperClient()
        failingMountClient.statusResult = HelperStatus(
            registration: .enabled,
            service: .running,
            mount: .unmounted,
            metricsReachable: false,
            lastError: nil
        )
        failingMountClient.mountResult = .failure(.operationFailed(operation: .mount, message: "NFS mount failed", logExcerpt: "mount_nfs timeout"))
        failingMountClient.logsResult = "mount_nfs timeout\nfull log"
        let failingReport = await LoginAutoMountCoordinator(helper: failingMountClient).run(activeProfile: try MountProfile.example())
        checks.expect(failingReport.outcome.isFailure, "auto-mount reports mount failure")
        checks.expect(failingReport.failure?.message.contains("NFS mount failed") == true, "auto-mount failure keeps human-readable message")
        checks.expect(failingReport.failure?.logExcerpt?.contains("mount_nfs timeout") == true, "auto-mount failure includes bounded log excerpt")
    }

    private static func checkPerformance(_ checks: inout CheckSuite) async throws {
        let missingMountRoot = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let missingWork = missingMountRoot.appendingPathComponent("work")
        try FileManager.default.createDirectory(at: missingWork, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: missingMountRoot) }
        let missingMountRunner = PerformanceTestRunner(
            fileManager: .default,
            helper: MockPerformanceHelper(),
            metrics: StaticMetricsProvider(metrics: ""),
            diskUsage: StaticDiskUsageProvider(),
            byteGenerator: RepeatingByteGenerator(byte: 0x2A),
            settleAfterCleanupNanoseconds: 0
        )
        do {
            _ = try await missingMountRunner.run(
                profileID: try ProfileID("example-profile"),
                mountDirectory: missingMountRoot.appendingPathComponent("not-mounted"),
                workDirectory: missingWork,
                sizeBytes: 4096
            )
            checks.expect(false, "performance runner rejects missing mount directory")
        } catch PerformanceTestError.mountNotAvailable {
            checks.expect(true, "performance runner rejects missing mount directory")
        }

        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let mount = tempRoot.appendingPathComponent("mount")
        let work = tempRoot.appendingPathComponent("work")
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let runner = PerformanceTestRunner(
            fileManager: .default,
            helper: MockPerformanceHelper(),
            metrics: StaticMetricsProvider(metrics: "zerofs_used_bytes 0\n"),
            diskUsage: StaticDiskUsageProvider(),
            byteGenerator: RepeatingByteGenerator(byte: 0x2A),
            settleAfterCleanupNanoseconds: 0
        )
        let report = try await runner.run(
            profileID: try ProfileID("example-profile"),
            mountDirectory: mount,
            workDirectory: work,
            sizeBytes: 4096
        )

        checks.expect(report.checksumStatus == .pass, "performance checksum passes")
        checks.expect(report.remoteCleanup == .removed, "performance remote temp file is removed")
        checks.expect(report.readbackCleanup == .removed, "performance readback temp file is removed")
        checks.expect(report.dfBeforeWrite.phase == .beforeWrite, "performance captures df before write")
        checks.expect(report.dfAfterWrite.phase == .afterWrite, "performance captures df after write")
        checks.expect(report.dfAfterCleanup.phase == .afterCleanup, "performance captures df after cleanup")
        checks.expect(report.metricsAfterCleanup.contains("zerofs_used_bytes"), "performance captures metrics after cleanup")
        checks.expect(report.capacityNote.contains("configured ZeroFS quota"), "performance report explains quota semantics")

        let failureRoot = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let failureMount = failureRoot.appendingPathComponent("mount")
        let failureWork = failureRoot.appendingPathComponent("work")
        try FileManager.default.createDirectory(at: failureMount, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: failureWork, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: failureRoot) }

        let failingRunner = PerformanceTestRunner(
            fileManager: .default,
            helper: MockPerformanceHelper(flushResult: .failure(HelperClientError.operationFailed(operation: .flush, message: "flush failed", logExcerpt: nil))),
            metrics: StaticMetricsProvider(metrics: ""),
            diskUsage: StaticDiskUsageProvider(),
            byteGenerator: RepeatingByteGenerator(byte: 0x2A),
            settleAfterCleanupNanoseconds: 0
        )
        do {
            _ = try await failingRunner.run(
                profileID: try ProfileID("example-profile"),
                mountDirectory: failureMount,
                workDirectory: failureWork,
                sizeBytes: 4096
            )
            checks.expect(false, "performance flush failure throws")
        } catch {
            let leftovers = try FileManager.default.contentsOfDirectory(atPath: failureMount.path)
            checks.expect(leftovers.isEmpty, "performance cleanup runs after flush failure")
        }
    }

    private static func checkReliabilityProbes(_ checks: inout CheckSuite) async throws {
        let profileID = try ProfileID("example-profile")
        let defaults = ProbeSettings()
        checks.expect(!defaults.enabled, "reliability probes default to disabled")
        checks.expect(defaults.intervalSeconds == 3_600, "reliability probe default interval is 60 minutes")
        checks.expect(defaults.sizeBytes == 4 * 1_048_576, "reliability probe default size is 4 MiB")
        checks.expect(defaults.manualSizeBytes == 4 * 1_048_576, "manual reliability probe default size is 4 MiB")
        checks.expect(defaults.lastScheduledProbeAt == nil, "reliability probe scheduled timestamp defaults empty")
        checks.expect(defaults.lastManualProbeAt == nil, "reliability probe manual timestamp defaults empty")
        checks.expect(ProbeDefaults.scheduledMaxSizeBytes == 16 * 1_048_576, "scheduled probe max size is 16 MiB")
        checks.expect(ProbeDefaults.manualMaxSizeBytesWithoutConfirmation == 64 * 1_048_576, "manual probe max without confirmation is 64 MiB")
        checks.expect(ProbeDefaults.confirmedManualMaxSizeBytes == 512 * 1_048_576, "confirmed manual probe max is 512 MiB")
        checks.expect(
            ProbeSizePolicy.resolvedScheduledSize(requestedBytes: 512 * 1_048_576) == ProbeDefaults.scheduledMaxSizeBytes,
            "probe size policy caps scheduled probes at 16 MiB"
        )
        checks.expect(
            ProbeSizePolicy.resolvedManualSize(requestedBytes: 512 * 1_048_576, confirmedLarge: false) == ProbeDefaults.manualMaxSizeBytesWithoutConfirmation,
            "probe size policy caps unconfirmed manual probes at 64 MiB"
        )
        checks.expect(
            ProbeSizePolicy.resolvedManualSize(requestedBytes: 512 * 1_048_576, confirmedLarge: true) == ProbeDefaults.confirmedManualMaxSizeBytes,
            "probe size policy allows confirmed 512 MiB manual probes"
        )

        checks.expect(
            ReliabilityClassifier.classification(settings: ProbeSettings(enabled: false), latestResult: nil) == .disabled,
            "disabled reliability probes classify as gray"
        )
        checks.expect(
            ReliabilityClassifier.classification(settings: ProbeSettings(enabled: true), latestResult: nil) == .unknown,
            "enabled reliability probes without data classify as gray"
        )

        let now = Date()
        let healthy = ProbeResult(
            profileID: profileID,
            trigger: .manual,
            outcome: .success,
            startedAt: now,
            endedAt: now.addingTimeInterval(0.2),
            sizeBytes: 1_048_576,
            writeSeconds: 0.1,
            readSeconds: 0.1,
            checksumStatus: .pass,
            remoteCleanup: .removed,
            readbackCleanup: .removed,
            dfBeforeWrite: nil,
            dfAfterWrite: nil,
            dfAfterCleanup: nil,
            metricsSummary: "zerofs_used_bytes 0",
            failureReason: nil
        )
        checks.expect(
            ReliabilityClassifier.classification(settings: ProbeSettings(enabled: true), latestResult: healthy) == .healthy,
            "successful checksum-clean probe classifies green"
        )

        var failed = healthy
        failed.outcome = .failed
        failed.failureReason = "Mount directory is not available"
        checks.expect(
            ReliabilityClassifier.classification(settings: ProbeSettings(enabled: true), latestResult: failed) == .failed,
            "failed reliability probes classify red"
        )

        var degraded = healthy
        degraded.writeSeconds = 80
        checks.expect(
            ReliabilityClassifier.classification(settings: ProbeSettings(enabled: true), latestResult: degraded) == .degraded,
            "very slow reliability probes classify yellow"
        )

        var historyLatest = healthy
        historyLatest.id = UUID()
        historyLatest.startedAt = now.addingTimeInterval(100)
        historyLatest.endedAt = historyLatest.startedAt.addingTimeInterval(0.55)
        historyLatest.sizeBytes = 10 * 1_048_576
        historyLatest.writeSeconds = 0.25
        historyLatest.readSeconds = 0.20
        let historyBaseline = (0..<10).map { offset in
            var sample = healthy
            sample.id = UUID()
            sample.startedAt = now.addingTimeInterval(Double(offset))
            sample.endedAt = sample.startedAt.addingTimeInterval(0.3)
            sample.sizeBytes = 10 * 1_048_576
            sample.writeSeconds = 0.10
            sample.readSeconds = 0.10
            return sample
        }
        checks.expect(
            ReliabilityClassifier.classification(
                settings: ProbeSettings(enabled: true),
                latestResult: historyLatest,
                history: [historyLatest] + historyBaseline
            ) == .degraded,
            "history-aware reliability classification flags a recent throughput drop"
        )

        let storeRoot = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: storeRoot) }
        let settingsStore = FileProbeSettingsStore(fileURL: storeRoot.appendingPathComponent("probe-settings.json"))
        let scheduledAt = now.addingTimeInterval(-900)
        let manualAt = now.addingTimeInterval(-120)
        try settingsStore.save([
            profileID: ProbeSettings(
                enabled: true,
                intervalSeconds: 900,
                sizeBytes: 1_048_576,
                manualSizeBytes: 512 * 1_048_576,
                backgroundLaunchDaemonEnabled: false,
                lastScheduledProbeAt: scheduledAt,
                lastManualProbeAt: manualAt
            )
        ])
        let loadedSettings = try settingsStore.load()
        checks.expect(loadedSettings[profileID]?.intervalSeconds == 900, "probe settings are stored outside profiles.json")
        checks.expect(loadedSettings[profileID]?.manualSizeBytes == 512 * 1_048_576, "probe settings persist manual probe size")
        checks.expect(loadedSettings[profileID]?.lastScheduledProbeAt == scheduledAt, "probe settings persist last scheduled probe timestamp")
        checks.expect(loadedSettings[profileID]?.lastManualProbeAt == manualAt, "probe settings persist last manual probe timestamp")

        let retention = ProbeResultRetention(maxRecordsPerProfile: 3, maxAgeSeconds: 60 * 60 * 24 * 30)
        let resultStore = FileProbeResultStore(directoryURL: storeRoot.appendingPathComponent("ProbeResults"), retention: retention)
        var old = healthy
        old.startedAt = now.addingTimeInterval(-60 * 60 * 24 * 31)
        old.endedAt = old.startedAt.addingTimeInterval(0.2)
        var first = healthy
        first.id = UUID()
        first.startedAt = now.addingTimeInterval(-3)
        var second = healthy
        second.id = UUID()
        second.startedAt = now.addingTimeInterval(-2)
        var third = healthy
        third.id = UUID()
        third.startedAt = now.addingTimeInterval(-1)
        var fourth = healthy
        fourth.id = UUID()
        fourth.startedAt = now
        for result in [old, first, second, third, fourth] {
            try resultStore.append(result)
        }
        let retained = try resultStore.load(profileID: profileID)
        checks.expect(retained.count == 3, "probe result store prunes by age and count")
        checks.expect(!retained.contains(where: { $0.startedAt == old.startedAt }), "probe result store drops expired records")
        let fixtureAccessKey = "AKPROBESECRETSTRING0000"
        let fixtureSecretKey = "probe-secret-fixture-with-entropy-1234567890"
        let fixtureShortPassword = "p@55"
        var secretBearing = healthy
        secretBearing.id = UUID()
        secretBearing.metricsSummary = "AWS_ACCESS_KEY_ID=\(fixtureAccessKey) ZEROFS_PASSWORD=\(fixtureShortPassword)"
        secretBearing.failureReason = "flush output leaked \(fixtureSecretKey) and \(fixtureShortPassword)"
        try resultStore.append(secretBearing, redactingSecrets: [fixtureAccessKey, fixtureSecretKey, fixtureShortPassword])
        let serializedResults = try String(contentsOf: resultStore.fileURL(for: profileID), encoding: .utf8)
        checks.expect(!serializedResults.contains(fixtureAccessKey), "probe result history does not contain access keys")
        checks.expect(!serializedResults.contains(fixtureSecretKey), "probe result history does not contain secret keys")
        checks.expect(!serializedResults.contains(fixtureShortPassword), "probe result history redacts profile-provided short passwords")

        let backgroundStore = FileProbeResultStore(
            directoryURL: storeRoot
                .appendingPathComponent("ProbeResults", isDirectory: true)
                .appendingPathComponent(profileID.rawValue, isDirectory: true)
        )
        try backgroundStore.append(healthy)
        checks.expect(
            FileManager.default.fileExists(atPath: backgroundStore.fileURL(for: profileID).path),
            "background probe result store writes nested per-profile result files"
        )

        let lockDirectory = storeRoot.appendingPathComponent("probe.lock", isDirectory: true)
        let lock = ProbeRunLock(lockDirectory: lockDirectory, staleAfterSeconds: 60)
        let firstLock = try lock.acquire(processIdentifier: ProcessInfo.processInfo.processIdentifier)
        checks.expect(firstLock != nil, "probe run lock can be acquired")
        checks.expect(try lock.acquire(processIdentifier: ProcessInfo.processInfo.processIdentifier) == nil, "probe run lock blocks concurrent acquisition")
        firstLock?.release()
        let secondLock = try lock.acquire(processIdentifier: ProcessInfo.processInfo.processIdentifier)
        checks.expect(secondLock != nil, "probe run lock releases cleanly")
        secondLock?.release()
        try? FileManager.default.removeItem(at: lockDirectory)
        try FileManager.default.createDirectory(at: lockDirectory, withIntermediateDirectories: true)
        let staleMetadata = #"{"pid":-1,"startedAt":"2000-01-01T00:00:00Z"}"#
        try staleMetadata.write(to: lockDirectory.appendingPathComponent("owner.json"), atomically: true, encoding: .utf8)
        let staleRecoveredLock = try lock.acquire(processIdentifier: ProcessInfo.processInfo.processIdentifier)
        checks.expect(staleRecoveredLock != nil, "probe run lock recovers stale lock directories")
        staleRecoveredLock?.release()

        let runnerRoot = storeRoot.appendingPathComponent("runner")
        let mount = runnerRoot.appendingPathComponent("mount", isDirectory: true)
        let work = runnerRoot.appendingPathComponent("work", isDirectory: true)
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        let mountedOutput = "127.0.0.1:/ on \(mount.path) (nfs, asynchronous, mounted by root)"
        let probeRunner = ReliabilityProbeRunner(
            fileManager: .default,
            helper: MockPerformanceHelper(),
            metrics: StaticMetricsProvider(metrics: "zerofs_used_bytes 0\n"),
            diskUsage: StaticDiskUsageProvider(),
            byteGenerator: RepeatingByteGenerator(byte: 0x2A),
            mountTable: StaticMountTableProvider(mountOutput: mountedOutput),
            settleAfterCleanupNanoseconds: 0
        )
        let probeResult = await probeRunner.run(
            profileID: profileID,
            mountDirectory: mount,
            workDirectory: work,
            sizeBytes: 4_096,
            trigger: .manual
        )
        checks.expect(probeResult.outcome != .failed, "reliability probe completes on a mounted local NFS path")
        checks.expect(probeResult.checksumStatus == .pass, "reliability probe verifies readback checksum")
        checks.expect(probeResult.remoteCleanup == .removed, "reliability probe removes remote hidden temp file")
        checks.expect(probeResult.readbackCleanup == .removed, "reliability probe removes local readback temp file")
        let hiddenProbeRoot = mount.appendingPathComponent(".zerofs-manager-probes", isDirectory: true)
        let hiddenLeftovers = (try? FileManager.default.contentsOfDirectory(atPath: hiddenProbeRoot.path)) ?? []
        checks.expect(hiddenLeftovers.isEmpty, "reliability probe cleanup removes hidden probe files")

        let unmountedRunner = ReliabilityProbeRunner(
            fileManager: .default,
            helper: MockPerformanceHelper(),
            metrics: StaticMetricsProvider(metrics: ""),
            diskUsage: StaticDiskUsageProvider(),
            byteGenerator: RepeatingByteGenerator(byte: 0x2A),
            mountTable: StaticMountTableProvider(mountOutput: ""),
            settleAfterCleanupNanoseconds: 0
        )
        let unmountedResult = await unmountedRunner.run(
            profileID: profileID,
            mountDirectory: mount,
            workDirectory: work,
            sizeBytes: 4_096,
            trigger: .manual
        )
        checks.expect(unmountedResult.outcome == .failed, "manual reliability probe records unmounted paths as failures")
        checks.expect(unmountedResult.failureReason?.contains("mounted") == true, "unmounted probe failure gives a concise reason")
    }

    private static func checkPackaging(_ checks: inout CheckSuite) throws {
        let layout = AppBundleLayout()
        checks.expect(layout.appBundleName == "ZeroFS Manager.app", "packaging layout uses app bundle name")
        checks.expect(layout.executablePath == "Contents/MacOS/ZeroFSManagerApp", "packaging layout points to app executable")
        checks.expect(layout.helperExecutablePath == "Contents/MacOS/ZeroFSPrivilegedHelper", "packaging layout points to helper executable")
        checks.expect(!layout.embedsZeroFSBinary, "packaging layout does not embed zerofs binary")
        checks.expect(layout.externalDependencyName == "zerofs", "packaging layout declares external zerofs dependency")
        checks.expect(layout.launchDaemonPlistPath == "Contents/Library/LaunchDaemons/com.zerofs.manager.helper.plist", "packaging layout includes launch daemon plist")
        checks.expect(!DistributionMode.githubDev.requiresNotarization, "GitHub-style dev distribution does not require notarization")
        checks.expect(DistributionMode.officialRelease.requiresNotarization, "official release distribution requires notarization")

        let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let appInfoPlistURL = projectRoot.appendingPathComponent("Resources/App/Info.plist")
        let appInfoPlistData = try Data(contentsOf: appInfoPlistURL)
        let appInfoPlist = try PropertyListSerialization.propertyList(from: appInfoPlistData, format: nil) as? [String: Any]
        checks.expect(appInfoPlist?["CFBundleIconFile"] as? String == "ZeroFSManager", "app Info.plist declares ZeroFSManager icon")
        checks.expect(appInfoPlist?["CFBundleShortVersionString"] as? String == "0.1.2", "app Info.plist version matches current dev package")
        checks.expect(appInfoPlist?["CFBundleVersion"] as? String == "3", "app Info.plist build number is bumped")
        checks.expect(
            FileManager.default.fileExists(atPath: projectRoot.appendingPathComponent("Resources/App/ZeroFSManager.icns").path),
            "app icon resource exists"
        )
        checks.expect(
            FileManager.default.fileExists(atPath: projectRoot.appendingPathComponent("Resources/DMG/background.png").path),
            "DMG background resource exists"
        )
        let buildAppScript = try String(contentsOf: projectRoot.appendingPathComponent("Scripts/build-app.sh"), encoding: .utf8)
        let verifyLocalScript = try String(contentsOf: projectRoot.appendingPathComponent("Scripts/verify-local.sh"), encoding: .utf8)
        checks.expect(buildAppScript.contains("codesign --force --deep --sign -"), "local app build ad-hoc signs the complete bundle")
        checks.expect(buildAppScript.contains("Contents/Resources/Scripts"), "app bundle includes dev helper scripts as resources")
        checks.expect(buildAppScript.contains("ZeroFSProbeTool"), "app bundle includes the background probe executable")
        checks.expect(buildAppScript.contains("manual-install-profile-launchdaemon.sh"), "app bundle includes sudo profile launchd installer")
        checks.expect(buildAppScript.contains("manual-uninstall-profile-launchdaemon.sh"), "app bundle includes sudo profile launchd uninstaller")
        checks.expect(buildAppScript.contains("Contents/Resources/LICENSE.txt"), "app bundle includes Apache license text")
        checks.expect(verifyLocalScript.contains("DEVELOPER_DIR"), "local verification can select a full Xcode developer directory")
        checks.expect(verifyLocalScript.contains("swift test --enable-xctest"), "local verification forces XCTest execution instead of build-only SwiftPM tests")
        let ciWorkflow = try String(contentsOf: projectRoot.appendingPathComponent(".github/workflows/ci.yml"), encoding: .utf8)
        checks.expect(ciWorkflow.contains("swift test --enable-xctest"), "CI forces XCTest execution")
        let packageSource = try String(contentsOf: projectRoot.appendingPathComponent("Package.swift"), encoding: .utf8)
        checks.expect(packageSource.contains(".executable(name: \"ZeroFSProbeTool\""), "Swift package exposes ZeroFSProbeTool executable product")
        checks.expect(packageSource.contains("name: \"ZeroFSProbeTool\""), "Swift package builds ZeroFSProbeTool target")
        checks.expect(packageSource.contains(".executable(name: \"ZeroFSProbeTests\""), "Swift package exposes probe regression test executable")
        checks.expect(packageSource.contains(".testTarget(\n            name: \"ZeroFSProbeXCTests\""), "Swift package includes an XCTest target for probe behavior")
        checks.expect(packageSource.contains("ZeroFSProbeToolCore"), "Swift package extracts probe tool behavior into a testable core library")
        let probeToolSource = try String(contentsOf: projectRoot.appendingPathComponent("Sources/ZeroFSProbeTool/main.swift"), encoding: .utf8)
        let probeToolCoreSource = try String(contentsOf: projectRoot.appendingPathComponent("Sources/ZeroFSProbeToolCore/ProbeToolCore.swift"), encoding: .utf8)
        checks.expect(probeToolSource.contains("ProbeToolSupport.exitCode"), "ZeroFSProbeTool computes exit status after lock cleanup")
        checks.expect(probeToolSource.contains("ProbeToolSupport.redactionSecrets"), "ZeroFSProbeTool redacts secrets from the root runtime environment")
        checks.expect(probeToolCoreSource.contains("resultJSON"), "ZeroFSProbeToolCore exposes sanitized JSON generation for tests")
        checks.expect(probeToolCoreSource.contains("case .failed:\n            return 1"), "ZeroFSProbeToolCore maps failed probes to exit code 1")
        checks.expect(probeToolCoreSource.contains("case .skipped:\n            return 75"), "ZeroFSProbeToolCore maps skipped probes to temporary failure exit code 75")
        checks.expect(probeToolCoreSource.contains("--skip-reason"), "ZeroFSProbeTool can persist skipped background probe results")
        checks.expect(!probeToolSource.contains("case .failed:\n                terminate(1)"), "ZeroFSProbeTool does not exit directly while holding a probe lock")
        checks.expect(!probeToolSource.contains("case .skipped:\n                terminate(75)"), "ZeroFSProbeTool does not exit directly while holding a probe lock after skipped runs")
        let reliabilityProbeSource = try String(contentsOf: projectRoot.appendingPathComponent("Sources/ZeroFSPerformance/ReliabilityProbes.swift"), encoding: .utf8)
        checks.expect(reliabilityProbeSource.contains("describeError(error)"), "reliability probe failures preserve actionable command output")
        checks.expect(reliabilityProbeSource.contains("Darwin.lockf"), "probe locks use kernel file locks that release after process crashes")
        checks.expect(reliabilityProbeSource.contains("ProbeRunLockRegistry"), "probe locks also block duplicate in-process acquisition")
        checks.expect(reliabilityProbeSource.contains("ProbeCleanupDiagnostics"), "probe diagnostics expose cleanup as structured data for UI localization")
        let rootViewSource = try String(contentsOf: projectRoot.appendingPathComponent("Sources/ZeroFSManagerUI/ZeroFSManagerRootView.swift"), encoding: .utf8)
        checks.expect(rootViewSource.contains("--env /path/to/.env.local --delete-env-on-exit"), "copy CLI command uses a safe env template instead of writing secrets")
        checks.expect(rootViewSource.contains("LocalPerformanceHelper"), "GitHub-style dev performance tests can run against an existing local mount without helper registration")
        checks.expect(rootViewSource.contains("ReliabilityProbeSection"), "UI includes reliability probe controls")
        checks.expect(rootViewSource.contains("ProbeReliabilityIcon"), "mount list shows reliability health icons")
        checks.expect(rootViewSource.contains("requestReliabilityProbe"), "UI can trigger manual reliability probes through confirmation flow")
        checks.expect(rootViewSource.contains("probeConfirmation"), "UI confirms large manual reliability probes")
        checks.expect(rootViewSource.contains("ProbeResultDetailGrid"), "UI shows richer reliability probe result details")
        checks.expect(rootViewSource.contains("language.probeCleanupSummary"), "UI localizes reliability probe cleanup status values")
        checks.expect(!rootViewSource.contains("result.diagnostics.cleanupSummary"), "UI does not display English-only cleanup summaries")
        checks.expect(rootViewSource.contains("ProbeHistoryDisplay.classification"), "probe history rows use display-specific classification")
        checks.expect(!rootViewSource.contains("history: model.probeResults(for: profile.id)"), "probe history row classification does not use future/full history")
        checks.expect(rootViewSource.contains("setProbeManualSize"), "UI separates manual reliability probe size from scheduled size")
        checks.expect(rootViewSource.contains("lastScheduledProbeAt"), "app scheduler uses explicit last scheduled probe timestamp")
        checks.expect(rootViewSource.contains("lastManualProbeAt"), "app records explicit last manual probe timestamp")
        checks.expect(rootViewSource.contains("startProbeScheduler"), "app-open scheduler starts enabled reliability probes")
        checks.expect(rootViewSource.contains("refreshBackgroundProbeResults"), "UI reads sanitized background probe results")
        checks.expect(rootViewSource.contains("backgroundProbeResultStore.directoryURL.appendingPathComponent(profileID.rawValue"), "UI reads nested per-profile background probe results")
        checks.expect(rootViewSource.contains("guard applyLocalMountState(for: profile.id) else { continue }"), "app-open scheduler skips unavailable mounts")
        checks.expect(rootViewSource.contains("ProbeRunLock(lockDirectory: Self.sharedProbeLockDirectory"), "UI probes share the background probe lock")
        checks.expect(rootViewSource.contains("(1...65_535).contains(profile.metricsPort)"), "reliability probe avoids invalid metrics URL crashes")
        checks.expect(rootViewSource.contains("ZEROFS_PROBE_TOOL"), "sudo env flow stages the bundled probe tool")
        checks.expect(rootViewSource.contains("installOrUpdateLaunchDaemon"), "GitHub-style dev UI can install or update sudo LaunchDaemons")
        checks.expect(rootViewSource.contains("uninstallLaunchDaemon"), "GitHub-style dev UI can remove sudo LaunchDaemons")
        checks.expect(rootViewSource.contains("PrivilegedMountPathPolicy"), "GitHub-style dev sudo LaunchDaemon path enforces privileged mount path policy")
        checks.expect(rootViewSource.contains("writeLaunchDaemonEnv"), "GitHub-style dev UI writes profile launchd env outside the repo")
        checks.expect(rootViewSource.contains("manual-install-profile-launchdaemon.sh"), "GitHub-style dev UI calls the sudo profile launchd installer")
        checks.expect(rootViewSource.contains("ZEROFS_MANAGER_SCRIPT_DIR"), "local dev script lookup uses an explicit environment override")
        checks.expect(!rootViewSource.contains("/Users/"), "app runtime does not hardcode developer machine script paths")
        checks.expect(rootViewSource.contains("EditableMountProfile.empty()"), "first launch starts from an empty profile template")
        let forbiddenBucket = "user-" + "123456789"
        checks.expect(!rootViewSource.contains(forbiddenBucket), "first launch does not seed a personal object-store profile")
        checks.expect(rootViewSource.contains("MountFailureRecovery.classify"), "mount failure dialogs classify recovery actions by failure type")
        checks.expect(rootViewSource.contains("case .credentials"), "missing credential failures avoid helper approval guidance")
        checks.expect(rootViewSource.contains("@AppStorage(AppLanguage.storageKey)"), "app persists selected UI language")
        checks.expect(rootViewSource.contains("LanguageMenu(selection:"), "app exposes an in-window language switcher")
        let localizationSource = try String(contentsOf: projectRoot.appendingPathComponent("Sources/ZeroFSManagerUI/AppLocalization.swift"), encoding: .utf8)
        checks.expect(localizationSource.contains("probeCleanupSummary"), "localization formats reliability probe cleanup summaries")
        for languageCase in ["english", "simplifiedChinese", "traditionalChinese", "japanese", "korean"] {
            checks.expect(localizationSource.contains("case \(languageCase)"), "localization supports \(languageCase)")
        }
        for marker in ["简体中文", "繁體中文", "日本語", "한국어"] {
            checks.expect(localizationSource.contains(marker), "localization includes \(marker) display name")
        }
        checks.expect(localizationSource.contains("GitHub-style development build"), "localization keeps English GitHub distribution copy")
        checks.expect(localizationSource.contains("Apply & Restart LaunchDaemon"), "localization includes English sudo launchd copy")
        checks.expect(localizationSource.contains("GitHub 风格开发版"), "localization includes Simplified Chinese GitHub distribution copy")
        checks.expect(localizationSource.contains("应用并重启 LaunchDaemon"), "localization includes Simplified Chinese sudo launchd copy")
        checks.expect(localizationSource.contains("GitHub 風格開發版"), "localization includes Traditional Chinese GitHub distribution copy")
        checks.expect(localizationSource.contains("套用並重啟 LaunchDaemon"), "localization includes Traditional Chinese sudo launchd copy")
        checks.expect(localizationSource.contains("GitHub 形式の開発ビルド"), "localization includes Japanese GitHub distribution copy")
        checks.expect(localizationSource.contains("適用して LaunchDaemon を再起動"), "localization includes Japanese sudo launchd copy")
        checks.expect(localizationSource.contains("GitHub 스타일 개발 빌드"), "localization includes Korean GitHub distribution copy")
        checks.expect(localizationSource.contains("적용 후 LaunchDaemon 재시작"), "localization includes Korean sudo launchd copy")
        checks.expect(localizationSource.contains("Reliability Probe"), "localization includes English reliability probe copy")
        checks.expect(localizationSource.contains("Run Large Probe?"), "localization includes English large probe confirmation copy")
        checks.expect(localizationSource.contains("Scheduled Size"), "localization includes English scheduled probe size copy")
        checks.expect(localizationSource.contains("Manual Size"), "localization includes English manual probe size copy")
        checks.expect(localizationSource.contains("可靠性检测"), "localization includes Simplified Chinese reliability probe copy")
        checks.expect(localizationSource.contains("运行大尺寸检测？"), "localization includes Simplified Chinese large probe confirmation copy")
        checks.expect(localizationSource.contains("可靠性檢測"), "localization includes Traditional Chinese reliability probe copy")
        checks.expect(localizationSource.contains("執行大尺寸檢測？"), "localization includes Traditional Chinese large probe confirmation copy")
        checks.expect(localizationSource.contains("信頼性プローブ"), "localization includes Japanese reliability probe copy")
        checks.expect(localizationSource.contains("大きいプローブを実行しますか？"), "localization includes Japanese large probe confirmation copy")
        checks.expect(localizationSource.contains("안정성 검사"), "localization includes Korean reliability probe copy")
        checks.expect(localizationSource.contains("큰 검사 실행?"), "localization includes Korean large probe confirmation copy")
        let verifyBundleScript = try String(contentsOf: projectRoot.appendingPathComponent("Scripts/verify-bundle.sh"), encoding: .utf8)
        checks.expect(verifyBundleScript.contains("codesign --verify --deep --strict"), "bundle verification enforces strict codesign")
        let requiredDevScripts = [
            "sign-app-adhoc.sh",
            "inspect-signature.sh",
            "package-github-dev.sh",
            "manual-mount-test.sh",
            "manual-install-launchdaemon-debug.sh",
            "manual-uninstall-launchdaemon-debug.sh",
            "manual-install-profile-launchdaemon.sh",
            "manual-uninstall-profile-launchdaemon.sh",
            "sign-app-developer-id.sh",
            "notarize-dmg.sh",
            "verify-release.sh"
        ]
        for scriptName in requiredDevScripts {
            let scriptURL = projectRoot.appendingPathComponent("Scripts/\(scriptName)")
            checks.expect(FileManager.default.fileExists(atPath: scriptURL.path), "script exists: \(scriptName)")
        }
        let inspectSignatureScript = try String(contentsOf: projectRoot.appendingPathComponent("Scripts/inspect-signature.sh"), encoding: .utf8)
        checks.expect(inspectSignatureScript.contains("--help"), "signature inspector supports help without treating it as a path")
        checks.expect(inspectSignatureScript.contains("TeamIdentifier=not set"), "signature inspector explains missing TeamIdentifier")
        checks.expect(inspectSignatureScript.contains("spctl assessment failed as expected for github-dev"), "signature inspector treats spctl as nonblocking in github-dev")
        let manualMountScript = try String(contentsOf: projectRoot.appendingPathComponent("Scripts/manual-mount-test.sh"), encoding: .utf8)
        checks.expect(manualMountScript.contains("redact"), "manual mount script redacts secrets")
        checks.expect(manualMountScript.contains("--delete-env-on-exit"), "manual mount script can delete temporary env files")
        checks.expect(manualMountScript.contains("zerofs run --config"), "manual mount script starts zerofs directly")
        checks.expect(manualMountScript.contains("shasum -a 256"), "manual mount script verifies readback checksum")
        checks.expect(manualMountScript.contains("/sbin/umount"), "manual mount script unmounts after the smoke test")
        let manualPerformanceScript = try String(contentsOf: projectRoot.appendingPathComponent("Scripts/manual-performance-test.sh"), encoding: .utf8)
        checks.expect(manualPerformanceScript.contains("SIZE_BYTES_DEFAULT=$((128 * 1024 * 1024))"), "manual performance test defaults to 128M")
        checks.expect(manualPerformanceScript.contains("--confirm-large-test"), "manual performance test requires confirmation for large runs")
        checks.expect(manualPerformanceScript.contains("--allow-non-zerofs-mount"), "manual performance test protects against accidental non-ZeroFS mount points")
        checks.expect(manualPerformanceScript.contains("Invalid --size"), "manual performance test reports invalid sizes cleanly")
        checks.expect(manualPerformanceScript.contains("small files"), "manual performance test covers small file operations")
        let profileInstallScript = try String(contentsOf: projectRoot.appendingPathComponent("Scripts/manual-install-profile-launchdaemon.sh"), encoding: .utf8)
        checks.expect(profileInstallScript.contains("launchctl bootstrap system"), "profile launchd installer bootstraps system LaunchDaemons")
        checks.expect(profileInstallScript.contains("launchctl kickstart -k"), "profile launchd installer restarts the profile jobs after config changes")
        checks.expect(profileInstallScript.contains("ZEROFS_MOUNT_POINT"), "profile launchd installer stores the selected mount point in config")
        checks.expect(profileInstallScript.contains("Refusing unsafe ZEROFS_MOUNT_POINT"), "profile launchd installer rejects unsafe mount points")
        checks.expect(profileInstallScript.contains("^[a-z0-9][a-z0-9-]{0,62}$"), "profile launchd installer uses app-compatible profile ids")
        checks.expect(profileInstallScript.contains("install -o root -g wheel -m 0600"), "profile launchd installer stores secrets in root-only env file")
        checks.expect(profileInstallScript.contains("STAGED_ZEROFS_BIN"), "profile launchd installer stages zerofs into the root-owned runtime directory")
        checks.expect(profileInstallScript.contains("install -o root -g wheel -m 0755"), "profile launchd installer installs staged zerofs as a root-owned executable")
        checks.expect(profileInstallScript.contains("assert_root_owned_runtime_file"), "profile launchd installer verifies staged zerofs permissions")
        checks.expect(profileInstallScript.contains("is_trusted_root_env"), "profile launchd installer only sources trusted root-owned existing env files")
        checks.expect(profileInstallScript.contains("launchctl bootout \"system/$label\""), "profile launchd installer falls back to label-based bootout")
        checks.expect(profileInstallScript.contains("RunAtLoad"), "profile launchd installer enables startup behavior")
        checks.expect(profileInstallScript.contains("StartInterval"), "profile launchd mount job retries mount readiness")
        checks.expect(profileInstallScript.contains("ZEROFS_PROBE_ENABLED"), "profile launchd installer accepts probe enablement config")
        checks.expect(profileInstallScript.contains("ZEROFS_PROBE_INTERVAL_SECONDS"), "profile launchd installer accepts probe interval config")
        checks.expect(profileInstallScript.contains("ZEROFS_PROBE_SIZE_BYTES"), "profile launchd installer accepts probe size config")
        checks.expect(profileInstallScript.contains("ZEROFS_PROBE_TOOL"), "profile launchd installer stages the bundled probe tool")
        checks.expect(profileInstallScript.contains("PROBE_RESULT_ROOT"), "profile launchd installer writes sanitized probe results outside secret runtime")
        checks.expect(profileInstallScript.contains("PROBE_LOCK_ROOT"), "profile launchd installer uses a shared probe lock root")
        checks.expect(profileInstallScript.contains(".probe"), "profile launchd installer manages a probe LaunchDaemon")
        checks.expect(profileInstallScript.contains("probe-zerofs.sh"), "profile launchd installer generates a root-owned probe wrapper")
        checks.expect(profileInstallScript.contains("source $(shell_quote \"$ENV_PATH\")"), "probe wrapper sources root-only env before running ZeroFSProbeTool")
        checks.expect(profileInstallScript.contains("Skipping probe because mount is not ready"), "probe wrapper waits for mount readiness before writing")
        checks.expect(profileInstallScript.contains("--skip-reason"), "probe wrapper records sanitized skipped results when mount readiness times out")
        checks.expect(profileInstallScript.contains("chmod 1777 \"$PROBE_LOCK_ROOT\""), "probe lock root is shared between GUI and root daemon")
        let profileUninstallScript = try String(contentsOf: projectRoot.appendingPathComponent("Scripts/manual-uninstall-profile-launchdaemon.sh"), encoding: .utf8)
        checks.expect(profileUninstallScript.contains("launchctl bootout system"), "profile launchd uninstaller stops system LaunchDaemons")
        checks.expect(profileUninstallScript.contains("launchctl bootout \"system/$label\""), "profile launchd uninstaller falls back to label-based bootout")
        checks.expect(profileUninstallScript.contains("ensure_job_unloaded"), "profile launchd uninstaller verifies launchd jobs are gone")
        checks.expect(profileUninstallScript.contains("is_trusted_root_env"), "profile launchd uninstaller only sources trusted root-owned existing env files")
        checks.expect(profileUninstallScript.contains("is_safe_mount_point"), "profile launchd uninstaller validates mount points before unmounting")
        checks.expect(profileUninstallScript.contains("^[a-z0-9][a-z0-9-]{0,62}$"), "profile launchd uninstaller uses app-compatible profile ids")
        checks.expect(profileUninstallScript.contains("sudo rm -f \"$PROBE_PLIST\" \"$MOUNT_PLIST\" \"$RUNTIME_PLIST\""), "profile launchd uninstaller removes installed plists")
        checks.expect(profileUninstallScript.contains("PROBE_LOCK_ROOT"), "profile launchd uninstaller removes profile probe locks")
        checks.expect(profileUninstallScript.contains("--keep-runtime"), "profile launchd uninstaller can preserve runtime files for debugging")
        checks.expect(profileUninstallScript.contains("PROBE_LABEL"), "profile launchd uninstaller stops probe LaunchDaemon")
        checks.expect(profileUninstallScript.contains("PROBE_RESULT_ROOT"), "profile launchd uninstaller knows sanitized probe result storage")
        checks.expect(profileUninstallScript.contains("KEEP_RUNTIME"), "profile launchd uninstaller preserves probe results when requested")
        let githubDevPackageScript = try String(contentsOf: projectRoot.appendingPathComponent("Scripts/package-github-dev.sh"), encoding: .utf8)
        checks.expect(githubDevPackageScript.contains("--help"), "github-dev package script supports help without building")
        checks.expect(githubDevPackageScript.contains("VERIFY_CODESIGN=0"), "github-dev unsigned package mode bypasses strict bundle codesign only when requested")
        checks.expect(githubDevPackageScript.contains("GitHub-style development build"), "github-dev package README warns about dev distribution")
        checks.expect(githubDevPackageScript.contains("ZeroFS-Manager-dev-adhoc.dmg"), "github-dev package emits dev adhoc DMG")
        checks.expect(githubDevPackageScript.contains("LICENSE.txt"), "github-dev DMG includes Apache license text")
        checks.expect(githubDevPackageScript.contains("Do not run the app directly from this mounted DMG"), "github-dev DMG README tells users to install before launching")
        checks.expect(!githubDevPackageScript.contains("cp -R \"$PROJECT_ROOT/Scripts\""), "github-dev DMG does not expose the full development Scripts directory")
        let developmentDocs = try String(contentsOf: projectRoot.appendingPathComponent("docs/development.md"), encoding: .utf8)
        checks.expect(developmentDocs.contains("cd <repo-root>"), "development docs use a generic repo-root path")
        checks.expect(!developmentDocs.contains("/Users/"), "development docs do not leak a local machine path")
        let localDMGScript = try String(contentsOf: projectRoot.appendingPathComponent("Scripts/package-dmg.sh"), encoding: .utf8)
        checks.expect(localDMGScript.contains("LICENSE.txt"), "local DMG includes Apache license text")
        let debugInstallScript = try String(contentsOf: projectRoot.appendingPathComponent("Scripts/manual-install-launchdaemon-debug.sh"), encoding: .utf8)
        checks.expect(debugInstallScript.contains("com.zerofs.manager.helper.debug"), "debug launchd install uses debug-only label")
        checks.expect(debugInstallScript.contains("ZEROFS_MANAGER_HELPER_MACH_SERVICE_NAME"), "debug launchd install sets matching helper Mach service name")
        checks.expect(debugInstallScript.contains("manual launchd debug path"), "debug launchd install explains it is not official SMAppService")

        let profileTemplate = try String(
            contentsOf: projectRoot.appendingPathComponent("Resources/LaunchDaemons/zerofs-profile.plist.template"),
            encoding: .utf8
        )
        checks.expect(profileTemplate.contains("<string>{{ZEROFS_RUN_SCRIPT}}</string>"), "profile launchd template uses root-only run wrapper")
        checks.expect(!profileTemplate.contains("{{ZEROFS_BINARY}}"), "profile launchd template does not bypass env wrapper")

        let configTemplate = try String(
            contentsOf: projectRoot.appendingPathComponent("Resources/Templates/zerofs.toml.template"),
            encoding: .utf8
        )
        checks.expect(configTemplate.contains("[storage]"), "packaged ZeroFS config template uses storage section")
        checks.expect(configTemplate.contains("url = \"{{S3_URL}}\""), "packaged ZeroFS config template uses precomputed S3 URL")
        checks.expect(!configTemplate.contains("{{S3_BUCKET}}/{{S3_PREFIX}}"), "packaged ZeroFS config template does not force empty-prefix slash")
        checks.expect(configTemplate.contains("[servers.nfs]"), "packaged ZeroFS config template uses servers.nfs section")
        checks.expect(!configTemplate.contains("[s3]"), "packaged ZeroFS config template does not use obsolete s3 section")

        let envTemplate = try String(
            contentsOf: projectRoot.appendingPathComponent("Resources/Templates/zerofs.env.template"),
            encoding: .utf8
        )
        checks.expect(envTemplate.contains("ZEROFS_PASSWORD="), "packaged env template uses ZeroFS password variable")
        checks.expect(!envTemplate.contains("ZEROFS_ENCRYPTION_PASSWORD"), "packaged env template does not use obsolete password variable")
    }
}

private extension LoginAutoMountOutcome {
    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}

struct CheckSuite {
    private var failures: [String] = []

    mutating func expect(_ condition: Bool, _ message: String) {
        if condition {
            print("PASS: \(message)")
        } else {
            failures.append(message)
            print("FAIL: \(message)")
        }
    }

    func finish() -> Never {
        if failures.isEmpty {
            print("All checks passed")
            exit(0)
        }

        fputs("Failed checks:\n", stderr)
        for failure in failures {
            fputs("- \(failure)\n", stderr)
        }
        exit(1)
    }
}

extension MountProfile {
    static func example(
        id: ProfileID = try! ProfileID("example-profile"),
        displayName: String = "example-profile"
    ) throws -> MountProfile {
        MountProfile(
            id: id,
            displayName: displayName,
            endpoint: "https://s3.example.invalid",
            bucket: "example-bucket",
            prefix: "example-prefix",
            mountPath: MountPath(rawValue: "/Volumes/ZeroFS-Example"),
            quota: Quota(gigabytes: 1024),
            cache: CacheSettings(diskGigabytes: 10, memoryGigabytes: 0.5),
            ports: PortSet(nfs: 2049, rpc: 17000, metrics: 9091),
            autoMount: .afterLogin,
            performanceTestSize: .megabytes(1024)
        )
    }
}
