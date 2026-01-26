import AppKit
import Darwin
import Foundation
import ShadowVMCore
import Virtualization
#if canImport(CryptoKit)
  import CryptoKit
#endif

@MainActor
final class ShadowVMCEVMController {
  static let shared = ShadowVMCEVMController()

  private struct EventLogMask: OptionSet {
    let rawValue: UInt64

    static let vmStateChanged = EventLogMask(rawValue: 1 << 0)
    static let fileTransferProgress = EventLogMask(rawValue: 1 << 1)
    static let fileTransferDone = EventLogMask(rawValue: 1 << 2)
    static let clipboardSyncDone = EventLogMask(rawValue: 1 << 3)
    static let vsockRawFrame = EventLogMask(rawValue: 1 << 4)
    static let vsockTLVFrame = EventLogMask(rawValue: 1 << 5)
    static let screenFrameAvailable = EventLogMask(rawValue: 1 << 6)
    static let errorOccurred = EventLogMask(rawValue: 1 << 7)
    static let agentStatusChanged = EventLogMask(rawValue: 1 << 8)

    static let all: EventLogMask = [
      .vmStateChanged,
      .fileTransferProgress,
      .fileTransferDone,
      .clipboardSyncDone,
      .vsockRawFrame,
      .vsockTLVFrame,
      .screenFrameAvailable,
      .errorOccurred,
      .agentStatusChanged,
    ]

    static let fallback: EventLogMask = .all
  }

  private struct TLVTypeLogMask: OptionSet {
    let rawValue: UInt64

    static let fallback: TLVTypeLogMask = defaultMask
    static let defaultMask: TLVTypeLogMask = {
      let all: [TLVType] = [
        .unknown,
        .fileChunk,
        .clipboardUpdate,
        .customCommand,
        .screenFrame,
        .heartbeat,
        .clipboardImageUpdate,
        .clipboardAck,
      ]
      var mask: UInt64 = 0
      for type in all {
        mask |= (1 << UInt64(type.rawValue))
      }
      // Default: exclude heartbeat (type=5).
      mask &= ~(1 << UInt64(TLVType.heartbeat.rawValue))
      return TLVTypeLogMask(rawValue: mask)
    }()

    func contains(type: TLVType) -> Bool {
      contains(TLVTypeLogMask(rawValue: 1 << UInt64(type.rawValue)))
    }
  }

  private final class WeakVM {
    weak var value: VirtualMachine?

    init(_ value: VirtualMachine) {
      self.value = value
    }
  }

  private let runtime = LocalRuntime.shared
  private var trackedVMs: [UUID: WeakVM] = [:]
  private var eventToken: EventBus.Token?
  private var clipboardPollingTasks: [UUID: Task<Void, Never>] = [:]
  private var lastClipboardChangeCounts: [UUID: Int] = [:]
  private let clipboardPollInterval: UInt64 = 500_000_000
  private let eventLogMask = EventLogMask.fallback
  private let tlvLogMask = TLVTypeLogMask.fallback
  private static let vmStateFilename = "vmstate.vzs"

  private init() {}

  func createVirtualMachine(at url: URL, persist: Bool = true) throws -> VirtualMachine {
    let vm = try runtime.createVM(at: url, persist: persist)
    track(vm)
    return vm
  }

  func openVirtualMachine(at url: URL, persist: Bool = true) throws -> VirtualMachine {
    let vm = try runtime.openVM(at: url, persist: persist)
    track(vm)
    return vm
  }

  func updateConfiguration(for vm: VirtualMachine, configuration: Configuration) throws {
    _ = try runtime.updateConfig(id: vm.metadata.id, config: configuration)
  }

