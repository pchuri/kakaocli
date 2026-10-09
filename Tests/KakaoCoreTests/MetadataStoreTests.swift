import Foundation
import Testing
@testable import KakaoCore

private func temporaryMetadataURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        .appendingPathComponent("metadata.json")
}

@Test func metadataRoundTripsDatesAndChatFields() throws {
    let url = temporaryMetadataURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let store = MetadataStore(fileURL: url)
    #expect(store.loadError == nil)
    store.update(chatId: 42, name: "친구들", memberCount: 3, chatType: 2, messageCount: 100)
    let originalDate = try #require(store.info(for: 42)?.lastHarvested)
    try store.save()

    let reloaded = MetadataStore(fileURL: url)
    #expect(reloaded.loadError == nil)
    #expect(reloaded.count == 1)
    let info = try #require(reloaded.info(for: 42))
    #expect(info.displayName == "친구들")
    #expect(info.memberCount == 3)
    #expect(info.chatType == 2)
    #expect(info.messageCount == 100)
    let date = try #require(info.lastHarvested)
    #expect(abs(date.timeIntervalSince(originalDate)) < 1) // ISO-8601 uses whole seconds.

    reloaded.update(chatId: 99, name: "Another chat")
    try reloaded.save()
    let final = MetadataStore(fileURL: url)
    #expect(final.count == 2)
    #expect(final.name(for: 42) == "친구들")
}

@Test func metadataLoadsExistingISO8601AndMissingOptionalFields() throws {
    let url = temporaryMetadataURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let json = #"{"42":{"displayName":"Alice","lastHarvested":"2026-03-30T15:32:12Z"},"99":{"displayName":"Bob"}}"#
    try Data(json.utf8).write(to: url)
    let store = MetadataStore(fileURL: url)
    #expect(store.loadError == nil)
    #expect(store.count == 2)
    #expect(store.info(for: 42)?.lastHarvested == ISO8601DateFormatter().date(from: "2026-03-30T15:32:12Z"))
    #expect(store.info(for: 99)?.lastHarvested == nil)
    try store.save()
    #expect(MetadataStore(fileURL: url).count == 2)
}

@Test(arguments: ["{broken", #"{"42":{"displayName":"Alice","lastHarvested":"invalid-date"}}"#])
func metadataPreservesOriginalBytesAfterDecodeFailure(json: String) throws {
    let url = temporaryMetadataURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let original = Data(json.utf8)
    try original.write(to: url)
    let store = MetadataStore(fileURL: url)
    #expect(store.loadError != nil)
    store.update(chatId: 99, name: "New chat")
    #expect(throws: (any Error).self) { try store.save() }
    #expect(try Data(contentsOf: url) == original)
}

@Test func metadataReadFailureAlsoBlocksSave() throws {
    let url = temporaryMetadataURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    // A directory cannot be read or overwritten as a metadata file.
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    let store = MetadataStore(fileURL: url)
    #expect(store.loadError != nil)
    #expect(throws: (any Error).self) { try store.save() }
    var isDirectory: ObjCBool = false
    #expect(FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory))
    #expect(isDirectory.boolValue)
}
