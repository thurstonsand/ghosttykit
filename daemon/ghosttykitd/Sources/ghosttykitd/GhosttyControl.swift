import AppKit
import Foundation

enum GhosttyKitError: Error, LocalizedError {
    case invalidResize(String)
    case terminalNotFound(String)

    var errorDescription: String? {
        switch self {
        case let .invalidResize(value): "invalid resize amount: \(value)"
        case let .terminalNotFound(value): "no Ghostty terminal is associated with \(value)"
        }
    }

    var protocolCode: String {
        switch self {
        case .invalidResize:
            ProtocolCode.invalidRequest
        case .terminalNotFound:
            ProtocolCode.terminalNotFound
        }
    }
}

protocol GhosttyControlling {
    func preflightAutomationPermission() throws -> Bool
    func terminalContext(forTTY tty: String) throws -> TerminalContext
    func readPasteboardContent() throws -> FrameStreamReply
    func activateKeyTable(_ table: String, terminal: TerminalContext) throws
    func deactivateKeyTable(terminal: TerminalContext) throws
    func focusSplit(direction: Direction, terminal: TerminalContext) throws
    func input(_ text: String, submit: Bool, terminal: TerminalContext) throws
    func toggleSplitZoom(terminal: TerminalContext) throws
    func tabTerminalCount(terminal: TerminalContext) throws -> Int
    @discardableResult
    func split(
        direction: Direction,
        cwd: String?,
        command: String?,
        focus: FocusTarget,
        terminal: TerminalContext
    ) throws -> TerminalContext
    func resize(direction: Direction, amount: ResizeAmount, terminal: TerminalContext) throws
}

final class DryRunGhosttyController: GhosttyControlling {
    private let terminal = TerminalContext(
        terminalID: "dry-run-terminal",
        windowID: "dry-run-window",
        tabID: "dry-run-tab"
    )
    private let pasteText: String?

    init(pasteText: String? = nil) {
        self.pasteText = pasteText
    }

    func preflightAutomationPermission() throws -> Bool {
        true
    }

    func terminalContext(forTTY _: String) throws -> TerminalContext {
        terminal
    }

    func readPasteboardContent() throws -> FrameStreamReply {
        guard let pasteText else { return try readSystemPasteboardContent() }
        let data = Data(pasteText.utf8)
        return FrameStreamReply(header: PasteStreamFrameHeader.text(byteCount: data.count), streams: [.data(data)])
    }

    func activateKeyTable(_: String, terminal _: TerminalContext) throws {}

    func deactivateKeyTable(terminal _: TerminalContext) throws {}

    func focusSplit(direction _: Direction, terminal _: TerminalContext) throws {}

    func input(_: String, submit _: Bool, terminal _: TerminalContext) throws {}

    func toggleSplitZoom(terminal _: TerminalContext) throws {}

    func tabTerminalCount(terminal _: TerminalContext) throws -> Int {
        1
    }

    func split(
        direction _: Direction,
        cwd _: String?,
        command _: String?,
        focus _: FocusTarget,
        terminal: TerminalContext
    ) throws -> TerminalContext {
        TerminalContext(
            terminalID: "dry-run-split-terminal",
            windowID: terminal.windowID,
            tabID: terminal.tabID
        )
    }

    func resize(direction _: Direction, amount _: ResizeAmount, terminal _: TerminalContext) throws {}
}

final class AppleEventGhosttyController: GhosttyControlling {
    private static let rendezvousTimeout: TimeInterval = 2.0
    private static let rendezvousPollInterval: useconds_t = 25000

    private let ghostty = GhosttyAppleEvents()
    private let windowGeometry = SystemEventsWindowGeometry()

    func preflightAutomationPermission() throws -> Bool {
        try ghostty.preflightAutomationPermission()
    }

