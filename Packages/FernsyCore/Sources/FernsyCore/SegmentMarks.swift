import Foundation

/// Where an episode's intro, recap and final credits are, from the server's media segments or,
/// without a credits segment, from a chapter named as credits (jellyfin-media-segments, design
/// 2 and 3). Times in seconds.
public struct SegmentMarks: Equatable, Sendable {
    public enum SkipKind: String, Sendable { case intro, recap }

    /// A part the player offers to skip.
    public struct Skip: Equatable, Sendable {
        public var kind: SkipKind
        public var start: Double
        public var end: Double

        public init(kind: SkipKind, start: Double, end: Double) {
            self.kind = kind
            self.start = start
            self.end = end
        }
    }

    /// The final credits: the next-episode card appears at `start`; it counts down only when
    /// the credits run (nearly) to the end of the file.
    public struct Credits: Equatable, Sendable {
        public var start: Double
        public var reachesEnd: Bool

        public init(start: Double, reachesEnd: Bool) {
            self.start = start
            self.reachesEnd = reachesEnd
        }
    }

    public var skips: [Skip]
    public var credits: Credits?

    public init(skips: [Skip] = [], credits: Credits? = nil) {
        self.skips = skips
        self.credits = credits
    }

    public static let none = SegmentMarks()

    /// Credits that end at most this long before the end of the file count as reaching it.
    public static let endTolerance: Double = 10
    /// Outro and Preview segments closer than this belong to one credits block.
    static let joinGap: Double = 2
    /// Shorter segments are noise.
    static let minimumLength: Double = 3
    /// Chapter names that mark the final credits (whole name, any case).
    static let creditsChapterNames: Set<String> = ["credits", "end credits", "ending credits", "closing credits", "ending", "abspann", "outro"]
    /// Chapter names that may follow the credits and still end the episode.
    static let previewChapterNames: Set<String> = ["preview", "next episode", "next time", "vorschau"]

    public var hasMarks: Bool { !skips.isEmpty || credits != nil }

    /// The skippable part playing at `position`.
    public func skip(at position: Double) -> Skip? {
        skips.first { position >= $0.start && position < $0.end - 0.5 }
    }

    public func isInCredits(_ position: Double) -> Bool {
        guard let credits else { return false }
        return position >= credits.start
    }

    public static func make(segments: [JFMediaSegment], chapters: [JFChapter], runtime: Double?) -> SegmentMarks {
        let runtime = runtime.flatMap { $0 > 0 ? $0 : nil }
        struct Part { var type: String; var start: Double; var end: Double }
        let parts: [Part] = segments.compactMap { segment in
            let start = max(0, Double(segment.startTicks) / 10_000_000)
            var end = Double(segment.endTicks) / 10_000_000
            if let runtime {
                guard start < runtime else { return nil }
                end = min(end, runtime)
            }
            guard end - start >= minimumLength else { return nil }
            return Part(type: segment.type.lowercased(), start: start, end: end)
        }.sorted { $0.start < $1.start }

        var credits: Credits?
        if let last = parts.last(where: { $0.type == "outro" }) {
            var blockEnd = last.end
            for part in parts where (part.type == "outro" || part.type == "preview") && part.start >= last.start && part.start <= blockEnd + joinGap {
                blockEnd = max(blockEnd, part.end)
            }
            credits = Credits(start: last.start, reachesEnd: runtime.map { blockEnd >= $0 - endTolerance } ?? true)
        } else {
            credits = creditsFromChapters(chapters, runtime: runtime)
        }

        let skips: [Skip] = parts.compactMap { part in
            let kind: SkipKind
            switch part.type {
            case "intro": kind = .intro
            case "recap": kind = .recap
            default: return nil
            }
            if let credits, part.start >= credits.start { return nil }
            return Skip(kind: kind, start: part.start, end: part.end)
        }
        return SegmentMarks(skips: skips, credits: credits)
    }

    /// The last chapter named as credits, in the second half of the episode (opening credits
    /// are not the end). It reaches the end unless a chapter other than a preview follows.
    static func creditsFromChapters(_ chapters: [JFChapter], runtime: Double?) -> Credits? {
        func name(_ chapter: JFChapter) -> String { (chapter.name ?? "").trimmingCharacters(in: .whitespaces).lowercased() }
        let sorted = chapters.sorted { $0.startPositionTicks < $1.startPositionTicks }
        guard let index = sorted.lastIndex(where: { creditsChapterNames.contains(name($0)) }) else { return nil }
        let start = Double(sorted[index].startPositionTicks) / 10_000_000
        if let runtime, start < runtime / 2 || start >= runtime { return nil }
        let after = sorted[(index + 1)...]
        return Credits(start: start, reachesEnd: after.allSatisfy { previewChapterNames.contains(name($0)) })
    }
}

extension JFMediaSegment {
    /// `JF_TESTSEGMENTS` (debug builds): "intro:5-20,outro:96-120" in seconds; types as the
    /// server names them, any case. Malformed parts are left out.
    public static func parseTestList(_ text: String) -> [JFMediaSegment] {
        text.split(separator: ",").compactMap { part in
            let pieces = part.split(separator: ":")
            guard pieces.count == 2 else { return nil }
            let range = pieces[1].split(separator: "-").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard range.count == 2, range[1] > range[0] else { return nil }
            let name = pieces[0].trimmingCharacters(in: .whitespaces)
            return JFMediaSegment(type: name.prefix(1).uppercased() + name.dropFirst().lowercased(),
                                  startTicks: Int64(range[0] * 10_000_000), endTicks: Int64(range[1] * 10_000_000))
        }
    }
}

/// The two player settings of Settings › Jellyfin Server (per device, not synced).
public struct SegmentPreferences: Equatable, Sendable {
    public enum Skipping: String, CaseIterable, Sendable {
        case button, auto, never
    }

    public static let autoplayKey = "jellyfin.autoplayNext"
    public static let skippingKey = "jellyfin.skipSegments"

    public var autoplayNext: Bool
    public var skipping: Skipping

    public init(autoplayNext: Bool = true, skipping: Skipping = .button) {
        self.autoplayNext = autoplayNext
        self.skipping = skipping
    }

    public static func read(_ defaults: UserDefaults = .standard) -> SegmentPreferences {
        SegmentPreferences(autoplayNext: defaults.object(forKey: autoplayKey) as? Bool ?? true,
                           skipping: defaults.string(forKey: skippingKey).flatMap(Skipping.init(rawValue:)) ?? .button)
    }

    public static var settings: SegmentPreferences { read() }
}
