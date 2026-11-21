import Testing
@testable import DadSearch
import Foundation

@Suite("QueryParser")
struct QueryParserTests {
    let parser = QueryParser()

    @Test func emptyQuery() {
        let r = parser.parse(query: "   ")
        #expect(r.rawQuery.isEmpty)
        #expect(r.allTerms.isEmpty)
    }

    @Test func extensionWordIsFilterNotText() {
        let r = parser.parse(query: "electric bill pdf")
        #expect(r.detectedFileExtensions == ["pdf"])
        #expect(r.cleanedTerms == ["electric", "bill"])
    }

    @Test func ordinaryWordsAreNeverSwallowed() {
        // v1 routed "phone bill" to Contacts and dropped words like "meeting", "word", "message".
        let r = parser.parse(query: "phone bill")
        #expect(r.cleanedTerms == ["phone", "bill"])
        #expect(!r.wantsContacts)
        #expect(parser.parse(query: "meeting notes").cleanedTerms == ["meeting", "notes"])
        #expect(parser.parse(query: "call").cleanedTerms == ["call"])
    }

    @Test func multiWordQueryKeepsEveryWord() {
        #expect(parser.parse(query: "tax invoice march 2025").cleanedTerms == ["tax", "invoice", "march", "2025"])
    }

    @Test func todayIsHardFilterMonthIsOnlyAHint() {
        let r = parser.parse(query: "invoice today")
        #expect(r.dateFilterRange != nil)
        #expect(r.cleanedTerms == ["invoice"])
        let m = parser.parse(query: "invoice march")
        #expect(m.dateFilterRange == nil)
        #expect(m.softDateRange != nil)
        #expect(m.cleanedTerms.contains("march"))
    }

    @Test func kindWordsBecomeHints() {
        let r = parser.parse(query: "email from doctor")
        #expect(r.kindHints == [.email])
        #expect(r.cleanedTerms == ["doctor"])
        #expect(parser.parse(query: "screenshot receipt").kindHints == [.screenshot])
        #expect(parser.parse(query: "whatsapp invoice").sourceHints == ["whatsapp"])
    }

    @Test func quotedPhrase() {
        let r = parser.parse(query: "\"tax invoice\" 2025")
        #expect(r.phrases == ["tax invoice"])
        #expect(r.cleanedTerms == ["2025"])
    }

    @Test func knownTypoIsCorrected() {
        let r = parser.parse(query: "recipt pdf")
        #expect(r.cleanedTerms == ["receipt"])
    }
}

@Suite("Vocabulary")
struct VocabularyTests {
    @Test func editDistance() {
        func d(_ a: String, _ b: String) -> Int {
            Vocabulary.distance(a.unicodeScalars.map { $0.value }, b.unicodeScalars.map { $0.value }, limit: 3)
        }
        #expect(d("invoice", "invoice") == 0)
        #expect(d("invoce", "invoice") == 1)
        #expect(d("recieve", "receive") == 1)   // adjacent swap
        #expect(d("abc", "xyz") > 2)
    }

    @Test func suggestsFromOwnWords() {
        let v = Vocabulary()
        v.add("Kyoritsu Clamp Meter calibration certificate invoice")
        #expect(v.suggestions(for: "calibraton").first == "calibration")
        #expect(v.suggestions(for: "invoce").first == "invoice")
        #expect(v.suggestions(for: "invoice").isEmpty)   // already a real word
    }
}

