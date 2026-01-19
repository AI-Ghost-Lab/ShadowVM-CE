import AppKit
import Darwin
import Foundation
import ShadowVMCore

enum ShadowVMCECLIError: Error {
  case message(String)
}

struct ShadowVMCECLI {
  enum UILaunchRequest {
    case startVM(URL)
    case stopVM(URL)
  }

  enum CLIRequestAction: String {
    case start
    case stop
  }

  static let cliRequestNotificationName = Notification.Name("ShadowVMCECLIRequest")
  static let cliRequestActionKey = "action"
  static let cliRequestBundleKey = "bundlePath"

  private static var launchRequest: UILaunchRequest?

  struct CreateOptions {
    var name: String
    var bundle: URL?
    var cpu: Int?
    var memoryMB: Int?
    var width: Int?
    var height: Int?
    var scale: Int?
    var json: Bool
  }

  struct CommandOptions {
    var bundle: URL
    var json: Bool
  }

  struct InstallOptions {
    var bundle: URL
    var ipsw: URL
    var diskGB: Int
    var json: Bool
  }

  enum Command {
    case help
    case vmCreate(CreateOptions)
    case vmInstall(InstallOptions)
    case vmStart(CommandOptions)
    case vmStop(CommandOptions)
    case vmStatus(CommandOptions)
  }

  static func userArguments() -> [String] {
    let raw = Array(CommandLine.arguments.dropFirst())
    var filtered: [String] = []
    var skipNext = false
    for arg in raw {
      if skipNext {
        skipNext = false
        continue
      }
      if arg.hasPrefix("-psn_") {
        continue
      }
      if arg.hasPrefix("-NS") || arg.hasPrefix("-Apple") {
        if !arg.contains("=") {
          skipNext = true
        }
        continue
      }
      filtered.append(arg)
    }
    return filtered
  }

  static func parse(_ args: [String]) throws -> Command? {
    guard !args.isEmpty else { return nil }
    var iter = ArgIterator(args: args)
    guard let head = iter.next() else { return nil }

    if head == "--help" || head == "-h" {
      return .help
    }

    if head != "vm" {
      throw ShadowVMCECLIError.message(
        "unknown command: \(head) (args: \(args.joined(separator: " ")))")
    }

    guard let sub = iter.next() else {
      throw ShadowVMCECLIError.message("missing vm subcommand")
    }

    switch sub {
    case "create":
      var name: String?
      var bundle: URL?
      var cpu: Int?
      var memoryMB: Int?
      var width: Int?
      var height: Int?
      var scale: Int?
      var json = false
      while let arg = iter.next() {
        switch arg {
        case "--name":
          name = try iter.requireValue(for: arg)
        case "--bundle":
          bundle = url(from: try iter.requireValue(for: arg))
        case "--cpu":
          cpu = try iter.requireInt(for: arg)
        case "--memory":
          memoryMB = try iter.requireInt(for: arg)
        case "--width":
          width = try iter.requireInt(for: arg)
        case "--height":
          height = try iter.requireInt(for: arg)
        case "--scale":
          scale = try iter.requireInt(for: arg)
        case "--json":
          json = true
        case "--help", "-h":
          return .help
        default:
          throw ShadowVMCECLIError.message("unknown option: \(arg)")
        }
      }

      guard let name else {
        throw ShadowVMCECLIError.message("--name is required")
      }
      return .vmCreate(CreateOptions(
        name: name,
        bundle: bundle,
        cpu: cpu,
        memoryMB: memoryMB,
        width: width,
        height: height,
        scale: scale,
        json: json
      ))
    case "install":
      var bundle: URL?
      var ipsw: URL?
      var diskGB: Int?
      var json = false
      while let arg = iter.next() {
        switch arg {
        case "--bundle":
          bundle = url(from: try iter.requireValue(for: arg))
        case "--ipsw":
          ipsw = url(from: try iter.requireValue(for: arg))
        case "--disk":
          diskGB = try iter.requireInt(for: arg)
        case "--json":
          json = true
        case "--help", "-h":
          return .help
        default:
          throw ShadowVMCECLIError.message("unknown option: \(arg)")
        }
      }
      guard let bundle else {
        throw ShadowVMCECLIError.message("--bundle is required")
      }
      guard let ipsw else {
        throw ShadowVMCECLIError.message("--ipsw is required")
      }
      guard let diskGB else {
        throw ShadowVMCECLIError.message("--disk is required")
      }
      return .vmInstall(InstallOptions(bundle: bundle, ipsw: ipsw, diskGB: diskGB, json: json))
    case "start":
      guard let options = try parseCommandOptions(&iter) else {
        return .help
      }
      return .vmStart(options)
    case "stop":
      guard let options = try parseCommandOptions(&iter) else {
        return .help
      }
      return .vmStop(options)
    case "status":
      guard let options = try parseCommandOptions(&iter) else {
        return .help
      }
      return .vmStatus(options)
    default:
      throw ShadowVMCECLIError.message("unknown vm subcommand: \(sub)")
    }
  }

