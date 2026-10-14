# OnCare iOS 3.17.0 · build 28

Medication photo text recognition with explicit review, local lifestyle questionnaire, app appearance/navigation preferences, and stable app link entry. All 87 checks passed (76 unit, 10 app UI, 1 system widget gallery). ARM64 app and widget packaging verified. IPA needs AltStore/SideStore signing. Actual medication bag recognition quality and physical device sync need separate device checks.

Verified build: https://github.com/Hisabori/oncare-ios-build/actions/runs/38533059566
Tested source: dfd6bbb76c7723a5933bd7dbc9324eeae2e04551
This repository includes reviewed iOS source only; no Android signing keys, local configuration, or personal health data.

---

# OnCare iOS 3.12.0 · build 21

Health records now support persistent favorites, whole-calendar-day 7/30-day filtering, and source/device search. 84 automated checks passed: 73 unit, 10 app UI, and 1 system widget gallery. ARM64 app and widget packaging validated. IPA requires AltStore/SideStore signing.

Verified build: https://github.com/Hisabori/oncare-ios-build/actions/runs/38411794718 (source 88c32d7eef0634be096c190d515a476eb5c0cc2d). Android, signing keys, local configuration and personal health data are excluded. Physical device sync is not covered by simulator tests.

---

## 3.10 최신 배포 검증

iOS 3.10.0 · 빌드 19입니다. 빠른 기록·고정 항목 편집·실제 기록의 주간 하이라이트를 추가했습니다. [빌드 성공](https://github.com/Hisabori/oncare-ios-build/actions/runs/38377330094): 71개 단위 검사·10개 앱 화면 검사·1개 시스템 위젯 목록 검사, 총 82개가 통과했습니다. unsigned IPA는 AltStore/SideStore 서명이 필요합니다. 아래는 이전 배포 기록입니다.

# OnCare iOS · 3.9.0 / 빌드 13

검토된 iOS 앱·위젯·공통 코드·테스트·이미지·수동 빌드 설정 58개 파일을 포함하는 공개 빌드 전용 저장소입니다. 원본 Hisabori/example 저장소는 비공개로 유지합니다. 실제 건강 데이터, Android 서명 키, 개발자 인증서 또는 기존 비공개 Git 이력은 포함하지 않습니다. 테스트 자료는 합성 값입니다.

건강·운동 42종과 의료 문서 12종을 지원 Android의 Health Connect에서 읽어 같은 Wi-Fi로 전달받는 보관함, 원본 수면 4단계 시간표, NHS 아티클 10편, QR 연결과 위젯을 제공합니다. 제공 OS·권한·원본 앱 공유에 따라 항목이 달라집니다. 의료 원문을 보존하며 처방·복용 일정을 자동 변경하지 않습니다.

[3.9 성공 빌드](https://github.com/Hisabori/oncare-ios-build/actions/runs/38348687462): ARM64 앱·위젯 및 검사 78개(단위 68·앱 UI 9·실제 시스템 위젯 목록 1) 통과. 검사한 앱 소스 커밋은 1ba75a5a5c7d87605bd75de948cafecf782015a7입니다. 이후 문서 변경은 앱 코드에 영향을 주지 않습니다. unsigned IPA의 설치 서명은 AltStore/SideStore에서 수행합니다.

확장 건강 자료가 있는 iPhone 전체 백업은 버전 4입니다. 이전 앱/Android 일반 일지 복원 화면은 이를 가져오지 않아 확장 자료가 누락되는 복원을 막습니다. 의료 항목 날짜는 가져온 시각이며 진료·검사 시각은 FHIR 원문에서 확인합니다.

실물 워치·두 휴대폰의 최신 확장 데이터 전송과 카메라 스캔·사이드로딩 설치는 확인하지 못했습니다.
