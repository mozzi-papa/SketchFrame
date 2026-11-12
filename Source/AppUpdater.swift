import Foundation

struct UpdateError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct AppVersion: Comparable {
    let numbers: [Int]
    init?(_ text: String) {
        let clean = text.hasPrefix("v") ? String(text.dropFirst()) : text
        let parts = clean.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }),
              parts.allSatisfy({ Int($0) != nil }) else { return nil }
        numbers = parts.map { Int($0)! }
    }
    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool { lhs.numbers.lexicographicallyPrecedes(rhs.numbers) }
}

struct UpdateRelease: Decodable {
    struct Asset: Decodable {
        let name: String
        let browser_download_url: String
    }
    let tag_name: String
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]
}

struct UpdateCandidate: Equatable {
    let version: String
    let tag: String
    var archiveName: String { "sketchframe-\(version)-arm64.zip" }
    var downloadURL: URL { URL(string: "https://github.com/mozzi-papa/SketchFrame/releases/download/\(tag)/\(archiveName)")! }
    var checksumURL: URL { URL(string: downloadURL.absoluteString + ".sha256")! }

    static func latest(in releases: [UpdateRelease]) -> UpdateCandidate? {
        releases.filter { !$0.draft && !$0.prerelease }.compactMap { release -> UpdateCandidate? in
            let version = release.tag_name.hasPrefix("v") ? String(release.tag_name.dropFirst()) : release.tag_name
            guard !version.hasPrefix("v"), AppVersion(version) != nil else { return nil }
            let candidate = UpdateCandidate(version: version, tag: release.tag_name)
            guard release.assets.contains(where: { $0.name == candidate.archiveName && $0.browser_download_url == candidate.downloadURL.absoluteString }),
                  release.assets.contains(where: { $0.name == candidate.archiveName + ".sha256" && $0.browser_download_url == candidate.checksumURL.absoluteString }) else { return nil }
            return candidate
        }.max { AppVersion($0.version)! < AppVersion($1.version)! }
    }
}

final class AppUpdater {
    static let repositoryURL = URL(string: "https://github.com/mozzi-papa/SketchFrame")!
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0" }
    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1" }
    static var versionLabel: String { "SketchFrame \(version) (빌드 \(build))" }

    private let session: URLSession
    private let worker = DispatchQueue(label: "personal.windowsketch.updater")
    private var timer: Timer?
    private var initialCheck: DispatchWorkItem?
    private var checkTask: URLSessionDataTask?
    private var generation = 0
    private(set) var checking = false
    private(set) var installing = false
    private(set) var available: UpdateCandidate?
    private(set) var lastCheck: Date?
    private(set) var status = "업데이트를 자동으로 확인합니다."
    var onChange: (() -> Void)?
    var onManualResult: ((Result<UpdateCandidate?, Error>) -> Void)?

    init(session: URLSession? = nil) {
        if let session = session { self.session = session } else {
            let config = URLSessionConfiguration.ephemeral
            config.urlCache = nil
            config.httpCookieStorage = nil
            config.urlCredentialStorage = nil
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            config.timeoutIntervalForRequest = 10
            config.timeoutIntervalForResource = 20
            self.session = URLSession(configuration: config)
        }
    }

    func start() {
        guard timer == nil else { return }
        let first = DispatchWorkItem { [weak self] in self?.check() }
        initialCheck = first
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: first)
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in self?.check() }
    }

    func stop() {
        generation += 1
        checkTask?.cancel()
        checkTask = nil
        checking = false
        initialCheck?.cancel()
        initialCheck = nil
        timer?.invalidate()
        timer = nil
        session.invalidateAndCancel()
    }

    static func parse(_ data: Data, statusCode: Int) throws -> UpdateCandidate? {
        guard statusCode == 200 else {
            throw UpdateError(message: statusCode == 403 || statusCode == 429
                ? "GitHub 조회 한도에 도달했습니다. 잠시 뒤 다시 확인해 주세요."
                : "업데이트 서버 응답을 확인하지 못했습니다 (HTTP \(statusCode)).")
        }
        guard data.count <= 2 * 1024 * 1024,
              let releases = try? JSONDecoder().decode([UpdateRelease].self, from: data) else {
            throw UpdateError(message: "업데이트 정보 형식이 올바르지 않습니다.")
        }
        return UpdateCandidate.latest(in: releases)
    }

    func check(manual: Bool = false) {
        guard !checking, !installing else { return }
        generation += 1
        let requestGeneration = generation
        checking = true
        status = "업데이트 확인 중…"
        onChange?()
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/mozzi-papa/SketchFrame/releases?per_page=30")!)
        request.setValue("SketchFrame/\(Self.version)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        checkTask = session.dataTask(with: request) { [weak self] data, response, error in
            let result = Result { () -> UpdateCandidate? in
                if let error = error { throw error }
                guard let data = data, let response = response as? HTTPURLResponse else {
                    throw UpdateError(message: "업데이트 서버에 연결하지 못했습니다.")
                }
                return try Self.parse(data, statusCode: response.statusCode)
            }
            DispatchQueue.main.async {
                guard let self = self, self.generation == requestGeneration else { return }
                self.checking = false
                self.checkTask = nil
                self.lastCheck = Date()
                let visibleResult: Result<UpdateCandidate?, Error>
                switch result {
                case .failure(let error):
                    self.status = "업데이트 확인 실패 · \(error.localizedDescription)"
                    visibleResult = .failure(error)
                case .success(let candidate):
                    if let candidate = candidate, let latest = AppVersion(candidate.version), let current = AppVersion(Self.version), latest > current {
                        self.available = candidate
                        self.status = "새 버전 \(candidate.version)을 사용할 수 있습니다."
                    } else {
                        self.available = nil
                        self.status = candidate == nil ? "게시된 정식 업데이트가 없습니다." : "최신 버전을 사용하고 있습니다."
                    }
                    visibleResult = .success(self.available)
                }
                self.onChange?()
                if manual { self.onManualResult?(visibleResult) }
            }
        }
        checkTask?.resume()
    }

    func prepareInstallation(_ candidate: UpdateCandidate, completion: @escaping (Result<PreparedUpdate, Error>) -> Void) {
        guard !installing else {
            completion(.failure(UpdateError(message: "업데이트를 이미 준비하고 있습니다.")))
            return
        }
        generation += 1
        checkTask?.cancel()
        checkTask = nil
        checking = false
        installing = true
        status = "업데이트 다운로드·검증 중…"
        onChange?()
        worker.async {
            let result = Result { try UpdateInstaller.prepare(candidate, currentApp: Bundle.main.bundleURL) }
            DispatchQueue.main.async {
                if case .failure(let error) = result {
                    self.installing = false
                    self.status = "업데이트 설치 준비 실패 · \(error.localizedDescription)"
                    self.onChange?()
                }
                completion(result)
            }
        }
    }

    func installationFailed(_ error: Error) {
        installing = false
        status = "업데이트 설치 실패 · \(error.localizedDescription)"
        onChange?()
    }
}
