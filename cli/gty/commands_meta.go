package main

import (
	"fmt"

	"github.com/spf13/cobra"

	"github.com/thurstonsand/ghosttykit/sdk/go/client"
	"github.com/thurstonsand/ghosttykit/sdk/go/protocol"
)

func pingCmd() *cobra.Command {
	return &cobra.Command{
		Use:  "ping",
		Args: cobra.NoArgs,
		RunE: func(_ *cobra.Command, _ []string) error {
			resp, err := client.New().Dispatch(protocol.PingRequest{Envelope: protocol.NewEnvelope("ping")})
			if err != nil {
				return err
			}
			printResponseValue(resp)
			return nil
		},
	}
}

func terminalIDCmd(opts *options) *cobra.Command {
	var refresh bool
	cmd := &cobra.Command{
		Use:  "terminal-id",
		Args: cobra.NoArgs,
		RunE: func(_ *cobra.Command, _ []string) error {
			resp, err := client.New().Dispatch(protocol.TerminalIDRequest{Envelope: protocol.NewEnvelope("terminal-id"), TTY: optionalTTY(opts), Refresh: refresh})
			if err != nil {
				return err
			}
			printResponseValue(resp)
			return nil
		},
	}
	cmd.Flags().BoolVar(&refresh, "refresh", false, "refresh cached terminal mapping before resolving")
	return cmd
}

func clearCacheCmd(opts *options) *cobra.Command {
	var all bool
	var wait bool
	cmd := &cobra.Command{
		Use:  "clear-cache",
		Args: cobra.NoArgs,
		RunE: func(_ *cobra.Command, _ []string) error {
			request := protocol.ClearCacheRequest{Envelope: protocol.NewEnvelope("clear-cache"), Ack: wait}
			if !all {
				value, err := requestTTY(opts)
				if err != nil {
					return err
				}
				request.TTY = value
			}
			_, err := client.New().Dispatch(request)
			return err
		},
	}
	cmd.Flags().BoolVar(&all, "all", false, "clear all cached terminal mappings")
	cmd.Flags().BoolVar(&wait, "wait", false, "wait for acknowledgement")
	return cmd
}

func printResponseValue(resp *protocol.Response) {
	if resp != nil && resp.Value != "" {
		fmt.Println(resp.Value)
	}
}
