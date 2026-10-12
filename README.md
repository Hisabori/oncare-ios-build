# OnCare iOS build

Public build snapshot of OnCare 3.8.0, build 12. Includes the iPhone app, WidgetKit extension, unit/UI tests and a manually triggered unsigned IPA workflow.

The snapshot contains source code and synthetic test fixtures only. Original Git history, Android code, private documents, user health records, signing certificates, account credentials and previous build outputs are not included.

## Build

Open Actions → Build OnCare unsigned IPA → Run workflow. The standard macOS runner compiles the app and widget, runs the tests, then packages the IPA. The workflow has contents-read permission and uses actions pinned to full commit SHAs. No Apple account or signing secret is used.

Download OnCare-unsigned-ipa after a successful run. Sign and install the IPA on your own device using AltStore or SideStore. No new IPA is published when tests fail.

## App features

Personal health journal, sleep routines, workout timer, medications, articles, widgets and shortcuts. QR pairing is Android-to-iPhone on the same Wi-Fi. Personal summary sharing offers selected categories, 7/30-day ranges and a preview. Health notes, medication details and pairing credentials are omitted from the summary.

The app is a personal journal and does not provide diagnosis or treatment. Camera scans and actual device-to-device transfer require physical-device verification.
