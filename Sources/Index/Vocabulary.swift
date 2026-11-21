import Foundation

/// Every word that appears in a file name, sender or subject on this Mac.
/// Used to turn "invoce" into "invoice" using the user's OWN words, not a 20-word dictionary.
final class Vocabulary: @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [String: Int] = [:]
    private var byLength: [Int: [String]] = [:]
    private let maxWords = 400_000

    static func tokens(in text: String) -> [String] {
        var out: [String] = []
        var current = ""
        for ch in text.lowercased() {
            if ch.isLetter || ch.isNumber {
                current.append(ch)
            } else {
                if current.count >= 3 && current.count <= 24 { out.append(current) }
                current.removeAll(keepingCapacity: true)
            }
        }
        if current.count >= 3 && current.count <= 24 { out.append(current) }
        return out
    }

    func add(_ text: String) {
        let toks = Vocabulary.tokens(in: text)
        guard !toks.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        for t in toks {
            if let c = counts[t] {
                counts[t] = c + 1
            } else if counts.count < maxWords {
                counts[t] = 1
                byLength[t.count, default: []].append(t)
            }
        }
    }

    func contains(_ token: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return counts[token] != nil
    }

    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return counts.count
    }

    /// Words in the index within edit distance 1 (short words) or 2 (long words), most common first.
    func suggestions(for token: String, maxResults: Int = 4) -> [String] {
        let t = token.lowercased()
        guard t.count >= 4 else { return [] }
        let maxDist = t.count >= 7 ? 2 : 1
        let target = t.unicodeScalars.map { $0.value }

        lock.lock()
        var pool: [String] = []
        for len in max(3, t.count - maxDist)...(t.count + maxDist) {
            if let words = byLength[len] { pool.append(contentsOf: words) }
        }
        let snapshotCounts = counts
        lock.unlock()

        if snapshotCounts[t] != nil { return [] }

        var scored: [(word: String, dist: Int, freq: Int)] = []
        for w in pool {
            let d = Vocabulary.distance(target, w.unicodeScalars.map { $0.value }, limit: maxDist)
            if d <= maxDist { scored.append((w, d, snapshotCounts[w] ?? 1)) }
        }
        scored.sort { a, b in
            if a.dist != b.dist { return a.dist < b.dist }
            return a.freq > b.freq
        }
        return scored.prefix(maxResults).map { $0.word }
    }

    /// Optimal string alignment distance (insert / delete / substitute / swap adjacent). Returns limit+1 if larger.
    static func distance(_ a: [UInt32], _ b: [UInt32], limit: Int) -> Int {
        if abs(a.count - b.count) > limit { return limit + 1 }
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev2 = [Int](repeating: 0, count: b.count + 1)
        var prev = Array(0...b.count)
        var cur = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            cur[0] = i
            var rowMin = cur[0]
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                var v = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
                if i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1] {
                    v = min(v, prev2[j - 2] + 1)
                }
                cur[j] = v
                rowMin = min(rowMin, v)
            }
            if rowMin > limit { return limit + 1 }
            prev2 = prev
            prev = cur
        }
        return prev[b.count]
    }
}
