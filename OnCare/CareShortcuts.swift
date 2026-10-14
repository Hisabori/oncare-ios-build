import AppIntents
import Combine
import SwiftUI
import UIKit
import UserNotifications

extension CareDestination {
    var sheet: CareSheet {
        switch self {
        case .sleep: return .sleepRoutine
        case .workout: return .practice
        case .mood: return .mood
        case .connect: return .healthConnection
        }
    }
    var tab: Int { self == .mood ? 1 : 2 }
}

/// Keeps a cold-launch request until the scene is active. A later request always wins.
@MainActor final class CareShortcutRouter: ObservableObject {
    static let shared = CareShortcutRouter()
    @Published private(set) var pending: CareRouteRequest?
    func open(_ destination: CareDestination) { guard pending?.destination != destination else { return }; pending = CareRouteRequest(destination: destination) }
    @discardableResult func open(_ url: URL) -> Bool {
        guard let destination = CareDestination.parse(url) else { return false }
        open(destination); return true
    }
    @discardableResult func open(quickActionType: String) -> Bool {
        guard let destination = CareDestination.parse(quickActionType: quickActionType) else { return false }
        open(destination); return true
    }
    func complete(_ id: UUID) { if pending?.id == id { pending = nil } }
}

/// These intents only open a form. The person still chooses any save, timer start or pairing action.
struct OpenCareSleepIntent: AppIntent {
    static var title: LocalizedStringResource = "수면 루틴 열기"
    static var description = IntentDescription("온케어의 수면 계획과 기록 화면을 엽니다.")
    static var openAppWhenRun: Bool = true
    @MainActor func perform() async throws -> some IntentResult {
        CareShortcutRouter.shared.open(.sleep); return .result()
    }
}
struct OpenCareWorkoutIntent: AppIntent {
    static var title: LocalizedStringResource = "운동 타이머 열기"
    static var description = IntentDescription("온케어의 운동 타이머 화면을 엽니다. 운동은 직접 시작합니다.")
    static var openAppWhenRun: Bool = true
    @MainActor func perform() async throws -> some IntentResult {
        CareShortcutRouter.shared.open(.workout); return .result()
    }
}
struct OpenCareMoodIntent: AppIntent {
    static var title: LocalizedStringResource = "마음 기록 열기"
    static var description = IntentDescription("온케어의 마음 체크인 화면을 엽니다. 기록은 직접 저장합니다.")
    static var openAppWhenRun: Bool = true
    @MainActor func perform() async throws -> some IntentResult {
        CareShortcutRouter.shared.open(.mood); return .result()
    }
}
struct OpenCareConnectionIntent: AppIntent {
    static var title: LocalizedStringResource = "건강 연결 열기"
    static var description = IntentDescription("온케어의 Android 건강 데이터 연결 화면을 엽니다.")
    static var openAppWhenRun: Bool = true
    @MainActor func perform() async throws -> some IntentResult {
        CareShortcutRouter.shared.open(.connect); return .result()
    }
}
struct CareAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: OpenCareSleepIntent(), phrases: ["\(.applicationName) 수면 루틴 열어줘"], shortTitle: "수면 루틴", systemImageName: "moon.zzz.fill")
        AppShortcut(intent: OpenCareWorkoutIntent(), phrases: ["\(.applicationName) 운동 타이머 열어줘"], shortTitle: "운동 타이머", systemImageName: "figure.walk")
        AppShortcut(intent: OpenCareMoodIntent(), phrases: ["\(.applicationName) 마음 기록 열어줘"], shortTitle: "마음 기록", systemImageName: "heart.text.square.fill")
        AppShortcut(intent: OpenCareConnectionIntent(), phrases: ["\(.applicationName) 건강 연결 열어줘"], shortTitle: "건강 연결", systemImageName: "arrow.triangle.2.circlepath")
    }
}

@MainActor final class CareShortcutAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool { UNUserNotificationCenter.current().delegate = self; if let url = launchOptions?[.url] as? URL { CareShortcutRouter.shared.open(url) }; return true }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.notification.request.identifier.hasPrefix("oncare-med.") { Task { @MainActor in MedicationNavigation.shared.pending = UUID() } }
        completionHandler()
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) { completionHandler([.banner, .sound]) }
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool { CareShortcutRouter.shared.open(url) }
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        if connectingSceneSession.role == .windowApplication { configuration.delegateClass = CareShortcutSceneDelegate.self }
        return configuration
    }
    func application(_ application: UIApplication, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        completionHandler(CareShortcutRouter.shared.open(quickActionType: shortcutItem.type))
    }
}
@MainActor final class CareShortcutSceneDelegate: NSObject, UIWindowSceneDelegate, ObservableObject {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let url = connectionOptions.urlContexts.first?.url { CareShortcutRouter.shared.open(url) }
        if let shortcut = connectionOptions.shortcutItem { CareShortcutRouter.shared.open(quickActionType: shortcut.type) }
    }
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        if let url = URLContexts.first?.url { CareShortcutRouter.shared.open(url) }
    }
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        completionHandler(CareShortcutRouter.shared.open(quickActionType: shortcutItem.type))
    }
}

@MainActor final class CareWindowReference: ObservableObject {
    weak var window: UIWindow?
    @Published private(set) var generation = 0
    func attach(_ value: UIWindow?) { guard window !== value else { return }; window = value; generation += 1 }
}
struct CareShortcutTaskKey: Equatable {
    let request: UUID?
    let active: Bool
    let windowReady: Bool
    var windowGeneration: Int = 0
}
/// Resolves the window belonging to this view, without looking up an unrelated foreground window.
struct CarePresentationAnchor: UIViewRepresentable {
    let reference: CareWindowReference
    let ready: () -> Void
    func makeUIView(context: Context) -> AnchorView { let view = AnchorView(); view.reference = reference; view.ready = ready; view.isUserInteractionEnabled = false; return view }
    func updateUIView(_ uiView: AnchorView, context: Context) { uiView.reference = reference; uiView.ready = ready; uiView.reportWindow() }
    final class AnchorView: UIView {
        var reference: CareWindowReference?
        var ready: (() -> Void)?
        override func didMoveToWindow() {
            super.didMoveToWindow(); reportWindow()
        }
        func reportWindow() { DispatchQueue.main.async { [weak self] in guard let self else { return }; self.reference?.attach(self.window); if self.window != nil { self.ready?() } } }
    }
}
@MainActor enum CareModalDismissal {
    static func dismiss(in window: UIWindow) async {
        guard let root = window.rootViewController else { return }
        while let presented = root.presentedViewController, !Task.isCancelled {
            if presented.isBeingDismissed {
                do { try await Task.sleep(nanoseconds: 20_000_000) } catch { return }
            } else {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    root.dismiss(animated: false) { continuation.resume() }
                }
            }
        }
    }
}
