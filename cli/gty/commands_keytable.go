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
			Use:  "activate <table>",
			Args: cobra.ExactArgs(1),
			RunE: func(_ *cobra.Command, args []string) error {
				target, err := requestTerminalTarget(opts)
				if err != nil {
					return err
				}
				return client.New().ActivateKeyTable(client.KeyTableOptions{
					TerminalOptions: client.TerminalOptions{TTY: target.tty, Focused: target.focused},
					AckOptions:      client.AckOptions{Wait: wait},
					Table:           args[0],
				})
			},
		},
		&cobra.Command{
			Use:  "deactivate",
			Args: cobra.NoArgs,
			RunE: func(_ *cobra.Command, _ []string) error {
				target, err := requestTerminalTarget(opts)
				if err != nil {
					return err
				}
				return client.New().DeactivateKeyTable(client.KeyTableOptions{
					TerminalOptions: client.TerminalOptions{TTY: target.tty, Focused: target.focused},
					AckOptions:      client.AckOptions{Wait: wait},
				})
			},
		},
	)
	cmd.PersistentFlags().BoolVar(&wait, "wait", false, "wait for acknowledgement")
	return cmd
}
