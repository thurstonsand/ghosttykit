package client

import (
	"fmt"
	"io"
	"os"
	"strconv"

	"github.com/thurstonsand/ghosttykit/sdk/go/protocol"
	"github.com/thurstonsand/ghosttykit/sdk/go/tty"
)

// TerminalOptions selects the terminal affected by terminal-scoped operations. TTY is derived
// (GTY_TTY, then the process's controlling terminal) when empty.
type TerminalOptions struct {
	TTY string
}

// ResolveTTY normalizes an explicit tty value, or derives the caller's: GTY_TTY first, then the
// process's own controlling terminal.
func ResolveTTY(value string) (string, error) {
	if value != "" {
		return tty.Normalize(value), nil
	}
	if env := os.Getenv("GTY_TTY"); env != "" {
		return tty.Normalize(env), nil
	}
	return tty.Current()
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
	ttyPath, err := ResolveTTY(opts.TTY)
	if err != nil {
		return "", err
	}
	reply, err := Call[protocol.FrameReply](c, protocol.NewTerminalIDRequest(ttyPath, opts.Refresh))
	if err != nil {
		return "", err
	}
	return reply.Value, nil
}

// TabTerminalCount returns the number of terminals in the caller's Ghostty tab.
func (c Client) TabTerminalCount(opts TerminalOptions) (int, error) {
	ttyPath, err := ResolveTTY(opts.TTY)
	if err != nil {
		return 0, err
	}
	reply, err := Call[protocol.FrameReply](c, protocol.NewTabTerminalCountRequest(ttyPath))
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
	ttyPath, err := ResolveTTY(opts.TTY)
	if err != nil {
		return err
	}
	request := protocol.NewFocusRequest(ttyPath, opts.Direction, opts.Wait)
	return NotifyAck(c, request, opts.Wait)
}

// Split creates a Ghostty split. Returns the new terminal's TTY
// when Waited.
func (c Client) Split(opts SplitOptions) (string, error) {
	ttyPath, err := ResolveTTY(opts.TTY)
	if err != nil {
		return "", err
	}
	request := protocol.NewSplitRequest(ttyPath, opts.Direction, opts.CWD, opts.CommandText, opts.Focus, opts.Wait)
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
	ttyPath, err := ResolveTTY(opts.TTY)
	if err != nil {
		return err
	}
	request := protocol.NewInputRequest(ttyPath, opts.Text, opts.Submit, opts.Wait)
	return NotifyAck(c, request, opts.Wait)
}

// Resize resizes a Ghostty split.
func (c Client) Resize(opts ResizeOptions) error {
	ttyPath, err := ResolveTTY(opts.TTY)
	if err != nil {
		return err
	}
	request := protocol.NewResizeRequest(ttyPath, opts.Direction, opts.Amount, opts.Wait)
	return NotifyAck(c, request, opts.Wait)
}

// Zoom toggles split zoom.
func (c Client) Zoom(opts ZoomOptions) error {
	ttyPath, err := ResolveTTY(opts.TTY)
	if err != nil {
		return err
	}
	request := protocol.NewZoomRequest(ttyPath, opts.Wait)
	return NotifyAck(c, request, opts.Wait)
}

// ActivateKeyTable activates a Ghostty key table.
func (c Client) ActivateKeyTable(opts KeyTableOptions) error {
	ttyPath, err := ResolveTTY(opts.TTY)
	if err != nil {
		return err
	}
	request := protocol.NewKeyTableActivateRequest(ttyPath, opts.Table, opts.Wait)
	return NotifyAck(c, request, opts.Wait)
}

// DeactivateKeyTable deactivates the current Ghostty key table.
func (c Client) DeactivateKeyTable(opts KeyTableOptions) error {
	ttyPath, err := ResolveTTY(opts.TTY)
	if err != nil {
		return err
	}
	request := protocol.NewKeyTableDeactivateRequest(ttyPath, opts.Wait)
	return NotifyAck(c, request, opts.Wait)
}

// SpawnClaim binds the caller TTY to the terminal the daemon spawned with Token.
func (c Client) SpawnClaim(opts SpawnClaimOptions) error {
	ttyPath, err := ResolveTTY(opts.TTY)
	if err != nil {
		return err
	}
	_, err = Call[protocol.FrameReply](c, protocol.NewSpawnClaimRequest(ttyPath, opts.Token))
	return err
}

// ClearCache removes cached terminal mappings.
func (c Client) ClearCache(opts ClearCacheOptions) error {
	request := protocol.NewClearCacheRequest(opts.TTY, opts.Wait)
	return NotifyAck(c, request, opts.Wait)
}

// Bridge creates a daemon-owned bridge and holds its lease until Close.
func (c Client) Bridge(opts BridgeOptions) (*Bridge, error) {
	ttyPath, err := ResolveTTY(opts.TTY)
	if err != nil {
		return nil, err
	}
	reply, err := Call[protocol.BridgeCreateReply](c, protocol.NewBridgeCreateRequest(ttyPath))
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
