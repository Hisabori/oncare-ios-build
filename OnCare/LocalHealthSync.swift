import SwiftUI
import CryptoKit
import Security

struct SyncPair: Codable, Equatable {
    var version: Int
    var host: String
    var port: Int
    var peer: String
    var token: String
    var fingerprint: String
    func validate() throws {
        let pieces = host.split(separator: ".", omittingEmptySubsequences: false)
        let octets = pieces.compactMap { Int($0) }
        guard version == 1, pieces.count == 4, octets.count == 4,
              zip(pieces, octets).allSatisfy({ pair in String(pair.1) == pair.0 && (0...255).contains(pair.1) }),
              octets[0] == 10 || (octets[0] == 192 && octets[1] == 168) || (octets[0] == 172 && (16...31).contains(octets[1])),
              port == 8766, UUID(uuidString: peer) != nil,
              token.range(of: #"^[A-Za-z0-9_-]{43}$"#, options: .regularExpression) != nil,
              fingerprint.range(of: #"^[a-f0-9]{64}$"#, options: .regularExpression) != nil else { throw CareError.invalid }
    }
    static func decode(_ code: String) throws -> SyncPair {
        let code = code.filter { !$0.isWhitespace }
        guard code.count <= 2048, code.hasPrefix("oncare1:") else { throw CareError.invalid }
        var raw = String(code.dropFirst(8)).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        raw += String(repeating: "=", count: (4 - raw.count % 4) % 4)
        guard let data = Data(base64Encoded: raw) else { throw CareError.invalid }
        let pair = try JSONDecoder().decode(SyncPair.self, from: data); try pair.validate(); return pair
    }
}
enum SyncKeychain {
    static let service = "app.oncare.personal.local-health-sync"
    static func load() -> SyncPair? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "pair", kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var value: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &value) == errSecSuccess, let data = value as? Data, let pair = try? JSONDecoder().decode(SyncPair.self, from: data), (try? pair.validate()) != nil else { return nil }
        return pair
    }
    static func save(_ pair: SyncPair) throws {
        try pair.validate()
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "pair"]
        let data = try JSONEncoder().encode(pair)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = query; add[kSecValueData as String] = data; add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { throw CareError.unreadable }
        } else if status != errSecSuccess { throw CareError.unreadable }
    }
    static func remove() { SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "pair"] as CFDictionary) }
}
struct HealthSnapshot: Codable {
    var version: Int
    var peer: String
    var generatedAt: Date
    var windowStart: Date
    var kinds: [String]
    var entries: [Entry]
    var healthRecords: [HealthRecord]? = nil
    var availability: [HealthAvailability]? = nil
    func validate(pair: SyncPair, now: Date = Date()) throws {
        guard version == 1, peer == pair.peer,
              abs(generatedAt.timeIntervalSince(now)) < 180,
              windowStart <= generatedAt, generatedAt.timeIntervalSince(windowStart) <= 31 * 86400,
              !kinds.isEmpty, Set(kinds).count == kinds.count, Set(kinds).isSubset(of: Set(["체중", "운동", "수면", "물", "걸음"] + HealthRecord.types.map { "health:" + $0 })),
              entries.allSatisfy({ kinds.contains($0.kind) && $0.id.hasPrefix("hc:") && $0.date >= windowStart && $0.date <= generatedAt && $0.source == nil }) else { throw CareError.invalid }
        try CareBackup(entries: entries, healthRecords: healthRecords, healthAvailability: availability).validate(now: now)
        guard (healthRecords ?? []).allSatisfy({ kinds.contains("health:" + $0.recordType) && $0.date >= windowStart && $0.date <= generatedAt && $0.source == nil }), (availability?.count ?? 0) <= HealthRecord.types.count else { throw CareError.invalid }
        for item in availability ?? [] { guard HealthRecord.types.contains(item.recordType), item.title.count <= 100, item.count >= 0, item.count <= 10000, ["ready", "empty", "permission", "unsupported", "error"].contains(item.status) else { throw CareError.invalid } }
    }
}
extension Journal {
    @discardableResult func applyHealth(_ snapshot: HealthSnapshot, pair: SyncPair, now: Date = Date()) throws -> Int {
        try snapshot.validate(pair: pair, now: now)
        let source = "health-connect:" + pair.peer
        let records = snapshot.entries.map { record -> Entry in
            var entry = record
            entry.id = "hc:" + SHA256.hash(data: Data((pair.peer + "|" + record.id).utf8)).map { String(format: "%02x", $0) }.joined()
            entry.source = source; return entry
        }
        var next = state
        // Replace only this peer's imported records inside a complete, validated read window.
        next.entries.removeAll { $0.source == source && snapshot.kinds.contains($0.kind) && $0.date >= snapshot.windowStart }
        let ids = Set(records.map(\.id)); next.entries.removeAll { ids.contains($0.id) }
        next.entries += records
        if let incoming = snapshot.healthRecords {
            var archive = next.healthRecords ?? []
            archive.removeAll { $0.source == source && snapshot.kinds.contains("health:" + $0.recordType) && ($0.category == "의료" || $0.date >= snapshot.windowStart) }
            let imported = incoming.map { raw -> HealthRecord in var record = raw; record.id = "hc:" + SHA256.hash(data: Data((pair.peer + "|" + raw.id).utf8)).map { String(format: "%02x", $0) }.joined(); record.source = source; return record }
            let ids = Set(imported.map(\.id)); archive.removeAll { ids.contains($0.id) }; archive += imported; next.healthRecords = archive
            next.healthAvailability = snapshot.availability
        }
        guard persist(next) else { throw CareError.unreadable }
        return records.count + (snapshot.healthRecords?.count ?? 0)
    }
}
final class PinnedSyncDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    let pair: SyncPair
    init(pair: SyncPair) { self.pair = pair }
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              challenge.protectionSpace.host == pair.host,
              let trust = challenge.protectionSpace.serverTrust, let certificate = SecTrustGetCertificateAtIndex(trust, 0) else { completionHandler(.cancelAuthenticationChallenge, nil); return }
        let digest = SHA256.hash(data: SecCertificateCopyData(certificate) as Data).map { String(format: "%02x", $0) }.joined()
        guard digest == pair.fingerprint else { completionHandler(.cancelAuthenticationChallenge, nil); return }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
