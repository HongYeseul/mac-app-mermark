import SwiftUI

struct SettingsView: View {
    @AppStorage(ExportOptions.scaleKey) private var scale = 2
    @AppStorage(ExportOptions.themeKey) private var theme = ExportTheme.light
    @AppStorage(ExportOptions.backgroundKey) private var background = ExportBackground.transparent

    var body: some View {
        Form {
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
        }
        .formStyle(.grouped)
        .frame(width: 380)
    }
}
