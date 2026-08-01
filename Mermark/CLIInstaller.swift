import Foundation

/// 앱 번들 안의 `mermark` 실행 파일을 PATH에 걸어 준다.
///
/// 복사가 아니라 심볼릭 링크를 만든다. 앱을 새로 빌드해도 링크가 그대로 새 실행 파일을 가리키므로
/// 버전이 어긋나지 않는다.
enum CLIInstaller {
    enum Result: Equatable {
        case installed(path: String)
        /// 링크를 만들 수 없을 때. 직접 실행할 명령을 함께 알려 준다.
        case needsManualStep(command: String)
    }

    static let defaultDestination = URL(fileURLWithPath: "/usr/local/bin", isDirectory: true)

    /// 번들 안의 실행 파일 위치. 개발 중 테스트 하네스에서는 없을 수 있다.
    ///
    /// Contents/MacOS가 아니라 Contents/Helpers에 둔다. 대소문자를 구분하지 않는 파일시스템에서는
    /// 앱 바이너리 "Mermark"와 도구 "mermark"가 같은 이름이라 서로를 덮어쓴다.
    static var bundledTool: URL? {
        let url = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/mermark")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    /// 이미 걸려 있고 이 앱을 가리키는지
    static func isInstalled(tool: URL, at destination: URL = defaultDestination) -> Bool {
        let link = destination.appendingPathComponent("mermark")
        guard let resolved = try? FileManager.default.destinationOfSymbolicLink(atPath: link.path) else {
            return false
        }
        return URL(fileURLWithPath: resolved).standardizedFileURL == tool.standardizedFileURL
    }

    static func install(tool: URL, at destination: URL = defaultDestination) -> Result {
        let fm = FileManager.default
        let link = destination.appendingPathComponent("mermark")
        let manual = "sudo mkdir -p \(destination.path) && sudo ln -sf '\(tool.path)' \(link.path)"

        guard fm.isWritableFile(atPath: destination.path) else {
            return .needsManualStep(command: manual)
        }
        // 이전 링크가 남아 있으면 갈아 끼운다
        if (try? fm.destinationOfSymbolicLink(atPath: link.path)) != nil || fm.fileExists(atPath: link.path) {
            guard (try? fm.removeItem(at: link)) != nil else {
                return .needsManualStep(command: manual)
            }
        }
        do {
            try fm.createSymbolicLink(at: link, withDestinationURL: tool)
        } catch {
            return .needsManualStep(command: manual)
        }
        return .installed(path: link.path)
    }
}
