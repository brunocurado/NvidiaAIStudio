import Foundation
import AppKit
import UniformTypeIdentifiers

/// Utility for saving generated images using NSSavePanel.
/// This avoids macOS permission popups by letting the user explicitly choose the destination.
enum ImageSaver {

    /// Shows an NSSavePanel and writes the image data to the chosen location.
    /// - Parameters:
    ///   - imageData: The raw image data (PNG, JPEG, etc.)
    ///   - suggestedFilename: Default filename to suggest in the save dialog
    ///   - completion: Called with success/failure result
    static func save(
        imageData: Data,
        suggestedFilename: String,
        completion: ((Result<URL, Error>) -> Void)? = nil
    ) {
        let panel = NSSavePanel()
        panel.title = "Save Image"
        panel.message = "Choose where to save the generated image"
        panel.nameFieldStringValue = suggestedFilename
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        // Determine the file type from the filename extension
        let ext = (suggestedFilename as NSString).pathExtension.lowercased()
        if let utType = UTType(filenameExtension: ext) {
            panel.allowedContentTypes = [utType]
        } else {
            // Fallback to PNG
            panel.allowedContentTypes = [UTType.png]
        }

        // Show the panel modally
        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                completion?(.failure(SaveError.cancelled))
                return
            }

            do {
                try imageData.write(to: url, options: .atomic)
                completion?(.success(url))
            } catch {
                completion?(.failure(error))
            }
        }
    }

    enum SaveError: LocalizedError {
        case cancelled

        var errorDescription: String? {
            switch self {
            case .cancelled: return "Save cancelled by user"
            }
        }
    }
}
