import Foundation
import Testing
@testable import Cicada

/// Ending a meeting: an empty one goes, one whose recording holds speech stays (issue #5).
@MainActor @Suite struct SessionStoreTests {
    func store() -> SessionStore {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cicada-store-\(UUID().uuidString)")
        return SessionStore(root: root)
    }

    /// The partial file the recorder writes while the meeting runs.
    func record(_ store: SessionStore, _ id: String) {
        FileManager.default.createFile(atPath: AudioFileWriter.partial(store.systemAudioURL(id)).path, contents: Data(count: 1024))
    }

    @Test func aMeetingWithNothingSaidIsDropped() {
        let s = store()
        let id = s.begin().id
        record(s, id)
        s.end()
        #expect(s.session(id) == nil)
        #expect(!FileManager.default.fileExists(atPath: s.folder(id).path))
    }

    @Test func aRecordingWithSpeechIsKeptWithoutLines() {
        let s = store()
        let id = s.begin().id
        record(s, id)
        s.end(heardSpeech: true)
        #expect(s.session(id)?.hasAudio == true)
        #expect(FileManager.default.fileExists(atPath: AudioFileWriter.partial(s.systemAudioURL(id)).path))
    }

    @Test func speechWithoutARecordingLeavesNothingToKeep() {
        let s = store()
        let id = s.begin().id
        s.end(heardSpeech: true)
        #expect(s.session(id) == nil)
    }
}

@MainActor @Suite struct ImportedAudioRetentionTests {
    @Test func importedAudioSurvivesRemovalOfOriginal() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Phone meeting.m4a")
        let bytes = Data([1, 2, 3, 4])
        try bytes.write(to: source)
        let store = SessionStore(root: root.appendingPathComponent("Sessions"))
        let session = try store.beginImport(file: source, recordedAt: Date(), duration: 60)
        #expect(session.sourceFile == "Phone meeting.m4a")
        #expect(session.sourcePath != source.path)
        try FileManager.default.removeItem(at: source)
        let retained = try #require(session.sourcePath)
        #expect(try Data(contentsOf: URL(fileURLWithPath: retained)) == bytes)
        #expect(SessionStore(root: store.root).session(session.id)?.sourcePath == retained)
    }

    @Test func missingSourceDoesNotCreateARecord() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SessionStore(root: root)
        #expect(throws: (any Error).self) {
            _ = try store.beginImport(file: root.appendingPathComponent("absent.m4a"), recordedAt: Date(), duration: 0)
        }
        #expect(store.sessions.isEmpty)
    }
}
