import Foundation
import Testing

@testable import KitfoldCore

@Suite struct UpdateTests {
    @Test func versionsCompareNumberByNumber() throws {
        func v(_ s: String) throws -> AppVersion { try #require(AppVersion(s)) }
        #expect(try v("v0.4.0") == v("0.4.0"))
        #expect(try v("0.4") == v("0.4.0"))
        #expect(try v("0.10.0") > v("0.9.9"))
        #expect(try v("0.4.1") > v("0.4.0"))
        #expect(try v("1.0") > v("0.99.99"))
        #expect(Set([try v("0.4"), try v("0.4.0")]).count == 1)
        #expect(AppVersion("0.4.0-beta") == nil)
        #expect(AppVersion("") == nil)
        #expect(AppVersion("x") == nil)
    }

    static let latestJSON = """
        {
          "tag_name": "v0.5.0", "name": "Kitfold 0.5.0", "body": "## New\\n- Updates", "draft": false, "prerelease": false,
          "html_url": "https://github.com/kadaliao/kitfold/releases/tag/v0.5.0",
          "published_at": "2026-11-11T08:00:00Z",
          "assets": [
            {"name": "SHA256SUMS", "browser_download_url": "https://github.com/kadaliao/kitfold/releases/download/v0.5.0/SHA256SUMS"},
            {"name": "Kitfold-0.5.0.dmg", "browser_download_url": "https://github.com/kadaliao/kitfold/releases/download/v0.5.0/Kitfold-0.5.0.dmg"}
          ]
        }
        """

    @Test func readsGitHubsLatestRelease() throws {
        let r = try Updates.parseLatest(Data(Self.latestJSON.utf8))
        #expect(r.version == AppVersion("0.5.0"))
        #expect(r.title == "Kitfold 0.5.0" && r.notes.hasPrefix("## New"))
        #expect(r.diskImageURL.lastPathComponent == "Kitfold-0.5.0.dmg")
        #expect(r.checksumsURL?.lastPathComponent == "SHA256SUMS")
        #expect(r.publishedAt != nil)
        #expect(Updates.isNewer(r, than: AppVersion("0.4.0")))
        #expect(!Updates.isNewer(r, than: AppVersion("0.5.0")))
        #expect(!Updates.isNewer(r, than: nil))  // a development build never updates

        let noImage = Self.latestJSON.replacingOccurrences(of: "Kitfold-0.5.0.dmg", with: "Kitfold-0.4.0.dmg")
        #expect(throws: UpdateError.noDiskImage) { try Updates.parseLatest(Data(noImage.utf8)) }
        #expect(throws: UpdateError.badResponse) { try Updates.parseLatest(Data("{\"message\": \"Not Found\"}".utf8)) }
    }

    @Test func findsTheChecksumForTheDiskImage() {
        let sums = "abc123  Kitfold-0.5.0.dmg\nDEF456 *Other.dmg\n"
        #expect(Updates.checksum(in: sums, for: "Kitfold-0.5.0.dmg") == "abc123")
        #expect(Updates.checksum(in: sums, for: "Other.dmg") == "def456")
        #expect(Updates.checksum(in: sums, for: "Missing.dmg") == nil)
    }

    @Test func findsTheAppAnExecutableIsPartOf() throws {
        let h = FakeHome()
        let app = h.path("Applications/Kitfold.app")
        h.write("Applications/Kitfold.app/Contents/Resources/kitfold", "")
        h.write("Applications/Kitfold.app/Contents/MacOS/Kitfold", "")
        h.write(
            "Applications/Kitfold.app/Contents/Info.plist",
            "<?xml version=\"1.0\"?><plist version=\"1.0\"><dict><key>CFBundleShortVersionString</key><string>0.4.0</string></dict></plist>"
        )
        // The CLI is usually linked into ~/.local/bin.
        h.link(".local/bin/kitfold", to: "Applications/Kitfold.app/Contents/Resources/kitfold")
        for exe in [".local/bin/kitfold", "Applications/Kitfold.app/Contents/MacOS/Kitfold"] {
            #expect(Updates.appBundle(containing: URL(fileURLWithPath: h.path(exe)))?.path == app)
        }
        #expect(Updates.appBundle(containing: URL(fileURLWithPath: h.path("src/.build/debug/kitfold"))) == nil)
        #expect(Updates.version(ofApp: URL(fileURLWithPath: app)) == AppVersion("0.4.0"))

        // Unsigned (a development build): it says why it can't update itself, and won't install anything.
        let url = URL(fileURLWithPath: app)
        #expect(Updates.whyNotInstallable(app: url)?.contains("signed release") == true)
        #expect(throws: UpdateError.self) { try Updates.verify(url, version: AppVersion("0.4.0")!, team: "HMDAVG9B8J") }
        #expect(throws: UpdateError.self) { try Updates.verify(url, version: AppVersion("0.5.0")!, team: "HMDAVG9B8J") }
    }

    @Test func refusesToUpdateFromATemporaryPlace() {
        let translocated = URL(fileURLWithPath: "/private/var/folders/x/AppTranslocation/ABC/d/Kitfold.app")
        #expect(Updates.whyNotInstallable(app: translocated)?.contains("temporary location") == true)
        let dmg = URL(fileURLWithPath: "/Volumes/Kitfold 0.4.0/Kitfold.app")
        #expect(Updates.whyNotInstallable(app: dmg)?.contains("disk image") == true)
    }
}
