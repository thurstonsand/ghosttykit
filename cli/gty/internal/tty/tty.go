// Package tty resolves terminal device paths for daemon requests.
package tty

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

// Normalize returns value as an absolute /dev path.
func Normalize(value string) string {
	if len(value) >= 5 && value[:5] == "/dev/" {
		return value
	}
	return "/dev/" + value
}

// Current returns the path for the controlling terminal.
func Current() (string, error) {
	file, err := os.OpenFile("/dev/tty", os.O_RDONLY, 0)
	if err != nil {
		return "", fmt.Errorf("open /dev/tty: %w", err)
	}
	defer func() { _ = file.Close() }()

	return ttyCommand(file)
}

func ttyCommand(stdin *os.File) (string, error) {
	cmd := exec.Command("tty")
	cmd.Stdin = stdin
	output, err := cmd.Output()
	if err != nil {
		return "", err
	}
	path := strings.TrimSpace(string(output))
	if path == "" || path == "not a tty" {
		return "", errors.New("tty command did not return a tty")
	}
	if !filepath.IsAbs(path) {
		return Normalize(path), nil
	}
	return path, nil
}
