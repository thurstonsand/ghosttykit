import AppKit
import Foundation

enum GhosttyKitError: Error, LocalizedError {
    case invalidResize(String)
    case terminalNotFound(String)
    case accessibilityNotGranted

    var errorDescription: String? {
        switch self {
        case let .invalidResize(value): "invalid resize amount: \(value)"
        case let .terminalNotFound(value): "no Ghostty terminal is associated with \(value)"
        case .accessibilityNotGranted:
            "percent resize reads the window size through System Events, which needs Accessibility " +
                "permission for ghosttykitd (System Settings → Privacy & Security)"
        }
    }

    var protocolCode: String {
        switch self {
        case .invalidResize:
            ProtocolCode.invalidRequest
        case .terminalNotFound:
            ProtocolCode.terminalNotFound
        case .accessibilityNotGranted:
            ProtocolCode.ghosttyUnavailable
        }
    }
}

protocol GhosttyControlling {
    /// Sends a harmless Apple Event and returns the running Ghostty's version, or nil when Ghostty
    /// is not running.
    func preflightAutomationPermission() throws -> String?
    /// Percent resize reads window sizes through System Events GUI scripting, which macOS gates
    /// behind Accessibility.
    func accessibilityGranted() -> Bool
    func terminalContext(forTTY tty: String) throws -> TerminalContext
    /// Whether the terminal still sits in its tab and window and still owns the tty.
    func isBound(_ terminal: TerminalContext, to tty: String) throws -> Bool
    func readPasteboardContent() throws -> FrameStreamReply
    func activateKeyTable(_ table: String, terminal: TerminalContext) throws
    func deactivateKeyTable(terminal: TerminalContext) throws
    func focusSplit(direction: Direction, terminal: TerminalContext) throws
    func input(_ text: String, submit: Bool, terminal: TerminalContext) throws
    func toggleSplitZoom(terminal: TerminalContext) throws
    func tabTerminalCount(terminal: TerminalContext) throws -> Int
    func split(
        direction: Direction,
        cwd: String?,
        command: String?,
        focus: FocusTarget,
        terminal: TerminalContext
    ) throws -> (tty: String, terminal: TerminalContext)
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

    func accessibilityGranted() -> Bool {
        true
    }

    func preflightAutomationPermission() throws -> String? {
        "1.4.0-dry-run"
    }

    func isBound(_: TerminalContext, to _: String) throws -> Bool {
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
    ) throws -> (tty: String, terminal: TerminalContext) {
        (
            tty: "/dev/dry-run-split",
            terminal: TerminalContext(
                terminalID: "dry-run-split-terminal",
                windowID: terminal.windowID,
                tabID: terminal.tabID
            )
        )
    }

    func resize(direction _: Direction, amount _: ResizeAmount, terminal _: TerminalContext) throws {}
}

final class AppleEventGhosttyController: GhosttyControlling {
    private let ghostty = GhosttyAppleEvents()
    private let windowGeometry = SystemEventsWindowGeometry()

    func preflightAutomationPermission() throws -> String? {
        try ghostty.preflightAutomationPermission()
    }

    func accessibilityGranted() -> Bool {
        AXIsProcessTrusted()
    }

    func isBound(_ terminal: TerminalContext, to tty: String) throws -> Bool {
        try ghostty.isBound(terminal, to: tty)
    }

    func terminalContext(forTTY tty: String) throws -> TerminalContext {
        guard let terminal = try ghostty.terminalContext(forTTY: tty) else {
            throw GhosttyKitError.terminalNotFound(tty)
        }
        return terminal
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
    ) throws -> (tty: String, terminal: TerminalContext) {
        let newTerminal = try ghostty.splitTerminal(
            terminalID: terminal.terminalID,
            direction: direction,
            configuration: GhosttySurfaceConfiguration(cwd: cwd, command: command)
        )
        switch focus {
        case .new:
            try ghostty.focusTerminal(id: newTerminal.id)
        case .original:
            try ghostty.focusTerminal(id: terminal.terminalID)
        }
        // Splits stay in the origin terminal's window and tab.
        return (
            tty: newTerminal.tty,
            terminal: TerminalContext(
                terminalID: newTerminal.id,
                windowID: terminal.windowID,
                tabID: terminal.tabID
            )
        )
    }

