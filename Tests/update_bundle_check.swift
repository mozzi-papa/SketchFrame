import Foundation

let current = URL(fileURLWithPath: CommandLine.arguments[1])
let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("SketchFrame-bundle-check-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
defer { try? FileManager.default.removeItem(at: temporary) }
let version = Bundle(url: current)!.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String
let requirement = try UpdateInstaller.signingRequirement(of: current)
try UpdateInstaller.validateBundle(current, version: version, requirement: requirement)
print("PASS: 현재 인증서 기반 서명과 정상 번들")
func rejected(_ label: String, _ operation: () throws -> Void) {
    do { try operation(); fatalError("거부하지 못했습니다: \(label)") }
    catch { print("PASS: \(label)") }
}
rejected("잘못된 버전 거부") { try UpdateInstaller.validateBundle(current, version: "999.0.0", requirement: requirement) }
for scenario in ["wrong-id", "tampered", "adhoc"] {
    let fixture = temporary.appendingPathComponent(scenario + ".app")
    try UpdateInstaller.run("/usr/bin/ditto", [current.path, fixture.path])
    if scenario == "wrong-id" {
        let info = fixture.appendingPathComponent("Contents/Info.plist")
        var plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: info), format: nil) as! [String: Any]
        plist["CFBundleIdentifier"] = "other.application"
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: info)
    } else if scenario == "tampered" {
        let executable = fixture.appendingPathComponent("Contents/MacOS/WindowSketch")
        let handle = try FileHandle(forWritingTo: executable)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("tampered".utf8))
        try handle.close()
    } else {
        try UpdateInstaller.run("/usr/bin/codesign", ["--force", "--sign", "-", "--identifier", "personal.windowsketch", fixture.path])
    }
    rejected(scenario + " 거부") { try UpdateInstaller.validateBundle(fixture, version: version, requirement: requirement) }
}
let archive = URL(fileURLWithPath: CommandLine.arguments[2])
try UpdateInstaller.validateArchive(entries: UpdateInstaller.run("/usr/bin/zipinfo", ["-1", archive.path]),
                                    details: UpdateInstaller.run("/usr/bin/zipinfo", ["-l", archive.path]))
let extracted = temporary.appendingPathComponent("extracted")
try UpdateInstaller.run("/usr/bin/ditto", ["-xk", archive.path, extracted.path])
try UpdateInstaller.validateBundle(extracted.appendingPathComponent("SketchFrame.app"), version: version, requirement: requirement)
try UpdateInstaller.verifyChecksum(String(contentsOfFile: archive.path + ".sha256", encoding: .utf8),
                                   actual: UpdateInstaller.run("/usr/bin/shasum", ["-a", "256", archive.path]))
print("PASS: 실제 배포 ZIP 경로·크기·체크섬·추출 후 서명")
rejected("현재 버전으로 재설치 거부") {
    _ = try UpdateInstaller.prepare(UpdateCandidate(version: version, tag: "v" + version), currentApp: current)
}
rejected("업데이트 작업 시간 제한") { _ = try UpdateInstaller.run("/bin/sleep", ["10"], timeout: 0.05) }
