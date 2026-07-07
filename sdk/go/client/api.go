package client

import (
	"fmt"
	"io"
	"strconv"

	"github.com/thurstonsand/ghosttykit/sdk/go/protocol"
)

// TerminalOptions selects the terminal affected by terminal-scoped operations.
type TerminalOptions struct {
	TTY     string
	Focused bool
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

// SpawnClaimOptions identifies a pending daemon spawn to claim.
type SpawnClaimOptions struct {
	TTY   string
	Token string
}

// ClearCacheOptions controls cache clearing.
type ClearCacheOptions struct {
	AckOptions
	TTY string
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
	reply, err := Call[protocol.FrameReply](c, protocol.NewTerminalIDRequest(opts.TTY, opts.Focused, opts.Refresh))
	if err != nil {
		return "", err
	}
	return reply.Value, nil
}

// TabTerminalCount returns the number of terminals in the selected Ghostty tab.
func (c Client) TabTerminalCount(opts TerminalOptions) (int, error) {
	reply, err := Call[protocol.FrameReply](c, protocol.NewTabTerminalCountRequest(opts.TTY, opts.Focused))
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
	request := protocol.NewFocusRequest(opts.TTY, opts.Direction, opts.Focused, opts.Wait)
	return NotifyAck(c, request, opts.Wait)
}

// Split creates a Ghostty split. Returns the new terminal's TTY
// when Waited.
func (c Client) Split(opts SplitOptions) (string, error) {
	request := protocol.NewSplitRequest(opts.TTY, opts.Direction, opts.CWD, opts.CommandText, opts.Focus, opts.Focused, opts.Wait)
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
	request := protocol.NewInputRequest(opts.TTY, opts.Text, opts.Submit, opts.Focused, opts.Wait)
	return NotifyAck(c, request, opts.Wait)
}

// Resize resizes a Ghostty split.
func (c Client) Resize(opts ResizeOptions) error {
	request := protocol.NewResizeRequest(opts.TTY, opts.Direction, opts.Amount, opts.Focused, opts.Wait)
	return NotifyAck(c, request, opts.Wait)
}

// Zoom toggles split zoom.
func (c Client) Zoom(opts ZoomOptions) error {
	request := protocol.NewZoomRequest(opts.TTY, opts.Focused, opts.Wait)
	return NotifyAck(c, request, opts.Wait)
}

// ActivateKeyTable activates a Ghostty key table.
func (c Client) ActivateKeyTable(opts KeyTableOptions) error {
	request := protocol.NewKeyTableActivateRequest(opts.TTY, opts.Table, opts.Focused, opts.Wait)
	return NotifyAck(c, request, opts.Wait)
}

// DeactivateKeyTable deactivates the current Ghostty key table.
func (c Client) DeactivateKeyTable(opts KeyTableOptions) error {
	request := protocol.NewKeyTableDeactivateRequest(opts.TTY, opts.Focused, opts.Wait)
	return NotifyAck(c, request, opts.Wait)
}

// SpawnClaim binds the caller TTY to the terminal the daemon spawned with Token.
func (c Client) SpawnClaim(opts SpawnClaimOptions) error {
	_, err := Call[protocol.FrameReply](c, protocol.NewSpawnClaimRequest(opts.TTY, opts.Token))
	return err
}

// ClearCache removes cached terminal mappings.
func (c Client) ClearCache(opts ClearCacheOptions) error {
	request := protocol.NewClearCacheRequest(opts.TTY, opts.Wait)
	return NotifyAck(c, request, opts.Wait)
}

// Bridge creates a daemon-owned bridge and holds its lease until Close.
func (c Client) Bridge(opts BridgeOptions) (*Bridge, error) {
	reply, err := Call[protocol.BridgeCreateReply](c, protocol.NewBridgeCreateRequest(opts.TTY, opts.Focused))
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
