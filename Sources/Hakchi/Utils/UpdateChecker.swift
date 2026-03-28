import Foundation

/// Checks for new versions on GitHub releases.
final class UpdateChecker {
    static let shared = UpdateChecker()

    private let repoOwner = "jorgeamartinezjr02"
    private let repoName = "Hakchi2-macOS-Port"
    private let session = URLSession.shared

    struct Release: Codable {
        let tagName: String
        let name: String
        let body: String
        let htmlUrl: String
        let publishedAt: String

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case name
            case body
            case htmlUrl = "html_url"
            case publishedAt = "published_at"
        }
    }

    private init() {}

    /// Check if a newer version is available.
    func checkForUpdate() async -> Release? {
        guard let url = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

        do {
            let (data, _) = try await session.data(for: request)
            let release = try JSONDecoder().decode(Release.self, from: data)

            let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
            if isNewer(release.tagName, than: currentVersion) {
                return release
            }
        } catch {
            HakchiLogger.general.error("Update check failed: \(error.localizedDescription)")
        }

        return nil
    }

    private func isNewer(_ tag: String, than current: String) -> Bool {
        let tagVersion = tag.replacingOccurrences(of: "v", with: "")
        let components1 = tagVersion.split(separator: ".").compactMap { Int($0) }
        let components2 = current.split(separator: ".").compactMap { Int($0) }

        for i in 0..<max(components1.count, components2.count) {
            let v1 = i < components1.count ? components1[i] : 0
            let v2 = i < components2.count ? components2[i] : 0
            if v1 > v2 { return true }
            if v1 < v2 { return false }
        }
        return false
    }
}
