# SketchFrame 0.1.0 검증과 게시 승인 대상

앱: build/SketchFrame.app

버전: 0.1.0 (빌드 1)

대상 저장소: https://github.com/mozzi-papa/SketchFrame

## 검증

- 최종 자체 검사 200개, 헬퍼 교체·복구 6개 경로, 실제 배포 ZIP·체크섬·번들·서명 검사가 통과했습니다.
- 잘못된 앱 식별자·버전·변조·인증서 없는 서명·현재 버전 재설치는 거부했습니다.
- 다른 코드 해시의 두 빌드가 같은 인증서 기반 식별 규칙으로 상호 검증을 통과했습니다.
- 이름 변경 후 손쉬운 사용 권한과 입력 연결이 유지됐고 실제 GitHub 빈 릴리스 응답을 확인했습니다.
- 설정창 세 크기의 레이아웃과 버전·모의 새 버전 안내를 확인했습니다.
- 독립 검토가 찾은 확인 후보 변경·조회 충돌 문제를 수정하고 재검토를 마쳤습니다.
- 실제 공개 릴리스 사이의 원격 다운로드·교체와 이름 변경 후의 실제 드래그 입력은 다시 수행하지 않았습니다.

## 포함 범위

이전부터 미커밋인 창 배치·단축키·QA 수정도 현재 앱을 구성하므로 함께 포함합니다. 이번 앱과 무관한 변경은 확인되지 않았습니다. 아래 목록의 현재 변경·추가 파일을 커밋 대상으로 승인받습니다.

- README.md
- Source/AppUpdater.swift
- Source/Info.plist
- Source/InteractionDiagnostics.swift
- Source/SelfCheck.swift
- Source/SettingsWindowController.swift
- Source/ShortcutRecorderView.swift
- Source/ShortcutSettings.swift
- Source/UpdateInstaller.swift
- Source/WindowAction.swift
- Source/WindowController.swift
- Source/WindowHistory.swift
- Source/WindowLayoutCalculator.swift
- Source/build.sh
- Source/main.swift
- Source/package-release.sh
- Source/setup-signing.sh
- Tests/NativeFixture.swift
- Tests/README.md
- Tests/native_check.py
- Tests/shortcut_check.py
- Tests/signing_check.sh
- Tests/update_bundle_check.swift
- Tests/update_helper_check.py
- docs/implementation-plan.md
- docs/mvp-design.md
- docs/qa/sketchframe-0.1.0-review.md
- docs/rectangle-shortcuts-design.md
- docs/releases/v0.1.0.md
- docs/superpowers/plans/2026-11-12-sketchframe-updates.md

## 제외 범위

build/ 앱·ZIP·체크섬은 Git 커밋에서 제외합니다. 임시 검사 파일·인증서·개인키·Python 캐시도 제외합니다. 첫 릴리스에는 승인받은 ZIP과 체크섬 두 파일만 별도 업로드합니다.

커밋 메시지: feat: SketchFrame 창 배치와 업데이트 기능 추가

## 실행 승인 대기 명령

```sh
git remote add origin https://github.com/mozzi-papa/SketchFrame.git
git add README.md Source Tests docs
git commit -m "feat: SketchFrame 창 배치와 업데이트 기능 추가"
git push -u origin main
gh release create v0.1.0 build/sketchframe-0.1.0-arm64.zip build/sketchframe-0.1.0-arm64.zip.sha256 --repo mozzi-papa/SketchFrame --target main --title "SketchFrame 0.1.0" --notes-file docs/releases/v0.1.0.md
```

위 명령은 아직 실행하지 않았습니다. 원격 연결, 스테이징·커밋, main 공개 업로드, v0.1.0 태그·릴리스 생성과 파일 공개 업로드를 수행합니다.
