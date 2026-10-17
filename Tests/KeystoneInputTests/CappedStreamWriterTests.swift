// CappedStreamWriterTests.swift — pins the streaming size cap used by the
// updater download. In-memory AsyncSequence, real FileHandle in a temp dir.

import Testing
import Foundation
@testable import KeystoneInput

@Suite("CappedStreamWriter")
struct CappedStreamWriterTests {
    private final class Counter: @unchecked Sendable { var n = 0 }

    private struct Source: AsyncSequence {
        typealias Element = UInt8
        let count: Int
        let pulled = Counter()

        struct Iterator: AsyncIteratorProtocol {
            var i = 0
            let count: Int
            let pulled: Counter
            mutating func next() async -> UInt8? {
                guard i < count else { return nil }
                i += 1
                pulled.n = i
                return UInt8(truncatingIfNeeded: i)
            }
        }

        func makeAsyncIterator() -> Iterator { Iterator(count: count, pulled: pulled) }
    }

    /// Runs the writer against a fresh temp file; returns (written, file contents, source).
    private func run(count: Int, limit: Int, chunk: Int = 16) async throws -> (Int64, Data, Source) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ks-capped-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: url) }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        let source = Source(count: count)
        let written = try await CappedStreamWriter.write(source, to: handle, limit: limit, chunkSize: chunk)
        try handle.synchronize()
        return (written, try Data(contentsOf: url), source)
    }

    @Test func underLimitWritesEverything() async throws {
        let (written, data, _) = try await run(count: 40, limit: 100)
        #expect(written == 40)
        #expect(data.count == 40)
        #expect(data.first == 1 && data.last == 40)
    }

    @Test func exactlyAtLimitIsAccepted() async throws {
        let (written, data, _) = try await run(count: 48, limit: 48)
        #expect(written == 48)
        #expect(data.count == 48)
    }

    @Test func emptyStreamIsAccepted() async throws {
        let (written, _, _) = try await run(count: 0, limit: 10)
        #expect(written == 0)
    }

    @Test func oneByteOverLimitThrowsTooLarge() async {
        await #expect(throws: CappedStreamError.tooLarge) {
            _ = try await run(count: 49, limit: 48)
        }
    }

    @Test func overLimitStopsReadingEarly() async throws {
        let source = Source(count: 1_000_000)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ks-capped-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: url) }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        await #expect(throws: CappedStreamError.tooLarge) {
            _ = try await CappedStreamWriter.write(source, to: handle, limit: 100, chunkSize: 16)
        }
        // Stops right after the first byte past the cap instead of draining.
        #expect(source.pulled.n == 101)
    }
}
