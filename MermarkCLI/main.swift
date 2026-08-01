import AppKit

// mermark 명령. 실제 동작은 MermarkCommand에 있고 여기서는 출력과 앱 실행만 맡는다.

let outcome = MermarkCommand.run(
    Array(CommandLine.arguments.dropFirst()),
    workspaces: WorkspaceConfig.load()
)

switch outcome {
case .text(let message):
    if !message.isEmpty { print(message) }
    exit(0)

case .openNote(let url):
    guard let scheme = MermarkURL.open(url) else {
        FileHandle.standardError.write(Data("주소를 만들지 못했습니다: \(url.path)\n".utf8))
        exit(1)
    }
    // 앱이 꺼져 있으면 LaunchServices가 띄운 뒤 주소를 전달한다
    NSWorkspace.shared.open(scheme)
    exit(0)

case .failure(let message):
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}
