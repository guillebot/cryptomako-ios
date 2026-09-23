import UIKit
import UniformTypeIdentifiers
import CryptoMakoShared

/// Stages shared files into the App Group inbox, then finishes.
/// Host app imports into the current vault directory when unlocked / foregrounded.
final class ShareViewController: UIViewController {
    private let statusLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.text = "Sending to CryptoMako…"
        view.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            statusLabel.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        Task { await processAndFinish() }
    }

    private func processAndFinish() async {
        var count = 0
        if let items = extensionContext?.inputItems as? [NSExtensionItem] {
            for item in items {
                guard let providers = item.attachments else { continue }
                for provider in providers {
                    if await stage(provider: provider) {
                        count += 1
                    }
                }
            }
        }
        await MainActor.run {
            statusLabel.text = count > 0
                ? "Queued \(count) file(s).\nOpen CryptoMako (unlocked) to import."
                : "Nothing to share."
        }
        try? await Task.sleep(nanoseconds: 600_000_000)
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }

    private func stage(provider: NSItemProvider) async -> Bool {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            return await loadFileURL(from: provider)
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            return await loadData(from: provider, type: UTType.image.identifier, defaultName: "shared.jpg")
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
            if await loadFileURL(from: provider) { return true }
            return await loadData(from: provider, type: UTType.movie.identifier, defaultName: "shared.mov")
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            return await loadText(from: provider)
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.data.identifier) {
            return await loadData(from: provider, type: UTType.data.identifier, defaultName: "shared.bin")
        }
        return false
    }

    private func loadFileURL(from provider: NSItemProvider) async -> Bool {
        await withCheckedContinuation { cont in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url: URL?
                if let u = item as? URL {
                    url = u
                } else if let data = item as? Data, let s = String(data: data, encoding: .utf8) {
                    url = URL(string: s)
                } else {
                    url = nil
                }
                var ok = false
                if let url {
                    ok = (try? ShareInbox.stage(fileAt: url)) != nil
                }
                cont.resume(returning: ok)
            }
        }
    }

    private func loadData(from provider: NSItemProvider, type: String, defaultName: String) async -> Bool {
        await withCheckedContinuation { cont in
            provider.loadItem(forTypeIdentifier: type, options: nil) { item, _ in
                var ok = false
                if let url = item as? URL {
                    ok = (try? ShareInbox.stage(fileAt: url)) != nil
                } else if let data = item as? Data {
                    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(defaultName)
                    try? data.write(to: tmp)
                    ok = (try? ShareInbox.stage(fileAt: tmp, preferredName: defaultName)) != nil
                    try? FileManager.default.removeItem(at: tmp)
                } else if let img = item as? UIImage, let data = img.jpegData(compressionQuality: 0.92) {
                    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("shared.jpg")
                    try? data.write(to: tmp)
                    ok = (try? ShareInbox.stage(fileAt: tmp, preferredName: "shared.jpg")) != nil
                    try? FileManager.default.removeItem(at: tmp)
                }
                cont.resume(returning: ok)
            }
        }
    }

    private func loadText(from provider: NSItemProvider) async -> Bool {
        await withCheckedContinuation { cont in
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                var ok = false
                if let text = item as? String {
                    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("shared.txt")
                    try? Data(text.utf8).write(to: tmp)
                    ok = (try? ShareInbox.stage(fileAt: tmp, preferredName: "shared.txt")) != nil
                    try? FileManager.default.removeItem(at: tmp)
                }
                cont.resume(returning: ok)
            }
        }
    }
}
