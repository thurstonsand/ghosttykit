// Package protocol defines the GhosttyKit JSON contract.
package protocol

import (
	ghosttykit "github.com/thurstonsand/ghosttykit/sdk/go"
)

const (
	// CodeOK means the request succeeded.
	CodeOK = "ok"
	// CodeProtocolVersionMismatch means the request protocol version is unsupported.
	CodeProtocolVersionMismatch = "protocol_version_mismatch"
	// CodeUnknownCommand means the request command is not recognized.
	CodeUnknownCommand = "unknown_command"
	// CodeInvalidRequest means the request shape or field value is invalid.
	CodeInvalidRequest = "invalid_request"
	// CodeTerminalNotFound means no Ghostty terminal matches the request target.
	CodeTerminalNotFound = "terminal_not_found"
	// CodeSpawnTokenNotFound means the spawn token is unknown, already claimed, or expired.
	CodeSpawnTokenNotFound = "spawn_token_not_found"
	// CodeGhosttyUnavailable means Ghostty cannot be reached or controlled.
	CodeGhosttyUnavailable = "ghostty_unavailable"
	// CodePasteEmpty means the clipboard has no supported paste content.
	CodePasteEmpty = "paste_empty"
	// CodePasteUnsupported means clipboard content exists but has no supported representation.
	CodePasteUnsupported = "paste_unsupported"
	// CodeStreamFailed means streamed content could not be sent completely.
	CodeStreamFailed = "stream_failed"
	// CodeInternalError means the daemon hit an unexpected failure.
	CodeInternalError = "internal_error"
)

// FrameEnvelope contains fields common to every daemon request.
type FrameEnvelope struct {
	Version int    `json:"version"`
	Command string `json:"command"`
}

// Request is implemented by every concrete command request.
type Request interface {
	isRequest()
}

// ValidatableRequest is implemented by requests with client-side invariants.
type ValidatableRequest interface {
	Validate() error
}

// ReplyMode describes how a command returns data over the daemon connection.
type ReplyMode int

const (
	// ReplyModeFrame means the command returns one JSON reply frame.
	ReplyModeFrame ReplyMode = iota
	// ReplyModeNone means the command closes the connection without a reply.
	ReplyModeNone
	// ReplyModeStream means the command returns a JSON header frame followed by raw bytes.
	ReplyModeStream
	// ReplyModeHold means the command returns one JSON reply frame and holds the connection open.
	ReplyModeHold
)

type replyModeRequest interface {
	replyMode() ReplyMode
}

// FrameReply is the daemon's JSON reply frame.
type FrameReply struct {
	Version int    `json:"version"`
	Code    string `json:"code"`
	Value   string `json:"value,omitempty"`
	Error   string `json:"error,omitempty"`
}

// FrameResponse is implemented by JSON response frames with protocol status codes.
type FrameResponse interface {
	Err() error
}

// StreamFrameHeader is implemented by streamed reply headers.
type StreamFrameHeader interface {
	FrameResponse
}

// NewFrameEnvelope returns a frame envelope for the current GhosttyKit protocol.
func NewFrameEnvelope(command string) FrameEnvelope {
	return FrameEnvelope{Version: ghosttykit.ProtocolVersion, Command: command}
}

// ReplyModeOf reports how request returns data over the daemon connection.
func ReplyModeOf(request Request) ReplyMode {
	if request, ok := request.(replyModeRequest); ok {
		return request.replyMode()
	}
	return ReplyModeFrame
}

// Err returns nil for success or a typed protocol error for failure.
func (r FrameReply) Err() error {
	if r.Code == CodeOK {
		return nil
	}
	base := protocolError{code: r.Code, message: r.Error}
	switch r.Code {
	case CodeProtocolVersionMismatch:
		return &VersionMismatchError{protocolError: base}
	case CodeUnknownCommand:
		return &UnknownCommandError{protocolError: base}
	case CodeInvalidRequest:
		return &InvalidRequestError{protocolError: base}
	case CodeTerminalNotFound:
		return &TerminalNotFoundError{protocolError: base}
	case CodeSpawnTokenNotFound:
		return &SpawnTokenNotFoundError{protocolError: base}
	case CodeGhosttyUnavailable:
		return &GhosttyUnavailableError{protocolError: base}
	case CodePasteEmpty:
		return &PasteEmptyError{protocolError: base}
	case CodePasteUnsupported:
		return &PasteUnsupportedError{protocolError: base}
	case CodeStreamFailed:
		return &StreamFailedError{protocolError: base}
	case CodeInternalError:
		return &InternalError{protocolError: base}
	default:
		return &ReplyError{protocolError: base}
	}
}

