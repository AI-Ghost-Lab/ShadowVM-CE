import Foundation
import Logging
import ShadowVMCore

enum ShadowVMCELogging {
  private static var configured = false
  static let logger = Logging.Logger(label: "com.shadowvm.ce")

  static func configure() {
    guard !configured else { return }
    configured = true
    let logURL = logFileURL()
    LoggingSystem.bootstrap { label in
      var handler = FileLogHandler(label: label, fileURL: logURL)
      handler.logLevel = Logging.Logger.Level.debug
      return handler
    }
    ShadowVMLog.setHandler { level, message in
      logger.log(level: map(level), "\(message)")
    }
  }

  static func log(
    _ level: Logging.Logger.Level = .info,
    _ message: @autoclosure () -> String
  ) {
    logger.log(level: level, "\(message())")
  }

  static func log(_ message: @autoclosure () -> String) {
    log(.info, message())
  }

  private static func map(_ level: LogLevel) -> Logging.Logger.Level {
    switch level {
    case .debug:
      return .debug
    case .info:
      return .info
    case .warning:
      return .warning
    case .error:
      return .error
    }
  }

  private static func logFileURL() -> URL {
    let logsDir = ShadowVMConfig.shared.logsDir
    try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
    return logsDir.appendingPathComponent("shadowvm-ce.log")
  }
}

func GXDLogDebug(_ message: @autoclosure () -> String) {
  ShadowVMCELogging.log(.debug, message())
}

func GXDLogInfo(_ message: @autoclosure () -> String) {
  ShadowVMCELogging.log(.info, message())
}

func GXDLogWarn(_ message: @autoclosure () -> String) {
  ShadowVMCELogging.log(.warning, message())
}

func GXDLogError(_ message: @autoclosure () -> String) {
  ShadowVMCELogging.log(.error, message())
}

private struct FileLogHandler: Logging.LogHandler {
  var logLevel: Logging.Logger.Level = .info
  var metadata: Logging.Logger.Metadata = [:]
  private let label: String
  private let storage: FileLogHandlerStorage

  init(label: String, fileURL: URL) {
    self.label = label
    self.storage = FileLogHandlerStorage(fileURL: fileURL)
  }

  subscript(metadataKey key: String) -> Logging.Logger.Metadata.Value? {
    get { metadata[key] }
    set { metadata[key] = newValue }
  }

  func log(
    level: Logging.Logger.Level,
    message: Logging.Logger.Message,
    metadata: Logging.Logger.Metadata?,
    source: String,
    file: String,
    function: String,
    line: UInt
  ) {
    guard level >= logLevel else { return }
    var combined = self.metadata
    if let metadata {
      combined.merge(metadata, uniquingKeysWith: { _, new in new })
    }
    let metadataText = formatMetadata(combined)
    let lineText = "\(storage.timestamp()) [\(level.rawValue)] \(label): \(message)\(metadataText)\n"
    storage.write(lineText)
  }

  private func formatMetadata(_ metadata: Logging.Logger.Metadata) -> String {
    guard !metadata.isEmpty else { return "" }
    let joined = metadata
      .map { "\($0)=\($1)" }
      .sorted()
      .joined(separator: " ")
    return " \(joined)"
  }
}

private final class FileLogHandlerStorage {
  private let lock = NSLock()
  private let fileURL: URL
  private let formatter = ISO8601DateFormatter()

  init(fileURL: URL) {
    self.fileURL = fileURL
  }

  func timestamp() -> String {
    formatter.string(from: Date())
  }

  func write(_ line: String) {
    lock.lock()
    defer { lock.unlock() }

    let data = line.data(using: .utf8) ?? Data()
    if !FileManager.default.fileExists(atPath: fileURL.path) {
      FileManager.default.createFile(atPath: fileURL.path, contents: nil)
    }
    do {
      let handle = try FileHandle(forWritingTo: fileURL)
      try handle.seekToEnd()
      try handle.write(contentsOf: data)
      try handle.close()
    } catch {
      return
    }
  }
}
