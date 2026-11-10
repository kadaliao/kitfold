import Foundation

#if os(macOS)
    import Security

    /// A release version like `0.4.0` (a tag's leading `v` is dropped). Compared number by number.
    public struct AppVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
        public let parts: [Int]
        public let text: String

        public init?(_ string: String) {
            var s = string.trimmingCharacters(in: .whitespaces)
            if s.hasPrefix("v") || s.hasPrefix("V") { s.removeFirst() }
            let numbers = s.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
            guard !numbers.isEmpty, numbers.allSatisfy({ $0 != nil && $0! >= 0 }) else { return nil }
            parts = numbers.map { $0! }
            text = s
        }

        public var description: String { text }

        public static func < (a: AppVersion, b: AppVersion) -> Bool {
            for i in 0..<max(a.parts.count, b.parts.count) {
                let x = i < a.parts.count ? a.parts[i] : 0, y = i < b.parts.count ? b.parts[i] : 0
                if x != y { return x < y }
            }
            return false
        }

        public static func == (a: AppVersion, b: AppVersion) -> Bool { !(a < b) && !(b < a) }
        /// `0.4` and `0.4.0` are the same version.
        public func hash(into h: inout Hasher) {
            var p = parts
            while p.count > 1 && p.last == 0 { p.removeLast() }
            h.combine(p)
        }
    }

    /// The newest published release, as GitHub describes it.
    public struct ReleaseInfo: Sendable, Hashable {
        public var version: AppVersion
        public var tag: String
        public var title: String
        /// Release notes (Markdown).
        public var notes: String
        public var pageURL: URL
        public var diskImageURL: URL
        public var checksumsURL: URL?
        public var publishedAt: Date?
    }

    public enum UpdateError: Error, LocalizedError, Equatable {
        case network(String)
        case badResponse
        case noDiskImage
        case checksumMismatch
        case notInstallable(String)
        case verification(String)
        case install(String)

        public var errorDescription: String? {
            switch self {
            case .network(let m): return L("Couldn't reach GitHub: \(m)")
            case .badResponse: return L("GitHub's answer about the latest release couldn't be read.")
            case .noDiskImage: return L("The latest release has no Kitfold disk image.")
            case .checksumMismatch: return L("The download doesn't match the release's SHA-256 checksum, so it wasn't installed.")
            case .notInstallable(let m), .verification(let m), .install(let m): return m
            }
        }
    }

    /// Finds out whether a newer Kitfold is out and installs it in place of a Kitfold.app: the disk image
    /// published with each GitHub release, checked against the release's SHA-256, signed by the same
    /// Developer ID team as the copy being replaced, and notarized by Apple. Nothing is replaced unless
    /// every check passes.
    public enum Updates {
        public static let repository = "kadaliao/kitfold"
        static var latestURL: URL { URL(string: "https://api.github.com/repos/\(repository)/releases/latest")! }
        public static var releasesPage: URL { URL(string: "https://github.com/\(repository)/releases/latest")! }

        // MARK: checking

        /// Reads GitHub's `releases/latest` answer (drafts and prereleases are never "latest").
        public static func parseLatest(_ data: Data) throws -> ReleaseInfo {
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let tag = json["tag_name"] as? String, let version = AppVersion(tag),
                let page = (json["html_url"] as? String).flatMap(URL.init(string:))
            else { throw UpdateError.badResponse }
            let assets = (json["assets"] as? [[String: Any]]) ?? []
            func asset(_ name: String) -> URL? {
                assets.first { ($0["name"] as? String) == name }.flatMap { ($0["browser_download_url"] as? String).flatMap(URL.init) }
            }
            guard let dmg = asset("Kitfold-\(version.text).dmg") else { throw UpdateError.noDiskImage }
            let date = (json["published_at"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
            return ReleaseInfo(
                version: version, tag: tag, title: (json["name"] as? String) ?? "Kitfold \(version)",
                notes: (json["body"] as? String) ?? "", pageURL: page, diskImageURL: dmg, checksumsURL: asset("SHA256SUMS"),
                publishedAt: date)
        }

        /// The newest release. Blocks while it asks GitHub; call it off the main thread.
        public static func latest(timeout: TimeInterval = 20) throws -> ReleaseInfo {
            var request = URLRequest(url: latestURL, timeoutInterval: timeout)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("Kitfold", forHTTPHeaderField: "User-Agent")
            let (data, response) = try fetch(request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError.badResponse }
            return try parseLatest(data)
        }

        /// `release` is newer than `current` (a development build, with no version, never updates).
        public static func isNewer(_ release: ReleaseInfo, than current: AppVersion?) -> Bool {
            guard let current else { return false }
            return release.version > current
        }

        // MARK: the copy being updated

        /// The version in a Kitfold.app's Info.plist.
        public static func version(ofApp app: URL) -> AppVersion? {
            guard let data = FileManager.default.contents(atPath: app.appendingPathComponent("Contents/Info.plist").path),
                let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                let v = plist["CFBundleShortVersionString"] as? String
            else { return nil }
            return AppVersion(v)
        }

        /// The Kitfold.app an executable sits in (the app itself, or the CLI in Contents/Resources),
        /// following links, so `~/.local/bin/kitfold` finds /Applications/Kitfold.app.
        public static func appBundle(containing executable: URL) -> URL? {
            // realpath, not resolvingSymlinksInPath (which turns /private/var into /var).
            var url = URL(fileURLWithPath: FS.realPath(executable.path) ?? executable.path)
            for _ in 0..<4 {
                url.deleteLastPathComponent()
                if url.pathExtension == "app" { return url }
            }
            return nil
        }

        /// The Developer ID team that signed an app, nil for an ad-hoc or unsigned build.
        public static func teamID(ofApp app: URL) -> String? {
            var code: SecStaticCode?
            guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code else { return nil }
            var info: CFDictionary?
            guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
                let dict = info as? [String: Any]
            else { return nil }
            return dict[kSecCodeInfoTeamIdentifier as String] as? String
        }

        /// Why `app` can't replace itself, or nil when it can.
        public static func whyNotInstallable(app: URL) -> String? {
            let path = app.path
            if path.contains("/AppTranslocation/") {
                return L("macOS is running Kitfold from a temporary location. Move it to Applications, open it from there, and try again.")
            }
            if path.hasPrefix("/Volumes/") {
                return L("Kitfold is running from a disk image. Copy it to Applications, open it from there, and try again.")
            }
            if teamID(ofApp: app) == nil {
                return L("This copy of Kitfold isn't a signed release (a development build), so it can't update itself.")
            }
            let parent = app.deletingLastPathComponent().path
            if !FileManager.default.isWritableFile(atPath: parent) || !FileManager.default.isWritableFile(atPath: path) {
                return L("Kitfold can't replace itself in \(parent): you don't have permission to change it there.")
            }
            return nil
        }

        // MARK: installing

        /// Download `release`, check it, and put it in place of `app`. `status` hears each step.
        /// Returns the installed app. On any failure the old app stays exactly as it was.
        @discardableResult
        public static func install(_ release: ReleaseInfo, replacing app: URL, status: (String) -> Void = { _ in }) throws -> URL {
            if let why = whyNotInstallable(app: app) { throw UpdateError.notInstallable(why) }
            guard let team = teamID(ofApp: app) else { throw UpdateError.notInstallable(L("This copy of Kitfold isn't signed.")) }
            let fm = FileManager.default
            let work = fm.temporaryDirectory.appendingPathComponent("kitfold-update-" + UUID().uuidString)
            try fm.createDirectory(at: work, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: work) }

            status(L("Downloading Kitfold \(release.version)…"))
            let dmg = work.appendingPathComponent(release.diskImageURL.lastPathComponent)
            try download(release.diskImageURL, to: dmg)
            if let sums = release.checksumsURL {
                let file = work.appendingPathComponent("SHA256SUMS")
                try download(sums, to: file)
                guard let expected = checksum(in: (try? String(contentsOf: file, encoding: .utf8)) ?? "", for: dmg.lastPathComponent),
                    let data = fm.contents(atPath: dmg.path), Hashing.sha256(data) == expected
                else { throw UpdateError.checksumMismatch }
            }

            status(L("Checking the new version…"))
            let mount = work.appendingPathComponent("mount")
            try fm.createDirectory(at: mount, withIntermediateDirectories: true)
            try run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path, dmg.path])
            // Copy the app next to the old one (same volume, so the swap is a rename), then let the image go.
            let staging = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: app, create: true)
            let staged = staging.appendingPathComponent(app.lastPathComponent)
            do {
                defer { _ = try? run("/usr/bin/hdiutil", ["detach", mount.path, "-force"]) }
                let source = mount.appendingPathComponent("Kitfold.app")
                guard fm.fileExists(atPath: source.path) else { throw UpdateError.verification(L("The disk image has no Kitfold.app.")) }
                try run("/usr/bin/ditto", [source.path, staged.path])
            } catch {
                try? fm.removeItem(at: staging)
                throw error
            }
            do {
                try verify(staged, version: release.version, team: team)
                status(L("Installing…"))
                _ = try fm.replaceItemAt(app, withItemAt: staged)
            } catch {
                try? fm.removeItem(at: staging)
                throw error
            }
            try? fm.removeItem(at: staging)
            return app
        }

        /// The copy about to be installed is the release it claims to be, from the same team, notarized.
        static func verify(_ app: URL, version: AppVersion, team: String) throws {
            guard Updates.version(ofApp: app) == version else {
                throw UpdateError.verification(L("The downloaded app isn't version \(version)."))
            }
            var code: SecStaticCode?
            var requirement: SecRequirement?
            let text = "anchor apple generic and certificate leaf[subject.OU] = \"\(team)\""
            guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
                SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess,
                SecStaticCodeCheckValidity(
                    code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode), requirement)
                    == errSecSuccess
            else { throw UpdateError.verification(L("The downloaded app isn't signed by the same developer as this one.")) }
            do {
                try run("/usr/sbin/spctl", ["--assess", "--type", "execute", app.path])
            } catch {
                throw UpdateError.verification(L("The downloaded app isn't notarized by Apple."))
            }
        }

        /// The SHA-256 a `shasum -a 256` listing gives for `name`.
        static func checksum(in listing: String, for name: String) -> String? {
            for line in listing.split(separator: "\n") {
                let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { continue }
                let file = parts[1].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "*"))
                if file == name { return parts[0].lowercased() }
            }
            return nil
        }

        // MARK: plumbing

        static func fetch(_ request: URLRequest) throws -> (Data, URLResponse) {
            let box = UnsafeSendableBox<(Data?, URLResponse?, Error?)>((nil, nil, nil))
            let done = DispatchSemaphore(value: 0)
            URLSession.shared.dataTask(with: request) { d, r, e in
                box.lock.withLock { box.value = (d, r, e) }
                done.signal()
            }.resume()
            done.wait()
            let (data, response, error) = box.lock.withLock { box.value }
            if let error { throw UpdateError.network(error.localizedDescription) }
            guard let data, let response else { throw UpdateError.badResponse }
            return (data, response)
        }

        static func download(_ url: URL, to destination: URL) throws {
            let request = URLRequest(url: url, timeoutInterval: 120)
            let (data, response) = try fetch(request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError.network(url.lastPathComponent) }
            try data.write(to: destination)
        }

        @discardableResult
        static func run(_ tool: String, _ arguments: [String]) throws -> String {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: tool)
            p.arguments = arguments
            let out = Pipe()
            p.standardOutput = out
            p.standardError = out
            p.standardInput = FileHandle.nullDevice
            try p.run()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            let text = String(decoding: data, as: UTF8.self)
            guard p.terminationStatus == 0 else {
                throw UpdateError.install(
                    L("\((tool as NSString).lastPathComponent) failed: \(text.trimmingCharacters(in: .whitespacesAndNewlines))"))
            }
            return text
        }
    }
#endif
