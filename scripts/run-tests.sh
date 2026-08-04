#!/bin/bash
# 앱 소스를 그대로 컴파일해 검증 하네스를 돌린다.
# 별도 테스트 타깃 없이 swiftc로 링크하므로 Xcode 없이 커맨드라인에서도 실행된다.
#
# 스위트마다 필요한 파일을 골라 적지 않고 앱 소스를 통째로 링크한다.
# (의존 파일이 늘 때마다 목록을 고치는 걸 잊어 컴파일이 조용히 실패하곤 했다)
# 진입점이 겹치므로 MermarkApp.swift만 뺀다.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT

export MERMARK_RESOURCES="$ROOT/Mermark/Resources"

APP_SOURCES=()
while IFS= read -r -d '' file; do
    APP_SOURCES+=("$file")
done < <(find "$ROOT/Mermark" "$ROOT/Shared" -name '*.swift' ! -name 'MermarkApp.swift' -print0)

# CLI 검증은 실제 실행 파일을 자식 프로세스로 돌린다. 앱 소스와 같은 컴파일러로 여기서 빌드한다.
SHARED_SOURCES=()
while IFS= read -r -d '' file; do
    SHARED_SOURCES+=("$file")
done < <(find "$ROOT/Shared" -name '*.swift' -print0)
if swiftc -o "$BUILD_DIR/mermark" "${SHARED_SOURCES[@]}" "$ROOT/MermarkCLI/main.swift"; then
    export MERMARK_CLI_BIN="$BUILD_DIR/mermark"
else
    echo "mermark 실행 파일 빌드 실패"
    exit 1
fi

failed=0

run_suite() {
    local name="$1"
    local main="$2"
    echo "▶ $name"
    if ! swiftc -o "$BUILD_DIR/$name" "${APP_SOURCES[@]}" "$main"; then
        echo "FAILURES: $name 컴파일 실패"
        failed=1
        return
    fi
    if ! "$BUILD_DIR/$name"; then
        failed=1
    fi
    echo
}

run_suite note-store       "$ROOT/Tests/NoteStoreTests/main.swift"
run_suite task-list        "$ROOT/Tests/TaskListTests/main.swift"
run_suite tags             "$ROOT/Tests/TagTests/main.swift"
run_suite quick-capture    "$ROOT/Tests/QuickCaptureTests/main.swift"
run_suite editor-scroll    "$ROOT/Tests/EditorTests/main.swift"
run_suite syntax-highlight "$ROOT/Tests/SyntaxTests/main.swift"
run_suite outline          "$ROOT/Tests/OutlineTests/main.swift"
run_suite mermaid-blocks   "$ROOT/Tests/MermaidBlocksTests/main.swift"
run_suite export-options   "$ROOT/Tests/ExportTests/main.swift"
run_suite batch-export     "$ROOT/Tests/BatchExportTests/main.swift"
run_suite image-resources  "$ROOT/Tests/ImageResourceTests/main.swift"
run_suite link-routing     "$ROOT/Tests/LinkRoutingTests/main.swift"
run_suite document-export  "$ROOT/Tests/DocumentExportTests/main.swift"
run_suite math             "$ROOT/Tests/MathTests/main.swift"
run_suite theme            "$ROOT/Tests/ThemeTests/main.swift"
run_suite view-mode        "$ROOT/Tests/ViewModeTests/main.swift"
run_suite cli              "$ROOT/Tests/CLITests/main.swift"
run_suite tabs             "$ROOT/Tests/TabTests/main.swift"
run_suite layout           "$ROOT/Tests/LayoutTests/main.swift"
run_suite trash            "$ROOT/Tests/TrashTests/main.swift"
run_suite workspace-menu   "$ROOT/Tests/WorkspaceMenuTests/main.swift"

if [ "$failed" -eq 0 ]; then
    echo "모든 검증 통과"
else
    echo "실패한 검증이 있습니다"
fi
exit "$failed"
