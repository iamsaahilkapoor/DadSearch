import Foundation
import PDFKit
@preconcurrency import Vision
import AppKit

public final class DocumentContentExtractor: @unchecked Sendable {
    public static let shared = DocumentContentExtractor()

    private let db = SearchIndexDatabase.shared
    private let radar = ArrivalRadarService.shared
    private let rescue = AttachmentRescueService.shared

    private init() {}

    public func indexFile(at url: URL) async {
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        // Skip directories for content extraction
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else {
            return
        }

        let filename = url.lastPathComponent
        let ext = url.pathExtension.lowercased()

        // 1. Determine item kind
        let kind = determineKind(for: url, extension: ext)

        // 2. Extract Arrival Radar metadata
        let metadata = radar.extractMetadata(for: url)

        // 3. Extract text content based on file type
        var content = ""
        if ext == "pdf" {
            content = extractPDFText(from: url)
        } else if isImage(ext: ext) {
            content = await extractImageOCRText(from: url)
        } else if ext == "txt" || ext == "csv" || ext == "rtf" {
            content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        }

        // 4. If this is an attachment in a temp folder, rescue it via APFS clone
        var finalURL = url
        if url.path.contains("Attachments") || url.path.contains("Mail Downloads") {
            if let rescued = rescue.rescueAttachment(from: url, sourceApp: metadata.downloadingApp ?? "Email") {
                finalURL = rescued
            }
        }

        let fileSize = (try? finalURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        let modDate = (try? finalURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()

        let whereFromsString = metadata.whereFroms.joined(separator: " ")
        let sourceDomain = metadata.primaryDomain ?? ""
        let sourceApp = metadata.downloadingApp ?? ""

        var subtitle = (finalURL.path as NSString).abbreviatingWithTildeInPath
        if !sourceDomain.isEmpty {
            subtitle = "\(sourceDomain) • \(subtitle)"
        } else if !sourceApp.isEmpty {
            subtitle = "\(sourceApp) • \(subtitle)"
        }

        let doc = IndexedDocument(
            id: finalURL.path,
            title: filename,
            content: content,
            subtitle: subtitle,
            path: finalURL.path,
            whereFroms: whereFromsString,
            sourceApp: sourceApp,
            kind: kind.rawValue,
            dateAdded: metadata.dateAdded,
            modDate: modDate,
            aliases: "",
            fileSize: Int64(fileSize)
        )

        db.upsert(document: doc)
    }

    private func extractPDFText(from url: URL) -> String {
        guard let pdfDoc = PDFDocument(url: url) else { return "" }
        var fullText = ""
        let pageCount = min(pdfDoc.pageCount, 15) // Index first 15 pages for speed
        for i in 0..<pageCount {
            if let page = pdfDoc.page(at: i), let pageText = page.string {
                fullText += pageText + " "
            }
        }
        return fullText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractImageOCRText(from url: URL) async -> String {
        guard let image = NSImage(contentsOf: url),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return ""
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
            guard let observations = request.results else {
                return ""
            }
            let recognizedStrings = observations.compactMap { observation in
                observation.topCandidates(1).first?.string
            }
            return recognizedStrings.joined(separator: " ")
        } catch {
            return ""
        }
    }

    private func determineKind(for url: URL, extension ext: String) -> SearchItemKind {
        let pathLower = url.path.lowercased()
        let nameLower = url.lastPathComponent.lowercased()

        if nameLower.hasPrefix("screenshot") || nameLower.hasPrefix("screen shot") || pathLower.contains("screenshots") {
            return .screenshot
        }
        if pathLower.contains("messages/attachments") || pathLower.contains("whatsapp") || pathLower.contains("telegram") {
            return .chatAttachment
        }
        if pathLower.contains("outlook") || pathLower.contains("mail") {
            return .email
        }
        if pathLower.contains("/downloads/") {
            return .download
        }

        switch ext {
        case "pdf", "doc", "docx", "pages", "numbers", "xls", "xlsx", "txt", "rtf", "ppt", "pptx":
            return .document
        case "png", "jpg", "jpeg", "heic", "webp", "gif", "tiff":
            return .image
        case "zip", "tar", "gz", "7z", "dmg", "pkg":
            return .archive
        case "app":
            return .application
        default:
            return .other
        }
    }

    private func isImage(ext: String) -> Bool {
        return ["png", "jpg", "jpeg", "heic", "webp", "tiff"].contains(ext)
    }
}
