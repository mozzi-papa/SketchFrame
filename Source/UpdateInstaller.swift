import Foundation
import Darwin

struct PreparedUpdate {
    let current: URL
    let staged: URL
    let work: URL
    let package: URL

    func cleanUp() {
        try? FileManager.default.removeItem(at: work)
        try? FileManager.default.removeItem(at: package)
    }

    func launch(oldPID: Int32) throws {
        let script = package.appendingPathComponent("install.sh")
        try UpdateInstaller.installScript.write(to: script, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path, String(oldPID), current.path, staged.path,
                             work.appendingPathComponent("previous.app").path, work.path, package.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }
}

enum UpdateInstaller {
    static let installScript = #"""
set -eu
old_pid=$1
current=$2
staged=$3
backup=$4
work=$5
package=$6
moved=0
installed=0
finish() {
    result=$?
    trap - EXIT
    if [ "$result" -ne 0 ]; then
        if [ "$moved" = 1 ]; then
            if [ "$installed" = 1 ]; then /bin/rm -rf "$current"; fi
            if ! /bin/mv "$backup" "$current"; then
                /usr/bin/osascript -e 'display alert "SketchFrame 업데이트 복구 실패" message "기존 앱 백업을 보존했습니다. 설치 폴더의 .SketchFrameUpdate- 폴더를 확인해 주세요."' || true
                exit "$result"
            fi
            /usr/bin/open "$current" || true
        fi
        /usr/bin/osascript -e 'display alert "SketchFrame 업데이트 실패" message "새 앱으로 교체하지 못했습니다. 기존 앱을 유지했습니다. 수동 설치를 이용해 주세요."' || true
    fi
    /bin/rm -rf "$work" "$package"
    exit "$result"
}
trap finish EXIT
attempt=0
while /bin/kill -0 "$old_pid" 2>/dev/null; do
    attempt=$((attempt + 1))
    [ "$attempt" -le 150 ] || exit 1
    /bin/sleep 0.2
done
/bin/mv "$current" "$backup"
moved=1
/bin/mv "$staged" "$current"
installed=1
/usr/bin/open "$current"
"""#

    @discardableResult
    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 30) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "C"
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let deadline = DispatchWorkItem {
            if process.isRunning {
                process.terminate()
                usleep(200_000)
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
        defer { deadline.cancel(); try? pipe.fileHandleForReading.close() }
        var output = Data()
        var oversized = false
        while let chunk = try pipe.fileHandleForReading.read(upToCount: 65_536), !chunk.isEmpty {
            if output.count + chunk.count <= 2 * 1024 * 1024 { output.append(chunk) }
            else { oversized = true; if process.isRunning { process.terminate() } }
        }
        process.waitUntilExit()
        guard !oversized, process.terminationStatus == 0 else {
            throw UpdateError(message: "업데이트 작업에 실패했습니다 (\(URL(fileURLWithPath: executable).lastPathComponent)). 기존 앱을 유지했습니다.")
        }
        return String(decoding: output, as: UTF8.self)
    }

    static func verifyChecksum(_ text: String, actual: String) throws {
        let expected = text.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? ""
        let actual = actual.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? ""
        guard expected.count == 64, expected.allSatisfy({ $0.isASCII && $0.isHexDigit }), expected.lowercased() == actual.lowercased() else {
            throw UpdateError(message: "업데이트 파일의 SHA-256이 일치하지 않습니다. 기존 앱을 유지했습니다.")
        }
    }

    static func validateArchive(entries: String, details: String) throws {
        let paths = entries.split(separator: "\n", omittingEmptySubsequences: false).filter { !$0.isEmpty }
        guard !paths.isEmpty, paths.count <= 5000, paths.allSatisfy({ path in
            let pieces = path.split(separator: "/", omittingEmptySubsequences: false)
            return pieces.first == "SketchFrame.app" && !pieces.contains("..") && !pieces.contains(".") && !path.contains("\\")
        }) else { throw UpdateError(message: "업데이트 압축 파일의 경로가 올바르지 않습니다.") }
        var total: Int64 = 0
        var count = 0
        for line in details.split(separator: "\n") {
            guard let first = line.first else { continue }
            if first == "l" { throw UpdateError(message: "업데이트 압축 파일의 링크 항목을 허용하지 않습니다.") }
            if first == "-" || first == "d" {
                let fields = line.split(whereSeparator: { $0.isWhitespace })
                guard fields.count >= 5, let size = Int64(fields[3]), size >= 0, size <= 256 * 1024 * 1024 - total else {
                    throw UpdateError(message: "업데이트 압축 파일이 허용 크기를 초과했습니다.")
                }
                total += size
                count += 1
            }
        }
        guard count == paths.count else { throw UpdateError(message: "업데이트 압축 파일의 항목을 확인하지 못했습니다.") }
    }

    static func validateBundle(_ app: URL, version: String, requirement: String) throws {
        guard let bundle = Bundle(url: app), bundle.bundleIdentifier == "personal.windowsketch",
              bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == version,
              let executable = bundle.executableURL, FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw UpdateError(message: "업데이트 앱의 식별자 또는 버전이 올바르지 않습니다.")
        }
        try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", "-R", "=" + requirement, app.path])
    }

    static func signingRequirement(of app: URL) throws -> String {
        try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
        let display = try run("/usr/bin/codesign", ["--display", "-r-", app.path])
        guard let line = display.split(separator: "\n").first(where: { $0.hasPrefix("designated => ") }) else {
            throw UpdateError(message: "현재 앱의 서명 식별 규칙을 읽지 못했습니다.")
        }
        let rule = String(line.dropFirst("designated => ".count))
        guard rule.contains("certificate "), rule.contains("personal.windowsketch") else {
            throw UpdateError(message: "업데이트에는 고정 인증서로 서명된 앱이 필요합니다.")
        }
        return rule
    }

    static func prepare(_ candidate: UpdateCandidate, currentApp: URL) throws -> PreparedUpdate {
        let files = FileManager.default
        let current = currentApp.resolvingSymlinksInPath()
        let parent = current.deletingLastPathComponent()
        guard let requested = AppVersion(candidate.version),
              !candidate.version.hasPrefix("v"),
              candidate.tag == candidate.version || candidate.tag == "v" + candidate.version,
              let bundle = Bundle(url: current), bundle.bundleIdentifier == "personal.windowsketch",
              let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              let existing = AppVersion(version), requested > existing,
              current.pathExtension == "app", files.isWritableFile(atPath: parent.path) else {
            throw UpdateError(message: "업데이트 버전 또는 설치 폴더 권한을 확인해 주세요.")
        }
        let requirement = try signingRequirement(of: current)
        let package = files.temporaryDirectory.appendingPathComponent("SketchFrameUpdate-\(UUID().uuidString)", isDirectory: true)
        let work = parent.appendingPathComponent(".SketchFrameUpdate-\(UUID().uuidString)", isDirectory: true)
        let prepared = PreparedUpdate(current: current, staged: work.appendingPathComponent("SketchFrame.app"), work: work, package: package)
        do {
            try files.createDirectory(at: package, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            let archive = package.appendingPathComponent("update.zip")
            let checksum = package.appendingPathComponent("update.zip.sha256")
            let curl = ["--proto", "=https", "--proto-redir", "=https", "--fail", "--location", "--silent", "--show-error", "--max-time", "60", "--max-filesize"]
            try run("/usr/bin/curl", curl + ["268435456", candidate.downloadURL.absoluteString, "-o", archive.path], timeout: 65)
            try run("/usr/bin/curl", curl + ["4096", candidate.checksumURL.absoluteString, "-o", checksum.path], timeout: 65)
            try verifyChecksum(String(contentsOf: checksum, encoding: .utf8), actual: run("/usr/bin/shasum", ["-a", "256", archive.path]))
            try validateArchive(entries: run("/usr/bin/zipinfo", ["-1", archive.path]), details: run("/usr/bin/zipinfo", ["-l", archive.path]))
            let extracted = package.appendingPathComponent("extracted", isDirectory: true)
            try files.createDirectory(at: extracted, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            try run("/usr/bin/ditto", ["-xk", archive.path, extracted.path])
            let source = extracted.appendingPathComponent("SketchFrame.app")
            try validateBundle(source, version: candidate.version, requirement: requirement)
            try files.createDirectory(at: work, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            try run("/usr/bin/ditto", [source.path, prepared.staged.path])
            try validateBundle(prepared.staged, version: candidate.version, requirement: requirement)
            return prepared
        } catch {
            prepared.cleanUp()
            throw error
        }
    }
}
