package main

import (
	"fmt"

	"github.com/spf13/cobra"

	ghosttykit "github.com/thurstonsand/ghosttykit/sdk/go"
)

func versionCmd() *cobra.Command {
	return &cobra.Command{
		Use:  "version",
		Args: cobra.NoArgs,
		Run: func(cmd *cobra.Command, _ []string) {
			_, _ = fmt.Fprintf(cmd.OutOrStdout(), "gty %s protocol=%d\n", ghosttykit.Version, ghosttykit.ProtocolVersion)
		},
	}
}
