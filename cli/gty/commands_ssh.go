package main

import (
	"os"

	"github.com/spf13/cobra"

	"github.com/thurstonsand/ghosttykit/cli/gty/internal/remote"
	"github.com/thurstonsand/ghosttykit/sdk/go/client"
)

func sshCmd(opts *options) *cobra.Command {
	sshOpts := &remote.SSHOptions{}
	cmd := &cobra.Command{
		Use:   "ssh [flags] host [-- remote command]",
		Short: "Start SSH with a bridge back to the caller's terminal",
		Args:  cobra.MinimumNArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			return runSSHWrapper(opts, *sshOpts, args, cmd.ArgsLenAtDash())
		},
	}
	cmd.Flags().BoolVar(&sshOpts.RequireBridge, "require-bridge", false, "fail instead of continuing as plain SSH when the bridge is unavailable")
	cmd.Flags().BoolVar(&sshOpts.UnmanagedSSH, "debug-unmanaged-ssh", false, "skip GhosttyKit managed OpenSSH options")
	cmd.Flags().BoolVar(&sshOpts.NoBootstrap, "debug-no-bootstrap", false, "skip remote gty bootstrap")
	cmd.AddCommand(sshRemoteInitCmd(), sshRemoteRunCmd())
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
	bridge, err := client.New().Bridge(client.BridgeOptions{TerminalOptions: client.TerminalOptions{TTY: opts.tty}})
	if err != nil {
		return remote.Bridge{}, err
	}
	return remote.Bridge{SocketPath: bridge.SocketPath, Lease: bridge}, nil
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