@MainActor final class LocalHealthSync: ObservableObject {
    @Published private(set) var pair = SyncKeychain.load()
    @Published private(set) var busy = false
    @Published private(set) var status = "Android 연결을 등록해주세요."
    @Published private(set) var lastSync: Date?
    @Published var liveStatus = UserDefaults.standard.bool(forKey: "sync-live-status")
    private var epoch = 0
    func connect(_ code: String) throws {
        let next = try SyncPair.decode(code); try SyncKeychain.save(next); epoch += 1; pair = next; lastSync = nil; status = "같은 Wi-Fi에서 연결을 확인해요."
    }
    func disconnect() { epoch += 1; SyncKeychain.remove(); pair = nil; lastSync = nil; status = "연결을 해제했어요. 받은 기록은 보존돼요."; Task { await CareLiveStatus.finish() } }
    func sync(_ journal: Journal) async {
        guard let pair, !busy else { return }
        let generation = epoch; busy = true
        defer { busy = false }
        status = "Android 건강 기록 확인 중"
        if liveStatus { await CareLiveStatus.update(message: "Android 연결 중", count: nil, syncing: true) }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10; config.timeoutIntervalForResource = 15; config.urlCache = nil
        let session = URLSession(configuration: config, delegate: PinnedSyncDelegate(pair: pair), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        do {
            try pair.validate()
            var request = URLRequest(url: URL(string: "https://\(pair.host):\(pair.port)/v1/health")!)
            request.setValue("Bearer " + pair.token, forHTTPHeaderField: "Authorization")
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard epoch == generation else { return }
            guard let response = response as? HTTPURLResponse else { throw CareError.unreadable }
            if response.statusCode == 401 { status = "연결 코드가 바뀌었어요. Android에서 새 코드를 등록해주세요."; throw CareError.unreadable }
            if response.statusCode == 503 { status = "Android에서 건강 기록을 준비 중이에요. 권한을 확인하고 잠시 기다려주세요."; throw CareError.unreadable }
            guard response.statusCode == 200, data.count <= 5 * 1024 * 1024 else { throw CareError.unreadable }
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
            let snapshot = try decoder.decode(HealthSnapshot.self, from: data)
            let count = try journal.applyHealth(snapshot, pair: pair)
            lastSync = Date(); let errors = (snapshot.availability ?? []).filter { $0.status == "error" }.count; status = "\(count)개 건강 기록 갱신" + (errors > 0 ? " · \(errors)개 항목 원본 읽기 확인 필요" : " · 중복 없이 갱신")
            if liveStatus { await CareLiveStatus.update(message: "건강 기록 최신 상태", count: count, syncing: false) }
        } catch {
            guard epoch == generation else { return }
            if Task.isCancelled { status = "앱을 열면 다시 동기화해요." }
            else if status == "Android 건강 기록 확인 중" { status = "연결하지 못했어요. 같은 Wi-Fi·두 앱 실행·로컬 네트워크 권한·기기 시간을 확인해주세요." }
            if liveStatus { await CareLiveStatus.update(message: "연결 확인 필요", count: nil, syncing: false) }
        }
    }
}
struct HealthConnectionView: View {
    @EnvironmentObject var journal: Journal
    @EnvironmentObject var sync: LocalHealthSync
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var error = ""
    @State private var scanning = false
    @State private var scannedCode: String?
    @State private var disconnecting = false
    var body: some View {
        NavigationStack {
            Form {
                Section { Text("Android Health Connect → 같은 Wi-Fi → iPhone\n두 앱을 열어두면 1분마다 최신 기록을 확인해요. 원본에 쓰지 않으며 목표와 루틴은 바꾸지 않아요.") }
                Section("한 번만 연결") {
                    Text("Android 온케어의 Health Connect · iPhone 연결에서 읽기 권한을 허용하고, 연결 코드를 내 iPhone으로 보내주세요.").font(.subheadline)
                    Button("QR로 간편 연결") { scanning = true }.accessibilityIdentifier("sync-qr-scan")
                    Text("Android에서 연결 QR 보기를 누르고 이 iPhone으로 스캔하세요.").font(.caption).foregroundStyle(.secondary)
                    TextField("oncare1: 연결 코드 붙여넣기", text: $code, axis: .vertical).lineLimit(2...4).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("sync-code")
                    if let parsed = try? SyncPair.decode(code) { Text("연결할 Android: " + parsed.host + " · 상단 기기 연결을 눌러 확인하세요.").font(.caption).accessibilityIdentifier("sync-qr-preview") }
                    if !error.isEmpty { Text(error).foregroundStyle(.red) }
                }
                Section("연결 상태") {
                    Text(sync.status).accessibilityIdentifier("sync-status")
                    if let pair = sync.pair { Text("Android · \(pair.host)").font(.caption).foregroundStyle(.secondary) }
                    if let date = sync.lastSync { Text("최근 확인: " + date.formatted(.dateTime.month().day().hour().minute().locale(Locale(identifier: "ko_KR")))).font(.caption) }
                    if sync.busy { ProgressView("건강 기록 확인 중") }
                    Button("지금 동기화") { Task { await sync.sync(journal) } }.disabled(sync.pair == nil || sync.busy).accessibilityIdentifier("sync-now")
                }
                Section("Galaxy Watch 수면 기록 가져오기") {
                    Text("Galaxy Watch → Android 삼성 헬스 → Health Connect → 같은 Wi-Fi → iPhone 온케어").font(.subheadline.weight(.semibold))
                    Text("1. 워치 수면 기록이 Android 삼성 헬스에 도착했는지 확인해요.\n2. 삼성 헬스에서 Health Connect로 수면 데이터를 공유해요.\n3. Android 온케어에 수면 읽기 권한을 허용하고 iPhone 연결을 켜요.\n4. 같은 Wi-Fi에서 두 기기의 온케어를 열고 연결 코드를 등록해요.").font(.subheadline)
                    Text("삼성 헬스·워치·Android 버전에 따라 제공되는 항목이 달라요. 공유된 수면 시간·단계·원본 앱·기기 정보만 읽고 원본에는 쓰지 않아요. Galaxy Watch에서 iPhone으로 직접 연결하는 방식은 아니에요.").font(.caption).foregroundStyle(.secondary)
                    Text("기기 이름이나 수면 단계를 받지 못하면 출처 확인 필요로 표시해요. 삼성 헬스 기록이라는 이유만으로 Galaxy Watch 측정값이라고 판단하거나 빠진 단계를 만들어 채우지 않아요.").font(.caption).foregroundStyle(.secondary)
                    Text("현재 실물 Galaxy Watch와 두 휴대폰 사이의 측정·전송은 확인하지 못했어요. 가져온 기록의 출처와 시간을 원본 앱에서 확인해주세요.").font(.caption).foregroundStyle(.secondary)
                }
                Section("다이내믹 아일랜드 · 잠금 화면") {
                    Toggle("동기화 상태 표시", isOn: $sync.liveStatus).accessibilityIdentifier("sync-live-toggle")
                    Text("지원 기기와 실시간 현황 허용 설정에서 표시돼요. 건강 수치와 메모는 표시하지 않아요. 앱을 닫으면 자동 동기화는 멈춰요.").font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    Text("지원되는 건강·운동 42종과 의료 문서 12종 중 허용된 기록을 가져와요. 생체·체성분·영양·주기 정보는 건강 탭의 연결된 건강 정보에서 확인해요. 의료 문서는 지원 Android에서 별도 권한으로 읽으며 문서 원문을 보존해요. 운동 경로는 세션별 동의가 필요해요. Android 14 이상이 필요하며, Google Health 등에서 Health Connect 공유를 켜야 해요. 원본에서 수정·삭제한 최근 기록은 다음 연결 때 반영해요. 직접 입력한 기록은 유지돼요.").font(.caption)
                    Text("Wi-Fi 주소가 바뀌면 Android의 연결 코드를 다시 등록하세요. 연결 코드는 암호 키처럼 내 기기에만 전달하세요.").font(.caption)
                    Button("연결 해제", role: .destructive) { disconnecting = true }.disabled(sync.pair == nil).accessibilityIdentifier("sync-disconnect")
                }
            }.navigationTitle("Android 건강 연결").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("기기 연결") { connect() }.disabled(sync.busy || code.isEmpty).accessibilityIdentifier("sync-connect") }
                    ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("완료") { hideKeyboard() } }
                }
                .sheet(isPresented: $scanning, onDismiss: { if let scannedCode { code = scannedCode; error = ""; self.scannedCode = nil } }) { PairQRScanView { scannedCode = $0; scanning = false } }
                .onChange(of: sync.liveStatus) { value in UserDefaults.standard.set(value, forKey: "sync-live-status"); if !value { Task { await CareLiveStatus.finish() } } }
                .confirmationDialog("연결을 해제할까요?", isPresented: $disconnecting, titleVisibility: .visible) { Button("연결 해제", role: .destructive) { sync.disconnect() } } message: { Text("받은 건강 기록은 그대로 남고 자동 동기화만 중단돼요.") }
        }
    }
    private func hideKeyboard() { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
    private func connect() {
        hideKeyboard()
        do { try sync.connect(code); code = ""; error = "" }
        catch { self.error = "연결 코드 또는 저장 상태를 확인해주세요. Android에서 새 코드를 복사할 수 있어요." }
    }

}