    /// Deterministic tty→terminal resolution: direct lookup through the terminal
    /// class's tty property where Ghostty supports it (1.4.0+), otherwise an OSC 7 rendezvous —
    /// write a working-directory nonce to the pty, scan for the terminal that reports it, restore.
    func terminalContext(forTTY tty: String) throws -> TerminalContext {
        if ghostty.supportsTTYProperty() {
            guard let terminal = try ghostty.terminalContext(matching: .tty, value: tty) else {
                throw GhosttyKitError.terminalNotFound(tty)
            }
            return terminal
        }
        return try rendezvous(tty: tty)
    }

    private func rendezvous(tty: String) throws -> TerminalContext {
        let device = try TTYDevice(path: tty)
        defer { device.close() }
        let restore = device.foregroundProcessWorkingDirectory()
        let nonce = "/gty-rendezvous/\(UUID().uuidString)"
        defer { try? device.reportWorkingDirectory(restore) }

        let deadline = Date().addingTimeInterval(Self.rendezvousTimeout)
        while true {
            // Re-asserted every poll: the pane's own program (a starting shell, most likely) can
            // overwrite the nonce with its own OSC 7 reports; the rendezvous wins at the first
            // quiet gap instead of losing the whole attempt to one race.
            try device.reportWorkingDirectory(nonce)
            if let terminal = try ghostty.terminalContext(matching: .workingDirectory, value: nonce) {
                return terminal
            }
            guard Date() < deadline else { throw GhosttyKitError.terminalNotFound(tty) }
            usleep(Self.rendezvousPollInterval)
        }
    }

    func readPasteboardContent() throws -> FrameStreamReply {
        try readSystemPasteboardContent()
    }

    func activateKeyTable(_ table: String, terminal: TerminalContext) throws {
        try ghostty.performAction("activate_key_table:\(table)", terminalID: terminal.terminalID)
    }

    func deactivateKeyTable(terminal: TerminalContext) throws {
        try ghostty.performAction("deactivate_key_table", terminalID: terminal.terminalID)
    }

    func focusSplit(direction: Direction, terminal: TerminalContext) throws {
        try ghostty.performAction("goto_split:\(direction.rawValue)", terminalID: terminal.terminalID)
    }

    /// Text arrives via bracketed paste and sits in the line editor unexecuted; submit follows it
    /// with an enter keypress.
    func input(_ text: String, submit: Bool, terminal: TerminalContext) throws {
        try ghostty.inputText(text, terminalID: terminal.terminalID)
        if submit {
            try ghostty.sendKey("enter", terminalID: terminal.terminalID)
        }
    }

    func toggleSplitZoom(terminal: TerminalContext) throws {
        try ghostty.performAction("toggle_split_zoom", terminalID: terminal.terminalID)
    }

    func tabTerminalCount(terminal: TerminalContext) throws -> Int {
        try ghostty.tabTerminalCount(tabID: terminal.tabID, windowID: terminal.windowID)
    }

    func split(
        direction: Direction,
        cwd: String?,
        command: String?,
        focus: FocusTarget,
        terminal: TerminalContext
    ) throws -> TerminalContext {
        let newTerminal = try ghostty.splitTerminal(
            terminalID: terminal.terminalID,
            direction: direction,
            configuration: GhosttySurfaceConfiguration(cwd: cwd, command: command)
        )
        switch focus {
        case .new:
            try ghostty.focusTerminal(newTerminal)
        case .original:
            try ghostty.focusTerminal(id: terminal.terminalID)
        }
        // Splits stay in the origin terminal's window and tab.
        return TerminalContext(
            terminalID: newTerminal.id,
            windowID: terminal.windowID,
            tabID: terminal.tabID
        )
    }

