import AppKit
import KitfoldCore
import SwiftUI

/// Where an update check or install stands, for the update sheet.
enum UpdateStatus: Equatable {
    case idle
    case checking
    case upToDate
    case available(ReleaseInfo)
    case installing(String)
    case failed(String)
}

extension AppModel {
    static let autoCheckKey = "updates.autoCheck"
    static let lastCheckKey = "updates.lastCheck"
    static let skippedKey = "updates.skipped"

    /// The running Kitfold.app, nil when launched some other way (`swift run`).
    var appURL: URL? { Bundle.main.bundleURL.pathExtension == "app" ? Bundle.main.bundleURL : nil }
    var appVersion: AppVersion? { appURL.flatMap(Updates.version(ofApp:)) }

    /// At launch and when the app comes back to the front: ask GitHub once a day, if allowed.
    func checkForUpdatesIfDue() {
        guard autoCheckUpdates, appVersion != nil, DebugSnapshots.directory == nil else { return }
        let last = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > 24 * 3600, updateStatus == .idle else { return }
        checkForUpdates(userInitiated: false)
    }

    /// Ask GitHub for the latest release. Asked by the user, the sheet shows the answer (and any error);
    /// otherwise a newer release that wasn't skipped shows up as a toolbar button, and errors stay quiet.
    func checkForUpdates(userInitiated: Bool) {
        if userInitiated {
            updateStatus = .checking
            showUpdate = true
        }
        let current = appVersion
        Task.detached(priority: .utility) {
            let result = Result { try Updates.latest() }
            await MainActor.run {
                switch result {
                case .success(let release):
                    UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)
                    let newer = Updates.isNewer(release, than: current)
                    let skipped = UserDefaults.standard.string(forKey: Self.skippedKey) == release.version.text
                    if newer && (userInitiated || !skipped) { self.availableUpdate = release }
                    if userInitiated { self.updateStatus = newer ? .available(release) : .upToDate }
                case .failure(let error):
                    if userInitiated { self.updateStatus = .failed(error.localizedDescription) }
                }
            }
        }
    }

    func showAvailableUpdate() {
        guard let release = availableUpdate else { return }
        updateStatus = .available(release)
        showUpdate = true
    }

    func skip(_ release: ReleaseInfo) {
        UserDefaults.standard.set(release.version.text, forKey: Self.skippedKey)
        availableUpdate = nil
        closeUpdate()
    }

    func closeUpdate() {
        showUpdate = false
        if case .installing = updateStatus { return }
        updateStatus = .idle
    }

    /// Download, check and swap in the new app, then quit and open it.
    func installUpdate(_ release: ReleaseInfo) {
        guard let app = appURL else { return }
        updateStatus = .installing(L("Getting ready…"))
        Task.detached(priority: .userInitiated) {
            do {
                try Updates.install(release, replacing: app) { step in
                    Task { @MainActor in self.updateStatus = .installing(step) }
                }
                await MainActor.run { self.relaunch(app) }
            } catch {
                await MainActor.run { self.updateStatus = .failed(error.localizedDescription) }
            }
        }
    }

    /// Open the new copy once this process is gone.
    func relaunch(_ app: URL) {
        let pid = ProcessInfo.processInfo.processIdentifier
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \"$0\"", app.path]
        try? p.run()
        NSApp.terminate(nil)
    }
}

/// The answer to "Check for Updates…", and the new version's notes with Install and Relaunch.
struct UpdateSheet: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch model.updateStatus {
            case .idle, .checking:
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(L("Checking for updates…"))
                }
                buttons { Button(L("Cancel")) { model.closeUpdate() }.keyboardShortcut(.cancelAction) }
            case .upToDate:
                Label(
                    model.appVersion.map { L("Kitfold \($0.text) is the latest version.") } ?? L("You have the latest version."),
                    systemImage: "checkmark.seal.fill"
                )
                .font(.headline)
                buttons { Button(L("OK")) { model.closeUpdate() }.keyboardShortcut(.defaultAction) }
            case .available(let release):
                available(release)
            case .installing(let step):
                Text(L("Updating Kitfold")).font(.headline)
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(step).foregroundStyle(.secondary)
                }
                Text(L("Kitfold reopens by itself when it's done.")).font(.caption).foregroundStyle(.secondary)
            case .failed(let message):
                Label(L("The update didn't go through"), systemImage: "exclamationmark.triangle.fill")
                    .font(.headline).foregroundStyle(.orange)
                Text(message).textSelection(.enabled)
                Text(L("Nothing was changed. You can download the new version from GitHub instead."))
                    .font(.callout).foregroundStyle(.secondary)
                buttons {
                    Button(L("Open the Download Page")) { NSWorkspace.shared.open(Updates.releasesPage) }
                    Button(L("OK")) { model.closeUpdate() }.keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(width: 560)
    }

    @ViewBuilder func available(_ release: ReleaseInfo) -> some View {
        let date = release.publishedAt.map {
            $0.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: Localization.language.locale))
        }
        VStack(alignment: .leading, spacing: 3) {
            Text(L("Kitfold \(release.version.text) is available")).font(.title3.weight(.semibold))
            Text(
                Localization.sentences([
                    model.appVersion.map { L("You have \($0.text).") } ?? "", date.map { L("Released \($0).") } ?? "",
                ])
            )
            .foregroundStyle(.secondary)
        }
        ScrollView {
            MarkdownView(text: release.notes).frame(maxWidth: .infinity, alignment: .leading).padding(12)
        }
        .frame(height: 300)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
        let blocked = model.appURL.flatMap(Updates.whyNotInstallable(app:))
        if let blocked {
            Label(blocked, systemImage: "info.circle").font(.callout).foregroundStyle(.secondary)
        } else if model.hasDraftEdits {
            Label(L("Switches you haven't applied are lost when Kitfold reopens."), systemImage: "exclamationmark.triangle")
                .font(.callout).foregroundStyle(.orange)
        }
        HStack {
            Button(L("Skip This Version")) { model.skip(release) }
            Spacer()
            Button(L("Later")) { model.closeUpdate() }.keyboardShortcut(.cancelAction)
            if blocked == nil, model.appURL != nil {
                Button(L("Install and Reopen")) { model.installUpdate(release) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            } else {
                Button(L("Open the Download Page")) { NSWorkspace.shared.open(release.pageURL) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    func buttons<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack {
            Spacer()
            content()
        }
    }
}
