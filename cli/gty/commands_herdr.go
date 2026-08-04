package main

import (
	"fmt"
	"os"
	"syscall"

	"github.com/spf13/cobra"

	"github.com/thurstonsand/ghosttykit/cli/gty/internal/herdr"
	"github.com/thurstonsand/ghosttykit/cli/gty/internal/osc"
	"github.com/thurstonsand/ghosttykit/cli/gty/internal/remote"
	"github.com/thurstonsand/ghosttykit/sdk/go/client"
)

func herdrCmd(opts *options) *cobra.Command {
	cmd := &cobra.Command{
		Use:   "herdr",
		Short: "Attach to Herdr and navigate its panes",
	}
	cmd.AddCommand(herdrAttachCmd(opts), herdrNavigateCmd())
	return cmd
}

// attachOptions are the policy choices gty herdr attach makes on top of the SSH transport.
type attachOptions struct {
	KeyTable     string
	HerdrBin     string
	UnmanagedSSH bool
	NoBootstrap  bool
}

func herdrAttachCmd(opts *options) *cobra.Command {
	attach := &attachOptions{}
	cmd := &cobra.Command{
		Use:   "attach [flags] host [-- herdr arguments]",
		Short: "Run Herdr over SSH with key navigation into Ghostty",
		Args:  cobra.MinimumNArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			return runHerdrAttach(opts, *attach, args, cmd.ArgsLenAtDash())
		},
	}
	cmd.Flags().StringVar(&attach.KeyTable, "key-table", "bypass", "Ghostty key table that passes navigation keys inward")
	cmd.Flags().StringVar(&attach.HerdrBin, "herdr-bin", "herdr", "herdr executable on the remote host")
	cmd.Flags().BoolVar(&attach.UnmanagedSSH, "debug-unmanaged-ssh", false, "skip GhosttyKit managed OpenSSH options")
	cmd.Flags().BoolVar(&attach.NoBootstrap, "debug-no-bootstrap", false, "skip remote gty bootstrap")
	return cmd
}

// runHerdrAttach owns one Herdr session: it prepares the bridge and the remote binaries, takes the
// Ghostty key table only once nothing else can fail, and gives it back on every exit it can see.
// Unlike gty ssh, it never degrades to plain SSH: bare navigation keys that reach a remote shell
// as control bytes are worse than a refused attach.
func runHerdrAttach(opts *options, attach attachOptions, args []string, dashIndex int) error {
	host, herdrArgs, err := remote.SplitSSHArgs(args, dashIndex)
	if err != nil {
		return usageError{err: err}
	}
	sshOpts := remote.SSHOptions{
		RequireBridge: true,
		UnmanagedSSH:  attach.UnmanagedSSH,
		NoBootstrap:   attach.NoBootstrap,
	}

	gty := client.New()
	tty, err := client.ResolveTTY(opts.tty)
	if err != nil {
		return err
	}
	terminal := client.TerminalOptions{TTY: tty}
	if _, err = gty.TerminalID(client.TerminalIDOptions{TerminalOptions: terminal}); err != nil {
		return fmt.Errorf("herdr attach needs this terminal to resolve through GhosttyKit: %w", err)
	}

	filter := navigationFilter(gty, terminal)
	runner := remote.Runner{
		CreateBridge: func() (remote.Bridge, error) { return createBridgeLease(opts) },
		Session: remote.SessionOptions{
			ForcePTY:          true,
			RequireManagedGTY: true,
			Stdout:            filter,
			ForwardSignals:    []os.Signal{syscall.SIGINT, syscall.SIGTERM, syscall.SIGHUP},
		},
	}
	prepared, err := runner.Prepare(sshOpts, host)
	if err != nil {
		return fmt.Errorf("herdr attach needs the GhosttyKit bridge: %w", err)
	}
	defer func() { _ = prepared.Close() }()
	if err := remote.RequireRemoteCommand(sshOpts, host, attach.HerdrBin); err != nil {
		return err
	}

	if err := gty.ActivateKeyTable(client.KeyTableOptions{
		TerminalOptions: terminal,
		AckOptions:      client.AckOptions{Wait: true},
		Table:           attach.KeyTable,
	}); err != nil {
		return err
	}
	// Deactivation waits: a key table left active outlives this process and leaves the surface
	// swallowing navigation keys until the user resets it by hand.
	defer func() {
		_ = gty.DeactivateKeyTable(client.KeyTableOptions{
			TerminalOptions: terminal,
			AckOptions:      client.AckOptions{Wait: true},
		})
	}()

	remoteCommand := append([]string{attach.HerdrBin}, herdrArgs...)
	sshErr := runner.RunPreparedSSH(sshOpts, host, remoteCommand, prepared)
	if closeErr := filter.Close(); sshErr == nil {
		sshErr = closeErr
	}
	return sshErr
}

// navigationFilter turns outward navigation sentinels in the SSH display stream into focus
// requests for the terminal this attach started in. A focus failure cannot be reported into that
// stream without corrupting the remote application's display, so it stays silent.
func navigationFilter(gty client.Client, terminal client.TerminalOptions) *osc.NavigationFilter {
	return osc.NewNavigationFilter(os.Stdout, func(direction string) {
		_ = gty.Focus(client.FocusOptions{TerminalOptions: terminal, Direction: direction})
	})
}

func herdrNavigateCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "navigate <left|down|up|right>",
		Short: "Navigate from a Herdr pane inward to Neovim or outward to Ghostty",
		Args:  cobra.ExactArgs(1),
		RunE: func(_ *cobra.Command, args []string) error {
			direction, err := herdr.ParseDirection(args[0])
			if err != nil {
				return usageError{err: err}
			}
			pane, err := herdr.ContextFromEnv()
			if err != nil {
				return err
			}
			return herdr.Navigator{
				API:    herdr.Client{SocketPath: pane.SocketPath},
				PaneID: pane.PaneID,
			}.Navigate(direction)
		},
	}
}
