import Darwin
import Foundation

/// Writes OSC 7 working-directory reports directly to a pty device so the daemon can rendezvous a
/// tty with the Ghostty terminal that renders it. The device is opened non-blocking:
/// a pty that cannot accept a short escape sequence is a failed resolution, never a wedged queue.
struct TTYDevice {
    private let fd: Int32
    private let path: String

    init(path: String) throws {
        self.path = path
        fd = open(path, O_WRONLY | O_NOCTTY | O_NONBLOCK)
        guard fd >= 0 else { throw GhosttyKitError.terminalNotFound(path) }
        guard isatty(fd) == 1 else {
            Darwin.close(fd)
            throw GhosttyKitError.terminalNotFound(path)
        }
    }

    func close() {
        Darwin.close(fd)
    }

    /// The cwd of the pty's foreground process group — "foreground" in the job-control sense (the
    /// job ^C would signal), unrelated to Ghostty focus. This is the fact OSC 7 exists to report,
    /// read from the kernel because the owning terminal is not known until the rendezvous
    /// completes. Prefers the group leader's cwd, then any group member's.
    func foregroundProcessWorkingDirectory() -> String? {
        let processes = processesOnTTY()
        guard let foregroundPGID = processes.first?.kp_eproc.e_tpgid else { return nil }
        let members = processes.filter { $0.kp_eproc.e_pgid == foregroundPGID }.map(\.kp_proc.p_pid)
        for pid in [foregroundPGID] + members where pid > 0 {
            if let cwd = workingDirectory(ofPID: pid) {
                return cwd
            }
        }
        return nil
    }

    /// `tcgetpgrp` refuses ttys the caller does not control, so process data comes from
    /// `sysctl KERN_PROC_TTY` — the same source `ps -t` reads. Every entry carries the tty's
    /// foreground pgid in `e_tpgid`.
    private func processesOnTTY() -> [kinfo_proc] {
        var status = stat()
        guard fstat(fd, &status) == 0 else { return [] }
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_TTY, Int32(bitPattern: UInt32(status.st_rdev))]
        var size = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else { return [] }
        var processes = [kinfo_proc](repeating: kinfo_proc(), count: size / MemoryLayout<kinfo_proc>.stride)
        guard sysctl(&mib, 4, &processes, &size, nil, 0) == 0 else { return [] }
        return Array(processes.prefix(size / MemoryLayout<kinfo_proc>.stride))
    }

    private func workingDirectory(ofPID pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        return withUnsafeBytes(of: info.pvi_cdir.vip_path) { raw in
            raw.bindMemory(to: CChar.self).baseAddress.map { String(cString: $0) }
        }
    }

    /// nil resets the terminal's pwd (empty OSC 7) — a clean unknown, never a wrong value.
    func reportWorkingDirectory(_ path: String?) throws {
        let url = path.map { candidate in
            "file://localhost" + (candidate.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? candidate)
        } ?? ""
        try write("\u{1B}]7;\(url)\u{07}")
    }

    private func write(_ text: String) throws {
        let bytes = Array(text.utf8)
        var written = 0
        while written < bytes.count {
            let result = bytes[written...].withUnsafeBytes { raw -> Int in
                guard let base = raw.baseAddress else { return -1 }
                return Darwin.write(fd, base, raw.count)
            }
            if result < 0, errno == EINTR {
                continue
            }
            guard result > 0 else { throw GhosttyKitError.terminalNotFound(path) }
            written += result
        }
    }
}
