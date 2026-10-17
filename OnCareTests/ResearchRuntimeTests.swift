import XCTest
import OnnxRuntimeBindings
@testable import OnCare

final class ResearchRuntimeTests: XCTestCase {
    // Generated constant graph, no learned parameters or participant data.
    // This checks native runtime wiring, not clinical prediction quality.
    func testNativeRuntimeContract() throws {
        let fixture = try XCTUnwrap(Data(base64Encoded: "CAg6qwEKRBIXY2FuZGlkYXRlX3Byb2JhYmlsaXRpZXMiCENvbnN0YW50Kh8KBXZhbHVlKhMIAQgCEAEiCAAAQD8AAIA+QgFwoAEEEhhzeW50aGV0aWMtY29udHJhY3QtY2hlY2taHgoHbG9nX21lbBITChEIARINCgIIAQoCCEAKAwi2F2IpChdjYW5kaWRhdGVfcHJvYmFiaWxpdGllcxIOCgwIARIICgIIAQoCCAJCBAoAEBE="))
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".onnx")
        try fixture.write(to: path); defer { try? FileManager.default.removeItem(at: path) }
        let env = try ORTEnv(loggingLevel: .error)
        let options = try ORTSessionOptions(); try options.setIntraOpNumThreads(1)
        let session = try ORTSession(env: env, modelPath: path.path, sessionOptions: options)
        let bytes = NSMutableData(length: 64*2998*4)!
        let input = try ORTValue(tensorData: bytes, elementType: .float, shape: [1,64,2998])
        let outputs = try session.run(withInputs: ["log_mel":input], outputNames: ["candidate_probabilities"], runOptions: nil)
        let value = try XCTUnwrap(outputs["candidate_probabilities"])
        let data = try value.tensorData()
        var probabilities = [Float](repeating: 0, count: 2)
        XCTAssertEqual(data.length, 8)
        probabilities.withUnsafeMutableBytes { data.getBytes($0.baseAddress!, length: 8) }
        XCTAssertEqual(probabilities[1], 0.25, accuracy: 0.00001)
    }
}
