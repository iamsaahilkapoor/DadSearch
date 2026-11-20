import Foundation

public final class BusinessSynonymRings: Sendable {
    public static let shared = BusinessSynonymRings()

    // Rings of equivalent business terms
    private let synonymRings: [[String]] = [
        ["invoice", "bill", "statement", "receipt", "chalan", "tax invoice"],
        ["po", "purchase order", "order", "indent"],
        ["quote", "quotation", "estimate", "bid", "proposal"],
        ["cert", "certificate", "calibration", "test report", "compliance"],
        ["contract", "agreement", "nda", "terms"],
        ["salary", "payslip", "pay slip", "compensation"],
        ["insurance", "policy", "premium", "coverage"]
    ]

    public init() {}

    public func expandQuery(_ rawQuery: String) -> [String] {
        let words = rawQuery.lowercased().components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        var expanded = Set(words)

        for word in words {
            for ring in synonymRings {
                if ring.contains(word) {
                    for synonym in ring {
                        expanded.insert(synonym)
                    }
                }
            }
        }

        return Array(expanded)
    }
}