type protocolError struct {
	code    string
	message string
}

func (e protocolError) Error() string {
	if e.message == "" {
		return e.code
	}
	return e.code + ": " + e.message
}

func (e protocolError) Code() string {
	return e.code
}

// ReplyError is a failed reply frame with an unrecognized code.
type ReplyError struct{ protocolError }

// VersionMismatchError means the request protocol version is unsupported.
type VersionMismatchError struct{ protocolError }

// UnknownCommandError means the request command is not recognized.
type UnknownCommandError struct{ protocolError }

// InvalidRequestError means the request shape or field value is invalid.
type InvalidRequestError struct{ protocolError }

// TerminalNotFoundError means no Ghostty terminal matches the request target.
type TerminalNotFoundError struct{ protocolError }

// SpawnTokenNotFoundError means the spawn token is unknown, already claimed, or expired.
type SpawnTokenNotFoundError struct{ protocolError }

// GhosttyUnavailableError means Ghostty cannot be reached or controlled.
type GhosttyUnavailableError struct{ protocolError }

// PasteEmptyError means the clipboard has no supported paste content.
type PasteEmptyError struct{ protocolError }

// PasteUnsupportedError means clipboard content exists but has no supported representation.
type PasteUnsupportedError struct{ protocolError }

// StreamFailedError means streamed content could not be sent completely.
type StreamFailedError struct{ protocolError }

// InternalError means the daemon hit an unexpected failure.
type InternalError struct{ protocolError }

// DoctorRequest asks the daemon to run active health checks.
type DoctorRequest struct {
	FrameEnvelope
}

func (DoctorRequest) isRequest() {}

// NewDoctorRequest returns a doctor request.
func NewDoctorRequest() DoctorRequest {
	return DoctorRequest{FrameEnvelope: NewFrameEnvelope("doctor")}
}

// DoctorReply is returned by doctor.
type DoctorReply struct {
	FrameReply
	Healthy bool          `json:"healthy"`
	Checks  []DoctorCheck `json:"checks,omitempty"`
}

// DoctorCheck is one daemon health check result.
type DoctorCheck struct {
	Name    string `json:"name"`
	Status  string `json:"status"`
	Message string `json:"message,omitempty"`
}

// TerminalIDRequest asks the daemon to resolve the caller's Ghostty terminal id.
type TerminalIDRequest struct {
	FrameEnvelope
	TTY     string `json:"tty"`
	Refresh bool   `json:"refresh,omitempty"`
}

func (TerminalIDRequest) isRequest() {}

// NewTerminalIDRequest returns a terminal-id request.
func NewTerminalIDRequest(tty string, refresh bool) TerminalIDRequest {
	return TerminalIDRequest{
		FrameEnvelope: NewFrameEnvelope("terminal-id"),
		TTY:           tty,
		Refresh:       refresh,
	}
}

// TabTerminalCountRequest asks for the terminal count in the caller's Ghostty tab.
type TabTerminalCountRequest struct {
	FrameEnvelope
	TTY string `json:"tty"`
}

func (TabTerminalCountRequest) isRequest() {}

// NewTabTerminalCountRequest returns a tab-terminal-count request.
func NewTabTerminalCountRequest(tty string) TabTerminalCountRequest {
	return TabTerminalCountRequest{
		FrameEnvelope: NewFrameEnvelope("tab-terminal-count"),
		TTY:           tty,
	}
}

// BridgeCreateRequest asks the local daemon to create a per-SSH-session bridge.
type BridgeCreateRequest struct {
	FrameEnvelope
	TTY string `json:"tty"`
}

func (BridgeCreateRequest) isRequest() {}

// NewBridgeCreateRequest returns a bridge-create request.
func NewBridgeCreateRequest(tty string) BridgeCreateRequest {
	return BridgeCreateRequest{
		FrameEnvelope: NewFrameEnvelope("bridge-create"),
		TTY:           tty,
	}
}

// BridgeCreateReply is returned by bridge-create.
type BridgeCreateReply struct {
	FrameReply
	SocketPath string `json:"socketPath,omitempty"`
	LeaseToken string `json:"leaseToken,omitempty"`
}

// BridgeLeaseRequest authenticates the persistent local lease connection.
type BridgeLeaseRequest struct {
	FrameEnvelope
	Token string `json:"token"`
}

func (BridgeLeaseRequest) isRequest() {}

