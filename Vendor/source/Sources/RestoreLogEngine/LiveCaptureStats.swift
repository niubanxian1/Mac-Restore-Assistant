import Foundation

/// Read-only, incremental projection of a raw log that is still being written.
///
/// Why this exists: the GUI used to show live counters that only ever changed
/// once, at stop, because nothing projected the growing file. Calling
/// `CaptureCoordinator.getStatus` on a timer would have worked numerically but it
/// also *advances session state* (it can declare a dead capture `.interrupted`),
/// which would have put the F05/A10 lifecycle on a UI timer. This type therefore
/// observes the file only: it never writes, never finalizes, never changes state
/// and never decides capture health.
///
/// Cost model: each call reads only the bytes appended since the previous call
/// for the same path. A 6.8 MB log is read once in total, not once per tick.
public actor LiveCaptureStats {
    public struct Snapshot: Sendable, Equatable {
        public let byteCount: Int
        public let eventCount: Int
        /// `false` means the file could not be observed right now (missing,
        /// unreadable, still being created). Callers must render this as
        /// *unknown*, never as a confident zero.
        public let isAvailable: Bool

        public init(byteCount: Int, eventCount: Int, isAvailable: Bool) {
            self.byteCount = byteCount
            self.eventCount = eventCount
            self.isAvailable = isAvailable
        }
    }

    private struct Cursor {
        var offset: Int = 0
        var events: Int = 0
        /// Trailing bytes of an incomplete line, held until its newline arrives.
        var carry = Data()
    }

    private var cursors: [String: Cursor] = [:]

    public init() {}

    /// Observe `path` and return the current projection.
    public func snapshot(forPath path: String) -> Snapshot {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let number = attributes[.size] as? NSNumber else {
            return Snapshot(byteCount: 0, eventCount: 0, isAvailable: false)
        }

        let size = number.intValue
        var cursor = cursors[path] ?? Cursor()

        // The file shrank: it was truncated or replaced. Start over rather than
        // reporting a negative delta or carrying stale counts forward.
        if size < cursor.offset {
            cursor = Cursor()
        }

        guard let handle = FileHandle(forReadingAtPath: path) else {
            // Size is known but content is not readable. Keep the count we proved
            // earlier, but flag the snapshot so the UI shows unknown.
            return Snapshot(byteCount: size, eventCount: cursor.events, isAvailable: false)
        }
        defer { try? handle.close() }

        do {
            try handle.seek(toOffset: UInt64(cursor.offset))
            let fresh = try handle.readToEnd() ?? Data()
            cursor.offset += fresh.count

            var buffer = cursor.carry
            buffer.append(fresh)

            while let newline = buffer.firstIndex(of: 0x0A) {
                let lineData = buffer[buffer.startIndex..<newline]
                buffer = buffer[buffer.index(after: newline)...]
                // PERF-01: 96% of the cold-catch-up cost was EventTaxonomy.classify,
                // which does grapheme-aware String.contains per rule per line
                // (measured: 3303 ms for 28k lines). The needles are pure ASCII, so
                // a UTF-8 byte search is an EXACT prefilter: the ASCII bytes must be
                // contiguous iff the grapheme sequence contains the ASCII needle.
                // Lines that fail it cannot match any rule, so classify is skipped
                // for them — no event is dropped, only a call that would return nil.
                guard Self.mayContainNeedle(lineData) else { continue }
                guard let line = String(data: lineData, encoding: .utf8) else { continue }
                // Same vocabulary as the finalized summary; no rule is relaxed
                // here, so the live count and the final count cannot diverge.
                if EventTaxonomy.classify(line) != nil {
                    cursor.events += 1
                }
            }

            cursor.carry = buffer
            cursors[path] = cursor
            return Snapshot(byteCount: size, eventCount: cursor.events, isAvailable: true)
        } catch {
            return Snapshot(byteCount: size, eventCount: cursor.events, isAvailable: false)
        }
    }

    /// Every needle of the vocabulary, as raw UTF-8, computed once.
    /// Kept in lockstep with `EventTaxonomy.rules` rather than duplicated by hand.
    private static let needleBytes: [Data] =
        EventTaxonomy.rules.flatMap { $0.needles }.map { Data($0.utf8) }

    /// Exact necessary condition: a line can only be classified if one of the rule
    /// needles appears in its bytes. Pure ASCII needles, so byte containment and
    /// grapheme-cluster containment agree; the prefilter never rejects a line that
    /// `EventTaxonomy.classify` would have matched.
    private static func mayContainNeedle(_ line: Data) -> Bool {
        for needle in needleBytes where line.range(of: needle) != nil {
            return true
        }
        return false
    }


    /// Drop the cursor for one path, e.g. when a session ends and the file is no
    /// longer growing.
    public func forget(path: String) {
        cursors[path] = nil
    }
}
