# 마크다운 뷰어/에디터 + Mermaid 이미지 내보내기 — 프로젝트 방향 제안

> 전제: **SwiftUI 네이티브 · macOS · 개인용 도구**
> 킬러 기능: **Mermaid 다이어그램을 PNG(고해상도)/SVG/클립보드로 내보내기** — 기존 마크다운 앱에 없는 기능

---

## 1. 제품 컨셉 한 줄 정리

"가볍게 뜨고 + 폴더 단위로 관리하며 + **다이어그램을 바로 이미지로 뽑아 쓰는** 마크다운 메모장"

- 메모를 Mac 메모장처럼 즉시 추가 (Cmd+N → 바로 타이핑, 자동 저장, 첫 줄 = 제목)
- 저장은 전부 **평범한 .md 파일** (특정 폴더 = 노트 폴더). 락인 없음, 다른 마크다운 앱과 같은 파일을 그대로 공유 가능
- 미리보기에서 Mermaid 블록 위에 마우스를 올리면 내보내기 버튼이 뜨는 것이 핵심 UX

## 2. 전체 아키텍처

```
┌─────────────────────────────────────────────┐
│ SwiftUI App (NavigationSplitView)           │
│                                             │
│ ┌──────────┐ ┌────────────┐ ┌────────────┐  │
│ │ Sidebar  │ │ Editor     │ │ Preview    │  │
│ │ 노트 목록 │ │ NSTextView │ │ WKWebView  │  │
│ │ 검색/TOC │ │ (AppKit    │ │ markdown-it│  │
│ │          │ │  래핑)     │ │ +mermaid.js│  │
│ └──────────┘ └────────────┘ └────────────┘  │
│        ▲            │              ▲        │
│        │            ▼              │        │
│   FSEvents      .md 파일 (노트 폴더)         │
│   (외부 변경 감지)                           │
└─────────────────────────────────────────────┘
```

### 왜 "에디터는 네이티브, 미리보기는 WKWebView" 하이브리드인가

- **Mermaid는 어차피 JS 라이브러리**라서 순수 네이티브 렌더링이 사실상 불가능 → 미리보기는 WKWebView가 정답에 가깝습니다. KaTeX(수식), highlight.js(코드 하이라이트)도 같은 WebView 안에서 해결됩니다.
- 에디터까지 WebView(CodeMirror)로 하면 "가볍고 빠른" 네이티브 느낌이 죽습니다. `NSTextView`를 `NSViewRepresentable`로 감싸면 한글 입력(IME), 시스템 단축키, 드래그&드롭이 전부 공짜로 따라옵니다.
- 렌더링용 HTML 템플릿 하나에 markdown-it + mermaid + KaTeX를 **로컬 번들**로 넣으면 완전 오프라인 동작이 됩니다.

### 뷰어 ↔ 에디터 전환

- 모드: ① 뷰어만 ② 에디터만 ③ 분할(스크롤 동기화)
- 같은 화면에서 즉시 전환하려면 **전환 시 스크롤 위치를 보존**하는 게 관건입니다. 에디터 쪽은 보이는 첫 줄 번호, 프리뷰 쪽은 각 블록에 `data-line` 속성(markdown-it의 source line mapping)을 심어서 서로 매핑하면 됩니다. 분할 모드 스크롤 동기화도 같은 매핑을 재사용합니다.

## 3. 킬러 기능: Mermaid 이미지 내보내기 설계

세 가지 방식이 있고, **b안을 메인으로, SVG는 a안으로** 조합하는 걸 추천합니다.

### a. SVG 추출 (SVG 내보내기용 — 간단·확실)

Mermaid는 렌더링 결과가 이미 SVG입니다. JS에서 해당 `<svg>`의 `outerHTML`을 꺼내 `WKScriptMessageHandler`로 Swift에 넘기면 끝.

- 주의 1: 텍스트가 CSS에 의존하므로 **스타일을 SVG 안에 인라인**해야 다른 앱에서 열어도 안 깨집니다 (mermaid는 기본적으로 `<style>`을 svg 안에 넣어줘서 대부분 OK, 폰트만 체크).
- 주의 2: mermaid 설정에서 `htmlLabels: false`를 주면 라벨이 `<foreignObject>`(HTML) 대신 순수 SVG `<text>`로 나와서 **외부 호환성이 크게 좋아집니다.** 내보내기용 렌더링에서는 이 옵션을 켜는 걸 권장.