    func resize(direction: Direction, amount: ResizeAmount, terminal: TerminalContext) throws {
        let pixels: Int
        switch (amount.pixels, amount.percent) {
        case (.some(let value), nil):
            pixels = value
        case (nil, let .some(value)):
            guard value > 0 else { throw GhosttyKitError.invalidResize("percent must be greater than 0") }
            // Without Accessibility, System Events can stall for its two-minute Apple Event timeout
            // instead of refusing.
            guard accessibilityGranted() else { throw GhosttyKitError.accessibilityNotGranted }
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
    let tty: String
}

private final class GhosttyAppleEvents {
    private let client = AppleEventClient(bundleIdentifier: "com.mitchellh.ghostty")

    func preflightAutomationPermission() throws -> String? {
        guard isGhosttyRunning() else { return nil }
        return try client.string(from: AppleEventSpecifier.property(.version), operation: "get Ghostty version")
    }

    /// Walks windows → tabs, bulk-reading the tty of every terminal per tab. One AppleEvent per tab
    /// keeps a full scan cheap.
    func terminalContext(forTTY tty: String) throws -> TerminalContext? {
        let windowCount = try client.count(.window, in: .null(), operation: "count Ghostty windows")
        guard windowCount > 0 else { return nil }
        for windowIndex in 1 ... windowCount {
            let window = AppleEventSpecifier.element(.window, index: windowIndex)
            let tabCount = try client.count(.tab, in: window, operation: "count Ghostty tabs")
            guard tabCount > 0 else { continue }
            for tabIndex in 1 ... tabCount {
                let tab = AppleEventSpecifier.element(.tab, index: tabIndex, of: window)
                let terminals = AppleEventSpecifier.every(.terminal, of: tab)
                let ttys = try client.stringList(
                    from: AppleEventSpecifier.property(.tty, of: terminals),
                    operation: "scan Ghostty terminal ttys"
                )
                guard let index = ttys.firstIndex(of: tty) else { continue }
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

    /// One Apple Event: reading the tty through the full window → tab → terminal path fails when
    /// any link has moved or closed.
    func isBound(_ terminal: TerminalContext, to tty: String) throws -> Bool {
        let window = AppleEventSpecifier.element(.window, id: terminal.windowID)
        let tab = AppleEventSpecifier.element(.tab, id: terminal.tabID, of: window)
        do {
            let boundTTY = try client.string(
                from: AppleEventSpecifier.property(
                    .tty, of: AppleEventSpecifier.element(.terminal, id: terminal.terminalID, of: tab)
                ),
                operation: "verify cached Ghostty terminal"
            )
            return boundTTY == tty
        } catch let error where error.isGhosttyObjectNotFound {
            return false
        }
    }

    func tabTerminalCount(tabID: String, windowID: String) throws -> Int {
        let window = AppleEventSpecifier.element(.window, id: windowID)
        let tab = AppleEventSpecifier.element(.tab, id: tabID, of: window)
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
        return try terminalReference(from: descriptor)
    }

    func focusTerminal(id terminalID: String) throws {
        let event = client.event(.ghostty, .focus)
        event.setParam(AppleEventSpecifier.element(.terminal, id: terminalID), forKeyword: keyDirectObject)
        _ = try client.send(event, operation: "focus Ghostty terminal \(terminalID)")
    }

    func windowIndex(windowID: String) throws -> Int {
        let count = try client.count(.window, in: .null(), operation: "count Ghostty windows")
        for index in stride(from: 1, through: count, by: 1) {
            let window = AppleEventSpecifier.element(.window, index: index)
            let id = try client.string(
                from: AppleEventSpecifier.property(.id, of: window),
                operation: "get Ghostty window id"
            )
            if id == windowID {
                return index
            }
        }
        throw AppleEventControlError.objectNotFound(operation: "find Ghostty window \(windowID)")
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

    private func terminalReference(from descriptor: NSAppleEventDescriptor) throws -> GhosttyTerminalReference {
        try GhosttyTerminalReference(
            id: client.string(
                from: AppleEventSpecifier.property(.id, of: descriptor),
                operation: "read split Ghostty terminal id"
            ),
            tty: client.string(
                from: AppleEventSpecifier.property(.tty, of: descriptor),
                operation: "read split Ghostty terminal tty"
            )
        )
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
        case id = 0x4944_2020
        case initialWorkingDirectory = 0x4753_6344
        case tty = 0x4774_7479
        case version = 0x7665_7273
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
