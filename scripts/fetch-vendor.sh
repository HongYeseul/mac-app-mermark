#!/bin/bash
# 프리뷰가 완전 오프라인으로 동작하도록 자바스크립트/CSS/폰트를 Resources에 내려받는다.
#
# Xcode의 synchronized folder는 리소스를 번들 Resources 루트에 평면으로 복사한다.
# 그래서 KaTeX 폰트도 하위 폴더 없이 평면으로 두고, CSS의 "fonts/" 참조를 지운다.
set -euo pipefail

MARKDOWN_IT_VERSION="14.1.0"
MERMAID_VERSION="11"
HIGHLIGHT_VERSION="11.11.1"
KATEX_VERSION="0.18.1"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESOURCES="$ROOT/Mermark/Resources"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "▶ markdown-it $MARKDOWN_IT_VERSION"
curl -fsSL -o "$RESOURCES/markdown-it.min.js" \
    "https://cdn.jsdelivr.net/npm/markdown-it@$MARKDOWN_IT_VERSION/dist/markdown-it.min.js"

echo "▶ mermaid $MERMAID_VERSION"
curl -fsSL -o "$RESOURCES/mermaid.min.js" \
    "https://cdn.jsdelivr.net/npm/mermaid@$MERMAID_VERSION/dist/mermaid.min.js"

echo "▶ highlight.js $HIGHLIGHT_VERSION"
curl -fsSL -o "$RESOURCES/highlight.min.js" \
    "https://cdn.jsdelivr.net/gh/highlightjs/cdn-release@$HIGHLIGHT_VERSION/build/highlight.min.js"
curl -fsSL -o "$RESOURCES/github.min.css" \
    "https://cdn.jsdelivr.net/gh/highlightjs/cdn-release@$HIGHLIGHT_VERSION/build/styles/github.min.css"
curl -fsSL -o "$RESOURCES/github-dark.min.css" \
    "https://cdn.jsdelivr.net/gh/highlightjs/cdn-release@$HIGHLIGHT_VERSION/build/styles/github-dark.min.css"

echo "▶ KaTeX $KATEX_VERSION (woff2 폰트만)"
curl -fsSL -o "$WORK/katex.tgz" \
    "https://registry.npmjs.org/katex/-/katex-$KATEX_VERSION.tgz"
tar xzf "$WORK/katex.tgz" -C "$WORK" package/dist
cp "$WORK/package/dist/katex.min.js" "$RESOURCES/katex.min.js"
rm -f "$RESOURCES"/KaTeX_*.woff2
cp "$WORK"/package/dist/fonts/*.woff2 "$RESOURCES/"

# 폰트를 평면으로 두므로 "fonts/" 경로를 지우고, 번들하지 않는 woff/ttf 대체는 제거한다
sed -e 's|url(fonts/|url(|g' \
    -e 's|,url([^)]*\.woff) format("woff")||g' \
    -e 's|,url([^)]*\.ttf) format("truetype")||g' \
    "$WORK/package/dist/katex.min.css" > "$RESOURCES/katex.min.css"

echo "▶ markdown-it-texmath (KaTeX ↔ markdown-it 연결)"
TEXMATH_TARBALL="$(curl -fsSL https://registry.npmjs.org/markdown-it-texmath/latest \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["dist"]["tarball"])')"
curl -fsSL -o "$WORK/texmath.tgz" "$TEXMATH_TARBALL"
tar xzf "$WORK/texmath.tgz" -C "$WORK" package/texmath.js
cp "$WORK/package/texmath.js" "$RESOURCES/texmath.js"

echo
echo "완료. Resources 용량:"
du -sh "$RESOURCES"
echo "KaTeX 폰트: $(ls "$RESOURCES"/KaTeX_*.woff2 | wc -l | tr -d ' ')개"
