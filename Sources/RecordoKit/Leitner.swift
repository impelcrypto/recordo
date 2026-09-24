import Foundation

enum Leitner {
    static let maxBox = 6
    private static let waits: [TimeInterval] = [4 * 3600, 86400, 3 * 86400, 7 * 86400, 14 * 86400, 30 * 86400]

    static func next(box: Int, correct: Bool, now: Date) -> (box: Int, due: Date) {
        guard correct else { return (0, now) }
        let wait = waits[min(max(box, 0), waits.count - 1)]
        return (min(box + 1, maxBox), now.addingTimeInterval(wait))
    }
}
