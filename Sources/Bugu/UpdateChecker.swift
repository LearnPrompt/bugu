import Foundation

/// Lightweight, no-install update check: asks GitHub for the latest release and
/// compares its version to the running build. It never downloads or replaces
/// anything — community builds are unsigned, so auto-install would be unsafe. When a
/// newer version exists, Bugu just surfaces a "download" link to the Releases page.
enum UpdateChecker {

    static let releasesPageURL = "https://github.com/LearnPrompt/bugu/releases/latest"
    private static let apiURL = "https://api.github.com/repos/LearnPrompt/bugu/releases/latest"

    struct Release: Sendable, Equatable {
        let version: String   // normalised, e.g. "0.2.2"
        let url: String       // release page to open
    }

    /// Fetches the latest published release, or nil on any failure (offline, rate
    /// limited, parse error). Callers treat nil as "no update info".
    static func fetchLatest() async -> Release? {
        guard let url = URL(string: apiURL) else { return nil }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = object["tag_name"] as? String else {
            return nil
        }
        let page = (object["html_url"] as? String) ?? releasesPageURL
        return Release(version: normalize(tag), url: page)
    }

    /// Strips a leading "v" from a tag like "v0.2.2".
    static func normalize(_ tag: String) -> String {
        var s = tag.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("v") || s.hasPrefix("V") { s.removeFirst() }
        return s
    }

    /// Numeric-component comparison ("0.2.10" > "0.2.9"), ignoring any pre-release
    /// suffix after "-" (so "0.2.2-dev" compares equal to "0.2.2").
    static func isNewer(_ latest: String, than current: String) -> Bool {
        func parts(_ v: String) -> [Int] {
            let core = v.split(separator: "-").first.map(String.init) ?? v
            return core.split(separator: ".").map { Int($0) ?? 0 }
        }
        let a = parts(latest), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