  @MainActor
  static func run(_ command: Command) async -> Int32 {
    do {
      switch command {
      case .help:
        printUsage()
        return 0
      case .vmCreate(let options):
        let result = try createVM(options)
        if options.json {
          printJSON(result)
        } else {
          print("created vm \(result.name) id=\(result.id)")
          print("bundle: \(result.bundlePath)")
        }
        return 0
      case .vmInstall(let options):
        try await installVM(options)
        if options.json {
          printJSON(["ok": true])
        } else {
          print("install complete for \(options.bundle.path)")
        }
        return 0
      case .vmStart(let options):
        try await startVM(options.bundle)
        if options.json {
          printJSON(["ok": true])
        } else {
          print("started \(options.bundle.path)")
        }
        return 0
      case .vmStop(let options):
        try await stopVM(options.bundle)
        if options.json {
          printJSON(["ok": true])
        } else {
          print("stopped \(options.bundle.path)")
        }
        return 0
      case .vmStatus(let options):
        let status = try await statusVM(options.bundle)
        if options.json {
          printJSON(status)
        } else {
          print("\(status.name) state=\(status.state) installed=\(status.installed)")
        }
        return 0
      }
    } catch {
      printError(error)
      return 1
    }
  }

  static func runBlocking(_ command: Command) -> Int32 {
    let group = DispatchGroup()
    var exitCode: Int32 = 1
    group.enter()
    Task { @MainActor in
      exitCode = await run(command)
      group.leave()
    }
    if Thread.isMainThread {
      while group.wait(timeout: .now()) != .success {
        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
      }
    } else {
      group.wait()
    }
    return exitCode
  }

  static func launchRequest(for command: Command) -> UILaunchRequest? {
    switch command {
    case .vmStart(let options):
      return .startVM(options.bundle)
    case .vmStop(let options):
      return .stopVM(options.bundle)
    default:
      return nil
    }
  }

  static func setLaunchRequest(_ request: UILaunchRequest?) {
    launchRequest = request
  }

  static func consumeLaunchRequest() -> UILaunchRequest? {
    let request = launchRequest
    launchRequest = nil
    return request
  }

  static func sendCLIRequest(_ request: UILaunchRequest) {
    let action: CLIRequestAction
    let url: URL
    switch request {
    case .startVM(let bundle):
      action = .start
      url = bundle
    case .stopVM(let bundle):
      action = .stop
      url = bundle
    }
    let payload: [String: Any] = [
      cliRequestActionKey: action.rawValue,
      cliRequestBundleKey: url.path,
    ]
    DistributedNotificationCenter.default().post(
      name: cliRequestNotificationName,
      object: nil,
      userInfo: payload
    )
  }

  static func printUsage() {
    print(
      """
Usage: ShadowVM-CE vm <command> [options]

Commands:
  vm create --name <name> [--bundle <path>] [--cpu <n>] [--memory <mb>] \\
    [--width <px>] [--height <px>] [--scale <n>] [--json]
  vm install --bundle <path> --ipsw <path> --disk <gb> [--json]
  vm start --bundle <path> [--json]
  vm stop --bundle <path> [--json]
  vm status --bundle <path> [--json]
"""
    )
  }

  static func printError(_ error: Error) {
    if case let ShadowVMCECLIError.message(message) = error {
      GXDLogError("[cli-ce] error: \(message)")
      return
    }
    let nsError = error as NSError
    GXDLogError("[cli-ce] error: \(nsError.localizedDescription)")
    printNSErrorDetails(nsError, indent: "")
  }

  static func exit(_ code: Int32) {
    Darwin.exit(code)
  }

  private struct CreateResult: Codable {
    let id: String
    let name: String
    let bundlePath: String
    let installed: Bool
  }

  private struct StatusResult: Codable {
    let id: String
    let name: String
    let bundlePath: String
    let state: String
    let installed: Bool
  }

  @MainActor
  private static func createVM(_ options: CreateOptions) throws -> CreateResult {
    let bundleURL = normalizeBundlePath(options.bundle, name: options.name)
    if FileManager.default.fileExists(atPath: bundleURL.path) {
      throw ShadowVMCECLIError.message("bundle already exists: \(bundleURL.path)")
    }
    let vm = try ShadowVMCEVMController.shared.createVirtualMachine(at: bundleURL)
    let defaults = defaultConfig()
    let cpu = options.cpu ?? defaults.cpu
    let memoryMB = options.memoryMB ?? defaults.memoryMB
    let width = options.width ?? defaults.width
    let height = options.height ?? defaults.height
    let scale = options.scale ?? defaults.scale
    let memoryBytes = UInt64(memoryMB) * 1024 * 1024
    let configuration = Configuration(
      cpuCount: cpu,
      memorySize: memoryBytes,
      screenWidth: width,
      screenHeight: height,
      screenScale: scale,
      bootIntoMacOSRecovery: false,
      bootIntoDFU: false,
      haltOnPanic: false,
      haltInIBoot1: false,
      haltInIBoot2: false,
      debugPort: nil
    )
    try ShadowVMCEVMController.shared.updateConfiguration(for: vm, configuration: configuration)
    return CreateResult(
      id: vm.metadata.id.uuidString,
      name: bundleURL.lastPathComponent,
      bundlePath: bundleURL.path,
      installed: vm.metadata.installed
    )
  }

