import Foundation

/// A text too long for its room that slides to its end and back like a news ticker
/// (tvos-guide-name-ticker): it rests at its beginning, slides until its end shows, rests, slides
/// back, and goes on like that.
public enum TickerMotion {
    /// Points per second.
    public static let speed: Double = 40
    /// Seconds the text stands still at its beginning and at its end.
    public static let rest: TimeInterval = 1

    /// How far the text has moved to the left `elapsed` seconds after it started, for a text
    /// `distance` points longer than its room; 0 for a text that fits.
    public static func offset(after elapsed: TimeInterval, distance: Double, speed: Double = speed, rest: TimeInterval = rest) -> Double {
        guard distance > 0, speed > 0, elapsed > 0 else { return 0 }
        let pass = distance / speed
        let time = elapsed.truncatingRemainder(dividingBy: 2 * (rest + pass))
        if time < rest { return 0 }
        if time < rest + pass { return (time - rest) * speed }
        if time < 2 * rest + pass { return distance }
        return distance - (time - 2 * rest - pass) * speed
    }
}
