package main

import (
	"strings"

	"github.com/spf13/cobra"

	"github.com/thurstonsand/ghosttykit/sdk/go/client"
)

func inputCmd(opts *options) *cobra.Command {
	var submit bool
	var wait bool
	cmd := &cobra.Command{
		Use:  "input <text...>",
		Args: cobra.MinimumNArgs(1),
		RunE: func(_ *cobra.Command, args []string) error {
			target, err := requestTerminalTarget(opts)
			if err != nil {
				return err
			}
			return client.New().Input(client.InputOptions{
				TerminalOptions: client.TerminalOptions{TTY: target.tty, Focused: target.focused},
				AckOptions:      client.AckOptions{Wait: wait},
				Text:            strings.Join(args, " "),
				Submit:          submit,
			})
		},
	}
	cmd.Flags().BoolVar(&submit, "submit", false, "follow the text with an enter keypress")
	cmd.Flags().BoolVar(&wait, "wait", false, "wait for acknowledgement")
	return cmd
}
