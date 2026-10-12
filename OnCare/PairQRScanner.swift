import SwiftUI
import AVFoundation

struct PairQRScanner: UIViewControllerRepresentable {
    var found: (String) -> Void
    func makeUIViewController(context: Context) -> PairQRController { let c = PairQRController(); c.found = found; return c }
    func updateUIViewController(_ uiViewController: PairQRController, context: Context) {}
}
final class PairQRController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var found: ((String) -> Void)?
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "oncare.qr.camera")
    private var layer: AVCaptureVideoPreviewLayer?
    private let message = UILabel()
    private var visible = false
    private var delivered = false
    private var configured = false
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .black
        NotificationCenter.default.addObserver(self, selector: #selector(pause), name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(resume), name: UIApplication.didBecomeActiveNotification, object: nil)
        message.text = "Android 온케어의 연결 QR을 비춰주세요"; message.textColor = .white; message.numberOfLines = 0; message.textAlignment = .center
        message.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(message)
        NSLayoutConstraint.activate([message.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24), message.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24), message.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24)])
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated); visible = true
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: start()
        case .notDetermined: AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in DispatchQueue.main.async { guard let self = self, self.visible else { return }; if allowed { self.start() } else { self.denied() } } }
        default: denied()
        }
    }
    deinit { NotificationCenter.default.removeObserver(self) }
    @objc private func pause() { queue.async { [session] in session.stopRunning() } }
    @objc private func resume() { if visible && AVCaptureDevice.authorizationStatus(for: .video) == .authorized { start() } }
    private func denied() { message.text = "카메라를 허용하지 않았어요. 설정에서 허용하거나 돌아가서 연결 코드를 붙여넣으세요." }
    private func start() {
        guard visible, !delivered else { return }
        queue.async { [weak self] in
            guard let self = self else { return }
            if !self.configured {
                guard let camera = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: camera), self.session.canAddInput(input) else { self.failed(); return }
                self.session.beginConfiguration(); self.session.addInput(input)
                let output = AVCaptureMetadataOutput()
                guard self.session.canAddOutput(output) else { self.session.commitConfiguration(); self.failed(); return }
                self.session.addOutput(output); output.setMetadataObjectsDelegate(self, queue: .main)
                guard output.availableMetadataObjectTypes.contains(.qr) else { self.session.commitConfiguration(); self.failed(); return }
                output.metadataObjectTypes = [.qr]; self.session.commitConfiguration(); self.configured = true
                DispatchQueue.main.async { [weak self] in guard let self = self else { return }; let preview = AVCaptureVideoPreviewLayer(session: self.session); preview.videoGravity = .resizeAspectFill; preview.frame = self.view.bounds; self.view.layer.insertSublayer(preview, at: 0); self.layer = preview }
            }
            self.session.startRunning()
        }
    }
    private func failed() { DispatchQueue.main.async { [weak self] in self?.message.text = "카메라를 사용할 수 없어요. 돌아가서 연결 코드를 붙여넣으세요." } }
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); layer?.frame = view.bounds }
    override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); visible = false; queue.async { [session] in session.stopRunning() } }
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard visible, !delivered, let code = (objects.first as? AVMetadataMachineReadableCodeObject)?.stringValue else { return }
        guard (try? SyncPair.decode(code)) != nil else { message.text = "온케어 연결 QR이 아니거나 유효하지 않아요. Android 연결 화면에서 다시 생성해주세요."; return }
        delivered = true; queue.async { [session] in session.stopRunning() }; found?(code)
    }
}
struct PairQRScanView: View {
    @Environment(\.dismiss) var dismiss
    let found: (String) -> Void
    var body: some View { NavigationStack { PairQRScanner(found: found).ignoresSafeArea(edges: .bottom).navigationTitle("연결 QR 스캔").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } } } }
    }
}
