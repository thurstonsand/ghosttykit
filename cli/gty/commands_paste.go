package main

import (
	"errors"
	"io"
	"strings"

	"github.com/spf13/cobra"

	"github.com/thurstonsand/ghosttykit/cli/gty/internal/paste"
	"github.com/thurstonsand/ghosttykit/sdk/go/client"
	"github.com/thurstonsand/ghosttykit/sdk/go/protocol"
)

func pasteCmd(opts *options) *cobra.Command {
	var outputDir string
	var jsonOutput bool
	cmd := &cobra.Command{
		Use:  "paste",
		Args: cobra.NoArgs,
		RunE: func(cmd *cobra.Command, _ []string) error {
			return runPaste(cmd.OutOrStdout(), opts, outputDir, jsonOutput)
		},
	}
	cmd.Flags().StringVar(&outputDir, "output-dir", "/tmp/pi-paste-file", "directory for materialized clipboard files")
	cmd.Flags().BoolVar(&jsonOutput, "json", false, "print structured paste metadata")
	return cmd
}

func runPaste(out io.Writer, opts *options, outputDir string, jsonOutput bool) error {
	if strings.TrimSpace(outputDir) == "" {
		return usageError{err: errors.New("--output-dir is required")}
	}
	request := protocol.NewPasteRequest(optionalTTY(opts))
	gtyClient := client.New()
	if !jsonOutput {
		return paste.Write(out, gtyClient, request, outputDir)
	}

	result, err := paste.Receive(gtyClient, request, outputDir)
	if err != nil {
		return err
	}
	return paste.PrintJSON(out, result)
}
