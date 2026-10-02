import Foundation

public struct AvailableUpdate: Sendable, Equatable {
    public let version: String
    public let releaseURL: URL
}
public enum UpdateCheckResult: Sendable, Equatable { case current, available(AvailableUpdate), notPublished }
public enum UpdateCheckError: Error { case responseRejected, tooLarge, invalidMetadata }

/// Metadata-only update discovery. Never downloads, installs, or opens an update.
/// Constructed only for an explicit manual check or an opted-in scheduled check.
private final class NoUpdateRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}

public actor UpdateChecker {
    public static let endpoint = URL(string: "https://api.github.com/repos/madeordinary/winnel/releases/latest")!
    public init() {}
    public func check(currentVersion: String) async throws -> UpdateCheckResult {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil; configuration.httpShouldSetCookies = false
        configuration.urlCache = nil; configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: configuration, delegate: NoUpdateRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: Self.endpoint)
        request.timeoutInterval = 15; request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Winnel/0.1 (manual-or-opted-in-release-check)", forHTTPHeaderField: "User-Agent")
        let (stream, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.url?.host == Self.endpoint.host else { throw UpdateCheckError.responseRejected }
        if http.statusCode == 404 { return .notPublished }
        guard http.statusCode == 200 else { throw UpdateCheckError.responseRejected }
        guard response.expectedContentLength <= 262_144 else { throw UpdateCheckError.tooLarge }
        var data = Data()
        for try await byte in stream { guard data.count < 262_144 else { throw UpdateCheckError.tooLarge }; data.append(byte) }
        return try Self.parse(data, currentVersion: currentVersion)
    }
    public static func parse(_ data: Data, currentVersion: String) throws -> UpdateCheckResult {
        struct Release: Decodable { let tag_name: String; let html_url: String; let draft: Bool; let prerelease: Bool }
        let release = try JSONDecoder().decode(Release.self, from: data)
        guard !release.draft, !release.prerelease, let url = URL(string: release.html_url), url.scheme == "https", url.host == "github.com", url.user == nil, url.password == nil,
              url.path.hasPrefix("/madeordinary/winnel/releases/tag/"), let remote = version(release.tag_name), let local = version(currentVersion) else { throw UpdateCheckError.invalidMetadata }
        return local.lexicographicallyPrecedes(remote) ? .available(.init(version: release.tag_name, releaseURL: url)) : .current
    }
    private static func version(_ input: String) -> [Int]? {
        let value = input.hasPrefix("v") ? String(input.dropFirst()) : input
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        let numbers = parts.compactMap { part -> Int? in guard !part.isEmpty, part.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }; return Int(part) }
        return numbers.count == 3 ? numbers : nil
    }
}