### b. 오프스크린 WKWebView 스냅샷 (PNG 내보내기용 — 품질 최상)

canvas로 SVG를 그려 PNG를 만드는 흔한 방법은 foreignObject·폰트·CORS 문제로 지저분합니다. macOS에서는 더 깔끔한 길이 있습니다:

1. 화면에 안 보이는 **내보내기 전용 WKWebView**를 만들고, 해당 Mermaid 코드만 담은 미니 HTML을 로드
2. 렌더 완료 후 SVG의 실제 크기를 JS로 측정 → WebView 프레임을 그 크기로 리사이즈
3. `WKWebView.takeSnapshot(with:)` 호출 — `snapshotWidth`를 (원본 폭 × 스케일)로 지정하면 **2x/3x 고해상도 PNG**가 그대로 나옵니다
4. 투명 배경: `webView.setValue(false, forKey: "drawsBackground")` + 페이지 배경 transparent

이 방식의 장점: 화면 프리뷰와 100% 동일한 렌더링 품질, 폰트 문제 없음, 다크/라이트 테마를 내보내기 시점에 강제 지정 가능 (프리뷰는 다크인데 문서용으론 라이트로 뽑기 등).

### c. 클립보드 복사

- PNG: 스냅샷 `NSImage` → `NSPasteboard`에 `.tiff`/`.png` 타입으로 쓰기 → Keynote·Slack·노션에 바로 붙여넣기
- SVG: 문자열로 복사 + 파일 프로미스 제공(선택)

### 내보내기 UX 제안

- 프리뷰의 각 Mermaid 블록에 **호버 툴바**: `PNG 복사 · PNG 저장 · SVG 저장 · ⚙︎`
- ⚙︎ 팝오버: 스케일(1x/2x/3x), 배경(투명/흰색/현재 테마), 테마(라이트/다크/현재)
- 우클릭 컨텍스트 메뉴에도 동일 항목
- 보너스: **"모든 다이어그램 일괄 내보내기"** — 문서 안 Mermaid가 여러 개일 때 `문서명-1.png, 문서명-2.png`로 한 번에 저장. 이건 다른 앱에도 잘 없는 차별점입니다.

## 4. 메모장식 빠른 추가

- **Cmd+N**: 사이드바에 즉시 새 노트, 제목 입력 없이 바로 본문 타이핑. 파일명은 첫 줄에서 자동 생성(중복 시 suffix), 첫 줄 수정 시 파일명 rename — Apple 메모 방식
- **자동 저장**: 디바운스(0.5초) + 포커스 아웃 시 저장. 저장 버튼·다이얼로그 없음
- **메뉴바 퀵 캡처** (Phase 2): SwiftUI `MenuBarExtra`로 메뉴바 아이콘 → 팝오버에 텍스트 필드 → Enter 하면 노트 폴더에 `2026-07-31 1432.md`로 저장. 메인 창 안 띄우고 메모 가능
- **전역 단축키** (Phase 2): 어디서든 Cmd+Shift+N으로 퀵 캡처 (개인용이면 `NSEvent.addGlobalMonitor` + 손쉬운 사용 권한으로 충분, KeyboardShortcuts 패키지 쓰면 더 편함)

## 5. 파일/노트 폴더 레이어

- 시작 시 폴더 선택(노트 폴더) → security-scoped bookmark로 재실행 후에도 접근 유지 *(참고: 현재 프로젝트는 샌드박스 미사용이라 일반 경로 저장으로 충분)*
- `FSEventStream`으로 외부 변경 감지 → 열려 있는 노트가 밖에서 바뀌면 자동 리로드
- 상대 경로 `.md` 링크 + 앵커(`#섹션`) 네비게이션: WebView의 `decidePolicyFor`에서 가로채 앱 내 이동으로 처리
- 노트 폴더를 iCloud Drive 폴더로 잡으면 동기화는 공짜 (앱이 따로 할 일 없음)

## 6. 단계별 로드맵

### Phase 1 — MVP (핵심 루프 완성)

