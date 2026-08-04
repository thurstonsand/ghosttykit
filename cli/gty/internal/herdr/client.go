// Package herdr speaks Herdr's socket API and owns GhosttyKit's Herdr navigation decisions.
package herdr

import (
	"bufio"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"os"
	"strconv"
	"sync/atomic"
	"time"
)

// API is the part of Herdr's socket API the navigation ladder uses.
type API interface {
	ProcessInfo(paneID string) (ProcessInfo, error)
	Neighbor(paneID string, direction Direction) (Neighbor, error)
	FocusDirection(paneID string, direction Direction) (Focus, error)
	SendKeys(paneID string, keys []string) error
	SetWindowTitle(title string) (WindowTitle, error)
	ClearWindowTitle() (WindowTitle, error)
	Ping() (Pong, error)
}

// Context is the Herdr socket and pane a command acts on.
type Context struct {
	SocketPath string
	PaneID     string
}

// ContextFromEnv resolves the Herdr context a command was invoked from. Herdr custom commands
// receive HERDR_ACTIVE_PANE_ID; processes running inside a pane, such as Neovim, receive
// HERDR_PANE_ID.
func ContextFromEnv() (Context, error) {
	socketPath := os.Getenv("HERDR_SOCKET_PATH")
	if socketPath == "" {
		return Context{}, errors.New("HERDR_SOCKET_PATH is required")
	}
	for _, variable := range []string{"HERDR_ACTIVE_PANE_ID", "HERDR_PANE_ID"} {
		if paneID := os.Getenv(variable); paneID != "" {
			return Context{SocketPath: socketPath, PaneID: paneID}, nil
		}
	}
	return Context{}, errors.New("no Herdr pane in the environment: HERDR_ACTIVE_PANE_ID or HERDR_PANE_ID is required")
}

// Client speaks Herdr's newline-delimited JSON socket protocol. Herdr may close an ordinary
// request connection after one response, so every request gets its own short connection.
type Client struct {
	SocketPath string
}

// ProcessInfo reports the processes running in a pane.
type ProcessInfo struct {
	PaneID              string    `json:"pane_id"`
	ForegroundProcesses []Process `json:"foreground_processes"`
}

// Process is one process Herdr reports for a pane.
type Process struct {
	PID  int    `json:"pid"`
	Name string `json:"name"`
}

// Neighbor is the pane adjacent to a pane in one direction, empty at a Herdr edge.
type Neighbor struct {
	PaneID         string `json:"pane_id"`
	NeighborPaneID string `json:"neighbor_pane_id"`
}

// Focus is the result of a directional pane focus.
type Focus struct {
	Changed       bool   `json:"changed"`
	FocusedPaneID string `json:"focused_pane_id"`
	Reason        string `json:"reason"`
}

// WindowTitle is the result of a foreground-client window title request.
type WindowTitle struct {
	Changed bool   `json:"changed"`
	Reason  string `json:"reason"`
}

// Pong is the server identity reported by ping.
type Pong struct {
	Version  string `json:"version"`
	Protocol int    `json:"protocol"`
}

// APIError is an error response from Herdr.
type APIError struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

func (e APIError) Error() string {
	return "herdr " + e.Code + ": " + e.Message
}

// ProcessInfo returns the pane's shell and foreground processes.
func (c Client) ProcessInfo(paneID string) (ProcessInfo, error) {
	var result struct {
		ProcessInfo ProcessInfo `json:"process_info"`
	}
	err := c.call("pane.process_info", paneParams{PaneID: paneID}, &result)
	return result.ProcessInfo, err
}

// Neighbor returns the pane adjacent to paneID in direction.
func (c Client) Neighbor(paneID string, direction Direction) (Neighbor, error) {
	var result struct {
		Neighbor Neighbor `json:"neighbor"`
	}
	err := c.call("pane.neighbor", paneDirectionParams{PaneID: paneID, Direction: direction}, &result)
	return result.Neighbor, err
}

