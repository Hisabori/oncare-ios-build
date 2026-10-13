import SwiftUI
import PhotosUI
import Vision
import ImageIO

enum MedicationBagText {
    static func lines(_ text: String) -> [String] {
        Array(text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.prefix(100)).map { String($0.prefix(500)) }
    }
    static func recognize(_ data: Data) throws -> String {
        guard data.count <= 20 * 1024 * 1024, let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 2048, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { throw CareError.invalid }
        let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate; request.usesLanguageCorrection = false
        let supported = try request.supportedRecognitionLanguages()
        request.recognitionLanguages = ["ko-KR", "en-US"].filter { supported.contains($0) }
        guard request.recognitionLanguages.contains("ko-KR") else { throw CareError.invalid }
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }
}
struct MedicationBagReader: View {
    let apply: (String, Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var photo: PhotosPickerItem?
    @State private var lines: [String] = []
    @State private var busy = false
    @State private var message = ""
    var body: some View {
        NavigationStack { List {
            Section { Text("약봉지를 밝은 곳에서 똑바로 촬영한 사진을 골라주세요. 환자 이름 등 개인정보가 있는 줄은 입력하지 마세요. 사진과 인식 원문은 투약 기록에 보관하지 않습니다.").font(.subheadline).foregroundStyle(.secondary)
                PhotosPicker(selection: $photo, matching: .images) { Label("약봉지 사진 선택", systemImage: "photo") }.disabled(busy).accessibilityIdentifier("medication-ocr-photo")
                if busy { ProgressView("글자를 읽고 있어요") }; if !message.isEmpty { Text(message).foregroundStyle(Palette.coral) }
            }
            Section("인식한 줄 · 직접 선택") { ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                VStack(alignment: .leading, spacing: 10) { Text(line).textSelection(.enabled)
                    HStack { Button("약 이름에 사용") { apply(line, true); dismiss() }; Spacer(); Button("복용 방법에 사용") { apply(line, false); dismiss() } }.font(.caption)
                }.padding(.vertical, 4)
            } }
            Section { Text("인식 오류가 있을 수 있어요. 용량·시간·요일은 자동으로 정하지 않으며 알림은 꺼진 상태로 돌아갑니다. 원본을 확인한 뒤 일정을 직접 저장하세요.").font(.caption).foregroundStyle(.secondary) }
        }.navigationTitle("약봉지 글자 인식").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("닫기") { dismiss() } } }
        .task(id: photo) {
            guard let selected = photo else { return }; busy = true; lines = []; message = ""
            do { guard let data = try await selected.loadTransferable(type: Data.self) else { throw CareError.invalid }
                let text = try await Task.detached(priority: .userInitiated) { try MedicationBagText.recognize(data) }.value
                guard !Task.isCancelled else { return }; lines = MedicationBagText.lines(text); if lines.isEmpty { message = "읽을 수 있는 글자가 없어요. 선명한 사진을 다시 선택해주세요." }
            } catch { if !Task.isCancelled { message = "사진을 읽지 못했어요. 20MB 이하의 선명한 사진인지 확인해주세요." } }
            busy = false
        }
        }
    }
}
