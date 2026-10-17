import Foundation

enum ResearchMel {
    static let frames = 2998
    static let window = (0..<100).map { Float(0.5 - 0.5 * cos(2 * .pi * Double($0) / 99)) }
    static let bank: [[Double]] = {
        let lo = 2595 * log10(1 + 80.0 / 700), hi = 2595 * log10(1 + 1900.0 / 700)
        let edges = (0..<66).map { 700 * (pow(10, (lo + (hi - lo) * Double($0) / 65) / 2595) - 1) }
        var result = [[Double]](repeating: [Double](repeating: 0, count: 65), count: 64)
        for m in 0..<64 { for k in 0..<65 {
            let frequency = Double(k) * 31.25
            let left = (frequency - edges[m]) / (edges[m+1] - edges[m])
            let right = (edges[m+2] - frequency) / (edges[m+2] - edges[m+1])
            result[m][k] = Double(Float(max(0, min(left, right))))
        } }
        return result
    }()
    static func extract(_ audio: [Float]) throws -> [Float] {
        guard audio.count == 120000, audio.allSatisfy({ $0.isFinite }) else { throw CareError.invalid }
        var output = [Float](repeating: 0, count: 64 * frames)
        var re = [Double](repeating: 0, count: 128), im = re
        for frame in 0..<frames {
            for i in 0..<128 { re[i] = i < 100 ? Double(audio[frame*40+i] * window[i]) : 0; im[i] = 0 }
            fft(&re, &im)
            var power = [Double](repeating: 0, count: 65)
            for k in 0..<65 { power[k] = re[k] * re[k] + im[k] * im[k] }
            for m in 0..<64 {
                var sum = 0.0
                for k in 0..<65 { sum += bank[m][k] * power[k] }
                output[m*frames+frame] = Float(log(max(sum, 1e-10)))
            }
        }
        return output
    }
    private static func fft(_ re: inout [Double], _ im: inout [Double]) {
        var j = 0
        for i in 1..<128 { var bit = 64; while j & bit != 0 { j ^= bit; bit >>= 1 }; j ^= bit; if i < j { re.swapAt(i, j) } }
        var size = 2
        while size <= 128 {
            let wr = cos(-2 * .pi / Double(size)), wi = sin(-2 * .pi / Double(size))
            for start in stride(from: 0, to: 128, by: size) {
                var ar = 1.0, ai = 0.0
                for k in 0..<(size/2) {
                    let a = start+k, b = a+size/2
                    let br = re[b]*ar-im[b]*ai, bi = re[b]*ai+im[b]*ar
                    re[b] = re[a]-br; im[b] = im[a]-bi; re[a] += br; im[a] += bi
                    let next = ar*wr-ai*wi; ai = ar*wi+ai*wr; ar = next
                }
            }; size *= 2
        }
    }
}