    func resize(direction: Direction, amount: ResizeAmount, terminal: TerminalContext) throws {
        let pixels: Int
        switch (amount.pixels, amount.percent) {
        case (.some(let value), nil):
            pixels = value
        case (nil, let .some(value)):
            guard value > 0 else { throw GhosttyKitError.invalidResize("percent must be greater than 0") }
            let windowIndex = try ghostty.windowIndex(windowID: terminal.windowID)
            let dimension = try windowGeometry.dimension(for: direction, windowIndex: windowIndex)
            pixels = max(Int(Double(dimension) * value / 100.0), 1)
        default:
            throw GhosttyKitError.invalidResize("specify exactly one of pixels or percent")
        }

        guard pixels > 0 else { throw GhosttyKitError.invalidResize("pixels must be greater than 0") }
        try ghostty.performAction("resize_split:\(direction.rawValue),\(pixels)", terminalID: terminal.terminalID)
    }
}

private struct GhosttySurfaceConfiguration {
    let cwd: String?
    let command: String?

    var isEmpty: Bool {
        cwd == nil && command == nil
    }
}

private struct GhosttyTerminalReference {
    let id: String
    fileprivate let descriptor: NSAppleEventDescriptor
}

private final class GhosttyAppleEvents {
    private enum TTYPropertySupport {
        case supported
        case unsupported
    }

    private let client = AppleEventClient(bundleIdentifier: "com.mitchellh.ghostty")
    private var ttyPropertySupport: TTYPropertySupport?

    func preflightAutomationPermission() throws -> Bool {
        guard isGhosttyRunning() else { return false }
        _ = try client.count(.window, in: .null(), operation: "count Ghostty windows")
        return true
    }

    /// Probes the terminal scripting class for the tty property Ghostty ships in 1.4.0. Memoized
    /// for the daemon's lifetime; a Ghostty upgrade restarts the daemon's world anyway.
    func supportsTTYProperty() -> Bool {
        if let ttyPropertySupport {
            return ttyPropertySupport == .supported
        }
        guard let windowCount = try? client.count(.window, in: .null(), operation: "count Ghostty windows"),
              windowCount > 0
        else { return false }
        let firstTerminal = AppleEventSpecifier.element(
            .terminal,
            index: 1,
            of: AppleEventSpecifier.element(.tab, index: 1, of: AppleEventSpecifier.element(.window, index: 1))
        )
        do {
            _ = try client.string(
                from: AppleEventSpecifier.property(.tty, of: firstTerminal),
                operation: "probe Ghostty terminal tty property"
            )
            ttyPropertySupport = .supported
        } catch AppleEventControlError.objectNotFound, AppleEventControlError.unsupportedScriptingAPI {
            ttyPropertySupport = .unsupported
        } catch {
            return false
        }
        return ttyPropertySupport == .supported
    }

    /// Walks windows → tabs, bulk-reading one property of every terminal per tab, and returns the
    /// terminal whose value matches. One AppleEvent per tab keeps a full scan cheap.
    func terminalContext(matching property: AppleEventCode.Property, value: String) throws -> TerminalContext? {
        let windowCount = try client.count(.window, in: .null(), operation: "count Ghostty windows")
        guard windowCount > 0 else { return nil }
        for windowIndex in 1 ... windowCount {
            let window = AppleEventSpecifier.element(.window, index: windowIndex)
            let tabCount = try client.count(.tab, in: window, operation: "count Ghostty tabs")
            guard tabCount > 0 else { continue }
            for tabIndex in 1 ... tabCount {
                let tab = AppleEventSpecifier.element(.tab, index: tabIndex, of: window)
                let terminals = AppleEventSpecifier.every(.terminal, of: tab)
                let values = try client.stringList(
                    from: AppleEventSpecifier.property(property, of: terminals),
                    operation: "scan Ghostty terminals"
                )
                guard let index = values.firstIndex(of: value) else { continue }
                let ids = try client.stringList(
                    from: AppleEventSpecifier.property(.id, of: terminals),
                    operation: "read scanned Ghostty terminal ids"
                )
                guard index < ids.count else { continue }
                return try TerminalContext(
                    terminalID: ids[index],
                    windowID: client.string(
                        from: AppleEventSpecifier.property(.id, of: window),
                        operation: "get Ghostty window id"
                    ),
                    tabID: client.string(
                        from: AppleEventSpecifier.property(.id, of: tab),
                        operation: "get Ghostty tab id"
                    )
                )
            }
        }
        return nil
    }

