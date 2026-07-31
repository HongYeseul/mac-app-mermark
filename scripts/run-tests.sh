#!/bin/bash
# 앱 소스를 그대로 컴파일해 검증 하네스를 돌린다.
# 별도 테스트 타깃 없이 swiftc로 링크하므로 Xcode 없이 커맨드라인에서도 실행된다.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT

failed=0

run_suite() {
    local name="$1"
    shift
    echo "▶ $name"
    if ! swiftc -o "$BUILD_DIR/$name" "$@"; then
        echo "✗ $name: 컴파일 실패"
        failed=1
        return
    fi
    if ! "$BUILD_DIR/$name"; then
        failed=1
    fi
    echo
}

run_suite note-store \
    "$ROOT/Mermark/Notes/NoteStore.swift" \
    "$ROOT/Tests/NoteStoreTests/main.swift"

run_suite editor-scroll \
    "$ROOT/Mermark/Editor/LineMath.swift" \
    "$ROOT/Mermark/Editor/EditorController.swift" \
    "$ROOT/Tests/EditorTests/main.swift"

run_suite view-mode \
    "$ROOT/Tests/ViewModeTests/main.swift"

if [ "$failed" -eq 0 ]; then
    echo "모든 검증 통과"
else
    echo "실패한 검증이 있습니다"
fi
exit "$failed"
