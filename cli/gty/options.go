package main

import (
	"os"

	"github.com/thurstonsand/ghosttykit/cli/gty/internal/tty"
)

type options struct {
	tty string
}

type terminalTarget struct {
	tty     string
	focused bool
}

func requestTerminalTarget(opts *options) (terminalTarget, error) {
	if opts.tty != "" {
		value := tty.Normalize(opts.tty)
		current, err := tty.Current()
		return terminalTarget{tty: value, focused: err == nil && current == value}, nil
	}
	if value := os.Getenv("GTY_TTY"); value != "" {
		return terminalTarget{tty: tty.Normalize(value), focused: true}, nil
	}
	value, err := tty.Current()
	if err != nil {
		return terminalTarget{}, err
	}
	return terminalTarget{tty: value, focused: true}, nil
}

func requestTTY(opts *options) (string, error) {
	target, err := requestTerminalTarget(opts)
	if err != nil {
		return "", err
	}
	return target.tty, nil
}

func optionalTerminalTarget(opts *options) terminalTarget {
	target, err := requestTerminalTarget(opts)
	if err != nil {
		return terminalTarget{}
	}
	return target
}

func optionalTTY(opts *options) string {
	return optionalTerminalTarget(opts).tty
}
