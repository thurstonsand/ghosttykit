import Foundation

final class SystemEventsWindowGeometry {
    func dimension(for direction: Direction, windowIndex: Int) throws -> Int {
        let axisIndex = (direction == .left || direction == .right) ? 1 : 2
        let source = """
        tell application "System Events"
            tell process "Ghostty"
                if (count of windows) is 0 then error "Ghostty has no windows"
                set winSize to size of window \(windowIndex)
                return item \(axisIndex) of winSize
            end tell
        end tell
        """
        return try AppleScriptRunner.intValue(from: AppleScriptRunner.execute(source))
    }
}

enum AppleScriptRunner {
    static func execute(_ source: String) throws -> NSAppleEventDescriptor {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            throw NSError(
                domain: "ghosttykitd",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "failed to compile AppleScript"]
            )
        }

        let result = script.executeAndReturnError(&error)
        if let error {
            let message = error[NSAppleScript.errorMessage] as? String ?? "AppleScript failed"
            var userInfo = error as? [String: Any] ?? [:]
            userInfo[NSLocalizedDescriptionKey] = message
            throw NSError(domain: "ghosttykitd", code: 1, userInfo: userInfo)
        }
        return result
    }

    static func intValue(from descriptor: NSAppleEventDescriptor) throws -> Int {
        if let stringValue = descriptor.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
           let intValue = Int(stringValue) {
            return intValue
        }

        let int32Value = Int(descriptor.int32Value)
        if int32Value != 0 || descriptor.stringValue == nil {
            return int32Value
        }

        throw NSError(
            domain: "ghosttykitd",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "failed to decode AppleScript integer result"]
        )
    }
}