    func tabTerminalCount(tabID: String?, windowID: String?) throws -> Int {
        let window = if let windowID {
            AppleEventSpecifier.element(.window, id: windowID)
        } else {
            AppleEventSpecifier.property(.frontWindow)
        }
        let tab = if let tabID {
            AppleEventSpecifier.element(.tab, id: tabID, of: window)
        } else {
            AppleEventSpecifier.property(.selectedTab, of: window)
        }
        return try client.count(.terminal, in: tab, operation: "count Ghostty tab terminals")
    }

    func performAction(_ action: String, terminalID: String) throws {
        let event = client.event(.ghostty, .performAction)
        event.setParam(AppleEventDescriptor.text(action), forKeyword: keyDirectObject)
        event.setParam(
            AppleEventSpecifier.element(.terminal, id: terminalID),
            forKeyword: AppleEventCode.Parameter.onTerminal.rawValue
        )
        _ = try client.send(event, operation: "perform Ghostty action \(action)")
    }

    func inputText(_ text: String, terminalID: String) throws {
        let event = client.event(.ghostty, .inputText)
        event.setParam(AppleEventDescriptor.text(text), forKeyword: keyDirectObject)
        event.setParam(
            AppleEventSpecifier.element(.terminal, id: terminalID),
            forKeyword: AppleEventCode.Parameter.inputTextTerminal.rawValue
        )
        _ = try client.send(event, operation: "input text to Ghostty terminal")
    }

    func sendKey(_ key: String, terminalID: String) throws {
        let event = client.event(.ghostty, .sendKey)
        event.setParam(AppleEventDescriptor.text(key), forKeyword: keyDirectObject)
        event.setParam(
            AppleEventSpecifier.element(.terminal, id: terminalID),
            forKeyword: AppleEventCode.Parameter.sendKeyTerminal.rawValue
        )
        _ = try client.send(event, operation: "send key to Ghostty terminal")
    }

    func splitTerminal(
        terminalID: String,
        direction: Direction,
        configuration: GhosttySurfaceConfiguration
    ) throws -> GhosttyTerminalReference {
        let event = client.event(.ghostty, .split)
        event.setParam(AppleEventSpecifier.element(.terminal, id: terminalID), forKeyword: keyDirectObject)
        event.setParam(
            AppleEventDescriptor.enumeration(AppleEventCode.SplitDirection(direction).rawValue),
            forKeyword: AppleEventCode.Parameter.direction.rawValue
        )
        if !configuration.isEmpty {
            try event.setParam(
                surfaceConfiguration(configuration),
                forKeyword: AppleEventCode.Parameter.splitConfiguration.rawValue
            )
        }
        let descriptor = try client.send(event, operation: "split Ghostty terminal")
        return try terminalReference(from: descriptor, operation: "read split Ghostty terminal id")
    }

    func focusTerminal(_ terminal: GhosttyTerminalReference) throws {
        let event = client.event(.ghostty, .focus)
        event.setParam(terminal.descriptor, forKeyword: keyDirectObject)
        _ = try client.send(event, operation: "focus Ghostty terminal \(terminal.id)")
    }

    func focusTerminal(id terminalID: String) throws {
        try focusTerminal(GhosttyTerminalReference(
            id: terminalID,
            descriptor: AppleEventSpecifier.element(.terminal, id: terminalID)
        ))
    }

    func windowIndex(windowID: String?) throws -> Int {
        guard let windowID else { return 1 }
        let count = try client.count(.window, in: .null(), operation: "count Ghostty windows")
        guard count > 0 else { return 1 }
        for index in 1 ... count {
            let window = AppleEventSpecifier.element(.window, index: index)
            let id = try client.string(
                from: AppleEventSpecifier.property(.id, of: window),
                operation: "get Ghostty window id"
            )
            if id == windowID {
                return index
            }
        }
        return 1
    }

