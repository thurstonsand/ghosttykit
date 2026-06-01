package main

import (
	"fmt"
	"os"
	"os/signal"

	"github.com/spf13/cobra"

	"github.com/thurstonsand/ghosttykit/cli/gty/internal/remote"
	"github.com/thurstonsand/ghosttykit/sdk/go/client"
	"github.com/thurstonsand/ghosttykit/sdk/go/protocol"
)

func sshCmd(opts *options) *cobra.Command {
	sshOpts := &remote.SSHOptions{}
	cmd := &cobra.Command{
		Use:   "ssh [flags] host [-- remote command]",
		Short: "Start SSH with a GhosttyKit bridge",
		Args:  cobra.MinimumNArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			return runSSHWrapper(opts, *sshOpts, args, cmd.ArgsLenAtDash())
		},
	}
	cmd.Flags().BoolVar(&sshOpts.RequireBridge, "require-bridge", false, "fail instead of continuing as plain SSH when the bridge is unavailable")
	cmd.Flags().BoolVar(&sshOpts.UnmanagedSSH, "debug-unmanaged-ssh", false, "skip GhosttyKit managed OpenSSH options")
	cmd.Flags().BoolVar(&sshOpts.NoBootstrap, "debug-no-bootstrap", false, "skip remote gty bootstrap")
	cmd.AddCommand(sshRemoteInitCmd(), sshRemoteRunCmd(), sshBridgeCreateCmd(opts), sshBridgeLeaseCmd())
	return cmd
}

func runSSHWrapper(opts *options, sshOpts remote.SSHOptions, args []string, dashIndex int) error {
	runner := remote.Runner{
		CreateBridge: func() (remote.Bridge, error) {
			return createBridgeLease(opts)
		},
	}
	if err := runner.RunSSH(sshOpts, args, dashIndex); err != nil {
		if _, _, splitErr := remote.SplitSSHArgs(args, dashIndex); splitErr != nil {
			return usageError{err: err}
		}
		return err
	}
	return nil
}

func createBridgeLease(opts *options) (remote.Bridge, error) {
	target, err := requestTerminalTarget(opts)
	if err != nil {
		return remote.Bridge{}, err
	}
	request := protocol.NewBridgeCreateRequest(target.tty, target.focused)
	reply, err := client.Call[protocol.BridgeCreateReply](client.New(), request)
	if err != nil {
		return remote.Bridge{}, err
	}
	leaseRequest := protocol.NewBridgeLeaseRequest(reply.LeaseToken)
	_, lease, err := client.Hold[protocol.FrameReply](client.ForSocket(reply.SocketPath), leaseRequest)
	if err != nil {
		return remote.Bridge{}, err
	}
	return remote.Bridge{SocketPath: reply.SocketPath, Lease: lease}, nil
}

func sshRemoteInitCmd() *cobra.Command {
	return &cobra.Command{
		Use:    "remote-init",
		Short:  "Prepare a remote GhosttyKit SSH runtime directory",
		Hidden: true,
		Args:   cobra.NoArgs,
		RunE: func(_ *cobra.Command, _ []string) error {
			return remote.Init(os.Stdout)
		},
	}
}

func sshRemoteRunCmd() *cobra.Command {
	return &cobra.Command{
		Use:                "remote-run [-- command...]",
		Short:              "Run a remote command with GTY_SOCK and clean up the remote socket",
		Hidden:             true,
		DisableFlagParsing: true,
		RunE: func(_ *cobra.Command, args []string) error {
			if len(args) > 0 && args[0] == "--" {
				args = args[1:]
			}
			return remote.Run(args, remote.RunOptions{
				Stdin:  os.Stdin,
				Stdout: os.Stdout,
				Stderr: os.Stderr,
				Env:    os.Environ(),
			})
		},
	}
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
			request := protocol.NewBridgeCreateRequest(target.tty, target.focused)
			reply, err := client.Call[protocol.BridgeCreateReply](client.New(), request)
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
			request := protocol.NewBridgeLeaseRequest(args[1])
			_, conn, err := client.Hold[protocol.FrameReply](client.ForSocket(args[0]), request)
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