// NewBridgeLeaseRequest returns a bridge-lease request.
func NewBridgeLeaseRequest(token string) BridgeLeaseRequest {
	return BridgeLeaseRequest{FrameEnvelope: NewFrameEnvelope("bridge-lease"), Token: token}
}

// SpawnClaimRequest binds the caller TTY to the pending daemon spawn identified by SpawnToken.
type SpawnClaimRequest struct {
	FrameEnvelope
	TTY        string `json:"tty"`
	SpawnToken string `json:"spawnToken"`
}

func (SpawnClaimRequest) isRequest() {}

// NewSpawnClaimRequest returns a spawn-claim request.
func NewSpawnClaimRequest(tty, spawnToken string) SpawnClaimRequest {
	return SpawnClaimRequest{
		FrameEnvelope: NewFrameEnvelope("spawn-claim"),
		TTY:           tty,
		SpawnToken:    spawnToken,
	}
}

// ClearCacheRequest removes one TTY mapping, or all mappings when TTY is empty.
type ClearCacheRequest struct {
	FrameEnvelope
	TTY string `json:"tty,omitempty"`
	Ack bool   `json:"ack,omitempty"`
}

func (ClearCacheRequest) isRequest() {}

// NewClearCacheRequest returns a clear-cache request.
func NewClearCacheRequest(tty string, ack bool) ClearCacheRequest {
	return ClearCacheRequest{FrameEnvelope: NewFrameEnvelope("clear-cache"), TTY: tty, Ack: ack}
}

func (r ClearCacheRequest) replyMode() ReplyMode { return ackReplyMode(r.Ack) }

// KeyTableActivateRequest activates a Ghostty key table for the caller TTY.
type KeyTableActivateRequest struct {
	FrameEnvelope
	TTY   string `json:"tty"`
	Table string `json:"table"`
	Ack   bool   `json:"ack,omitempty"`
}

func (KeyTableActivateRequest) isRequest() {}

// NewKeyTableActivateRequest returns a key-table-activate request.
func NewKeyTableActivateRequest(tty, table string, ack bool) KeyTableActivateRequest {
	return KeyTableActivateRequest{
		FrameEnvelope: NewFrameEnvelope("key-table-activate"),
		TTY:           tty,
		Table:         table,
		Ack:           ack,
	}
}

func (r KeyTableActivateRequest) replyMode() ReplyMode { return ackReplyMode(r.Ack) }

// KeyTableDeactivateRequest deactivates the current Ghostty key table for the caller TTY.
type KeyTableDeactivateRequest struct {
	FrameEnvelope
	TTY string `json:"tty"`
	Ack bool   `json:"ack,omitempty"`
}

func (KeyTableDeactivateRequest) isRequest() {}

// NewKeyTableDeactivateRequest returns a key-table-deactivate request.
func NewKeyTableDeactivateRequest(tty string, ack bool) KeyTableDeactivateRequest {
	return KeyTableDeactivateRequest{
		FrameEnvelope: NewFrameEnvelope("key-table-deactivate"),
		TTY:           tty,
		Ack:           ack,
	}
}

func (r KeyTableDeactivateRequest) replyMode() ReplyMode { return ackReplyMode(r.Ack) }

// FocusRequest moves Ghostty focus in a direction for the caller TTY.
type FocusRequest struct {
	FrameEnvelope
	TTY       string `json:"tty"`
	Direction string `json:"direction"`
	Ack       bool   `json:"ack,omitempty"`
}

func (FocusRequest) isRequest() {}

// NewFocusRequest returns a focus request.
func NewFocusRequest(tty, direction string, ack bool) FocusRequest {
	return FocusRequest{
		FrameEnvelope: NewFrameEnvelope("focus"),
		TTY:           tty,
		Direction:     direction,
		Ack:           ack,
	}
}

func (r FocusRequest) replyMode() ReplyMode { return ackReplyMode(r.Ack) }

// SplitRequest creates a Ghostty split from the caller TTY terminal.
type SplitRequest struct {
	FrameEnvelope
	TTY         string `json:"tty"`
	Direction   string `json:"direction"`
	CWD         string `json:"cwd,omitempty"`
	CommandText string `json:"commandText,omitempty"`
	Focus       string `json:"focus,omitempty"`
	Ack         bool   `json:"ack,omitempty"`
}

func (SplitRequest) isRequest() {}