    private func surfaceConfiguration(_ configuration: GhosttySurfaceConfiguration) throws -> NSAppleEventDescriptor {
        let event = client.event(.ghostty, .newSurfaceConfiguration)
        let descriptor = try client.send(event, operation: "create Ghostty surface configuration")
        if let cwd = configuration.cwd {
            descriptor.setDescriptor(
                AppleEventDescriptor.text(cwd),
                forKeyword: AppleEventCode.Property.initialWorkingDirectory.rawValue
            )
        }
        if let command = configuration.command {
            descriptor.setDescriptor(
                AppleEventDescriptor.text(command),
                forKeyword: AppleEventCode.Property.command.rawValue
            )
        }
        return descriptor
    }

    private func terminalReference(
        from descriptor: NSAppleEventDescriptor,
        operation: String
    ) throws -> GhosttyTerminalReference {
        let id = try client.string(from: AppleEventSpecifier.property(.id, of: descriptor), operation: operation)
        return GhosttyTerminalReference(id: id, descriptor: descriptor)
    }

    private func isGhosttyRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains { app in
            app.bundleIdentifier == "com.mitchellh.ghostty" || app.localizedName == "Ghostty"
        }
    }
}

private final class AppleEventClient {
    private let bundleIdentifier: String

    init(bundleIdentifier: String) {
        self.bundleIdentifier = bundleIdentifier
    }

