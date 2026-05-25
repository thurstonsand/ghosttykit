// Package remote implements GhosttyKit remote SSH bridge behavior.
package remote

import "strings"

// RunCommand builds the shell command used for the final SSH session.
func RunCommand(remoteGTY, socketPath string, args []string) string {
	parts := []string{"GTY_SOCK=" + ShellQuote(socketPath), ShellQuote(remoteGTY), "ssh", "remote-run"}
	if len(args) > 0 {
		parts = append(parts, "--")
		for _, arg := range args {
			parts = append(parts, ShellQuote(arg))
		}
	}
	return strings.Join(parts, " ")
}

// ShellQuote quotes a string for POSIX shell command assembly.
func ShellQuote(value string) string {
	if value == "" {
		return "''"
	}
	return "'" + strings.ReplaceAll(value, "'", "'\\''") + "'"
}
