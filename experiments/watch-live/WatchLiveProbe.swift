// EXPERIMENTAL TRANSPORT PROBE, not a shipped Cicada target.
// Add to a separate watchOS 10+ SwiftUI app target; see README.
import SwiftUI
import AVFoundation

private final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil) // Never forward the pairing token to another destination.
    }
}

private struct ProbeFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

@MainActor
final class WatchProbe: ObservableObject {
    @Published var status = "未开始 · 实验性远程收音"
    @Published var running = false
    private var engine: AVAudioEngine?
    private var upload: Task<Void, Never>?
    private var capture: Capture?
    private var observers: [NSObjectProtocol] = []
    private var generation = UUID()

    func start(endpoint: String, token: String) {
        guard !running, upload == nil else { return }
        guard let base = URL(string: endpoint), base.scheme == "https",
              base.host != nil, base.user == nil, base.password == nil,
              base.query == nil, base.fragment == nil,
              base.path.isEmpty || base.path == "/",
              token.count == 64, token.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) else {
            status = "需要 HTTPS 主机地址和本轮配对令牌"; return
        }
        let id = UUID(); generation = id
        running = true; status = "请求权限与连接…"
        upload = Task {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 8
            config.timeoutIntervalForResource = 10
            let session = URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
            defer { session.invalidateAndCancel() }
            var remote: String?
            do {
                let allowed = await withCheckedContinuation { c in
                    AVAudioSession.sharedInstance().requestRecordPermission { c.resume(returning: $0) }
                }
                try Task.checkCancellation()
                guard allowed else { throw ProbeFailure(message: "未获录音权限") }
                func request(_ path: String, _ body: Data = Data()) async throws -> [String: Any] {
                    var r = URLRequest(url: base.appendingPathComponent(path))
                    r.httpMethod = "POST"; r.httpBody = body
                    r.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
                    r.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
                    let (data, response) = try await session.data(for: r)
                    guard let http = response as? HTTPURLResponse, (200...201).contains(http.statusCode),
                          let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        throw ProbeFailure(message: "接收端拒绝或响应无效；已停录，不静默补传")
                    }
                    return value
                }
                let opened = try await request("session")
                guard let sid = opened["session"] as? String, sid.count == 32 else {
                    throw ProbeFailure(message: "会话响应无效")
                }
                remote = sid
                try Task.checkCancellation()
                let stream = AsyncThrowingStream<Data, Error>(bufferingPolicy: .bufferingOldest(3)) { continuation in
                    self.capture = Capture(continuation: continuation)
                }
                let audio = AVAudioSession.sharedInstance()
                try audio.setCategory(.record, mode: .measurement)
                try audio.setActive(true)
                let engine = AVAudioEngine()
                guard let capture else { throw ProbeFailure(message: "采集未创建") }
                try capture.install(on: engine)
                self.engine = engine
                observers = [
                    NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: audio, queue: .main) { [weak self] _ in
                        Task { @MainActor in self?.abort("音频中断；本轮停止，请重新开始") }
                    },
                    NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
                        Task { @MainActor in self?.abort("音频设备变化；本轮停止，请重新开始") }
                    }
                ]
                try engine.start()
                status = "边录边传 · 请在 Mac 检查识别"
                var sequence = 0
                for try await frame in stream {
                    try Task.checkCancellation()
                    let reply = try await request("pcm/\(sid)/\(sequence)", frame)
                    guard let accepted = reply["accepted"] as? Int, accepted == sequence else {
                        throw ProbeFailure(message: "确认序号不符，存在音频缺口")
                    }
                    sequence += 1
                    status = "传输层已接收 \(sequence) 段 · 非识别确认"
                }
                _ = try await request("end/\(sid)")
                remote = nil
                status = "传输已结束；请在 Mac 检查字幕收尾"
            } catch {
                if generation == id { status = "已停止：\(error.localizedDescription)；可能有未送达音频" }
            }
            // No reconnect/retry: the operator must explicitly start a fresh session.
            // If ending failed, the receiver expires this session after 30 seconds.
            _ = remote
            if generation == id {
                cleanupAudio()
                upload = nil; running = false
            }
        }
    }

    func stop() {
        guard running else { return }
        if engine == nil {
            abort("已取消开始"); return
        }
        engine?.stop()
        capture?.finish()
        status = "已停止采集，等待末段确认…"
        running = false // start still blocked by non-nil upload until drain ends.
    }

    private func abort(_ reason: String) {
        upload?.cancel()
        capture?.fail(ProbeFailure(message: reason))
        engine?.stop()
        status = reason
    }

    private func cleanupAudio() {
        engine?.stop()
        if engine != nil { engine?.inputNode.removeTap(onBus: 0) }
        engine = nil; capture = nil
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
        try? AVAudioSession.sharedInstance().setActive(false)
    }
}

