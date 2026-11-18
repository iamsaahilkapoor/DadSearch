import Testing
@testable import DadSearch
import Foundation

@Suite("DadSearch QueryParser & Ranking Tests")
struct DadSearchTests {

    @Test("Test empty query parsing")
    func testEmptyQuery() {
        let parser = QueryParser()
        let result = parser.parse(query: "   ")
        #expect(result.rawQuery.isEmpty)
        #expect(result.cleanedTerms.isEmpty)
    }

    @Test("Test PDF extension extraction")
    func testPdfExtraction() {
        let parser = QueryParser()
        let result = parser.parse(query: "electric bill pdf")
        #expect(result.detectedFileExtensions.contains("pdf"))
        #expect(result.cleanedTerms.contains("electric"))
        #expect(result.cleanedTerms.contains("bill"))
        #expect(result.inferredCategory == .documents)
    }

    @Test("Test date token parsing: today")
    func testTodayToken() {
        let parser = QueryParser()
        let result = parser.parse(query: "download today")
        #expect(result.dateFilterRange != nil)
        #expect(result.inferredCategory == .downloads)
    }

    @Test("Test Outlook email inference")
    func testOutlookEmailToken() {
        let parser = QueryParser()
        let result = parser.parse(query: "mail from doctor")
        #expect(result.inferredCategory == .emails)
        #expect(result.cleanedTerms.contains("doctor"))
    }

    @Test("Test screenshot inference")
    func testScreenshotInference() {
        let parser = QueryParser()
        let result = parser.parse(query: "screenshot receipt")
        #expect(result.inferredCategory == .screenshots)
        #expect(result.cleanedTerms.contains("receipt"))
    }

    @Test("Test chat attachment inference: whatsapp & telegram")
    func testChatAttachmentInference() {
        let parser = QueryParser()
        let result = parser.parse(query: "whatsapp invoice")
        #expect(result.inferredCategory == .chatAttachments)
        #expect(result.cleanedTerms.contains("invoice"))
    }

    @Test("Test typo tolerance: recipt -> receipt and invoce -> invoice")
    func testTypoCorrections() {
        let parser = QueryParser()
        let result1 = parser.parse(query: "recipt pdf")
        #expect(result1.cleanedTerms.contains("receipt"))
        #expect(result1.inferredCategory == .documents)

        let result2 = parser.parse(query: "invoce today")
        #expect(result2.cleanedTerms.contains("invoice"))
        #expect(result2.dateFilterRange != nil)
    }

    @Test("Test app and contact query inference")
    func testAppAndContactTokens() {
        let parser = QueryParser()
        let appResult = parser.parse(query: "launch safari app")
        #expect(appResult.inferredCategory == .apps)
        #expect(appResult.cleanedTerms.contains("safari"))

        let contactResult = parser.parse(query: "call doctor phone")
        #expect(contactResult.inferredCategory == .contacts)
        #expect(contactResult.cleanedTerms.contains("doctor"))
    }

    @Test("Test relevance ranking: exact match ranks higher than substring")
    func testRelevanceRankingExactMatch() {
        let ranking = RelevanceRankingEngine()
        let parsed = QueryParser().parse(query: "tax")

        let exactItem = SearchItem(
            title: "tax",
            subtitle: "Documents",
            fileURL: nil,
            kind: .document,
            modificationDate: Date()
        )

        let partialItem = SearchItem(
            title: "tax_deductions_2024_old_record",
            subtitle: "Documents",
            fileURL: nil,
            kind: .document,
            modificationDate: Date()
        )

        let ranked = ranking.rank(items: [partialItem, exactItem], parsedQuery: parsed, targetCategory: .all)
        #expect(ranked.first?.title == "tax")
        #expect(ranked.first?.score ?? 0 > ranked.last?.score ?? 0)
    }
}