// NewSplitRequest returns a split request.
func NewSplitRequest(tty, direction, cwd, commandText, focus string, ack bool) SplitRequest {
	return SplitRequest{
		FrameEnvelope: NewFrameEnvelope("split"),
		TTY:           tty,
		Direction:     direction,
		CWD:           cwd,
		CommandText:   commandText,
		Focus:         focus,
		Ack:           ack,
	}
}

func (r SplitRequest) replyMode() ReplyMode { return ackReplyMode(r.Ack) }

// InputRequest sends text to a terminal as pasted input, optionally submitted with enter.
type InputRequest struct {
	FrameEnvelope
	TTY    string `json:"tty"`
	Text   string `json:"text"`
	Submit bool   `json:"submit,omitempty"`
	Ack    bool   `json:"ack,omitempty"`
}

func (InputRequest) isRequest() {}

// NewInputRequest returns an input request.
func NewInputRequest(tty, text string, submit, ack bool) InputRequest {
	return InputRequest{
		FrameEnvelope: NewFrameEnvelope("input"),
		TTY:           tty,
		Text:          text,
		Submit:        submit,
		Ack:           ack,
	}
}

func (r InputRequest) replyMode() ReplyMode { return ackReplyMode(r.Ack) }

// ResizeRequest resizes a Ghostty split adjacent to the caller TTY terminal.
type ResizeRequest struct {
	FrameEnvelope
	TTY       string       `json:"tty"`
	Direction string       `json:"direction"`
	Amount    ResizeAmount `json:"amount"`
	Ack       bool         `json:"ack,omitempty"`
}

func (ResizeRequest) isRequest() {}

// NewResizeRequest returns a resize request.
func NewResizeRequest(tty, direction string, amount ResizeAmount, ack bool) ResizeRequest {
	return ResizeRequest{
		FrameEnvelope: NewFrameEnvelope("resize"),
		TTY:           tty,
		Direction:     direction,
		Amount:        amount,
		Ack:           ack,
	}
}

func (r ResizeRequest) replyMode() ReplyMode { return ackReplyMode(r.Ack) }

// ResizeAmount represents exactly one resize amount variant.
type ResizeAmount struct {
	Pixels  *int     `json:"pixels,omitempty"`
	Percent *float64 `json:"percent,omitempty"`
}

// ZoomRequest toggles split zoom for the caller TTY terminal.
type ZoomRequest struct {
	FrameEnvelope
	TTY string `json:"tty"`
	Ack bool   `json:"ack,omitempty"`
}

func (ZoomRequest) isRequest() {}

// NewZoomRequest returns a zoom request.
func NewZoomRequest(tty string, ack bool) ZoomRequest {
	return ZoomRequest{FrameEnvelope: NewFrameEnvelope("zoom"), TTY: tty, Ack: ack}
}

func (r ZoomRequest) replyMode() ReplyMode { return ackReplyMode(r.Ack) }

// PasteRequest asks the daemon to read the local clipboard for text or file-like content.
type PasteRequest struct {
	FrameEnvelope
	TTY string `json:"tty,omitempty"`
}

func (PasteRequest) isRequest() {}

// NewPasteRequest returns a paste request.
func NewPasteRequest(tty string) PasteRequest {
	return PasteRequest{FrameEnvelope: NewFrameEnvelope("paste"), TTY: tty}
}

func (PasteRequest) replyMode() ReplyMode { return ReplyModeStream }

func (BridgeLeaseRequest) replyMode() ReplyMode { return ReplyModeHold }

func ackReplyMode(ack bool) ReplyMode {
	if ack {
		return ReplyModeFrame
	}
	return ReplyModeNone
}

// PasteKind is the paste result variant.
type PasteKind string

const (
	// PasteKindText carries plain clipboard text after the header.
	PasteKindText PasteKind = "text"
	// PasteKindFiles carries one or more materialized file entries in Files.
	PasteKindFiles PasteKind = "files"
)

// PasteFile is one file-like clipboard item returned by the daemon or written by the client.
type PasteFile struct {
	Path      string `json:"path,omitempty"`
	FileName  string `json:"fileName,omitempty"`
	MediaType string `json:"mediaType,omitempty"`
	Bytes     int64  `json:"bytes,omitempty"`
	Source    string `json:"source,omitempty"`
}

// PasteStreamFrameHeader is the JSON header sent before any streamed paste bytes.
type PasteStreamFrameHeader struct {
	FrameReply
	Kind  PasteKind   `json:"kind,omitempty"`
	Files []PasteFile `json:"files,omitempty"`
	Bytes int64       `json:"bytes,omitempty"`
}
