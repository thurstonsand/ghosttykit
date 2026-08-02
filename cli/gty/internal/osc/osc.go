// Package osc emits terminal control sequences.
package osc

import (
	"os"
	"strings"
	"unicode"
)

// Title sets the terminal title after stripping control characters from value.
func Title(value string) error {
	return writeTTY("\x1b]2;" + sanitizeTitle(value) + "\x07")
}

// ResetInteractiveModes returns the terminal to the state an interactive shell expects. A
// full-screen application normally unwinds these modes itself on exit; when its session dies
// without unwinding, nothing else does it. Ghostty does not implement DECSTR, and kitty keyboard
// flags live on a per-screen stack, so every mode is unwound explicitly and the kitty stack is
// drained on both the alternate and primary screens.
func ResetInteractiveModes() error {
	return writeTTY("\x1b[?9;1000;1002;1003;1004;2004;2026l" +
		"\x1b[<8u" +
		"\x1b[?1049;1047;47l" +
		"\x1b[<8u" +
		"\x1b[r\x1b[?7h\x1b[?1l\x1b>\x1b[0m\x1b[?25h")
}

func writeTTY(sequence string) error {
	file, err := os.OpenFile("/dev/tty", os.O_WRONLY, 0)
	if err != nil {
		return err
	}
	defer func() { _ = file.Close() }()
	_, err = file.WriteString(sequence)
	return err
}

func sanitizeTitle(value string) string {
	return strings.Map(func(r rune) rune {
		if unicode.IsControl(r) {
			return -1
		}
		return r
	}, value)
}
