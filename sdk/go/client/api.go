package client

import (
	"fmt"
	"io"
	"os"
	"strconv"

	"github.com/thurstonsand/ghosttykit/sdk/go/protocol"
	"github.com/thurstonsand/ghosttykit/sdk/go/tty"
)

// TerminalOptions selects the terminal affected by terminal-scoped operations. An empty TTY
// targets the caller's own terminal.
type TerminalOptions struct {
	TTY string
}

// ResolveTarget makes value, or else GTY_TTY, an explicit target. Without either it names the
// process's own controlling terminal as the caller's, and a process with no terminal names
// none: whether its endpoint needs one is the daemon's decision.
func ResolveTarget(value string) protocol.Target {
	if value == "" {
		value = os.Getenv("GTY_TTY")
	}
	if value != "" {
		return protocol.Target{TTY: tty.Normalize(value)}
	}
	if current, err := tty.Current(); err == nil {
		return protocol.Target{CallerTTY: current}
	}
	return protocol.Target{}
}

// TerminalIDOptions selects the terminal-id lookup behavior.
type TerminalIDOptions struct {
	TerminalOptions
	Refresh bool
}

// AckOptions controls whether fire-and-forget commands wait for acknowledgement.
type AckOptions struct {
	Wait bool
}

// FocusOptions controls a focus operation.
type FocusOptions struct {
	TerminalOptions
	AckOptions
	Direction string
}

// SplitOptions controls a split operation.
type SplitOptions struct {
	TerminalOptions
	AckOptions
	Direction   string
	CWD         string
	CommandText string
	Focus       string
}

// InputOptions controls typed input delivery.
type InputOptions struct {
	TerminalOptions
	AckOptions
	Text   string
	Submit bool
}

// ResizeOptions controls a resize operation.
type ResizeOptions struct {
	TerminalOptions
	AckOptions
	Direction string
	Amount    protocol.ResizeAmount
}

// ZoomOptions controls a zoom operation.
type ZoomOptions struct {
	TerminalOptions
	AckOptions
}

// ClearCacheOptions controls cache clearing: the terminal's own mapping, or every mapping when
// All is set.
type ClearCacheOptions struct {
	TerminalOptions
	AckOptions
	All bool
}

// KeyTableOptions selects a Ghostty key table operation.
type KeyTableOptions struct {
	TerminalOptions
	AckOptions
	Table string
}

// BridgeOptions selects the terminal that owns a bridge session.
type BridgeOptions struct {
	TerminalOptions
}

// Bridge is a daemon-owned bridge session lease.
type Bridge struct {
	SocketPath string
	lease      io.Closer
}

// Doctor asks the daemon to run health checks.
func (c Client) Doctor() (protocol.DoctorReply, error) {
	return Call[protocol.DoctorReply](c, protocol.NewDoctorRequest())
}

// TerminalID resolves a Ghostty terminal id.
func (c Client) TerminalID(opts TerminalIDOptions) (string, error) {
	target := ResolveTarget(opts.TTY)
	reply, err := Call[protocol.FrameReply](c, protocol.NewTerminalIDRequest(target, opts.Refresh))
	if err != nil {
		return "", err
	}
	return reply.Value, nil
}

// TabTerminalCount returns the number of terminals in the caller's Ghostty tab.
func (c Client) TabTerminalCount(opts TerminalOptions) (int, error) {
	target := ResolveTarget(opts.TTY)
	reply, err := Call[protocol.FrameReply](c, protocol.NewTabTerminalCountRequest(target))
	if err != nil {
		return 0, err
	}
	count, err := strconv.Atoi(reply.Value)
	if err != nil {
		return 0, fmt.Errorf("parse tab terminal count %q: %w", reply.Value, err)
	}
	return count, nil
}

// Focus moves Ghostty focus in a direction.
func (c Client) Focus(opts FocusOptions) error {
	target := ResolveTarget(opts.TTY)
	request := protocol.NewFocusRequest(target, opts.Direction, opts.Wait)
	return NotifyAck(c, request, opts.Wait)
}

// Split creates a Ghostty split. Returns the new terminal's TTY
// when Waited.
func (c Client) Split(opts SplitOptions) (string, error) {
	target := ResolveTarget(opts.TTY)
	request := protocol.NewSplitRequest(target, opts.Direction, opts.CWD, opts.CommandText, opts.Focus, opts.Wait)
	if !opts.Wait {
		return "", Notify(c, request)
	}
	reply, err := Call[protocol.FrameReply](c, request)
	if err != nil {
		return "", err
	}
	return reply.Value, nil
}

// Input sends text to a terminal as pasted input; Submit follows it with an enter keypress.
func (c Client) Input(opts InputOptions) error {
	target := ResolveTarget(opts.TTY)
	request := protocol.NewInputRequest(target, opts.Text, opts.Submit, opts.Wait)
	return NotifyAck(c, request, opts.Wait)
}

// Resize resizes a Ghostty split.
func (c Client) Resize(opts ResizeOptions) error {
	target := ResolveTarget(opts.TTY)
	request := protocol.NewResizeRequest(target, opts.Direction, opts.Amount, opts.Wait)
	return NotifyAck(c, request, opts.Wait)
}

// Zoom toggles split zoom.
func (c Client) Zoom(opts ZoomOptions) error {
	target := ResolveTarget(opts.TTY)
	request := protocol.NewZoomRequest(target, opts.Wait)
	return NotifyAck(c, request, opts.Wait)
}

// ActivateKeyTable activates a Ghostty key table.
func (c Client) ActivateKeyTable(opts KeyTableOptions) error {
	target := ResolveTarget(opts.TTY)
	request := protocol.NewKeyTableActivateRequest(target, opts.Table, opts.Wait)
	return NotifyAck(c, request, opts.Wait)
}

// DeactivateKeyTable deactivates the current Ghostty key table.
func (c Client) DeactivateKeyTable(opts KeyTableOptions) error {
	target := ResolveTarget(opts.TTY)
	request := protocol.NewKeyTableDeactivateRequest(target, opts.Wait)
	return NotifyAck(c, request, opts.Wait)
}

// ClearCache removes cached terminal mappings.
func (c Client) ClearCache(opts ClearCacheOptions) error {
	var target protocol.Target
	if !opts.All {
		target = ResolveTarget(opts.TTY)
	}
	request := protocol.NewClearCacheRequest(target, opts.All, opts.Wait)
	return NotifyAck(c, request, opts.Wait)
}

// Bridge creates a daemon-owned bridge and holds its lease until Close.
func (c Client) Bridge(opts BridgeOptions) (*Bridge, error) {
	target := ResolveTarget(opts.TTY)
	reply, err := Call[protocol.BridgeCreateReply](c, protocol.NewBridgeCreateRequest(target))
	if err != nil {
		return nil, err
	}
	_, lease, err := Hold[protocol.FrameReply](ForSocket(reply.SocketPath), protocol.NewBridgeLeaseRequest(reply.LeaseToken))
	if err != nil {
		return nil, err
	}
	return &Bridge{SocketPath: reply.SocketPath, lease: lease}, nil
}

// Close releases the bridge lease.
func (b *Bridge) Close() error {
	if b == nil || b.lease == nil {
		return nil
	}
	return b.lease.Close()
}
