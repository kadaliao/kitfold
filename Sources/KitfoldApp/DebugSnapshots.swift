import AppKit
import KitfoldCore
import ObjectiveC
import SwiftUI

/// Development aid: with KITFOLD_SNAPSHOT_DIR set, the app walks through its pages and renders
/// its own window into PNGs (no screen-recording permission needed), then quits.
///
/// - KITFOLD_SNAPSHOT_SCRIPT=marketing  curated states for release screenshots (see scripts/screenshots/make.sh)
/// - KITFOLD_SNAPSHOT_SCRIPT=video      states for the launch video (see scripts/video); applies its
///   draft only inside a fake home (KITFOLD_FAKE_HOME)
/// - KITFOLD_SNAPSHOT_APPEARANCE=light|dark
/// - KITFOLD_SNAPSHOT_SIZE=1440x900     window size in points
/// Draft changes made by a script are never applied.
enum DebugSnapshots {
    static var env: [String: String] { ProcessInfo.processInfo.environment }
    static var directory: String? { env["KITFOLD_SNAPSHOT_DIR"] }

    @MainActor
    static func run(model: AppModel) async {
        guard let dir = directory else { return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        switch env["KITFOLD_SNAPSHOT_APPEARANCE"] {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
        for _ in 0..<150 where model.snapshot == nil { try? await Task.sleep(for: .milliseconds(100)) }
        var size = CGSize(width: 1320, height: 860)
        if let s = env["KITFOLD_SNAPSHOT_SIZE"]?.split(separator: "x"), s.count == 2, let w = Double(s[0]), let h = Double(s[1]) {
            size = CGSize(width: w, height: h)
        }
        if let window = mainWindow {
            window.setFrame(NSRect(x: 60, y: 60, width: size.width, height: size.height), display: true)
            // Render as the active window (colored traffic lights, accent selection) even when
            // macOS won't hand focus to an app launched from a script.
            forceActiveAppearance()
            window.makeKeyAndOrderFront(nil)
            NotificationCenter.default.post(name: NSWindow.didBecomeMainNotification, object: window)
            NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
            window.contentView?.superview?.needsDisplay = true
            try? await Task.sleep(for: .milliseconds(300))
        }
        if env["KITFOLD_SNAPSHOT_SCRIPT"] == "marketing" {
            await marketing(model: model, dir: dir)
        } else if env["KITFOLD_SNAPSHOT_SCRIPT"] == "video" {
            await video(model: model, dir: dir)
        } else {
            await tour(model: model, dir: dir)
        }
        // exit() rather than NSApp.terminate: a sheet that is still closing can veto termination.
        if env["KITFOLD_SNAPSHOT_KEEP_OPEN"] == nil { exit(0) }
    }

    /// Snapshot mode only: every window reports itself as key and main.
    static func forceActiveAppearance() {
        for sel in [#selector(getter: NSWindow.isKeyWindow), #selector(getter: NSWindow.isMainWindow)] {
            guard let method = class_getInstanceMethod(NSWindow.self, sel) else { continue }
            let alwaysTrue: @convention(block) (NSWindow) -> Bool = { _ in true }
            method_setImplementation(method, imp_implementationWithBlock(alwaysTrue))
        }
    }

    @MainActor static var mainWindow: NSWindow? { NSApp.windows.first { $0.isVisible && $0.sheetParent == nil && $0.contentView != nil } }

    @MainActor
    static func show(_ model: AppModel, _ item: SidebarItem, wait: Int = 900, then name: String, dir: String) async {
        model.selection = item
        try? await Task.sleep(for: .milliseconds(wait))
        capture(to: "\(dir)/\(name).png")
    }

    /// Every page once (UI regression check).
    @MainActor
    static func tour(model: AppModel, dir: String) async {
        if let first = model.snapshot?.catalog.first(where: { $0.origin != .library })?.path { model.selectedSkillPath = first }
        await show(model, .dashboard, then: "1-dashboard", dir: dir)
        await show(model, .skills, then: "2-skills", dir: dir)
        for a in model.agents { await show(model, .agent(a.id), then: "3-agent-\(a.id.rawValue)", dir: dir) }
        await show(model, .profiles, then: "4-profiles", dir: dir)
        await show(model, .history, then: "5-history", dir: dir)
    }

    /// Curated states for release screenshots.
    @MainActor
    static func marketing(model: AppModel, dir: String) async {
        guard let snap = model.snapshot else { return }
        await show(model, .agent(.codex), then: "agent", dir: dir)
        model.skillsMatrix = true
        await show(model, .skills, then: "matrix", dir: dir)
        model.skillsMatrix = false
        model.selectedSkillPath = snap.skill(named: "code-review")?.path
        await show(model, .skills, then: "skill", dir: dir)
        model.selectedProfileID = "code-reviewer"
        await show(model, .profiles, then: "profile", dir: dir)
        if let p = model.draft.projects.first(where: { $0.name == "acme-web" }) {
            await show(model, .project(p.path), then: "project", dir: dir)
        }
        await show(model, .dashboard, then: "dashboard", dir: dir)

        // Pending changes (one of them through OpenCode's own settings), then the review sheet.
        model.toggleProfile("researcher", agent: .geminiCLI, scope: .global)
        model.toggle(skill: "playwright-e2e", agent: .claudeCode, scope: .global)
        model.toggle(skill: "deep-research", agent: .openCode, scope: .global)
        await show(model, .agent(.geminiCLI), wait: 1200, then: "pending", dir: dir)
        model.showReview = true
        try? await Task.sleep(for: .milliseconds(1400))
        if let sheet = NSApp.windows.first(where: { $0.isVisible && $0.sheetParent != nil }) {
            capture(window: sheet, to: "\(dir)/review-sheet.png")
        }
        model.showReview = false
        model.discardDraft()
    }

    /// The launch video's states, in story order: what an agent loads, the grid, hiding a skill
    /// from one agent through its own settings, the review, the result and the undo history.
    @MainActor
    static func video(model: AppModel, dir: String) async {
        guard let snap = model.snapshot else { return }
        // The agents' marks as transparent PNGs (dark appearance), for title cards.
        for a in model.agents {
            guard let logo = AgentLogo(a.id) else { continue }
            let r = ImageRenderer(content: logo.frame(width: 256, height: 256).environment(\.colorScheme, .dark))
            r.scale = 2
            if let cg = r.cgImage {
                try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?
                    .write(to: URL(fileURLWithPath: "\(dir)/logo-\(a.id.rawValue).png"))
            }
        }
        await show(model, .dashboard, then: "v01-dashboard", dir: dir)
        await show(model, .agent(.codex), then: "v02-agent-codex", dir: dir)
        model.skillsMatrix = true
        await show(model, .skills, then: "v03-matrix", dir: dir)
        model.toggle(skill: "deep-research", agent: .openCode, scope: .global)
        await show(model, .skills, wait: 1200, then: "v04-matrix-pending", dir: dir)
        model.showReview = true
        try? await Task.sleep(for: .milliseconds(1400))
        if let sheet = NSApp.windows.first(where: { $0.isVisible && $0.sheetParent != nil }) {
            capture(window: sheet, to: "\(dir)/v05-review.png")
        }
        capture(to: "\(dir)/v05-review-window.png")
        model.showReview = false
        try? await Task.sleep(for: .milliseconds(600))
        // Applying is only allowed against a throwaway home.
        guard env["KITFOLD_FAKE_HOME"] != nil else { return model.discardDraft() }
        model.applyDraft()
        model.toast = nil
        for _ in 0..<60 where model.isScanning || model.isPlanning { try? await Task.sleep(for: .milliseconds(100)) }
        await show(model, .skills, wait: 1200, then: "v06-matrix-applied", dir: dir)
        await show(model, .agent(.openCode), then: "v07-agent-opencode", dir: dir)
        await show(model, .history, then: "v08-history", dir: dir)
        model.skillsMatrix = false
        model.selectedSkillPath = snap.skill(named: "code-review")?.path
        await show(model, .skills, then: "v09-skill", dir: dir)
        model.selectedProfileID = "code-reviewer"
        await show(model, .profiles, then: "v10-profile", dir: dir)
    }

    @MainActor
    static func capture(window: NSWindow? = nil, to path: String) {
        guard let window = window ?? mainWindow,
            let view = window.contentView?.superview ?? window.contentView
        else { return }
        let bounds = view.bounds
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        view.cacheDisplay(in: bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
