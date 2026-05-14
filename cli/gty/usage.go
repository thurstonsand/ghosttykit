package main

import (
	"github.com/spf13/cobra"
)

type usageError struct {
	err error
}

func (e usageError) Error() string {
	return e.err.Error()
}

func (e usageError) Unwrap() error {
	return e.err
}

func (e usageError) ExitCode() int {
	return exitUsage
}

func configureUsageErrors(command *cobra.Command) {
	command.SetFlagErrorFunc(func(_ *cobra.Command, err error) error {
		return usageError{err: err}
	})
	if command.Args != nil {
		validateArgs := command.Args
		command.Args = func(cmd *cobra.Command, args []string) error {
			if err := validateArgs(cmd, args); err != nil {
				return usageError{err: err}
			}
			return nil
		}
	}
	for _, child := range command.Commands() {
		configureUsageErrors(child)
	}
}
