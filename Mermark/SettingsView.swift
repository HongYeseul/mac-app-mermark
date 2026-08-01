import SwiftUI

struct SettingsView: View {
    @AppStorage(ExportOptions.scaleKey) private var scale = 2
    @AppStorage(ExportOptions.themeKey) private var theme = ExportTheme.light
    @AppStorage(ExportOptions.backgroundKey) private var background = ExportBackground.transparent

    @AppStorage(Theme.storageKey) private var themeName = Theme.mint.rawValue

    @State private var installedPath: String?
    @State private var manualCommand: String?
    @State private var cliInstalled = CLIInstaller.bundledTool.map { CLIInstaller.isInstalled(tool: $0) } ?? false

    var body: some View {
        Form {
            Picker("메인 색상", selection: themeBinding) {
                ForEach(Theme.allCases) { theme in
                    HStack(spacing: 7) {
                        Circle()
                            .fill(Color(nsColor: theme.logo.nsColor))
                            .frame(width: 12, height: 12)
                        Text(theme.label)
                    }
                    .tag(theme)
                }
            }
            Text("에디터·프리뷰·사이드바와 Dock 아이콘에 함께 적용됩니다. Finder에 보이는 아이콘은 앱에 들어 있어 바뀌지 않습니다.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Divider()

            Picker("해상도", selection: $scale) {
                Text("1x").tag(1)
                Text("2x").tag(2)
                Text("3x").tag(3)
            }
            .pickerStyle(.segmented)

            Picker("테마", selection: $theme) {
                ForEach(ExportTheme.allCases) { theme in
                    Text(theme.label).tag(theme)
                }
            }

            Picker("배경", selection: $background) {
                ForEach(ExportBackground.allCases) { background in
                    Text(background.label).tag(background)
                }
            }

            Text("PNG 내보내기에 적용됩니다. SVG는 배경 없이 테마만 반영합니다.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Divider()

            commandLineSection
        }
        .formStyle(.grouped)
        .frame(width: 380)
    }

    @ViewBuilder
    private var commandLineSection: some View {
        HStack {
            Text("명령줄 도구")
            Spacer()
            Button(cliInstalled ? "다시 설치" : "설치") { installCLI() }
                .disabled(CLIInstaller.bundledTool == nil)
        }
        if let manualCommand {
            Text("권한이 없어 직접 실행해야 합니다:")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(manualCommand)
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
        } else if let installedPath {
            Text("\(installedPath) 에 걸었습니다. `mermark help`로 확인하세요.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            Text("터미널에서 `mermark new 회의록`처럼 쓸 수 있게 /usr/local/bin에 링크를 만듭니다.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func installCLI() {
        guard let tool = CLIInstaller.bundledTool else { return }
        switch CLIInstaller.install(tool: tool) {
        case .installed(let path):
            installedPath = path
            manualCommand = nil
            cliInstalled = true
        case .needsManualStep(let command):
            manualCommand = command
            installedPath = nil
        }
    }

    private var themeBinding: Binding<Theme> {
        Binding(
            get: { Theme(rawValue: themeName) ?? .mint },
            set: { Brand.select($0) }
        )
    }
}
