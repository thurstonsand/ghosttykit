package main

import (
	"errors"
	"strconv"

	"github.com/spf13/cobra"

	"github.com/thurstonsand/ghosttykit/sdk/go/client"
	"github.com/thurstonsand/ghosttykit/sdk/go/protocol"
)

func tabTerminalCountCmd(opts *options) *cobra.Command {
	return &cobra.Command{
		Use:  "tab-terminal-count",
		Args: cobra.NoArgs,
		RunE: func(_ *cobra.Command, _ []string) error {
			target := optionalTerminalTarget(opts)
			count, err := client.New().TabTerminalCount(client.TerminalOptions{TTY: target.tty, Focused: target.focused})
			if err != nil {
				return err
			}
			printValue(strconv.Itoa(count))
			return nil
		},
	}
}

func focusCmd(opts *options) *cobra.Command {
	var wait bool
	cmd := &cobra.Command{
		Use:  "focus <left|down|up|right>",
		Args: cobra.ExactArgs(1),
		RunE: func(_ *cobra.Command, args []string) error {
			target, err := requestTerminalTarget(opts)
			if err != nil {
				return err
			}
			return client.New().Focus(client.FocusOptions{
				TerminalOptions: client.TerminalOptions{TTY: target.tty, Focused: target.focused},
				AckOptions:      client.AckOptions{Wait: wait},
				Direction:       args[0],
			})
		},
	}
	cmd.Flags().BoolVar(&wait, "wait", false, "wait for acknowledgement")
	return cmd
}

func splitCmd(opts *options) *cobra.Command {
	var cwd string
	var commandText string
	var focus string
	var wait bool
	cmd := &cobra.Command{
		Use:  "split <left|down|up|right>",
		Args: cobra.ExactArgs(1),
		RunE: func(_ *cobra.Command, args []string) error {
			target, err := requestTerminalTarget(opts)
			if err != nil {
				return err
			}
			return client.New().Split(client.SplitOptions{
				TerminalOptions: client.TerminalOptions{TTY: target.tty, Focused: target.focused},
				AckOptions:      client.AckOptions{Wait: wait},
				Direction:       args[0],
				CWD:             cwd,
				CommandText:     commandText,
				Focus:           focus,
			})
		},
	}
	cmd.Flags().StringVar(&cwd, "cwd", "", "initial working directory")
	cmd.Flags().StringVar(&commandText, "command", "", "command to run")
	cmd.Flags().StringVar(&focus, "focus", "new", "focus target: new or original")
	cmd.Flags().BoolVar(&wait, "wait", false, "wait for acknowledgement")
	return cmd
}

func resizeCmd(opts *options) *cobra.Command {
	var pixels int
	var percent float64
	var wait bool
	cmd := &cobra.Command{
		Use:  "resize <left|down|up|right>",
		Args: cobra.ExactArgs(1),
		RunE: func(_ *cobra.Command, args []string) error {
			target, err := requestTerminalTarget(opts)
			if err != nil {
				return err
			}
			amount, err := resizeAmount(pixels, percent)
			if err != nil {
				return err
			}
			return client.New().Resize(client.ResizeOptions{
				TerminalOptions: client.TerminalOptions{TTY: target.tty, Focused: target.focused},
				AckOptions:      client.AckOptions{Wait: wait},
				Direction:       args[0],
				Amount:          amount,
			})
		},
	}
	cmd.Flags().IntVar(&pixels, "pixels", 0, "resize amount in pixels")
	cmd.Flags().Float64Var(&percent, "percent", 0, "resize amount as percentage")
	cmd.Flags().BoolVar(&wait, "wait", false, "wait for acknowledgement")
	return cmd
}

func resizeAmount(pixels int, percent float64) (protocol.ResizeAmount, error) {
	switch {
	case pixels > 0 && percent == 0:
		return protocol.ResizeAmount{Pixels: &pixels}, nil
	case percent > 0 && pixels == 0:
		return protocol.ResizeAmount{Percent: &percent}, nil
	default:
		return protocol.ResizeAmount{}, usageError{err: errors.New("specify exactly one of --pixels or --percent")}
	}
}

func zoomCmd(opts *options) *cobra.Command {
	var wait bool
	cmd := &cobra.Command{
		Use:  "zoom",
		Args: cobra.NoArgs,
		RunE: func(_ *cobra.Command, _ []string) error {
			target, err := requestTerminalTarget(opts)
			if err != nil {
				return err
			}
			return client.New().Zoom(client.ZoomOptions{
				TerminalOptions: client.TerminalOptions{TTY: target.tty, Focused: target.focused},
				AckOptions:      client.AckOptions{Wait: wait},
			})
		},
	}
	cmd.Flags().BoolVar(&wait, "wait", false, "wait for acknowledgement")
	return cmd
}
