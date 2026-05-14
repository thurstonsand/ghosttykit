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
	errResponseRequired   = errors.New("request requires a response")
	errNoResponseExpected = errors.New("request does not expect a response")
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

// Stream sends request, decodes the first JSON header line, and returns the body stream.
func Stream[T protocol.StreamHeader](client Client, request protocol.Request) (T, io.ReadCloser, error) {
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

// Dispatch sends request using the response behavior defined by the protocol.
func (c Client) Dispatch(request protocol.Request) (*protocol.Response, error) {
	if expectsResponse(request) {
		return c.call(request)
	}
	return nil, c.notify(request)
}

func (c Client) call(request protocol.Request) (*protocol.Response, error) {
	if !expectsResponse(request) {
		return nil, errNoResponseExpected
	}
	conn, err := c.Dial()
	if err != nil {
		return nil, err
	}
	defer func() { _ = conn.Close() }()

	if err := conn.send(request); err != nil {
		return nil, err
	}
	return conn.waitForResponse()
}

func (c Client) notify(request protocol.Request) error {
	if expectsResponse(request) {
		return errResponseRequired
	}
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

func expectsResponse(request protocol.Request) bool {
	switch req := request.(type) {
	case protocol.KeyTableActivateRequest:
		return req.Ack
	case protocol.KeyTableDeactivateRequest:
		return req.Ack
	case protocol.FocusRequest:
		return req.Ack
	case protocol.SplitRequest:
		return req.Ack
	case protocol.ResizeRequest:
		return req.Ack
	case protocol.ZoomRequest:
		return req.Ack
	case protocol.ClearCacheRequest:
		return req.Ack
	default:
		return true
	}
}

func (c Client) stream(request protocol.Request) (*Conn, error) {
	conn, err := c.Dial()
	if err != nil {
		return nil, err
	}
	if err := conn.send(request); err != nil {
		_ = conn.Close()
		return nil, err
	}
	if err := conn.closeWrite(); err != nil {
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

func (c *Conn) closeWrite() error {
	if err := c.conn.CloseWrite(); err != nil {
		return fmt.Errorf("close write: %w", err)
	}
	return nil
}

func (c *Conn) waitForResponse() (*protocol.Response, error) {
	if err := c.closeWrite(); err != nil {
		return nil, err
	}

	var response protocol.Response
	if err := json.NewDecoder(c.reader).Decode(&response); err != nil {
		return nil, fmt.Errorf("read response: %w", err)
	}
	if err := response.Err(); err != nil {
		return &response, err
	}
	return &response, nil
}

func (c *Conn) waitForEOF() error {
	if err := c.closeWrite(); err != nil {
		return err
	}
	if _, err := c.reader.ReadByte(); errors.Is(err, io.EOF) {
		return nil
	} else if err != nil {
		return fmt.Errorf("wait for daemon completion: %w", err)
	}
	return errors.New("daemon sent unexpected data for no-response request")
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