  func start(_ vm: VirtualMachine) async throws {
    if #available(macOS 14.0, *) {
      if try await restoreVMStateIfPresent(for: vm) {
        startClipboardPollingIfNeeded(for: vm)
        return
      }
    }
    try await runtime.startVM(id: vm.metadata.id)
    startClipboardPollingIfNeeded(for: vm)
  }

  func stop(_ vm: VirtualMachine) async throws {
    try await runtime.stopVM(id: vm.metadata.id)
    stopClipboardPolling(for: vm.metadata.id)
  }

  func suspend(_ vm: VirtualMachine) async throws {
    guard vm.running || vm.paused else {
      return
    }
    guard #available(macOS 14.0, *) else {
      GXDLogInfo(
        "[ui-ce] vmstate save skipped vm=\(vm.metadata.id.uuidString) reason=unsupported_macos"
      )
      try await runtime.stopVM(id: vm.metadata.id)
      stopClipboardPolling(for: vm.metadata.id)
      return
    }
    let stateURL = vmStateURL(for: vm)
    guard let vzVM = runtime.vmManager.vzVirtualMachine(id: vm.metadata.id) else {
      throw ShadowVMCEVMControllerError(message: "Virtualization VM instance is unavailable.")
    }
    removeExistingVMState(at: stateURL)
    GXDLogInfo(
      "[ui-ce] vmstate save begin vm=\(vm.metadata.id.uuidString) path=\(stateURL.path)"
    )
    do {
      try await saveMachineState(vzVM, to: stateURL)
    } catch {
      removeExistingVMState(at: stateURL)
      throw error
    }
    GXDLogInfo(
      "[ui-ce] vmstate save end vm=\(vm.metadata.id.uuidString) path=\(stateURL.path)"
    )
    stopClipboardPolling(for: vm.metadata.id)
  }

  func pause(_ vm: VirtualMachine) async throws {
    try await runtime.pauseVM(id: vm.metadata.id)
    startClipboardPollingIfNeeded(for: vm)
  }

  func resume(_ vm: VirtualMachine) async throws {
    try await runtime.resumeVM(id: vm.metadata.id)
    startClipboardPollingIfNeeded(for: vm)
  }

  func status(for vm: VirtualMachine) async throws -> VMInfo {
    if let info = runtime.info(id: vm.metadata.id) {
      return info
    }
    return vm.info
  }

  func close(_ vm: VirtualMachine) {
    guard !vm.running else { return }
    trackedVMs.removeValue(forKey: vm.metadata.id)
    stopClipboardPolling(for: vm.metadata.id)
    stopEventBridgeIfNeeded()
    runtime.closeVM(id: vm.metadata.id)
  }

  private func track(_ vm: VirtualMachine) {
    trackedVMs[vm.metadata.id] = WeakVM(vm)
    runtime.setAgentSettings(vmID: vm.metadata.id, settings: vm.metadata.agentSettings)
    startEventBridgeIfNeeded()
    updateClipboardPolling(for: vm)
    notifyStateChanged(vm.metadata.id)
  }

  func setHostClipboardToGuestEnabled(_ enabled: Bool, for vm: VirtualMachine) throws {
    var settings = vm.metadata.agentSettings
    settings.hostClipboardToGuest = enabled
    try vm.updateAgentSettings(settings)
    runtime.setAgentSettings(vmID: vm.metadata.id, settings: settings)
    persistMetadata(for: vm)
    updateClipboardPolling(for: vm)
  }

  func setGuestClipboardToHostEnabled(_ enabled: Bool, for vm: VirtualMachine) throws {
    var settings = vm.metadata.agentSettings
    settings.guestClipboardToHost = enabled
    try vm.updateAgentSettings(settings)
    runtime.setAgentSettings(vmID: vm.metadata.id, settings: settings)
    persistMetadata(for: vm)
  }

  private func persistMetadata(for vm: VirtualMachine) {
    let metadataURL = vm.url.appendingPathComponent("metadata.json")
    do {
      let data = try JSONEncoder().encode(vm.metadata)
      try data.write(to: metadataURL, options: .atomic)
    } catch {
      GXDLogError(
        "[ui-ce] persist metadata failed vm=\(vm.metadata.id.uuidString) error=\(error.localizedDescription)"
      )
    }
  }

  private func vmStateURL(for vm: VirtualMachine) -> URL {
    vm.url.appendingPathComponent(Self.vmStateFilename)
  }

  private func removeExistingVMState(at url: URL) {
    guard FileManager.default.fileExists(atPath: url.path) else {
      return
    }
    do {
      try FileManager.default.removeItem(at: url)
    } catch {
      GXDLogError("[ui-ce] vmstate cleanup failed path=\(url.path) error=\(error.localizedDescription)")
    }
  }

  @available(macOS 14.0, *)
  private func restoreVMStateIfPresent(for vm: VirtualMachine) async throws -> Bool {
    let stateURL = vmStateURL(for: vm)
    guard FileManager.default.fileExists(atPath: stateURL.path) else {
      return false
    }
    guard let vzVM = runtime.vmManager.vzVirtualMachine(id: vm.metadata.id) else {
      throw ShadowVMCEVMControllerError(message: "Virtualization VM instance is unavailable.")
    }
    GXDLogInfo(
      "[ui-ce] vmstate restore begin vm=\(vm.metadata.id.uuidString) path=\(stateURL.path)"
    )
    do {
      try await restoreMachineState(vzVM, from: stateURL)
      removeExistingVMState(at: stateURL)
      GXDLogInfo(
        "[ui-ce] vmstate restore end vm=\(vm.metadata.id.uuidString) path=\(stateURL.path)"
      )
      return true
    } catch {
      GXDLogError(
        "[ui-ce] vmstate restore failed vm=\(vm.metadata.id.uuidString) path=\(stateURL.path) error=\(error.localizedDescription)"
      )
      removeExistingVMState(at: stateURL)
      return false
    }
  }

  @available(macOS 14.0, *)
  private func saveMachineState(_ vzVM: VZVirtualMachine, to url: URL) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      vzVM.saveMachineStateTo(url: url) { error in
        if let error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume(returning: ())
        }
      }
    }
  }

  @available(macOS 14.0, *)
  private func restoreMachineState(_ vzVM: VZVirtualMachine, from url: URL) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      vzVM.restoreMachineStateFrom(url: url) { error in
        if let error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume(returning: ())
        }
      }
    }
  }

  func installAgentViaUSB(for vm: VirtualMachine) async throws -> USBMassStorageAttachResult {
    let imageURL = try resolvedAgentInstallImageURL()
    GXDLogInfo(
      "[ui-ce] agent install start vm=\(vm.metadata.id.uuidString) image=\(imageURL.path)"
    )
    do {
      let result = try await vm.attachUSBMassStorage(imageURL: imageURL, readOnly: true)
      GXDLogInfo(
        "[ui-ce] agent install ready vm=\(vm.metadata.id.uuidString) result=\(result)"
      )
      return result
    } catch {
      GXDLogError(
        "[ui-ce] agent install failed vm=\(vm.metadata.id.uuidString) error=\(error.localizedDescription)"
      )
      throw error
    }
  }

  private func resolvedAgentInstallImageURL() throws -> URL {
    guard let imageURL = Bundle.main.url(forResource: "ShadowVMAgent", withExtension: "img") else {
      GXDLogError(
        "[ui-ce] agent install failed error=ShadowVMAgent.img not found in app bundle resources"
      )
      throw ShadowVMCEVMControllerError(
        message: "ShadowVMAgent.img not found in app bundle resources."
      )
    }
    let resolvedURL = imageURL.resolvingSymlinksInPath().standardizedFileURL
    let baseCacheDir = ShadowVMConfig.shared.homeDir.appendingPathComponent(
      "agent_cache", isDirectory: true)
    let trimmedVersion = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let cacheVersion = trimmedVersion.isEmpty ? "unversioned" : trimmedVersion
    let cacheDir = baseCacheDir.appendingPathComponent(cacheVersion, isDirectory: true)
    do {
      try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    } catch {
      GXDLogError("[ui-ce] agent install failed error=cache dir create \(error.localizedDescription)")
      throw error
    }
    let targetURL = cacheDir.appendingPathComponent(resolvedURL.lastPathComponent)
    if !FileManager.default.fileExists(atPath: targetURL.path) {
      do {
        // DiskImages writes metadata alongside the image; copy to a writable cache to avoid warnings.
        try FileManager.default.copyItem(at: resolvedURL, to: targetURL)
      } catch {
        GXDLogError(
          "[ui-ce] agent install failed error=cache image copy \(error.localizedDescription)"
        )
        throw error
      }
    }
    return targetURL
  }

  private func startEventBridgeIfNeeded() {
    guard eventToken == nil else { return }
    eventToken = runtime.addEventHandler { [weak self] event in
      Task { @MainActor in
        self?.handle(event)
      }
    }
  }

  private func stopEventBridgeIfNeeded() {
    guard let token = eventToken, trackedVMs.isEmpty else { return }
    runtime.removeEventHandler(token)
    eventToken = nil
  }

  private func handle(_ event: ShadowVMEvent) {
    logEvent(event)
    switch event {
    case .vmStateChanged(let info):
      let id = info.id
      guard let entry = trackedVMs[id], let vm = entry.value else {
        trackedVMs.removeValue(forKey: id)
        stopClipboardPolling(for: id)
        stopEventBridgeIfNeeded()
        return
      }
      updateClipboardPolling(for: vm)
      notifyStateChanged(id)
    case .fileTransferProgress,
      .fileTransferDone,
      .clipboardSyncDone,
      .vsockRawFrame,
      .vsockTLVFrame,
      .screenFrameAvailable,
      .agentStatusChanged,
      .errorOccurred:
      return
    }
  }

  private func notifyStateChanged(_ id: UUID) {
    NotificationCenter.default.post(
      name: .shadowVMCEVMStateDidChange,
      object: nil,
      userInfo: ["id": id]
    )
  }

  private func updateClipboardPolling(for vm: VirtualMachine) {
    guard vm.metadata.agentSettings.hostClipboardToGuest else {
      stopClipboardPolling(for: vm.metadata.id)
      return
    }
    if vm.running || vm.paused {
      startClipboardPollingIfNeeded(for: vm)
    } else {
      stopClipboardPolling(for: vm.metadata.id)
    }
  }

  private func startClipboardPollingIfNeeded(for vm: VirtualMachine) {
    let vmID = vm.metadata.id
    guard vm.metadata.agentSettings.hostClipboardToGuest else { return }
    guard clipboardPollingTasks[vmID] == nil else { return }
    lastClipboardChangeCounts[vmID] = NSPasteboard.general.changeCount
    let task = Task { @MainActor [weak self, weak vm] in
      guard let self, let vm else { return }
      await self.runClipboardPollingLoop(vmID: vmID, vm: vm)
    }
    clipboardPollingTasks[vmID] = task
  }

  private func stopClipboardPolling(for vmID: UUID) {
    clipboardPollingTasks[vmID]?.cancel()
    clipboardPollingTasks[vmID] = nil
    lastClipboardChangeCounts[vmID] = nil
  }

  private func runClipboardPollingLoop(vmID: UUID, vm: VirtualMachine) async {
    while !Task.isCancelled {
      guard vm.running || vm.paused else { break }
      let changeCount = NSPasteboard.general.changeCount
      if lastClipboardChangeCounts[vmID] != changeCount {
        if runtime.clipboardService.consumeGuestClipboardChangeCountIfMatches(
          vmID: vmID,
          changeCount: changeCount
        ) {
          lastClipboardChangeCounts[vmID] = changeCount
          continue
        }
        lastClipboardChangeCounts[vmID] = changeCount
        await pushHostClipboardAfterChange(vmID: vmID)
      }
      try? await Task.sleep(nanoseconds: clipboardPollInterval)
    }
    clipboardPollingTasks[vmID] = nil
    lastClipboardChangeCounts[vmID] = nil
  }

  private func pushHostClipboardAfterChange(vmID: UUID) async {
    do {
      try await runtime.pushHostClipboard(vmID: vmID)
      GXDLogDebug("[ui-ce] [clipboard][auto-push] host clipboard pushed vm=\(vmID)")
    } catch {
      GXDLogError(
        "[ui-ce] [clipboard][auto-push] host clipboard push failed vm=\(vmID) error=\(error.localizedDescription)"
      )
    }
  }

  private func logEvent(_ event: ShadowVMEvent) {
    guard shouldLogEvent(event) else { return }
    let prefix = "[ui-ce] [event]"
    switch event {
    case .vmStateChanged(let info):
      let flags = info.currentState.runtimeFlags
      let installed = info.installed ?? false
      GXDLogInfo(
        "\(prefix) kind=vmStateChanged vm=\(info.id.uuidString) state=\(info.currentState.rawValue) running=\(flags.running) paused=\(flags.paused) installed=\(installed)"
      )
    case .fileTransferProgress(let vmID, let progress):
      let percent = String(format: "%.1f", progress * 100)
      GXDLogInfo(
        "\(prefix) kind=fileTransferProgress vm=\(vmID.uuidString) progress=\(percent)%"
      )
    case .fileTransferDone(let vmID, let result):
      GXDLogInfo(
        "\(prefix) kind=fileTransferDone vm=\(vmID.uuidString) result=\"\(truncate(result ?? "done"))\""
      )
    case .clipboardSyncDone(let vmID):
      GXDLogInfo("\(prefix) kind=clipboardSyncDone vm=\(vmID.uuidString)")
    case .vsockRawFrame(let vmID, let direction, let data):
      let vmText = vmID?.uuidString ?? "nil"
      let digest = digestString(data)
      GXDLogInfo(
        "\(prefix) kind=vsockRawFrame vm=\(vmText) dir=\(directionText(direction)) len=\(data.count) preview=<redacted> digest=\(digest)"
      )
    case .vsockTLVFrame(let vmID, let direction, let frame):
      let vmText = vmID?.uuidString ?? "nil"
      let typeText = tlvTypeLabel(frame.type)
      let (preview, digest) = tlvPreview(frame: frame)
      var message =
        "\(prefix) kind=vsockTLVFrame vm=\(vmText) dir=\(directionText(direction)) type=\(typeText) len=\(frame.payload.count) preview=\(preview)"
      if let digest {
        message.append(" digest=\(digest)")
      }
      GXDLogInfo(
        message
      )
    case .screenFrameAvailable(let vmID, let metadata):
      let vmText = vmID?.uuidString ?? "nil"
      let metaText = truncate(metadata ?? "")
      GXDLogInfo(
        "\(prefix) kind=screenFrameAvailable vm=\(vmText) meta=\"\(metaText)\""
      )
    case .agentStatusChanged(let vmID, let status, let reason):
      let reasonText = truncate(reason ?? "")
      if reasonText.isEmpty {
        GXDLogInfo(
          "\(prefix) kind=agentStatusChanged vm=\(vmID.uuidString) status=\(status.rawValue)"
        )
      } else {
        GXDLogInfo(
          "\(prefix) kind=agentStatusChanged vm=\(vmID.uuidString) status=\(status.rawValue) reason=\"\(reasonText)\""
        )
      }
    case .errorOccurred(let vmID, let error):
      let vmText = vmID?.uuidString ?? "nil"
      GXDLogInfo(
        "\(prefix) kind=errorOccurred vm=\(vmText) error=\"\(truncate(error))\""
      )
    }
  }

  private func shouldLogEvent(_ event: ShadowVMEvent) -> Bool {
    switch event {
    case .vmStateChanged:
      return eventLogMask.contains(.vmStateChanged)
    case .fileTransferProgress:
      return eventLogMask.contains(.fileTransferProgress)
    case .fileTransferDone:
      return eventLogMask.contains(.fileTransferDone)
    case .clipboardSyncDone:
      return eventLogMask.contains(.clipboardSyncDone)
    case .vsockRawFrame:
      return eventLogMask.contains(.vsockRawFrame)
    case .vsockTLVFrame(_, _, let frame):
      guard eventLogMask.contains(.vsockTLVFrame) else { return false }
      if let typed = TLVType(rawValue: frame.type) {
        return tlvLogMask.contains(type: typed)
      }
      return true
    case .screenFrameAvailable:
      return eventLogMask.contains(.screenFrameAvailable)
    case .agentStatusChanged:
      return eventLogMask.contains(.agentStatusChanged)
    case .errorOccurred:
      return eventLogMask.contains(.errorOccurred)
    }
  }

  private func truncate(_ text: String, limit: Int = 256) -> String {
    guard text.count > limit else { return text }
    let end = text.index(text.startIndex, offsetBy: limit)
    return "\(text[..<end])..."
  }

  private func hexPreview(_ data: Data, limit: Int = 32) -> String {
    let prefix = data.prefix(limit)
    let hex = prefix.map { String(format: "%02x", $0) }.joined()
    if data.count > limit {
      return "\(hex)..."
    }
    return hex
  }

  private func directionText(_ direction: VsockDirection) -> String {
    switch direction {
    case .inbound:
      return "inbound"
    case .outbound:
      return "outbound"
    }
  }

  private func tlvTypeLabel(_ type: UInt16) -> String {
    if let typed = TLVType(rawValue: type) {
      return String(describing: typed)
    }
    return "unknown(\(type))"
  }

  private func tlvPreview(frame: TLVFrame) -> (String, String?) {
    if isSensitiveTLVType(frame.type) {
      return ("<redacted>", digestString(frame.payload))
    }
    return (hexPreview(frame.payload), nil)
  }

  private func isSensitiveTLVType(_ type: UInt16) -> Bool {
    guard let typed = TLVType(rawValue: type) else { return true }
    switch typed {
    case .heartbeat, .clipboardAck:
      return false
    default:
      return true
    }
  }

  private func digestString(_ data: Data) -> String {
    #if canImport(CryptoKit)
      let digest = SHA256.hash(data: data)
      let hex = digest.prefix(8).map { String(format: "%02x", $0) }.joined()
      return "sha256:\(hex)"
    #else
      return String(format: "hash:%08x", data.hashValue)
    #endif
  }
}

struct ShadowVMCEVMControllerError: LocalizedError {
  let message: String

  var errorDescription: String? {
    message
  }
}

extension Notification.Name {
  static let shadowVMCEVMStateDidChange = Notification.Name("ShadowVMCEVMStateDidChange")
}
