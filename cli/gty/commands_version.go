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
		Run: func(_ *cobra.Command, _ []string) {
			fmt.Printf("gty %s protocol=%d\n", ghosttykit.Version, ghosttykit.ProtocolVersion)
		},
	}
}
