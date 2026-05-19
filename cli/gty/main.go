// Command gty controls GhosttyKit local and bridged terminal sessions.
package main

import (
	"errors"
	"fmt"
	"os"

	"github.com/spf13/cobra"
)

func main() {
	if err := newRootCmd().Execute(); err != nil {
		fmt.Fprintln(os.Stderr, "gty:", err)
		os.Exit(exitCode(err))
	}
}

func newRootCmd() *cobra.Command {
	opts := &options{}
	root := &cobra.Command{
		Use:           "gty",
		SilenceUsage:  true,
		SilenceErrors: true,
	}
	root.PersistentFlags().StringVar(&opts.tty, "tty", "", "terminal TTY path override")

	root.AddCommand(
		versionCmd(),
		pingCmd(),
		terminalIDCmd(opts),
		tabTerminalCountCmd(opts),
		keyTableCmd(opts),
		focusCmd(opts),
		splitCmd(opts),
		resizeCmd(opts),
		zoomCmd(opts),
		pasteCmd(opts),
		clearCacheCmd(opts),
		titleCmd(),
		sshCmd(opts),
	)
	configureUsageErrors(root)
	return root
}

const (
	exitRuntime = 1
	exitUsage   = 2
)

type cliError interface {
	error
	ExitCode() int
}

func exitCode(err error) int {
	if cliErr, ok := errors.AsType[cliError](err); ok {
		return cliErr.ExitCode()
	}
	return exitRuntime
}
