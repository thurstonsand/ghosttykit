package main

import (
	"fmt"
	"os"
	"os/signal"

	"github.com/spf13/cobra"

	"github.com/thurstonsand/ghosttykit/sdk/go/client"
	"github.com/thurstonsand/ghosttykit/sdk/go/protocol"
)

func sshCmd(opts *options) *cobra.Command {
	cmd := &cobra.Command{
		Use:   "ssh",
		Short: "Manage GhosttyKit SSH bridge setup",
	}
	cmd.AddCommand(sshBridgeCreateCmd(opts), sshBridgeLeaseCmd())
	return cmd
}

func sshBridgeCreateCmd(opts *options) *cobra.Command {
	return &cobra.Command{
		Use:    "bridge-create",
		Short:  "Create a local daemon-owned SSH bridge session",
		Hidden: true,
		Args:   cobra.NoArgs,
		RunE: func(_ *cobra.Command, _ []string) error {
			target, err := requestTerminalTarget(opts)
			if err != nil {
				return err
			}
			reply, err := client.Call[protocol.BridgeCreateReply](client.New(), protocol.BridgeCreateRequest{
				FrameEnvelope: protocol.NewFrameEnvelope("bridge-create"),
				TTY:           target.tty,
				Focused:       target.focused,
			})
			if err != nil {
				return err
			}
			fmt.Printf("%s\t%s\n", reply.SocketPath, reply.LeaseToken)
			return nil
		},
	}
}

func sshBridgeLeaseCmd() *cobra.Command {
	return &cobra.Command{
		Use:    "bridge-lease SOCKET TOKEN",
		Short:  "Hold a local bridge lease open until interrupted",
		Hidden: true,
		Args:   cobra.ExactArgs(2),
		RunE: func(_ *cobra.Command, args []string) error {
			_, conn, err := client.Hold[protocol.FrameReply](client.ForSocket(args[0]), protocol.BridgeLeaseRequest{
				FrameEnvelope: protocol.NewFrameEnvelope("bridge-lease"),
				Token:         args[1],
			})
			if err != nil {
				return err
			}
			defer func() { _ = conn.Close() }()

			signals := make(chan os.Signal, 1)
			signal.Notify(signals, os.Interrupt)
			defer signal.Stop(signals)
			<-signals
			return nil
		},
	}
}