  @MainActor
  private static func installVM(_ options: InstallOptions) async throws {
    let vm = try ShadowVMCEVMController.shared.openVirtualMachine(at: options.bundle)
    guard vm.metadata.configuration != nil else {
      throw ShadowVMCECLIError.message("missing configuration in \(options.bundle.path)")
    }
    try await vm.install(ipsw: options.ipsw, diskSize: options.diskGB)
  }

  @MainActor
  private static func startVM(_ bundle: URL) async throws {
    let vm = try ShadowVMCEVMController.shared.openVirtualMachine(at: bundle)
    try await ShadowVMCEVMController.shared.start(vm)
  }

  @MainActor
  private static func stopVM(_ bundle: URL) async throws {
    let vm = try ShadowVMCEVMController.shared.openVirtualMachine(at: bundle)
    try await ShadowVMCEVMController.shared.stop(vm)
  }

  @MainActor
  private static func statusVM(_ bundle: URL) async throws -> StatusResult {
    let vm = try ShadowVMCEVMController.shared.openVirtualMachine(at: bundle)
    let info = try await ShadowVMCEVMController.shared.status(for: vm)
    return StatusResult(
      id: info.id.uuidString,
      name: info.name,
      bundlePath: info.bundlePath,
      state: info.currentState.rawValue,
      installed: info.installed ?? false
    )
  }

  private static func parseCommandOptions(_ iter: inout ArgIterator) throws -> CommandOptions? {
    var bundle: URL?
    var json = false
    while let arg = iter.next() {
      switch arg {
      case "--bundle":
        bundle = url(from: try iter.requireValue(for: arg))
      case "--json":
        json = true
      case "--help", "-h":
        return nil
      default:
        throw ShadowVMCECLIError.message("unknown option: \(arg)")
      }
    }
    guard let bundle else {
      throw ShadowVMCECLIError.message("--bundle is required")
    }
    return CommandOptions(bundle: bundle, json: json)
  }

  private struct DefaultConfig {
    let cpu: Int
    let memoryMB: Int
    let width: Int
    let height: Int
    let scale: Int
  }

  private static func defaultConfig() -> DefaultConfig {
    let cpu = ShadowVMCEDefaults.defaultCpuCount()
    let memoryMB = Int(ShadowVMCEDefaults.defaultMemoryBytes() >> 20)
    let size = ShadowVMCEDefaults.defaultScreenSize()
    let scale = ShadowVMCEDefaults.defaultScreenScale
    return DefaultConfig(
      cpu: cpu,
      memoryMB: memoryMB,
      width: size.width,
      height: size.height,
      scale: scale
    )
  }

  private static func normalizeBundlePath(_ bundle: URL?, name: String) -> URL {
    if let bundle {
      return ensureVMappleExtension(bundle)
    }
    let safeName = name.hasSuffix(".vmapple") ? name : "\(name).vmapple"
    let base = ShadowVMConfig.shared.homeDir
    return base.appendingPathComponent(safeName, isDirectory: true)
  }

  private static func ensureVMappleExtension(_ url: URL) -> URL {
    if url.pathExtension == "vmapple" { return url }
    return url.appendingPathExtension("vmapple")
  }

  private static func url(from raw: String) -> URL {
    let expanded = (raw as NSString).expandingTildeInPath
    return URL(fileURLWithPath: expanded)
  }

  private static func printJSON<T: Encodable>(_ value: T) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    if let data = try? encoder.encode(value), let text = String(data: data, encoding: .utf8) {
      print(text)
      fflush(stdout)
    }
  }

  private static func printNSErrorDetails(_ error: NSError, indent: String) {
    GXDLogError("[cli-ce] \(indent)error details: domain=\(error.domain) code=\(error.code)")
    if let reason = error.localizedFailureReason, !reason.isEmpty {
      GXDLogError("[cli-ce] \(indent)failure reason: \(reason)")
    }
    if let recovery = error.localizedRecoverySuggestion, !recovery.isEmpty {
      GXDLogError("[cli-ce] \(indent)recovery: \(recovery)")
    }
    if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
      GXDLogError("[cli-ce] \(indent)underlying error:")
      printNSErrorDetails(underlying, indent: "\(indent)  ")
    }
  }
}

struct ArgIterator {
  let args: [String]
  private(set) var index: Int = 0

  mutating func next() -> String? {
    guard index < args.count else { return nil }
    let value = args[index]
    index += 1
    return value
  }

  mutating func requireValue(for option: String) throws -> String {
    guard let value = next() else {
      throw ShadowVMCECLIError.message("missing value for \(option)")
    }
    return value
  }

  mutating func requireInt(for option: String) throws -> Int {
    let raw = try requireValue(for: option)
    guard let value = Int(raw) else {
      throw ShadowVMCECLIError.message("invalid value for \(option): \(raw)")
    }
    return value
  }
}
