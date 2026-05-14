package main

import (
	"os"

	"github.com/thurstonsand/ghosttykit/cli/gty/internal/tty"
)

type options struct {
	tty string
}

func requestTTY(opts *options) (string, error) {
	if opts.tty != "" {
		return tty.Normalize(opts.tty), nil
	}
	if value := os.Getenv("GTY_TTY"); value != "" {
		return tty.Normalize(value), nil
	}
	return tty.Current()
}

func optionalTTY(opts *options) string {
	value, err := requestTTY(opts)
	if err != nil {
		return ""
	}
	return value
}