// Bounded audio queue. Chunk boundaries are sample-count based, not UI timers.
// Conversion runs off the render thread; copied buffers are bounded separately.
private final class Capture: @unchecked Sendable {
    private let queue = DispatchQueue(label: "cicada.watch.capture")
    private let lock = NSLock()
    private var pending = 0
    private var closed = false
    private var bytes = Data()
    private var converter: AVAudioConverter?
    private let output = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!
    private let continuation: AsyncThrowingStream<Data, Error>.Continuation

    init(continuation: AsyncThrowingStream<Data, Error>.Continuation) {
        self.continuation = continuation
    }

    func install(on engine: AVAudioEngine) throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, let convert = AVAudioConverter(from: format, to: output) else {
            throw ProbeFailure(message: "不支持的录音格式")
        }
        converter = convert
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            self.lock.lock()
            guard !self.closed else { self.lock.unlock(); return }
            guard self.pending < 8 else {
                self.closed = true; self.lock.unlock()
                self.continuation.finish(throwing: ProbeFailure(message: "音频处理积压，已停录")); return
            }
            self.pending += 1
            guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else {
                self.pending -= 1; self.lock.unlock()
                self.fail(ProbeFailure(message: "无法分配音频缓冲")); return
            }
            copy.frameLength = buffer.frameLength
            let src = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
            let dst = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
            for i in 0..<src.count {
                if let s = src[i].mData, let d = dst[i].mData { memcpy(d, s, Int(src[i].mDataByteSize)) }
            }
            self.queue.async {
                defer { self.lock.lock(); self.pending -= 1; self.lock.unlock() }
                self.convert(copy)
            }
            self.lock.unlock()
        }
    }

    private func convert(_ source: AVAudioPCMBuffer) {
        let capacity = AVAudioFrameCount(ceil(Double(source.frameLength) * 16000 / source.format.sampleRate)) + 32
        guard let converter, let out = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: capacity) else {
            fail(ProbeFailure(message: "无法创建转换缓冲")); return
        }
        var supplied = false
        var error: NSError?
        let result = converter.convert(to: out, error: &error) { _, state in
            if supplied { state.pointee = .noDataNow; return nil }
            supplied = true; state.pointee = .haveData; return source
        }
        if result == .error || error != nil {
            fail(ProbeFailure(message: "音频转换失败")); return
        }
        if let data = out.int16ChannelData, out.frameLength > 0 {
            bytes.append(Data(bytes: data[0], count: Int(out.frameLength) * 2))
        }
        while bytes.count >= 128000 {
            emit(Data(bytes.prefix(128000))); bytes.removeFirst(128000)
        }
    }

    private func emit(_ data: Data) {
        switch continuation.yield(data) {
        case .dropped:
            fail(ProbeFailure(message: "上传积压超过约 12 秒；停止而不是偷偷丢音频"))
        default: break
        }
    }

    private func flushConverter() {
        guard let converter else { return }
        // Preserve the resampler tail rather than silently cutting the final samples.
        for _ in 0..<16 {
            guard let out = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: 4096) else {
                fail(ProbeFailure(message: "无法创建末段缓冲")); return
            }
            var error: NSError?
            let result = converter.convert(to: out, error: &error) { _, state in
                state.pointee = .endOfStream; return nil
            }
            if error != nil || result == .error {
                fail(ProbeFailure(message: "末段转换失败")); return
            }
            if let data = out.int16ChannelData, out.frameLength > 0 {
                bytes.append(Data(bytes: data[0], count: Int(out.frameLength) * 2))
            }
            while bytes.count >= 128000 {
                emit(Data(bytes.prefix(128000))); bytes.removeFirst(128000)
            }
            if result == .endOfStream || out.frameLength == 0 { return }
        }
        fail(ProbeFailure(message: "末段转换未在上限内完成"))
    }

    func finish() {
        lock.lock(); closed = true
        queue.async {
            self.flushConverter()
            if !self.bytes.isEmpty { self.emit(self.bytes); self.bytes.removeAll() }
            self.continuation.finish()
        }
        lock.unlock()
    }

    func fail(_ error: Error) {
        lock.lock(); closed = true; lock.unlock()
        continuation.finish(throwing: error)
    }
}

@main
struct LiveTransportProbeApp: App {
    @StateObject private var probe = WatchProbe()
    @State private var endpoint = ""
    @State private var token = ""
    var body: some Scene {
        WindowGroup {
            ScrollView {
                Text("实验：Watch → Mac")
                TextField("https://Mac主机:8443", text: $endpoint)
                SecureField("本轮配对令牌", text: $token)
                Text(probe.status).font(.caption)
                if probe.running {
                    Button("停止并确认末段") { probe.stop() }
                } else {
                    Button("开始远程收音") { probe.start(endpoint: endpoint, token: token) }
                }
            }
        }
    }
}
