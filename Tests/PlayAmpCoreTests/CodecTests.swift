import XCTest
import AVFoundation
import SFBAudioEngine
final class CodecTests: XCTestCase {
    func testRealFormatsDecodeAndSeek() throws {
        let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures")
        guard FileManager.default.fileExists(atPath: root.path) else { throw XCTSkip("Run scripts/generate-fixtures.sh first (requires ffmpeg)") }
        for ext in ["wav","mp3","opus","flac","m4a","aiff","ogg","aac"] {
            print("CODEC \(ext) open")
            let url = root.appendingPathComponent("tone.\(ext)")
            let decoder = try ext == "aac" ? AudioDecoder(url: url, decoderName: .coreAudio) : AudioDecoder(url: url)
            print("DECODER \(decoder)")
            try decoder.open()
            let format = decoder.processingFormat
            XCTAssertGreaterThan(format.sampleRate, 0, ext)
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096))
            try decoder.decode(into: buffer, length: 4096)
            XCTAssertGreaterThan(buffer.frameLength, 0, ext)
            XCTAssertTrue(decoder.supportsSeeking, ext)
            print("CODEC \(ext) seek")
            try decoder.seek(to: AVAudioFramePosition(format.sampleRate))
            try decoder.decode(into: buffer, length: 4096)
            XCTAssertGreaterThan(buffer.frameLength, 0, ext)
            try decoder.close()
        }
        XCTAssertThrowsError(try { let d = try AudioDecoder(url: root.appendingPathComponent("corrupt.mp3")); try d.open() }())
    }
}
