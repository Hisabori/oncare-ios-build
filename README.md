# OnCare iOS build

Public build snapshot of OnCare 3.9.0, build 12. Includes the iPhone app, WidgetKit extension, unit/UI tests and a manually triggered unsigned IPA workflow.

The snapshot contains source code and synthetic test fixtures only. Original Git history, Android code, private documents, user health records, signing certificates, account credentials and previous build outputs are not included.

## Build

Open Actions → Build OnCare unsigned IPA → Run workflow. The standard macOS runner compiles the app and widget, runs the tests, then packages the IPA. The workflow has contents-read permission and uses actions pinned to full commit SHAs. No Apple account or signing secret is used.

Download OnCare-unsigned-ipa after a successful run. Sign and install the IPA on your own device using AltStore or SideStore. No new IPA is published when tests fail.

## App features

Personal health journal, sleep routines, workout timer, medications, articles, widgets and shortcuts. QR pairing is Android-to-iPhone on the same Wi-Fi. Personal summary sharing offers selected categories, 7/30-day ranges and a preview. Health notes, medication details and pairing credentials are omitted from the summary.

The app is a personal journal and does not provide diagnosis or treatment. Camera scans and actual device-to-device transfer require physical-device verification.

## 3.9 건강 데이터 확장
지원 Android가 제공하고 사용자가 허용한 건강·운동 42종 및 의료 문서 12종을 같은 Wi-Fi로 전달받는 보관함, 원본 수면 4단계 시간표, NHS 아티클 10편을 포함합니다. 문서의 실제 진료 날짜는 FHIR 원문에서 확인하며 처방이나 복용 일정을 자동 변경하지 않습니다. 확장 자료가 있는 iPhone 백업은 버전 4이며 이전 앱과 Android 일반 일지 백업 화면에서는 가져올 수 없습니다. 이 공개 저장소에는 실제 건강 기록이나 Android 서명 키가 없습니다.
