struct DoctorRequest: CommandRequest {
    let version: Int
    let command: String

    var tty: String? {
        nil
    }

    func reply(using context: CommandContext) throws -> ReplyBody {
        var checks = [DoctorCheck.ok(name: "daemon", message: "socket reachable")]

        do {
            if try context.ghostty.preflightAutomationPermission() {
                checks.append(.ok(name: "automation", message: "Ghostty accepted Apple Events"))
            } else {
                checks.append(.warning(
                    name: "automation",
                    message: "Ghostty is not running; Automation permission was not checked"
                ))
            }
        } catch {
            checks.append(.failure(name: "automation", message: error.localizedDescription))
        }

        return .frame(DoctorReply(checks: checks))
    }
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
