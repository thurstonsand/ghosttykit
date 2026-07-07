import Foundation

/// Composes the command a daemon-created terminal runs so its first act is a spawn claim:
/// `/bin/sh -c 'GTY_SOCK=<socket> <gty> spawn-claim <token> >/dev/null 2>&1; exec <target>'`.
/// The socket is pinned because Ghostty-spawned processes do not inherit the daemon's
/// environment. The `;` is deliberate — a failed claim must still run the target, degrading
/// to lazy heuristic binding.
struct SpawnWrapper {
    struct Spawn {
        let token: String
        let command: String
    }

    let gtyPath: String
    let socketPath: String
    var loginShell: () -> String = resolveLoginShell

    /// Mints a fresh single-use token and the wrapped command that will claim it. The token is
    /// generated here, before the split AppleEvent, because it must ride in the command; the
    /// rendezvous escrows the terminal under it afterward, once the split reply names it.
    func mint(wrapping target: String?) -> Spawn {
        let token = UUID().uuidString.lowercased()
        return Spawn(token: token, command: command(token: token, wrapping: target))
    }

    func command(token: String, wrapping target: String?) -> String {
        let execTarget = target ?? "-l \(shellWordEscape(loginShell()))"
        let claim = "GTY_SOCK=\(shellWordEscape(socketPath)) \(shellWordEscape(gtyPath)) spawn-claim \(token)"
        let script = "\(claim) >/dev/null 2>&1; exec \(execTarget)"
        return "/bin/sh -c \(shellWordEscape(script))"
    }
}

/// Backslash-escapes one word for Ghostty's shell-words command parsing. Backslash escapes
/// survive both Ghostty's parser and `/bin/sh`; quote characters are avoided
/// entirely so no quoting mode can be broken out of. `=` stays literal — escaping it would
/// stop `/bin/sh` from recognizing the `GTY_SOCK=` prefix as an assignment.
func shellWordEscape(_ word: String) -> String {
    let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-./="))
    var escaped = ""
    escaped.unicodeScalars.reserveCapacity(word.unicodeScalars.count)
    for scalar in word.unicodeScalars {
        if !safe.contains(scalar) {
            escaped.unicodeScalars.append("\\")
        }
        escaped.unicodeScalars.append(scalar)
    }
    return escaped
}

/// The user record's shell (backed by DirectoryServices, same source as `dscl`), then `$SHELL`,
/// then `/bin/zsh`.
private func resolveLoginShell() -> String {
    if let passwd = getpwuid(getuid()), let shell = passwd.pointee.pw_shell {
        let value = String(cString: shell)
        if !value.isEmpty {
            return value
        }
    }
    if let shell = ProcessInfo.processInfo.environment["SHELL"], !shell.isEmpty {
        return shell
    }
    return "/bin/zsh"
}
