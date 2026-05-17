// Package osc emits terminal control sequences.
package osc

import (
	"os"
	"strings"
	"unicode"
)

// Title sets the terminal title after stripping control characters from value.
func Title(value string) error {
	clean := sanitizeTitle(value)

	file, err := os.OpenFile("/dev/tty", os.O_WRONLY, 0)
	if err != nil {
		return err
	}
	defer func() { _ = file.Close() }()
	_, err = file.WriteString("\x1b]2;" + clean + "\x07")
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
