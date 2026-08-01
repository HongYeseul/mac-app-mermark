import Foundation

/// `mermark` 명령의 알맹이. 화면 출력과 앱 실행은 호출하는 쪽이 맡고
/// 여기서는 "무엇을 할지"만 정한다. 덕분에 실제 폴더로 그대로 검증할 수 있다.
enum MermarkCommand {
    enum Outcome: Equatable {
        /// 표준 출력으로 찍고 0으로 끝난다
        case text(String)
        /// 앱에서 이 노트를 연다
        case openNote(URL)
        /// 표준 오류로 찍고 1로 끝난다
        case failure(String)
    }

    static let usage = """
    mermark — 명령줄에서 Mermark 노트 다루기

    사용법:
      mermark new <제목> [--workspace <이름>]   노트를 만들고 경로를 출력
      mermark open <제목|경로>                  앱에서 노트 열기
      mermark list [--workspace <이름>] [--tag <태그>]
                                                노트 경로 목록 (최근 수정 순)
      mermark path [--workspace <이름>]         작업 공간 경로
      mermark help                              이 도움말

    예:
      vim "$(mermark new 회의록)"
      mermark list --tag 정산 | fzf | xargs vim
      mermark open 회의록

    작업 공간 목록은 앱과 같은 파일에서 읽습니다:
      ~/.config/mermark/config.json
    """

    static func run(_ arguments: [String], workspaces: [URL]) -> Outcome {
        guard let command = arguments.first else { return .text(usage) }
        var rest = Array(arguments.dropFirst())

        switch command {
        case "help", "--help", "-h":
            return .text(usage)
        case "new", "open", "list", "path":
            break
        default:
            return .failure("모르는 명령입니다: \(command)\n\n\(usage)")
        }

        guard !workspaces.isEmpty else {
            return .failure("연결된 작업 공간이 없습니다. 앱에서 먼저 폴더를 연결하세요 (⌘O).")
        }

        var wanted: String?
        var tag: String?
        do {
            wanted = try takeOption("--workspace", from: &rest)
            tag = try takeOption("--tag", from: &rest)
        } catch let error as OptionError {
            return .failure(error.message)
        } catch {
            return .failure("\(error)")
        }

        let scope: [URL]
        if let wanted {
            guard let matched = workspace(named: wanted, in: workspaces) else {
                let names = workspaces.map(\.lastPathComponent).joined(separator: ", ")
                return .failure("그런 작업 공간이 없습니다: \(wanted)\n연결된 작업 공간: \(names)")
            }
            scope = [matched]
        } else {
            scope = workspaces
        }

        switch command {
        case "path":
            return .text(scope.map(\.path).joined(separator: "\n"))
        case "list":
            return list(in: scope, tag: tag)
        case "new":
            return create(rest.joined(separator: " "), in: scope[0])
        case "open":
            return openNote(rest.joined(separator: " "), in: scope)
        default:
            return .failure(usage)
        }
    }

    // MARK: - 명령별 동작

    private static func list(in workspaces: [URL], tag: String?) -> Outcome {
        var found = workspaces.flatMap { NoteScanner.scan($0) }
        if let tag, !tag.isEmpty {
            found = found.filter { note in
                let text = (try? String(contentsOf: note.url, encoding: .utf8)) ?? ""
                return MarkdownTags.tags(in: text).contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
            }
        }
        let paths = found.sorted { $0.modifiedAt > $1.modifiedAt }.map(\.url.path)
        return .text(paths.joined(separator: "\n"))
    }

    private static func create(_ title: String, in workspace: URL) -> Outcome {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure("제목이 필요합니다: mermark new <제목>") }

        let url = NoteNaming.uniqueURL(for: NoteNaming.fileTitle(from: trimmed), in: workspace)
        do {
            // 첫 줄을 제목으로 둬야 앱의 "첫 줄 = 파일명" 규칙과 어긋나지 않는다
            try "# \(trimmed)\n".write(to: url, atomically: true, encoding: .utf8)
        } catch {
            return .failure("노트를 만들지 못했습니다: \(error.localizedDescription)")
        }
        return .text(url.path)
    }

    private static func openNote(_ target: String, in workspaces: [URL]) -> Outcome {
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure("열 노트가 필요합니다: mermark open <제목|경로>") }

        // 경로를 그대로 준 경우 (mermark list의 출력을 파이프로 넘기는 흐름)
        let asPath = URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath).standardizedFileURL
        if FileManager.default.fileExists(atPath: asPath.path) {
            return .openNote(asPath)
        }

        let matches = workspaces.flatMap { NoteScanner.scan($0) }.filter {
            $0.url.deletingPathExtension().lastPathComponent.caseInsensitiveCompare(trimmed) == .orderedSame
        }
        switch matches.count {
        case 0:
            return .failure("그런 노트가 없습니다: \(trimmed)")
        case 1:
            return .openNote(matches[0].url)
        default:
            let paths = matches.map { "  " + $0.url.path }.joined(separator: "\n")
            return .failure("같은 제목이 여럿입니다. 경로로 지정하세요:\n\(paths)")
        }
    }

    // MARK: - 인자 처리

    private struct OptionError: Error {
        let message: String
    }

    /// `--이름 값`을 찾아 빼낸다. 남은 인자는 제목이 된다.
    private static func takeOption(_ name: String, from arguments: inout [String]) throws -> String? {
        guard let index = arguments.firstIndex(of: name) else { return nil }
        guard index + 1 < arguments.count else {
            throw OptionError(message: "\(name) 뒤에 값이 필요합니다.")
        }
        let value = arguments[index + 1]
        arguments.removeSubrange(index...(index + 1))
        return value
    }

    /// 폴더 이름으로도, 전체 경로로도 고를 수 있다
    private static func workspace(named wanted: String, in workspaces: [URL]) -> URL? {
        let expanded = URL(fileURLWithPath: (wanted as NSString).expandingTildeInPath).standardizedFileURL.path
        return workspaces.first { $0.lastPathComponent.caseInsensitiveCompare(wanted) == .orderedSame }
            ?? workspaces.first { $0.path == expanded }
    }
}
