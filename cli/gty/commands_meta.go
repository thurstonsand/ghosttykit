package main

import (
	"errors"
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
			reply, err := client.Call[protocol.FrameReply](client.New(), protocol.PingRequest{FrameEnvelope: protocol.NewFrameEnvelope("ping")})
			if err != nil {
				return err
			}
			printReplyValue(reply)
			return nil
		},
	}
}

func terminalIDCmd(opts *options) *cobra.Command {
	var refresh bool
	cmd := &cobra.Command{
		Use:  "terminal-id",
		Args: cobra.NoArgs,
		RunE: func(cmd *cobra.Command, _ []string) error {
			if refresh && cmd.Root().PersistentFlags().Changed("tty") {
				return usageError{err: errors.New("--refresh cannot be combined with explicit --tty")}
			}
			request := protocol.TerminalIDRequest{FrameEnvelope: protocol.NewFrameEnvelope("terminal-id"), Refresh: refresh, Focused: true}
			if refresh {
				target, err := requestTerminalTarget(opts)
				if err != nil {
					return err
				}
				request.TTY = target.tty
				request.Focused = target.focused
			} else {
				target := optionalTerminalTarget(opts)
				request.TTY = target.tty
				request.Focused = target.focused
			}
			reply, err := client.Call[protocol.FrameReply](client.New(), request)
			if err != nil {
				return err
			}
			printReplyValue(reply)
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
			request := protocol.ClearCacheRequest{FrameEnvelope: protocol.NewFrameEnvelope("clear-cache"), Ack: wait}
			if !all {
				value, err := requestTTY(opts)
				if err != nil {
					return err
				}
				request.TTY = value
			}
			return client.NotifyAck(client.New(), request, wait)
		},
	}
	cmd.Flags().BoolVar(&all, "all", false, "clear all cached terminal mappings")
	cmd.Flags().BoolVar(&wait, "wait", false, "wait for acknowledgement")
	return cmd
}

func printReplyValue(reply protocol.FrameReply) {
	if reply.Value != "" {
		fmt.Println(reply.Value)
	}
}
