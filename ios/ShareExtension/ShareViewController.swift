import UIKit
import Social
import UniformTypeIdentifiers

/// Share extension: receives text or images from other apps,
/// stores them in a shared App Group, and opens PintSizeAI.
class ShareViewController: UIViewController {

    // Must match the App Group in both targets' entitlements.
    // (requires paid Apple Developer account to provision)
    private static let appGroupID = "group.com.pintsize.ai"
    private static let urlScheme  = "pintsize-ai://share"

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Task { await handleShare() }
    }

    private func handleShare() async {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            done(); return
        }

        var sharedText: String?
        var sharedImageData: Data?

        for item in items {
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    let text = try? await provider.loadItem(
                        forTypeIdentifier: UTType.plainText.identifier) as? String
                    sharedText = text
                }
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    let url = try? await provider.loadItem(
                        forTypeIdentifier: UTType.url.identifier) as? URL
                    if let url, !url.isFileURL {
                        sharedText = (sharedText ?? "") + url.absoluteString
                    }
                }
                if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    if let url = try? await provider.loadItem(
                        forTypeIdentifier: UTType.image.identifier) as? URL {
                        sharedImageData = try? Data(contentsOf: url)
                    } else if let img = try? await provider.loadItem(
                        forTypeIdentifier: UTType.image.identifier) as? UIImage {
                        sharedImageData = img.jpegData(compressionQuality: 0.85)
                    }
                }
            }
        }

        // Persist in shared container
        if let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupID) {

            let pending = container.appendingPathComponent("pending_share.json")
            var payload: [String: Any] = [:]
            if let text = sharedText { payload["text"] = text }
            if let imgData = sharedImageData {
                let imgPath = container.appendingPathComponent("shared_image.jpg")
                try? imgData.write(to: imgPath)
                payload["imagePath"] = imgPath.path
            }
            let json = try? JSONSerialization.data(withJSONObject: payload)
            try? json?.write(to: pending)
        }

        // Open the main app
        if let url = URL(string: Self.urlScheme) {
            _ = try? await extensionContext?.open(url)
        }
        done()
    }

    private func done() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
}