1. 노트 폴더 열기 + 사이드바 노트 목록 + 파일 열기/저장
2. 에디터(NSTextView, 마크다운 신택스 하이라이트는 일단 없이)
3. WKWebView 프리뷰: GFM + 코드 하이라이트 + Mermaid + KaTeX (로컬 번들)
4. **Mermaid 내보내기: PNG 저장/복사(2x) + SVG 저장** ← 여기까지가 "이 앱을 만든 이유"

### Phase 2 — 데일리 드라이버화

5. 뷰어↔에디터 즉시 전환 + 분할 모드 스크롤 동기화
6. Cmd+N 빠른 메모 + 자동 저장 + 첫 줄=제목
7. 전문 검색(노트 목록 필터), TOC 사이드바
8. 내보내기 옵션 UI(스케일/배경/테마), 일괄 내보내기

### Phase 3 — 완성도

9. 메뉴바 퀵 캡처 + 전역 단축키
10. 에디터 신택스 하이라이트, 라이트/다크/글자 크기 설정
11. 문서 전체 PDF 내보내기, 프론트매터 표시
12. (원하면) 태그

## 7. 기술 스택 요약

| 영역 | 선택 | 비고 |
|---|---|---|
| UI | SwiftUI + NavigationSplitView | macOS 14+ 타깃 추천 |
| 에디터 | NSTextView (NSViewRepresentable) | IME/단축키/성능 |
| 마크다운 렌더 | markdown-it (WebView 내) | source line mapping 지원 |
| 다이어그램 | mermaid.js 로컬 번들 | `htmlLabels:false`는 내보내기 시 |
| 수식 | KaTeX 로컬 번들 | |
| 코드 하이라이트 | highlight.js | |
| PNG 내보내기 | 오프스크린 WKWebView + takeSnapshot | 스케일·투명배경 지원 |
| SVG 내보내기 | SVG outerHTML 추출 + 스타일 인라인 | |
| 파일 감지 | FSEventStream | |
| 전역 단축키 | KeyboardShortcuts (sindresorhus) | Phase 3 |

## 8. 미리 알아두면 좋은 함정들

- **Mermaid 렌더는 비동기**: `mermaid.run()` 완료 후에 스냅샷을 찍어야 합니다. JS → Swift 콜백으로 "렌더 완료" 신호를 받고 진행할 것.
- **긴 다이어그램**: 시퀀스 다이어그램이 세로로 매우 길어지면 스냅샷 크기도 커짐 → 최대 픽셀 제한(예: 8192px)과 스케일 자동 하향 로직 필요.
- **폰트**: 시스템 폰트(SF Pro/Apple SD 산돌고딕)로 렌더하면 SVG를 다른 OS에서 열 때 다르게 보일 수 있음 → SVG 내보내기 시 `font-family`에 폴백 체인 명시.
- **한글 파일명/제목**: 첫 줄=파일명 자동화 시 `/:` 등 금지 문자 치환 필수.
- **WKWebView 로컬 리소스**: `loadFileURL(_:allowingReadAccessTo:)`로 번들 디렉터리 접근 허용해야 JS/CSS가 로드됩니다.
- **노트 기준 상대경로 이미지** *(검토 시 추가)*: preview.html은 앱 번들에서 로드되므로 `![](./img.png)` 같은 노트 파일 기준 상대경로 이미지가 그대로는 안 보입니다. `WKURLSchemeHandler`(커스텀 스킴)로 노트 폴더 파일을 서빙하거나 렌더 시 절대 `file://` URL로 치환 필요.
- **data-line 매핑** *(검토 시 추가)*: markdown-it의 source line mapping은 내장 옵션이 아니라 `token.map`을 이용해 블록 렌더러 룰에 `data-line`을 심는 커스텀 룰이 필요합니다(코드 몇 줄 수준).

---

### 다음 단계 제안

1. ~~Xcode 프로젝트 뼈대 + "md 파일 하나 열어서 Mermaid 포함 프리뷰" 스파이크~~ ✅ (2026-07-31 초기 세팅 완료)
2. 그 위에 takeSnapshot 기반 PNG 내보내기 스파이크 (여기서 품질 확인이 되면 나머지는 순탄합니다)
3. Phase 1 나머지 채우기
