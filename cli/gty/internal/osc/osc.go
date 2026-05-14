// Package osc emits terminal control sequences.
package osc

import (
	"os"
	"strings"
)

// Title sets the terminal title after stripping control characters from value.
func Title(value string) error {
	clean := strings.Map(func(r rune) rune {
		if r < 0x20 || r == 0x7f {
			return -1
		}
		return r
	}, value)

	file, err := os.OpenFile("/dev/tty", os.O_WRONLY, 0)
	if err != nil {
		return err
	}
	defer func() { _ = file.Close() }()
	_, err = file.WriteString("\x1b]2;" + clean + "\x07")
	return err
}
