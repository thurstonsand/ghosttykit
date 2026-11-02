struct DoctorRequest: CommandRequest {
    let version: Int
    let command: String

    var tty: String? {
        nil
    }

    func reply(using context: CommandContext) throws -> ReplyBody {
        var checks = [DoctorCheck.ok(name: "daemon", message: "socket reachable")]

        do {
            if let version = try context.ghostty.preflightAutomationPermission() {
                checks.append(.ok(name: "automation", message: "Ghostty accepted Apple Events"))
                checks.append(ghosttyVersionCheck(version))
            } else {
                checks.append(.warning(
                    name: "automation",
                    message: "Ghostty is not running; Automation permission was not checked"
                ))
            }
        } catch {
            checks.append(.failure(name: "automation", message: error.localizedDescription))
        }

        if context.ghostty.accessibilityGranted() {
            checks.append(.ok(
                name: "accessibility",
                message: "Accessibility granted; percent resize can read window sizes"
            ))
        } else {
            checks.append(.warning(
                name: "accessibility",
                message: "Accessibility not granted; resize --percent fails until ghosttykitd is allowed in " +
                    "System Settings → Privacy & Security"
            ))
        }

        return .frame(DoctorReply(checks: checks))
    }
}

private let minimumGhosttyVersion = [1, 4, 0]

/// Tip builds carry suffixes such as `1.4.0-dev+abc`; only the leading numbers of each component count.
private func ghosttyVersionCheck(_ version: String) -> DoctorCheck {
    let components = version.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
    guard components.lexicographicallyPrecedes(minimumGhosttyVersion) else {
        return .ok(name: "ghostty", message: "Ghostty \(version)")
    }
    let minimum = minimumGhosttyVersion.map(String.init).joined(separator: ".")
    return .failure(name: "ghostty", message: "Ghostty \(version) is older than the required \(minimum)")
}

struct DoctorReply: Codable {
    let version = ProtocolVersion.current
    let code = ProtocolCode.ok
    let healthy: Bool
    let checks: [DoctorCheck]

    init(checks: [DoctorCheck]) {
        self.checks = checks
        healthy = checks.allSatisfy { $0.status != DoctorCheck.Status.failed.rawValue }
    }

    enum CodingKeys: String, CodingKey {
        case version
        case code
        case healthy
        case checks
    }
}

struct DoctorCheck: Codable {
    enum Status: String {
        case ok
        case warning
        case failed
    }

    let name: String
    let status: String
    let message: String

    static func ok(name: String, message: String) -> DoctorCheck {
        DoctorCheck(name: name, status: Status.ok.rawValue, message: message)
    }

    static func warning(name: String, message: String) -> DoctorCheck {
        DoctorCheck(name: name, status: Status.warning.rawValue, message: message)
    }

    static func failure(name: String, message: String) -> DoctorCheck {
        DoctorCheck(name: name, status: Status.failed.rawValue, message: message)
    }
}
