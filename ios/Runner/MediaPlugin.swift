import Flutter
import UIKit
import Vision
import PDFKit
import CoreImage
import Speech
import AVFoundation

/// Flutter plugin handling:
///   analyzeImage   → Vision scene/OCR/face analysis → text description
///   removeBackground → VNGenerateForegroundInstanceMask → transparent PNG
///   extractPDF     → PDFKit text extraction
///   editImage      → img2img forwarded to SDPipelineRunner
///
/// Channel: pintsize/media
final class MediaPlugin: NSObject {

    private weak var binaryMessenger: FlutterBinaryMessenger?

    static func register(with messenger: FlutterBinaryMessenger) {
        let plugin = MediaPlugin()
        plugin.binaryMessenger = messenger
        FlutterMethodChannel(name: "pintsize/media", binaryMessenger: messenger)
            .setMethodCallHandler(plugin.handle(_:result:))
    }

    private func handle(_ call: FlutterMethodCall,
                        result: @escaping FlutterResult) {
        switch call.method {

        case "analyzeImage":
            guard let args = call.arguments as? [String: Any],
                  let bytes = args["bytes"] as? FlutterStandardTypedData else {
                result(FlutterError(code: "BAD_ARGS",
                                    message: "analyzeImage requires {bytes: Uint8List}",
                                    details: nil))
                return
            }
            analyzeImage(bytes.data, result: result)

        case "removeBackground":
            guard let args = call.arguments as? [String: Any],
                  let bytes = args["bytes"] as? FlutterStandardTypedData else {
                result(FlutterError(code: "BAD_ARGS",
                                    message: "removeBackground requires {bytes: Uint8List}",
                                    details: nil))
                return
            }
            if #available(iOS 17.0, *) {
                removeBackground(bytes.data, result: result)
            } else {
                result(FlutterError(code: "OS_UNSUPPORTED",
                                    message: "Background removal requires iOS 17+",
                                    details: nil))
            }

        case "extractPDF":
            guard let args = call.arguments as? [String: Any],
                  let path = args["path"] as? String else {
                result(FlutterError(code: "BAD_ARGS",
                                    message: "extractPDF requires {path: String}",
                                    details: nil))
                return
            }
            extractPDF(path: path, result: result)

        case "extractText":
            guard let args = call.arguments as? [String: Any],
                  let path = args["path"] as? String else {
                result(FlutterError(code: "BAD_ARGS",
                                    message: "extractText requires {path: String}",
                                    details: nil))
                return
            }
            extractText(path: path, result: result)

        case "transcribeAudio":
            guard let args = call.arguments as? [String: Any],
                  let path = args["path"] as? String else {
                result(FlutterError(code: "BAD_ARGS",
                                    message: "transcribeAudio requires {path: String}",
                                    details: nil))
                return
            }
            transcribeAudio(path: path, result: result)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // ── Image analysis ────────────────────────────────────────────────────────

    private func analyzeImage(_ data: Data, result: @escaping FlutterResult) {
        guard let cgImage = UIImage(data: data)?.cgImage else {
            result(FlutterError(code: "BAD_IMAGE", message: "Cannot decode image", details: nil))
            return
        }

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        var parts: [String] = []
        let group = DispatchGroup()

        // OCR
        group.enter()
        let textReq = VNRecognizeTextRequest { req, _ in
            defer { group.leave() }
            let texts = (req.results as? [VNRecognizedTextObservation])?
                .compactMap { $0.topCandidates(1).first?.string }
                .filter { $0.count > 2 }
            if let texts = texts, !texts.isEmpty {
                parts.append("Text visible: \(texts.prefix(8).joined(separator: ", "))")
            }
        }
        textReq.recognitionLevel = .accurate

        // Scene classification
        group.enter()
        let classifyReq = VNClassifyImageRequest { req, _ in
            defer { group.leave() }
            let top = (req.results as? [VNClassificationObservation])?
                .filter { $0.confidence > 0.3 }
                .prefix(5)
                .map { $0.identifier.replacingOccurrences(of: "_", with: " ") }
            if let top = top, !top.isEmpty {
                parts.append("Scene: \(top.joined(separator: ", "))")
            }
        }

        // Face detection
        group.enter()
        let faceReq = VNDetectFaceRectanglesRequest { req, _ in
            defer { group.leave() }
            let count = (req.results as? [VNFaceObservation])?.count ?? 0
            if count > 0 {
                parts.append(count == 1 ? "1 person detected" : "\(count) people detected")
            }
        }

        DispatchQueue.global(qos: .userInitiated).async {
            try? handler.perform([textReq, classifyReq, faceReq])
            group.notify(queue: .main) {
                let description = parts.isEmpty
                    ? "An image (no recognisable content detected)"
                    : "[Image analysis]\n" + parts.joined(separator: "\n")
                result(description)
            }
        }
    }

    // ── Background removal ────────────────────────────────────────────────────

    @available(iOS 17.0, *)
    private func removeBackground(_ data: Data, result: @escaping FlutterResult) {
        guard let inputImage = UIImage(data: data),
              let cgImage = inputImage.cgImage else {
            result(FlutterError(code: "BAD_IMAGE", message: "Cannot decode image", details: nil))
            return
        }

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let req = VNGenerateForegroundInstanceMaskRequest()

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([req])
                guard let obs = req.results?.first as? VNInstanceMaskObservation else {
                    result(FlutterError(code: "NO_MASK",
                                        message: "No foreground subject found",
                                        details: nil))
                    return
                }

                // Apply the mask to get a transparent-background image
                let maskedImage = try obs.generateMaskedImage(
                    ofInstances: obs.allInstances,
                    from: handler,
                    croppedToInstancesExtent: false
                )

                // Render the CIImage through a CIContext to a CGImage first —
                // UIImage(ciImage:).pngData() always returns nil (no CGImage
                // backing), which previously broke background removal. Going via
                // a CGImage also preserves the alpha (transparent) channel.
                let ciImage = CIImage(cvPixelBuffer: maskedImage)
                let ciContext = CIContext()
                guard let outputCG = ciContext.createCGImage(
                        ciImage, from: ciImage.extent) else {
                    result(FlutterError(code: "ENCODE_FAILED",
                                        message: "Could not render masked image",
                                        details: nil))
                    return
                }
                let uiImg = UIImage(cgImage: outputCG)
                guard let pngData = uiImg.pngData() else {
                    result(FlutterError(code: "ENCODE_FAILED",
                                        message: "PNG encoding failed",
                                        details: nil))
                    return
                }
                DispatchQueue.main.async {
                    result(FlutterStandardTypedData(bytes: pngData))
                }
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(code: "VISION_ERROR",
                                        message: error.localizedDescription,
                                        details: nil))
                }
            }
        }
    }

    // ── Generic text extraction (txt, csv, rtf, docx) ────────────────────────

    private func extractText(path: String, result: @escaping FlutterResult) {
        DispatchQueue.global(qos: .userInitiated).async {
            let url = URL(fileURLWithPath: path)
            let ext = url.pathExtension.lowercased()

            // Plain text / CSV
            if ext == "txt" || ext == "csv" || ext == "tsv" || ext == "md" || ext == "json" {
                do {
                    let text = try String(contentsOf: url, encoding: .utf8)
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    DispatchQueue.main.async {
                        if trimmed.isEmpty {
                            result(FlutterError(code: "NO_TEXT", message: "File is empty", details: nil))
                        } else {
                            // For CSV/TSV, add a header note
                            let header = (ext == "csv" || ext == "tsv")
                                ? "[CSV file: \(url.lastPathComponent)]\n"
                                : ""
                            result(header + trimmed)
                        }
                    }
                } catch {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "READ_ERROR",
                                            message: error.localizedDescription,
                                            details: nil))
                    }
                }
                return
            }

            // RTF / RTFD / DOC / DOCX via NSAttributedString
            // .officeOpenXML is macOS-only; DOCX falls back to raw UTF-8 read
            let docTypes: [NSAttributedString.DocumentType: [String]] = [
                .rtf:  ["rtf"],
                .rtfd: ["rtfd"],
                .html: ["html", "htm"],
                .plain: ["txt"],
            ]

            var docType: NSAttributedString.DocumentType = .plain
            for (type, exts) in docTypes where exts.contains(ext) {
                docType = type
                break
            }

            do {
                let data = try Data(contentsOf: url)
                let opts: [NSAttributedString.DocumentReadingOptionKey: Any] = [
                    .documentType: docType,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ]
                let attrStr = try NSAttributedString(data: data, options: opts, documentAttributes: nil)
                let text = attrStr.string.trimmingCharacters(in: .whitespacesAndNewlines)
                DispatchQueue.main.async {
                    if text.isEmpty {
                        result(FlutterError(code: "NO_TEXT", message: "Document contains no extractable text", details: nil))
                    } else {
                        result(text)
                    }
                }
            } catch {
                // Fallback: try reading as raw UTF-8
                do {
                    let text = try String(contentsOf: url, encoding: .utf8)
                    DispatchQueue.main.async { result(text) }
                } catch {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "PARSE_ERROR",
                                            message: "Cannot read \(ext) file: \(error.localizedDescription)",
                                            details: nil))
                    }
                }
            }
        }
    }

    // ── PDF text extraction ───────────────────────────────────────────────────

    private func extractPDF(path: String, result: @escaping FlutterResult) {
        DispatchQueue.global(qos: .userInitiated).async {
            let url = URL(fileURLWithPath: path)
            guard let doc = PDFDocument(url: url) else {
                result(FlutterError(code: "OPEN_FAILED",
                                    message: "Cannot open PDF: \(path)",
                                    details: nil))
                return
            }

            var text = ""
            let maxPages = min(doc.pageCount, 30)
            for i in 0..<maxPages {
                if let page = doc.page(at: i),
                   let pageText = page.string {
                    text += pageText + "\n\n"
                }
            }

            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async {
                if trimmed.isEmpty {
                    result(FlutterError(code: "NO_TEXT",
                                        message: "PDF contains no extractable text (may be scanned)",
                                        details: nil))
                } else {
                    result(trimmed)
                }
            }
        }
    }

    // ── Audio transcription ───────────────────────────────────────────────────

    private func transcribeAudio(path: String, result: @escaping FlutterResult) {
        SFSpeechRecognizer.requestAuthorization { status in
            guard status == .authorized else {
                DispatchQueue.main.async {
                    result(FlutterError(code: "PERMISSION_DENIED",
                                        message: "Speech recognition permission denied",
                                        details: nil))
                }
                return
            }

            guard let recognizer = SFSpeechRecognizer(locale: .current),
                  recognizer.isAvailable else {
                DispatchQueue.main.async {
                    result(FlutterError(code: "UNAVAILABLE",
                                        message: "Speech recognizer not available",
                                        details: nil))
                }
                return
            }

            let url = URL(fileURLWithPath: path)
            let request = SFSpeechURLRecognitionRequest(url: url)
            request.shouldReportPartialResults = false
            // Keep transcription on-device where supported (privacy promise);
            // older devices fall back to Apple's servers.
            request.requiresOnDeviceRecognition =
                recognizer.supportsOnDeviceRecognition

            recognizer.recognitionTask(with: request) { response, error in
                DispatchQueue.main.async {
                    if let error = error {
                        result(FlutterError(code: "TRANSCRIPTION_ERROR",
                                            message: error.localizedDescription,
                                            details: nil))
                        return
                    }
                    guard let text = response?.bestTranscription.formattedString,
                          !text.isEmpty else {
                        result(FlutterError(code: "NO_SPEECH",
                                            message: "No speech detected in audio file",
                                            details: nil))
                        return
                    }
                    result(text)
                }
            }
        }
    }
}