@Suite("IndexStore")
struct IndexStoreTests {
    func makeStore() -> IndexStore {
        let s = IndexStore(path: ":memory:")
        s.upsert([
            IndexRecord(key: "/d/Statement_83742.pdf", path: "/d/Statement_83742.pdf", name: "Statement_83742.pdf",
                        kind: .document, source: "file", ext: "pdf", size: 10, mtime: Date(), added: Date(),
                        origin: "Chrome airtel.in", body: "Airtel postpaid bill GST invoice"),
            IndexRecord(key: "/d/Tax Invoice March 2025.pdf", path: "/d/Tax Invoice March 2025.pdf", name: "Tax Invoice March 2025.pdf",
                        kind: .document, source: "file", ext: "pdf", size: 10, mtime: Date(timeIntervalSinceNow: -86_400 * 90)),
            IndexRecord(key: "/h/.zshrc", path: "/h/.zshrc", name: ".zshrc", kind: .other, source: "file", ext: "", size: 5,
                        mtime: Date(), hidden: true),
            IndexRecord(key: "outlook:p:1", path: nil, name: "Quotation for Additel 286", kind: .email, source: "outlook",
                        mtime: Date(), added: Date(), sender: "rahul@abc.com", ref: "1", body: "please find the quotation attached")
        ])
        return s
    }

    @Test func multiWordAndSubstring() {
        let s = makeStore()
        var q = StoreQuery(); q.termGroups = [["tax"], ["invoic"]]
        #expect(s.search(q).map { $0.name } == ["Tax Invoice March 2025.pdf"])
    }

    @Test func findsByWhereItCameFromAndByEmailSenderAndBody() {
        let s = makeStore()
        var q = StoreQuery(); q.termGroups = [["airtel"]]
        #expect(s.search(q).first?.name == "Statement_83742.pdf")
        q.termGroups = [["rahul"]]
        #expect(s.search(q).first?.kind == .email)
        q.termGroups = [["postpaid"]]
        #expect(s.search(q).count == 1)
    }

    @Test func hiddenFilesAreFoundUnlessExcluded() {
        let s = makeStore()
        var q = StoreQuery(); q.termGroups = [["zshrc"]]
        #expect(s.search(q).count == 1)
        q.includeHidden = false
        #expect(s.search(q).isEmpty)
    }

    @Test func shortTokensUseLikeFallback() {
        let s = makeStore()
        var q = StoreQuery(); q.termGroups = [["zs"]]   // < 3 chars: trigram cannot match, LIKE must
        #expect(s.search(q).isEmpty == false)
    }

    @Test func noResultCapBeforeRanking() {
        let s = IndexStore(path: ":memory:")
        s.upsert((0..<500).map { i in
            IndexRecord(key: "/x/report\(i).txt", path: "/x/report\(i).txt", name: "report\(i).txt", kind: .document, source: "file", ext: "txt", size: 1, mtime: Date())
        })
        var q = StoreQuery(); q.termGroups = [["report"]]; q.limit = 1000
        #expect(s.search(q).count == 500)   // v1 truncated to 80 before ranking
    }

    @Test func learnedAliasFindsFile() {
        let s = makeStore()
        s.learn(key: "/d/Statement_83742.pdf", terms: ["mobile", "recharge"])
        var q = StoreQuery(); q.termGroups = [["recharge"]]
        #expect(s.search(q).first?.name == "Statement_83742.pdf")
    }

    @Test func universalSearchTiers() {
        // Typo tolerance end-to-end using the shared store would touch the real index, so test the pieces:
        let s = makeStore()
        s.vocabulary.add("invoice statement")
        #expect(s.vocabulary.suggestions(for: "invoce").contains("invoice"))
        #expect(Lexicon.synonymIndex["bill"]?.contains("invoice") == true)
    }
}

@Suite("Outlook helpers")
struct OutlookHelperTests {
    @Test func dateFormats() {
        let unix = OutlookLegacyConnector.date(from: 1_700_000_000)!
        #expect(Int(unix.timeIntervalSince1970) == 1_700_000_000)
        let ms = OutlookLegacyConnector.date(from: 1_700_000_000_000)!
        #expect(Int(ms.timeIntervalSince1970) == 1_700_000_000)
        let cf = OutlookLegacyConnector.date(from: 700_000_000)!   // 2001-epoch seconds
        #expect(cf.timeIntervalSinceReferenceDate == 700_000_000)
    }

    @Test func rfc2047() {
        #expect(RFC2047.decode("=?UTF-8?B?SGVsbG8gV29ybGQ=?=") == "Hello World")
        #expect(RFC2047.decode("=?ISO-8859-1?Q?Caf=E9_menu?=") == "Café menu")
    }
}