// FocusDirection moves Herdr's focus from paneID in direction.
func (c Client) FocusDirection(paneID string, direction Direction) (Focus, error) {
	var result struct {
		Focus Focus `json:"focus"`
	}
	err := c.call("pane.focus_direction", paneDirectionParams{PaneID: paneID, Direction: direction}, &result)
	return result.Focus, err
}

// SendKeys delivers Herdr key-combo strings to a pane.
func (c Client) SendKeys(paneID string, keys []string) error {
	return c.call("pane.send_keys", sendKeysParams{PaneID: paneID, Keys: keys}, nil)
}

// SetWindowTitle sets the outer terminal title of Herdr's foreground attached client.
func (c Client) SetWindowTitle(title string) (WindowTitle, error) {
	var result WindowTitle
	err := c.call("client.window_title.set", titleParams{Title: title}, &result)
	return result, err
}

// ClearWindowTitle restores the default title of Herdr's foreground attached client.
func (c Client) ClearWindowTitle() (WindowTitle, error) {
	var result WindowTitle
	err := c.call("client.window_title.clear", emptyParams{}, &result)
	return result, err
}

// Ping reports the running server's version and protocol.
func (c Client) Ping() (Pong, error) {
	var result Pong
	err := c.call("ping", emptyParams{}, &result)
	return result, err
}

type paneParams struct {
	PaneID string `json:"pane_id"`
}

type paneDirectionParams struct {
	PaneID    string    `json:"pane_id"`
	Direction Direction `json:"direction"`
}

type sendKeysParams struct {
	PaneID string   `json:"pane_id"`
	Keys   []string `json:"keys"`
}

type titleParams struct {
	Title string `json:"title"`
}

type emptyParams struct{}

// call sends one request and decodes its response into result, which may be nil for methods whose
// result carries nothing the ladder needs. Unknown response fields are ignored on purpose: Herdr
// documents forward-compatible handling of protocol additions.
func (c Client) call(method string, params any, result any) error {
	request := struct {
		ID     string `json:"id"`
		Method string `json:"method"`
		Params any    `json:"params"`
	}{ID: nextRequestID(), Method: method, Params: params}
	encoded, err := json.Marshal(request)
	if err != nil {
		return err
	}

	conn, err := net.Dial("unix", c.SocketPath)
	if err != nil {
		return fmt.Errorf("connect to herdr at %s: %w", c.SocketPath, err)
	}
	defer func() { _ = conn.Close() }()
	if err = conn.SetDeadline(time.Now().Add(requestTimeout)); err != nil {
		return err
	}
	if _, err = conn.Write(append(encoded, '\n')); err != nil {
		return fmt.Errorf("send %s: %w", method, err)
	}

	line, err := bufio.NewReader(conn).ReadBytes('\n')
	if len(line) == 0 {
		if err != nil {
			return fmt.Errorf("read %s response: %w", method, err)
		}
		return fmt.Errorf("read %s response: empty reply", method)
	}
	return decodeResponse(method, request.ID, line, result)
}

func decodeResponse(method string, requestID string, line []byte, result any) error {
	var response struct {
		ID     string          `json:"id"`
		Result json.RawMessage `json:"result"`
		Error  *APIError       `json:"error"`
	}
	if err := json.Unmarshal(line, &response); err != nil {
		return fmt.Errorf("decode %s response: %w", method, err)
	}
	if response.Error != nil {
		return *response.Error
	}
	if response.ID != requestID {
		return fmt.Errorf("herdr answered %s with request id %q, want %q", method, response.ID, requestID)
	}
	if result == nil {
		return nil
	}
	if err := json.Unmarshal(response.Result, result); err != nil {
		return fmt.Errorf("decode %s result: %w", method, err)
	}
	return nil
}

func nextRequestID() string {
	return "gty-" + strconv.FormatUint(requestCounter.Add(1), 10)
}

var requestCounter atomic.Uint64

// requestTimeout bounds a navigation keypress: a hung socket must not leave the key dead for
// longer than the user would wait before pressing it again.
const requestTimeout = 2 * time.Second
