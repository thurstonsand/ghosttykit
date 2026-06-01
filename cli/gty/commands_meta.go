package main

import (
	"encoding/json"
	"errors"
	"fmt"

	"github.com/spf13/cobra"

	"github.com/thurstonsand/ghosttykit/sdk/go/client"
	"github.com/thurstonsand/ghosttykit/sdk/go/protocol"
)

func doctorCmd() *cobra.Command {
	var jsonOutput bool
	cmd := &cobra.Command{
		Use:  "doctor",
		Args: cobra.NoArgs,
		RunE: func(cmd *cobra.Command, _ []string) error {
			reply, err := client.Call[protocol.DoctorReply](client.New(), protocol.NewDoctorRequest())
			if err != nil {
				return err
			}
			if jsonOutput {
				encoder := json.NewEncoder(cmd.OutOrStdout())
				encoder.SetIndent("", "  ")
				if err := encoder.Encode(reply); err != nil {
					return err
				}
				if !reply.Healthy {
					return doctorError{}
				}
				return nil
			}
			for _, check := range reply.Checks {
				if check.Message == "" {
					cmd.Printf("%s: %s\n", check.Name, check.Status)
					continue
				}
				cmd.Printf("%s: %s - %s\n", check.Name, check.Status, check.Message)
			}
			if !reply.Healthy {
				return doctorError{}
			}
			return nil
		},
	}
	cmd.Flags().BoolVar(&jsonOutput, "json", false, "print structured doctor output")
	return cmd
}

type doctorError struct{}

func (doctorError) Error() string { return "doctor found failed checks" }

func (doctorError) ExitCode() int { return exitRuntime }

func terminalIDCmd(opts *options) *cobra.Command {
	var refresh bool
	cmd := &cobra.Command{
		Use:  "terminal-id",
		Args: cobra.NoArgs,
		RunE: func(cmd *cobra.Command, _ []string) error {
			if refresh && cmd.Root().PersistentFlags().Changed("tty") {
				return usageError{err: errors.New("--refresh cannot be combined with explicit --tty")}
			}
			var target terminalTarget
			if refresh {
				var err error
				target, err = requestTerminalTarget(opts)
				if err != nil {
					return err
				}
			} else {
				target = optionalTerminalTarget(opts)
			}
			request := protocol.NewTerminalIDRequest(target.tty, target.focused, refresh)
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
			tty := ""
			if !all {
				value, err := requestTTY(opts)
				if err != nil {
					return err
				}
				tty = value
			}
			request := protocol.NewClearCacheRequest(tty, wait)
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
