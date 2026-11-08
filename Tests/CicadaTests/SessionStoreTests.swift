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
    @Test func importedAudioSurvivesRemovalOfOriginal() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Phone meeting.m4a")
        let bytes = Data([1, 2, 3, 4])
        try bytes.write(to: source)
        let store = SessionStore(root: root.appendingPathComponent("Sessions"))
        let session = try await store.beginImport(file: source, recordedAt: Date(), duration: 60)
        #expect(session.sourceFile == "Phone meeting.m4a")
        #expect(session.sourcePath != source.path)
        try FileManager.default.removeItem(at: source)
        let retained = try #require(session.sourcePath)
        #expect(try Data(contentsOf: URL(fileURLWithPath: retained)) == bytes)
        #expect(SessionStore(root: store.root).session(session.id)?.sourcePath == retained)
    }

    @Test func missingSourceDoesNotCreateARecord() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SessionStore(root: root)
        await #expect(throws: (any Error).self) {
            _ = try await store.beginImport(file: root.appendingPathComponent("absent.m4a"), recordedAt: Date(), duration: 0)
        }
        #expect(store.sessions.isEmpty)
    }
}

@MainActor @Suite struct AudioHandoffTests {
    @Test func onlyCompletedReadableAudioCanBeShared() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = SessionStore(root: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let live = store.begin()
        try Data([1, 2]).write(to: store.systemAudioURL(live.id))
        var s = live
        s.hasAudio = true
        s.endedAt = Date()
        #expect(store.shareableAudioURL(s) == nil)
        s.id = "completed"
        try FileManager.default.createDirectory(at: store.folder(s.id), withIntermediateDirectories: true)
        try Data([1, 2]).write(to: store.systemAudioURL(s.id))
        #expect(store.shareableAudioURL(s) == store.systemAudioURL(s.id))
        let partial = AudioFileWriter.partial(store.systemAudioURL(s.id))
        try Data([1]).write(to: partial)
        #expect(store.shareableAudioURL(s) == nil)
        try FileManager.default.removeItem(at: partial)
        #expect(store.shareableAudioURL(s) != nil)
        s.importing = true
        #expect(store.shareableAudioURL(s) == nil)
        s.importing = nil
        try FileManager.default.removeItem(at: store.systemAudioURL(s.id))
        #expect(store.shareableAudioURL(s) == nil)
    }

    @Test func duplicateNamesStaySeparateAndDeletingRecordKeepsOriginal() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("meeting.m4a")
        try Data([1]).write(to: source)
        let store = SessionStore(root: root.appendingPathComponent("Sessions"))
        let a = try await store.beginImport(file: source, recordedAt: Date(), duration: 2)
        let b = try await store.beginImport(file: source, recordedAt: Date(), duration: 2)
        #expect(a.id != b.id && a.sourcePath != b.sourcePath)
        store.delete(a.id)
        #expect(FileManager.default.fileExists(atPath: source.path))
        let retained = try #require(b.sourcePath)
        let removed = try #require(a.sourcePath)
        #expect(FileManager.default.fileExists(atPath: retained))
        #expect(!FileManager.default.fileExists(atPath: removed))
    }
}
