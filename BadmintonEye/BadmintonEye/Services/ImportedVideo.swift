// ImportedVideo.swift
// Streamed photo-library video import.
//
// `PhotosPickerItem.loadTransferable(type: Data.self)` loads the ENTIRE video
// into RAM before it can be written out — a multi-GB clip will spike memory and
// can kill the app. `ImportedVideo` instead uses `FileRepresentation`, so PhotosUI
// streams the asset (including any silent iCloud download) straight to a file on
// disk, and we only copy that file into our own temporary location.

import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// Errors surfaced to the user when a photo-library video import fails.
enum VideoImportError: LocalizedError {
    /// The picker returned no movie content for the selected item.
    case unsupportedItem
    /// The imported file is missing or has zero bytes on disk.
    case emptyFile

    var errorDescription: String? {
        switch self {
        case .unsupportedItem:
            return String(localized: "The selected item is not a supported video.")
        case .emptyFile:
            return String(localized: "The video could not be copied from your library. Please try again.")
        }
    }
}

/// A video imported from the photo library via a file representation,
/// so the asset is streamed to disk and never loaded into memory.
struct ImportedVideo: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            ImportedVideo(url: try copyToUniqueTemporaryURL(from: received.file))
        }
    }

    /// Copies `source` (a transfer-scoped file that PhotosUI deletes after the
    /// closure returns) to a unique URL in the temporary directory.
    static func copyToUniqueTemporaryURL(
        from source: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        let ext = source.pathExtension.isEmpty ? "mov" : source.pathExtension
        let destination = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
        try fileManager.copyItem(at: source, to: destination)
        return destination
    }

    /// Verifies the imported file exists and is non-empty.
    /// - Throws: `VideoImportError.emptyFile` if missing or zero bytes.
    static func validate(url: URL, fileManager: FileManager = .default) throws {
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        guard let size = attributes?[.size] as? UInt64, size > 0 else {
            throw VideoImportError.emptyFile
        }
    }
}
