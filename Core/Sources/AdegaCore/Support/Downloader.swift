import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol Downloading: Sendable {
    /// Baixa `url` para `destination` (sobrescreve). Aceita `file://` (cópia local).
    func download(from url: URL, to destination: URL, progress: (@Sendable (Double) -> Void)?) async throws
}

public struct URLSessionDownloader: Downloading {
    public init() {}

    public func download(from url: URL, to destination: URL, progress: (@Sendable (Double) -> Void)?) async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }

        if url.isFileURL {
            try fm.copyItem(at: url, to: destination)
            progress?(1)
            return
        }

        let delegate = DownloadDelegate(destination: destination, progress: progress)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            delegate.continuation = continuation
            session.downloadTask(with: url).resume()
        }
    }
}

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let destination: URL
    let progress: (@Sendable (Double) -> Void)?
    var continuation: CheckedContinuation<Void, Error>?
    private var moveError: Error?

    init(destination: URL, progress: (@Sendable (Double) -> Void)?) {
        self.destination = destination
        self.progress = progress
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            moveError = AdegaError.httpStatus(http.statusCode)
            return
        }
        // O arquivo temporário é apagado quando este método retorna: mover agora.
        do {
            try FileManager.default.moveItem(at: location, to: destination)
        } catch {
            moveError = error
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        progress?(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let continuation = self.continuation
        self.continuation = nil
        if let error {
            continuation?.resume(throwing: AdegaError.downloadFailed(error.localizedDescription))
        } else if let moveError {
            continuation?.resume(throwing: moveError)
        } else {
            progress?(1)
            continuation?.resume()
        }
    }
}
