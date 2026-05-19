// Package client connects to GhosttyKit daemon and bridge endpoints.
package client

import (
	"bufio"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"os"
	"path/filepath"

	"github.com/thurstonsand/ghosttykit/sdk/go/protocol"
)

var (
	// ErrStreamReplyMode means the request returns a stream reply, not a single JSON frame.
	ErrStreamReplyMode = errors.New("request reply mode is stream")
	// ErrFrameReplyMode means the request returns a single JSON frame, not a stream.
	ErrFrameReplyMode = errors.New("request reply mode is frame")
	// ErrNoReplyMode means the request does not return reply bytes.
	ErrNoReplyMode = errors.New("request reply mode is none")
	// ErrHoldReplyMode means the request holds the connection open after the reply frame.
	ErrHoldReplyMode = errors.New("request reply mode is hold")
)

// Client opens one connection per request to a GhosttyKit endpoint.
type Client struct {
	socketPath string
}

// New returns a client for GTY_SOCK or the default local daemon socket.
func New() Client {
	return Client{socketPath: socketPath()}
}

// ForSocket returns a client bound to socketPath. It is mainly for tests.
func ForSocket(socketPath string) Client {
	return Client{socketPath: socketPath}
}

// Call sends a request and decodes one JSON reply frame.
func Call[T protocol.FrameResponse](client Client, request protocol.Request) (T, error) {
	var reply T
	if err := requireReplyMode(request, protocol.ReplyModeFrame); err != nil {
		return reply, err
	}
	conn, err := client.Dial()
	if err != nil {
		return reply, err
	}
	defer func() { _ = conn.Close() }()

	if err := conn.send(request); err != nil {
		return reply, err
	}
	return readReply[T](conn.reader)
}

// Notify sends a request and waits for the daemon to close without reply bytes.
func Notify(client Client, request protocol.Request) error {
	if err := requireReplyMode(request, protocol.ReplyModeNone); err != nil {
		return err
	}
	conn, err := client.Dial()
	if err != nil {
		return err
	}
	defer func() { _ = conn.Close() }()

	if err := conn.send(request); err != nil {
		return err
	}
	return conn.waitForEOF()
}

// Stream sends request, decodes the first JSON header line, and returns the body stream.
func Stream[T protocol.StreamFrameHeader](client Client, request protocol.Request) (T, io.ReadCloser, error) {
	var header T
	if err := requireReplyMode(request, protocol.ReplyModeStream); err != nil {
		return header, nil, err
	}
	conn, err := client.Dial()
	if err != nil {
		return header, nil, err
	}
	if err := conn.send(request); err != nil {
		_ = conn.Close()
		return header, nil, err
	}
	header, err = readReply[T](conn.reader)
	if err != nil {
		_ = conn.Close()
		return header, nil, err
	}
	return header, conn, nil
}

// Hold sends request, validates its initial reply frame, and returns the held connection.
func Hold[T protocol.FrameResponse](client Client, request protocol.Request) (T, io.Closer, error) {
	var reply T
	if err := requireReplyMode(request, protocol.ReplyModeHold); err != nil {
		return reply, nil, err
	}
	conn, err := client.Dial()
	if err != nil {
		return reply, nil, err
	}
	if err := conn.send(request); err != nil {
		_ = conn.Close()
		return reply, nil, err
	}
	reply, err = readReply[T](conn.reader)
	if err != nil {
		_ = conn.Close()
		return reply, nil, err
	}
	return reply, conn, nil
}

// NotifyAck calls request when wait is true and notifies without reply otherwise.
func NotifyAck(client Client, request protocol.Request, wait bool) error {
	if wait {
		_, err := Call[protocol.FrameReply](client, request)
		return err
	}
	return Notify(client, request)
}

func requireReplyMode(request protocol.Request, want protocol.ReplyMode) error {
	if err := validateRequest(request); err != nil {
		return err
	}
	got := protocol.ReplyModeOf(request)
	if got == want {
		return nil
	}
	switch got {
	case protocol.ReplyModeFrame:
		return ErrFrameReplyMode
	case protocol.ReplyModeNone:
		return ErrNoReplyMode
	case protocol.ReplyModeStream:
		return ErrStreamReplyMode
	case protocol.ReplyModeHold:
		return ErrHoldReplyMode
	default:
		return fmt.Errorf("unsupported reply mode %d", got)
	}
}

func validateRequest(request protocol.Request) error {
	if validatable, ok := request.(protocol.ValidatableRequest); ok {
		return validatable.Validate()
	}
	return nil
}

// Dial opens one Unix socket connection to the client's endpoint.
func (c Client) Dial() (*Conn, error) {
	return Dial(c.socketPath)
}

// Dial opens one Unix socket connection to socketPath. It is mainly for tests.
func Dial(socketPath string) (*Conn, error) {
	if socketPath == "" {
		return nil, errors.New("socket path is empty")
	}

	addr := net.UnixAddr{Name: socketPath, Net: "unix"}
	conn, err := net.DialUnix("unix", nil, &addr)
	if err != nil {
		return nil, fmt.Errorf("connect %s: %w", socketPath, err)
	}
	return &Conn{conn: conn, reader: bufio.NewReader(conn)}, nil
}

// Conn is one Unix socket connection to a GhosttyKit endpoint.
type Conn struct {
	conn   *net.UnixConn
	reader *bufio.Reader
}

func (c *Conn) Read(p []byte) (int, error) {
	return c.reader.Read(p)
}

// Close closes the connection without waiting for daemon completion.
func (c *Conn) Close() error {
	return c.conn.Close()
}

func (c *Conn) send(request protocol.Request) error {
	if err := json.NewEncoder(c.conn).Encode(request); err != nil {
		return fmt.Errorf("send request: %w", err)
	}
	return nil
}

func readReply[T protocol.FrameResponse](reader *bufio.Reader) (T, error) {
	var reply T
	line, err := reader.ReadBytes('\n')
	if err != nil {
		return reply, fmt.Errorf("read reply: %w", err)
	}
	if err := json.Unmarshal(line, &reply); err != nil {
		return reply, fmt.Errorf("decode reply: %w", err)
	}
	if err := reply.Err(); err != nil {
		return reply, err
	}
	return reply, nil
}

func (c *Conn) waitForEOF() error {
	if _, err := c.reader.ReadByte(); errors.Is(err, io.EOF) {
		return nil
	} else if err != nil {
		return fmt.Errorf("wait for daemon completion: %w", err)
	}
	return errors.New("daemon sent unexpected data for no-reply request")
}

func socketPath() string {
	if value := os.Getenv("GTY_SOCK"); value != "" {
		return value
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return ""
	}
	return filepath.Join(home, ".local/run/ghosttykit/ghosttykitd.sock")
}