    func event(_ eventClass: AppleEventCode.EventClass, _ eventID: AppleEventCode.EventID) -> NSAppleEventDescriptor {
        NSAppleEventDescriptor(
            eventClass: eventClass.rawValue,
            eventID: eventID.rawValue,
            targetDescriptor: NSAppleEventDescriptor(bundleIdentifier: bundleIdentifier),
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
    }

    func send(_ event: NSAppleEventDescriptor, operation: String) throws -> NSAppleEventDescriptor {
        do {
            let reply = try event.sendEvent(options: .waitForReply, timeout: 30)
            if let errorCode = reply.paramDescriptor(forKeyword: keyErrorNumber)?.int32Value,
               errorCode != 0 {
                let message = reply.paramDescriptor(forKeyword: keyErrorString)?.stringValue ?? "AppleEvent failed"
                throw AppleEventControlError.from(
                    code: Int(errorCode),
                    operation: operation,
                    message: message
                )
            }
            return reply.paramDescriptor(forKeyword: keyDirectObject) ?? reply
        } catch let error as AppleEventControlError {
            throw error
        } catch let error as NSError {
            throw AppleEventControlError.from(
                code: error.code,
                operation: operation,
                message: error.localizedDescription
            )
        }
    }

    func get(_ object: NSAppleEventDescriptor, operation: String) throws -> NSAppleEventDescriptor {
        let event = event(.core, .getData)
        event.setParam(object, forKeyword: keyDirectObject)
        return try send(event, operation: operation)
    }

    func string(from object: NSAppleEventDescriptor, operation: String) throws -> String {
        try get(object, operation: operation).stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// Non-string items become empty strings rather than being dropped so that parallel bulk reads
    /// of different properties stay index-aligned.
    func stringList(from object: NSAppleEventDescriptor, operation: String) throws -> [String] {
        let result = try get(object, operation: operation)
        guard result.descriptorType == typeAEList else {
            return [result.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""]
        }
        return (0 ..< result.numberOfItems).map { index in
            result.atIndex(index + 1)?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
    }

    func count(
        _ elementClass: AppleEventCode.ObjectClass,
        in container: NSAppleEventDescriptor,
        operation: String
    ) throws -> Int {
        let event = event(.core, .countElements)
        event.setParam(container, forKeyword: keyDirectObject)
        event.setParam(AppleEventDescriptor.type(elementClass.rawValue), forKeyword: keyAEObjectClass)
        return try Int(send(event, operation: operation).int32Value)
    }
}

private enum AppleEventSpecifier {
    static func property(
        _ property: AppleEventCode.Property,
        of container: NSAppleEventDescriptor = .null()
    ) -> NSAppleEventDescriptor {
        objectSpecifier(
            desiredClass: .property,
            container: container,
            keyForm: FourCharCode(formPropertyID),
            keyData: AppleEventDescriptor.type(property.rawValue)
        )
    }

    static func element(
        _ elementClass: AppleEventCode.ObjectClass,
        id: String,
        of container: NSAppleEventDescriptor = .null()
    ) -> NSAppleEventDescriptor {
        objectSpecifier(
            desiredClass: elementClass,
            container: container,
            keyForm: FourCharCode(formUniqueID),
            keyData: AppleEventDescriptor.text(id)
        )
    }

    static func element(
        _ elementClass: AppleEventCode.ObjectClass,
        index: Int,
        of container: NSAppleEventDescriptor = .null()
    ) -> NSAppleEventDescriptor {
        objectSpecifier(
            desiredClass: elementClass,
            container: container,
            keyForm: FourCharCode(formAbsolutePosition),
            keyData: NSAppleEventDescriptor(int32: Int32(index))
        )
    }

    static func every(
        _ elementClass: AppleEventCode.ObjectClass,
        of container: NSAppleEventDescriptor = .null()
    ) -> NSAppleEventDescriptor {
        objectSpecifier(
            desiredClass: elementClass,
            container: container,
            keyForm: FourCharCode(formAbsolutePosition),
            keyData: AppleEventDescriptor.absoluteOrdinal(FourCharCode(kAEAll))
        )
    }

    private static func objectSpecifier(
        desiredClass: AppleEventCode.DescriptorType,
        container: NSAppleEventDescriptor,
        keyForm: FourCharCode,
        keyData: NSAppleEventDescriptor
    ) -> NSAppleEventDescriptor {
        let specifier = NSAppleEventDescriptor.record()
        specifier.setDescriptor(
            AppleEventDescriptor.type(desiredClass.rawValue),
            forKeyword: AEKeyword(keyAEDesiredClass)
        )
        specifier.setDescriptor(container, forKeyword: AEKeyword(keyAEContainer))
        specifier.setDescriptor(AppleEventDescriptor.enumeration(keyForm), forKeyword: AEKeyword(keyAEKeyForm))
        specifier.setDescriptor(keyData, forKeyword: AEKeyword(keyAEKeyData))
        return specifier.coerce(toDescriptorType: typeObjectSpecifier) ?? specifier
    }

    private static func objectSpecifier(
        desiredClass: AppleEventCode.ObjectClass,
        container: NSAppleEventDescriptor,
        keyForm: FourCharCode,
        keyData: NSAppleEventDescriptor
    ) -> NSAppleEventDescriptor {
        objectSpecifier(
            desiredClass: .object(desiredClass),
            container: container,
            keyForm: keyForm,
            keyData: keyData
        )
    }
}

private enum AppleEventDescriptor {
    static func text(_ value: String) -> NSAppleEventDescriptor {
        NSAppleEventDescriptor(string: value)
    }

    /// The ordinal payload is a native-order OSType, matching what AppleScript itself sends.
    static func absoluteOrdinal(_ code: FourCharCode) -> NSAppleEventDescriptor {
        var value = code
        let descriptor = withUnsafeBytes(of: &value) { raw in
            NSAppleEventDescriptor(descriptorType: typeAbsoluteOrdinal, bytes: raw.baseAddress, length: raw.count)
        }
        return descriptor ?? enumeration(code)
    }

    static func type(_ code: FourCharCode) -> NSAppleEventDescriptor {
        NSAppleEventDescriptor(typeCode: code)
    }

    static func enumeration(_ code: FourCharCode) -> NSAppleEventDescriptor {
        NSAppleEventDescriptor(enumCode: code)
    }
}

extension Error {
    /// Discriminates the AppleEvent failure meaning "this terminal no longer exists" so request
    /// dispatch can heal stale tty bindings
    var isGhosttyObjectNotFound: Bool {
        if case .objectNotFound = self as? AppleEventControlError {
            return true
        }
        return false
    }
}

enum AppleEventControlError: Error, LocalizedError {
    case ghosttyUnavailable(operation: String)
    case automationDenied(operation: String)
    case automationConsentRequired(operation: String)
    case unsupportedScriptingAPI(operation: String)
    case objectNotFound(operation: String)
    case invalidDescriptor(operation: String)
    case failed(operation: String, code: Int, message: String)

    var errorDescription: String? {
        switch self {
        case let .ghosttyUnavailable(operation):
            "Ghostty is unavailable while trying to \(operation)"
        case let .automationDenied(operation):
            "Automation permission was denied while trying to \(operation)"
        case let .automationConsentRequired(operation):
            "Automation permission is required to \(operation)"
        case let .unsupportedScriptingAPI(operation):
            "Ghostty does not support the scripting operation needed to \(operation)"
        case let .objectNotFound(operation):
            "Ghostty object was not found while trying to \(operation)"
        case let .invalidDescriptor(operation):
            "Ghostty scripting returned an unexpected value while trying to \(operation)"
        case let .failed(operation, code, message):
            "failed to \(operation): \(message) (\(code))"
        }
    }

    static func from(code: Int, operation: String, message: String) -> AppleEventControlError {
        switch code {
        case Int(procNotFound), Int(connectionInvalid):
            .ghosttyUnavailable(operation: operation)
        case Int(errAEEventNotPermitted):
            .automationDenied(operation: operation)
        case Int(errAEEventWouldRequireUserConsent):
            .automationConsentRequired(operation: operation)
        case Int(errAEEventNotHandled):
            .unsupportedScriptingAPI(operation: operation)
        case Int(errAENoSuchObject):
            .objectNotFound(operation: operation)
        case Int(errAECoercionFail):
            .invalidDescriptor(operation: operation)
        default:
            .failed(operation: operation, code: code, message: message)
        }
    }
}

private enum AppleEventCode {
    enum EventClass: FourCharCode {
        case core = 0x636F_7265
        case ghostty = 0x4768_7374
    }

    enum EventID: FourCharCode {
        case countElements = 0x636E_7465
        case focus = 0x4663_7573
        case getData = 0x6765_7464
        case inputText = 0x496E_5478
        case newSurfaceConfiguration = 0x4E53_4366
        case performAction = 0x5066_4163
        case sendKey = 0x534B_6579
        case split = 0x5370_6C74
    }

    enum ObjectClass: FourCharCode {
        case tab = 0x4774_6162
        case terminal = 0x4774_726D
        case window = 0x4777_6E64
    }

    enum Property: FourCharCode {
        case command = 0x4753_6343
        case frontWindow = 0x4746_576E
        case id = 0x4944_2020
        case initialWorkingDirectory = 0x4753_6344
        case selectedTab = 0x4757_7354
        case tty = 0x4774_7479
        case workingDirectory = 0x4777_6472
    }

    enum Parameter: FourCharCode {
        case direction = 0x4753_7064
        case inputTextTerminal = 0x4749_7454
        case onTerminal = 0x476F_6E54
        case sendKeyTerminal = 0x474B_6554
        case splitConfiguration = 0x4753_7053
    }

    enum SplitDirection: FourCharCode {
        case right = 0x4753_7274
        case left = 0x4753_6C66
        case down = 0x4753_646E
        case up = 0x4753_7570

        init(_ direction: Direction) {
            switch direction {
            case .right: self = .right
            case .left: self = .left
            case .down: self = .down
            case .up: self = .up
            }
        }
    }

    enum DescriptorType {
        case property
        case object(ObjectClass)

        var rawValue: FourCharCode {
            switch self {
            case .property: 0x7072_6F70
            case let .object(objectClass): objectClass.rawValue
            }
        }
    }
}
