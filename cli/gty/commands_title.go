package main

import (
	"github.com/spf13/cobra"

	"github.com/thurstonsand/ghosttykit/cli/gty/internal/osc"
)

func titleCmd() *cobra.Command {
	return &cobra.Command{
		Use:  "title <text>",
		Args: cobra.ExactArgs(1),
		RunE: func(_ *cobra.Command, args []string) error {
			return osc.Title(args[0])
		},
	}
}
