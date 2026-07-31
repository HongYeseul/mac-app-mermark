# Third Party Notices

Mermark는 완전한 오프라인 동작을 위해 아래 자바스크립트 라이브러리를 `Mermark/Resources/`에
정적 파일로 번들합니다. 각 라이브러리의 라이선스와 저작권은 원저작자에게 있습니다.

| 라이브러리 | 버전 | 라이선스 | 용도 |
|---|---|---|---|
| [markdown-it](https://github.com/markdown-it/markdown-it) | 14.1.0 | MIT | 마크다운 → HTML 렌더링, 소스 줄 매핑 |
| [mermaid](https://github.com/mermaid-js/mermaid) | 11.x | MIT | 다이어그램 렌더링 및 이미지 내보내기 |
| [highlight.js](https://github.com/highlightjs/highlight.js) | 11.11.1 | BSD-3-Clause | 코드 블록 문법 강조 |

highlight.js의 `github.min.css`, `github-dark.min.css` 테마 파일도 같은 BSD-3-Clause 라이선스를 따릅니다.

번들 파일을 갱신하는 방법은 [README](README.md#번들-라이브러리-갱신)를 참고하세요.
