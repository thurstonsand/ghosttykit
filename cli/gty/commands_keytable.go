package main

import (
	"github.com/spf13/cobra"

	"github.com/thurstonsand/ghosttykit/sdk/go/client"
)

func keyTableCmd(opts *options) *cobra.Command {
	var wait bool
	cmd := &cobra.Command{
		Use:   "key-table",
		Short: "Activate or deactivate Ghostty key tables",
	}
	cmd.AddCommand(
		&cobra.Command{
			Use:   "activate <table>",
			Short: "Activate a Ghostty key table for the caller's terminal",
			Args:  cobra.ExactArgs(1),
			RunE: func(_ *cobra.Command, args []string) error {
				return client.New().ActivateKeyTable(client.KeyTableOptions{
					TerminalOptions: client.TerminalOptions{TTY: opts.tty},
					AckOptions:      client.AckOptions{Wait: wait},
					Table:           args[0],
				})
			},
		},
		&cobra.Command{
			Use:   "deactivate",
			Short: "Deactivate the caller's active Ghostty key table",
			Args:  cobra.NoArgs,
			RunE: func(_ *cobra.Command, _ []string) error {
				return client.New().DeactivateKeyTable(client.KeyTableOptions{
					TerminalOptions: client.TerminalOptions{TTY: opts.tty},
					AckOptions:      client.AckOptions{Wait: wait},
				})
			},
		},
	)
	cmd.PersistentFlags().BoolVar(&wait, "wait", false, "wait for acknowledgement")
	return cmd
}
