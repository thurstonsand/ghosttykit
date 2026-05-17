package main

import (
	"github.com/spf13/cobra"

	"github.com/thurstonsand/ghosttykit/sdk/go/client"
	"github.com/thurstonsand/ghosttykit/sdk/go/protocol"
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
				_, err = client.New().Do(protocol.KeyTableActivateRequest{FrameEnvelope: protocol.NewFrameEnvelope("key-table-activate"), TTY: target.tty, Focused: target.focused, Table: args[0], Ack: wait})
				return err
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
				_, err = client.New().Do(protocol.KeyTableDeactivateRequest{FrameEnvelope: protocol.NewFrameEnvelope("key-table-deactivate"), TTY: target.tty, Focused: target.focused, Ack: wait})
				return err
			},
		},
	)
	cmd.PersistentFlags().BoolVar(&wait, "wait", false, "wait for acknowledgement")
	return cmd
}
