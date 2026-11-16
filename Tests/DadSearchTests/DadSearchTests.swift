import Testing
@testable import DadSearch
import Foundation

@Suite("DadSearch QueryParser Tests")
struct QueryParserTests {

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
}
