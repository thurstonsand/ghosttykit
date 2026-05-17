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

var errStreamReply = errors.New("request requires stream handling")

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

// Stream sends request, decodes the first JSON header line, and returns the body stream.
func Stream[T protocol.FrameHeader](client Client, request protocol.Request) (T, io.ReadCloser, error) {
	var header T
	body, err := client.stream(request)
	if err != nil {
		return header, nil, err
	}
	headerLine, err := body.reader.ReadBytes('\n')
	if err != nil {
		_ = body.Close()
		return header, nil, fmt.Errorf("read stream header: %w", err)
	}
	if err := json.Unmarshal(headerLine, &header); err != nil {
		_ = body.Close()
		return header, nil, fmt.Errorf("decode stream header: %w", err)
	}
	if err := header.Err(); err != nil {
		_ = body.Close()
		return header, nil, err
	}
	return header, body, nil
}

// Do sends request and returns a reply when the protocol expects one.
func (c Client) Do(request protocol.Request) (*protocol.FrameReply, error) {
	if err := validateRequest(request); err != nil {
		return nil, err
	}
	switch protocol.ReplyModeOf(request) {
	case protocol.ReplyModeFrame:
		return c.doWithReply(request)
	case protocol.ReplyModeNone:
		return nil, c.doNoReply(request)
	case protocol.ReplyModeStream:
		return nil, errStreamReply
	default:
		return nil, fmt.Errorf("unsupported reply mode %d", protocol.ReplyModeOf(request))
	}
}

func (c Client) doWithReply(request protocol.Request) (*protocol.FrameReply, error) {
	conn, err := c.Dial()
	if err != nil {
		return nil, err
	}
	defer func() { _ = conn.Close() }()

	if err := conn.send(request); err != nil {
		return nil, err
	}
	return conn.waitForReply()
}

func (c Client) doNoReply(request protocol.Request) error {
	conn, err := c.Dial()
	if err != nil {
		return err
	}
	defer func() { _ = conn.Close() }()

	if err := conn.send(request); err != nil {
		return err
	}
	return conn.waitForEOF()
}

func validateRequest(request protocol.Request) error {
	if validatable, ok := request.(protocol.ValidatableRequest); ok {
		return validatable.Validate()
	}
	return nil
}

func (c Client) stream(request protocol.Request) (*Conn, error) {
	if protocol.ReplyModeOf(request) != protocol.ReplyModeStream {
		return nil, errStreamReply
	}
	if err := validateRequest(request); err != nil {
		return nil, err
	}
	conn, err := c.Dial()
	if err != nil {
		return nil, err
	}
	if err := conn.send(request); err != nil {
		_ = conn.Close()
		return nil, err
	}
	return conn, nil
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

func (c *Conn) waitForReply() (*protocol.FrameReply, error) {
	var reply protocol.FrameReply
	if err := json.NewDecoder(c.reader).Decode(&reply); err != nil {
		return nil, fmt.Errorf("read reply: %w", err)
	}
	if err := reply.Err(); err != nil {
		return &reply, err
	}
	return &reply, nil
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
