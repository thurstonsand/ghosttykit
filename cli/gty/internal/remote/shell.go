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
	return posixShellCommand(strings.Join(parts, " "))
}

// posixShellCommand wraps a script for `ssh host <command>`, which runs it through the account's
// login shell. That shell need not parse POSIX syntax, so GhosttyKit's own scripts run under
// /bin/sh. An interactive session still reaches the user's shell, by way of gty ssh remote-run.
func posixShellCommand(script string) string {
	return "/bin/sh -c " + ShellQuote(script)
}

// ShellQuote quotes a string for POSIX shell command assembly.
func ShellQuote(value string) string {
	if value == "" {
		return "''"
	}
	return "'" + strings.ReplaceAll(value, "'", "'\\''") + "'"
}
