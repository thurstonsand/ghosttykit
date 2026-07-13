// Package tty resolves terminal device paths for daemon requests.
package tty

import (
	"errors"
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

// Current returns the terminal path of the first stdio descriptor that is valid.
func Current() (string, error) {
	for _, stdio := range []*os.File{os.Stdin, os.Stdout, os.Stderr} {
		if path, err := ttyCommand(stdio); err == nil {
			return path, nil
		}
	}
	return "", errors.New("no stdio descriptor is a terminal")
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
