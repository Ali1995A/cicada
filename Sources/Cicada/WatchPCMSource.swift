// Developer-only bridge: authenticated HTTPS receiver -> private FIFO -> normal recognition.
// Not a network listener; no model key or alternative AI client lives here.
#if CICADA_WATCH_BRIDGE && !CICADA_IOS
import AVFoundation
import Darwin

final class WatchPCMSource: AudioSource, @unchecked Sendable {
    var isReady: (() -> Bool)?
    var onAudio: ((AVAudioPCMBuffer) -> Void)?
    var onEnded: ((_ clean: Bool) -> Void)?
    private let path: String
    private let queue = DispatchQueue(label: "cicada.watch.pcm")
    private var timer: DispatchSourceTimer?
    private var fd: Int32 = -1
    private var bytes = Data()
    private var received = false
    private var lastData = Date()
    private var running = false
    private var muted = false
    func setMuted(_ on: Bool) { queue.sync { muted = on } }
    private let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!

    init(path: String) { self.path = path }

    func start() throws {
        try queue.sync {
            guard !running else { return }
            let descriptor = Darwin.open(path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW)
            guard descriptor >= 0 else { throw failure("无法打开手表音频管道") }
            var info = stat()
            guard fstat(descriptor, &info) == 0,
                  (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFIFO),
                  info.st_uid == getuid(), (info.st_mode & 0o777) == 0o600 else {
                Darwin.close(descriptor)
                throw failure("手表音频管道必须属于当前用户且权限为 0600")
            }
            fd = descriptor; running = true; lastData = Date()
            let t = DispatchSource.makeTimerSource(queue: queue)
            t.schedule(deadline: .now(), repeating: .milliseconds(20))
            t.setEventHandler { [weak self] in self?.readAvailable() }
            timer = t; t.resume()
        }
    }

    func stop() { queue.sync { closeInput() } }

    private func closeInput() {
        running = false
        timer?.cancel(); timer = nil
        if fd >= 0 { Darwin.close(fd); fd = -1 }
        bytes.removeAll()
    }

    private func end(_ clean: Bool) {
        // A short silence lets the normal recognizer settle its final sentence.
        if let silence = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16000) {
            silence.frameLength = 16000
            if let channel = silence.floatChannelData {
                channel[0].initialize(repeating: 0, count: 16000)
                onAudio?(silence)
            }
        }
        closeInput()
        onEnded?(clean)
    }

    private func readAvailable() {
        guard running else { return }
        guard isReady?() != false else {
            if Date().timeIntervalSince(lastData) > 120 { end(false) }
            return
        }
        var chunk = [UInt8](repeating: 0, count: 8192)
        // Bound a poll; never monopolize the queue or grow arbitrary memory.
        for _ in 0..<20 {
            let n = chunk.withUnsafeMutableBytes { raw in
                Darwin.read(fd, raw.baseAddress, raw.count)
            }
            if n > 0 {
                received = true; lastData = Date()
                bytes.append(contentsOf: chunk.prefix(n))
                guard consumeFrames() else { return }
            } else if n == 0 {
                if received { end(false) }
                break
            } else {
                if errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR { end(false) }
                break
            }
        }
        if running && Date().timeIntervalSince(lastData) > (received ? 20 : 120) { end(false) }
    }

    private func consumeFrames() -> Bool {
        while bytes.count >= 4 {
            let count = bytes.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            if count == 0 {
                bytes.removeFirst(4); end(bytes.isEmpty); return false
            }
            guard count <= 128000, count % 2 == 0 else { end(false); return false }
            guard bytes.count >= 4 + Int(count) else { return true }
            let pcm = Array(bytes.dropFirst(4).prefix(Int(count)))
            bytes.removeFirst(4 + Int(count))
            // Small buffers preserve voice-gate timing and flow through AudioRouter unchanged.
            var offset = 0
            while offset < pcm.count {
                let samples = min(1600, (pcm.count - offset) / 2)
                guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples)),
                      let channel = out.floatChannelData else { end(false); return false }
                out.frameLength = AVAudioFrameCount(samples)
                for i in 0..<samples {
                    let value = UInt16(pcm[offset + i * 2]) | (UInt16(pcm[offset + i * 2 + 1]) << 8)
                    channel[0][i] = muted ? 0 : Float(Int16(bitPattern: value)) / 32768
                }
                onAudio?(out)
                offset += samples * 2
            }
        }
        return true
    }

    private func failure(_ text: String) -> Error {
        NSError(domain: "Cicada.WatchPCM", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
    }
}
#endif
