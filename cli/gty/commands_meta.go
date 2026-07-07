package main

import (
	"encoding/json"
	"errors"
	"fmt"

	"github.com/spf13/cobra"

	"github.com/thurstonsand/ghosttykit/sdk/go/client"
)

func doctorCmd() *cobra.Command {
	var jsonOutput bool
	cmd := &cobra.Command{
		Use:  "doctor",
		Args: cobra.NoArgs,
		RunE: func(cmd *cobra.Command, _ []string) error {
			reply, err := client.New().Doctor()
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
			// Not cmd.Printf: cobra's Print helpers write to stderr.
			for _, check := range reply.Checks {
				if check.Message == "" {
					_, _ = fmt.Fprintf(cmd.OutOrStdout(), "%s: %s\n", check.Name, check.Status)
					continue
				}
				_, _ = fmt.Fprintf(cmd.OutOrStdout(), "%s: %s - %s\n", check.Name, check.Status, check.Message)
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
			terminalID, err := client.New().TerminalID(client.TerminalIDOptions{
				TerminalOptions: client.TerminalOptions{TTY: target.tty, Focused: target.focused},
				Refresh:         refresh,
			})
			if err != nil {
				return err
			}
			_, _ = fmt.Fprintln(cmd.OutOrStdout(), terminalID)
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
			return client.New().ClearCache(client.ClearCacheOptions{TTY: tty, AckOptions: client.AckOptions{Wait: wait}})
		},
	}
	cmd.Flags().BoolVar(&all, "all", false, "clear all cached terminal mappings")
	cmd.Flags().BoolVar(&wait, "wait", false, "wait for acknowledgement")
	return cmd
}

func spawnClaimCmd(opts *options) *cobra.Command {
	return &cobra.Command{
		Use:    "spawn-claim <token>",
		Hidden: true,
		Args:   cobra.ExactArgs(1),
		RunE: func(_ *cobra.Command, args []string) error {
			tty, err := requestTTY(opts)
			if err != nil {
				return err
			}
			return client.New().SpawnClaim(client.SpawnClaimOptions{TTY: tty, Token: args[0]})
		},
	}
}
