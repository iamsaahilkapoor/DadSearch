import Foundation
import PDFKit
import Vision
import ImageIO

private final class DataBox: @unchecked Sendable {
    var data = Data()
}

/// Pulls searchable text out of files: PDFs, Word/Excel/PowerPoint, plain text, and — via on-device OCR —
/// screenshots, photos of documents and scanned PDFs.
enum ContentExtractor {

    static let plainTextExts: Set<String> = [
        "txt", "md", "csv", "log", "json", "xml", "yaml", "yml", "tex", "ini", "conf", "swift", "py", "js", "ts",
        "html", "htm", "css", "sh", "sql", "tsv", "rtf" // rtf also handled by textutil below
    ]
    static let textutilExts: Set<String> = ["doc", "docx", "rtf", "odt", "rtfd", "webarchive"]
    static let zipXMLExts: Set<String> = ["xlsx", "pptx"]
    static let ocrExts: Set<String> = ["png", "jpg", "jpeg", "heic", "heif", "tiff", "tif", "gif", "bmp", "webp"]

    static func canExtract(ext: String, size: Int64) -> Bool {
        if size <= 0 { return false }
        if ext == "pdf" { return size < 400_000_000 }
        if plainTextExts.contains(ext) || textutilExts.contains(ext) || zipXMLExts.contains(ext) { return size < 200_000_000 }
        if ocrExts.contains(ext) { return size > 15_000 && size < 40_000_000 }
        return false
    }

    static func extract(path: String, ext: String) -> String {
        let url = URL(fileURLWithPath: path)
        if ext == "pdf" { return pdfText(url) }
        if textutilExts.contains(ext) {
            return runTool("/usr/bin/textutil", ["-convert", "txt", "-stdout", path]) ?? ""
        }
        if plainTextExts.contains(ext) { return readPlain(url) }
        if ext == "xlsx" {
            return stripXML(runTool("/usr/bin/unzip", ["-p", path, "xl/sharedStrings.xml"]) ?? "")
        }
        if ext == "pptx" {
            return stripXML(runTool("/usr/bin/unzip", ["-p", path, "ppt/slides/*.xml"]) ?? "")
        }
        if ocrExts.contains(ext) {
            guard let image = loadImage(url, maxPixels: 2400) else { return "" }
            return ocr(image)
        }
        return ""
    }

    // MARK: - Individual formats

    private static func readPlain(_ url: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: 256_000)) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    private static func pdfText(_ url: URL) -> String {
        guard let doc = PDFDocument(url: url) else { return "" }
        let pages = min(doc.pageCount, 60)
        var text = ""
        for i in 0..<pages {
            if let s = doc.page(at: i)?.string { text += s + "\n" }
            if text.count > 60_000 { break }
        }
        // Scanned PDF (no text layer): OCR the first few pages.
        if text.trimmingCharacters(in: .whitespacesAndNewlines).count < 20, doc.pageCount > 0 {
            for i in 0..<min(doc.pageCount, 5) {
                guard let page = doc.page(at: i) else { continue }
                let thumb = page.thumbnail(of: CGSize(width: 1500, height: 2000), for: .mediaBox)
                if let cg = thumb.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    text += ocr(cg) + "\n"
                }
            }
        }
        return text
    }

    private static func loadImage(_ url: URL, maxPixels: Int) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }

    static func ocr(_ image: CGImage) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        if #available(macOS 13.0, *) { request.automaticallyDetectsLanguage = true }
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do { try handler.perform([request]) } catch { return "" }
        let observations = request.results ?? []
        return observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    static func stripXML(_ xml: String) -> String {
        var s = xml.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        for (entity, rep) in [("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&apos;", "'"), ("&#10;", " ")] {
            s = s.replacingOccurrences(of: entity, with: rep)
        }
        return s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    /// Runs a helper tool with a hard timeout so one bad file can never hang the indexer.
    static func runTool(_ executable: String, _ args: [String], timeout: TimeInterval = 20, maxBytes: Int = 400_000) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }

        let box = DataBox()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .background).async {
            box.data = pipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        if group.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            _ = group.wait(timeout: .now() + 2)
        }
        return String(decoding: box.data.prefix(maxBytes), as: UTF8.self)
    }
}

/// Reads file contents in the background, newest files first, politely (low priority, pauses when hot / low power).
final class ExtractionWorker: @unchecked Sendable {
    static let shared = ExtractionWorker()

    private let queue = DispatchQueue(label: "dadsearch.extractor", qos: .background)
    private let stateLock = NSLock()
    private var running = false
    private let store = IndexStore.shared

    func kick() {
        stateLock.lock()
        if running { stateLock.unlock(); return }
        running = true
        stateLock.unlock()

        queue.async { [weak self] in
            self?.drain()
            self?.stateLock.lock()
            self?.running = false
            self?.stateLock.unlock()
        }
    }

    private func drain() {
        while true {
            let batch = store.pendingExtraction(limit: 40)
            if batch.isEmpty { return }
            for job in batch {
                // Be a good citizen: slow down when the Mac is hot or in Low Power Mode.
                let info = ProcessInfo.processInfo
                if info.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue || info.isLowPowerModeEnabled {
                    Thread.sleep(forTimeInterval: 5)
                }
                if FileManager.default.fileExists(atPath: job.path) {
                    let text = autoreleasepool { ContentExtractor.extract(path: job.path, ext: job.ext) }
                    store.setBody(id: job.id, body: text)   // marks extracted=1 even when empty, so we never retry forever
                } else {
                    store.setBody(id: job.id, body: "")
                }
            }
        }
    }
}
