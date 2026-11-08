#if CICADA_WATCH_BRIDGE
import Testing
import Foundation
import AVFoundation
import Darwin
@testable import Cicada

private final class WatchCaptureResults: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = []
    private var endings: [Bool] = []
    func audio(_ buffer: AVAudioPCMBuffer) {
        lock.lock(); defer { lock.unlock() }
        if let channel = buffer.floatChannelData {
            samples.append(contentsOf: UnsafeBufferPointer(start: channel[0], count: Int(buffer.frameLength)))
        }
    }
    func ended(_ clean: Bool) { lock.lock(); endings.append(clean); lock.unlock() }
    func snapshot() -> ([Float], [Bool]) {
        lock.lock(); defer { lock.unlock() }; return (samples, endings)
    }
}

private final class WatchPipeFixture {
    let directory: URL
    let path: String
    let source: WatchPCMSource
    let results = WatchCaptureResults()
    var writer: Int32 = -1
    init(mode: mode_t = 0o600) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        path = directory.appendingPathComponent("audio.pcm").path
        guard mkfifo(path, mode) == 0 else { throw CocoaError(.fileWriteUnknown) }
        _ = chmod(path, mode)
        source = WatchPCMSource(path: path)
        let results = self.results
        source.isReady = { true }
        source.onAudio = { results.audio($0) }
        source.onEnded = { results.ended($0) }
    }
    func start() throws {
        try source.start()
        writer = Darwin.open(path, O_WRONLY | O_NONBLOCK)
        guard writer >= 0 else { throw CocoaError(.fileWriteUnknown) }
    }
    func write(_ bytes: [UInt8]) throws {
        let n = bytes.withUnsafeBytes { Darwin.write(writer, $0.baseAddress, $0.count) }
        guard n == bytes.count else { throw CocoaError(.fileWriteUnknown) }
    }
    func awaitEnd() async throws -> ([Float], [Bool]) {
        for _ in 0..<200 {
            let result = results.snapshot()
            if !result.1.isEmpty { return result }
            try await Task.sleep(for: .milliseconds(10))
        }
        return results.snapshot()
    }
    deinit {
        if writer >= 0 { Darwin.close(writer) }
        source.stop()
        try? FileManager.default.removeItem(at: directory)
    }
}

@Suite struct WatchPCMSourceTests {
    @Test func framedAudioReachesNativeSourceAndCleanEnd() async throws {
        let fixture = try WatchPipeFixture()
        try fixture.start()
        // Three PCM16LE samples: minimum, zero, maximum; then explicit clean end.
        try fixture.write([0,0,0,6, 0,128, 0,0, 255,127, 0,0,0,0])
        let (samples, ends) = try await fixture.awaitEnd()
        #expect(ends == [true])
        #expect(samples.count == 16003)
        #expect(Array(samples.prefix(3)) == [-1,0,Float(32767)/32768])
    }

    @Test func mutePreservesClockButRemovesSpeech() async throws {
        let fixture = try WatchPipeFixture()
        fixture.source.setMuted(true)
        try fixture.start()
        try fixture.write([0,0,0,2, 255,127, 0,0,0,0])
        let (samples, ends) = try await fixture.awaitEnd()
        #expect(ends == [true])
        #expect(samples.count == 16001)
        #expect(samples.allSatisfy { $0 == 0 })
    }

    @Test func oddLengthFrameFailsVisibly() async throws {
        let fixture = try WatchPipeFixture()
        try fixture.start()
        try fixture.write([0,0,0,3, 1,2,3])
        let (_, ends) = try await fixture.awaitEnd()
        #expect(ends == [false])
    }

    @Test func eofWithoutEndMarkerIsNotSuccess() async throws {
        let fixture = try WatchPipeFixture()
        try fixture.start()
        try fixture.write([0,0,0,2, 1,0])
        Darwin.close(fixture.writer); fixture.writer = -1
        let (_, ends) = try await fixture.awaitEnd()
        #expect(ends == [false])
    }

    @Test func sharedPermissionsAreRejected() throws {
        let fixture = try WatchPipeFixture(mode: 0o644)
        #expect(throws: (any Error).self) { try fixture.source.start() }
    }
}
#endif
