package herdr

import (
	"bufio"
	"encoding/json"
	"errors"
	"net"
	"os"
	"path/filepath"
	"reflect"
	"strconv"
	"strings"
	"testing"
)

func TestClientRequestsAndDecodesResponses(t *testing.T) {
	cases := []struct {
		name        string
		reply       string
		invoke      func(Client) (any, error)
		wantRequest string
		want        any
	}{
		{
			name:        "process info",
			reply:       `{"result":{"type":"pane_process_info","process_info":{"pane_id":"w1:p1","shell_pid":10,"foreground_processes":[{"pid":11,"name":"nvim","argv":["nvim"],"unknown":1}]}}}`,
			invoke:      func(c Client) (any, error) { return c.ProcessInfo("w1:p1") },
			wantRequest: `"method":"pane.process_info","params":{"pane_id":"w1:p1"}`,
			want:        ProcessInfo{PaneID: "w1:p1", ForegroundProcesses: []Process{{PID: 11, Name: "nvim"}}},
		},
		{
			name:        "neighbor at an edge",
			reply:       `{"result":{"type":"pane_neighbor","neighbor":{"pane_id":"w1:p1","direction":"left","neighbor_pane_id":null,"layout":{}}}}`,
			invoke:      func(c Client) (any, error) { return c.Neighbor("w1:p1", Left) },
			wantRequest: `"method":"pane.neighbor","params":{"pane_id":"w1:p1","direction":"left"}`,
			want:        Neighbor{PaneID: "w1:p1"},
		},
		{
			name:        "focus direction",
			reply:       `{"result":{"type":"pane_focus_direction","focus":{"changed":true,"source_pane_id":"w1:p1","focused_pane_id":"w1:p2","layout":{}}}}`,
			invoke:      func(c Client) (any, error) { return c.FocusDirection("w1:p1", Right) },
			wantRequest: `"method":"pane.focus_direction","params":{"pane_id":"w1:p1","direction":"right"}`,
			want:        Focus{Changed: true, FocusedPaneID: "w1:p2"},
		},
		{
			name:        "window title set",
			reply:       `{"result":{"type":"client_window_title","changed":true,"reason":"set"}}`,
			invoke:      func(c Client) (any, error) { return c.SetWindowTitle("gty-nav:v1:left") },
			wantRequest: `"method":"client.window_title.set","params":{"title":"gty-nav:v1:left"}`,
			want:        WindowTitle{Changed: true, Reason: "set"},
		},
		{
			name:        "window title clear",
			reply:       `{"result":{"type":"client_window_title","changed":true,"reason":"cleared"}}`,
			invoke:      func(c Client) (any, error) { return c.ClearWindowTitle() },
			wantRequest: `"method":"client.window_title.clear","params":{}`,
			want:        WindowTitle{Changed: true, Reason: "cleared"},
		},
		{
			name:        "ping",
			reply:       `{"result":{"type":"pong","version":"0.7.5","protocol":17,"capabilities":{"events":true}}}`,
			invoke:      func(c Client) (any, error) { return c.Ping() },
			wantRequest: `"method":"ping","params":{}`,
			want:        Pong{Version: "0.7.5", Protocol: 17},
		},
	}
	for _, testCase := range cases {
		t.Run(testCase.name, func(t *testing.T) {
			requests := make(chan string, 1)
			client := testClient(t, testCase.reply, requests)
			got, err := testCase.invoke(client)
			if err != nil {
				t.Fatalf("request error = %v", err)
			}
			if !reflect.DeepEqual(got, testCase.want) {
				t.Fatalf("result = %+v, want %+v", got, testCase.want)
			}
			request := <-requests
			if !strings.Contains(request, testCase.wantRequest) {
				t.Fatalf("request = %s, want %s", request, testCase.wantRequest)
			}
		})
	}
}

func TestClientSendKeysUsesHerdrKeyCombos(t *testing.T) {
	requests := make(chan string, 1)
	client := testClient(t, `{"result":{"type":"ok"}}`, requests)
	if err := client.SendKeys("w1:p1", []string{"ctrl+h"}); err != nil {
		t.Fatalf("SendKeys() error = %v", err)
	}
	if want := `"method":"pane.send_keys","params":{"pane_id":"w1:p1","keys":["ctrl+h"]}`; !strings.Contains(<-requests, want) {
		t.Fatalf("request missing %s", want)
	}
}

func TestClientReturnsErrorResponses(t *testing.T) {
	requests := make(chan string, 1)
	client := testClient(t, `{"id":"gty-1","error":{"code":"not_found","message":"pane not found"}}`, requests)
	_, err := client.ProcessInfo("w1:p9")
	if err == nil {
		t.Fatal("ProcessInfo() error = nil, want not_found")
	}
	apiErr, ok := errors.AsType[APIError](err)
	if !ok {
		t.Fatalf("ProcessInfo() error = %T, want APIError", err)
	}
	if apiErr.Code != "not_found" {
		t.Fatalf("code = %q, want not_found", apiErr.Code)
	}
	<-requests
}

func TestClientRejectsMismatchedResponseIDs(t *testing.T) {
	requests := make(chan string, 1)
	client := testClient(t, `{"id":"someone-else","result":{"type":"pong","version":"0.7.5","protocol":17}}`, requests)
	if _, err := client.Ping(); err == nil {
		t.Fatal("Ping() error = nil, want request id mismatch")
	}
	<-requests
}

func TestContextFromEnvPrefersTheActivePane(t *testing.T) {
	t.Setenv("HERDR_SOCKET_PATH", "/tmp/herdr.sock")
	t.Setenv("HERDR_ACTIVE_PANE_ID", "w1:p1")
	t.Setenv("HERDR_PANE_ID", "w1:p2")
	pane, err := ContextFromEnv()
	if err != nil {
		t.Fatalf("ContextFromEnv() error = %v", err)
	}
	if pane.PaneID != "w1:p1" || pane.SocketPath != "/tmp/herdr.sock" {
		t.Fatalf("ContextFromEnv() = %+v, want w1:p1 on /tmp/herdr.sock", pane)
	}

	t.Setenv("HERDR_ACTIVE_PANE_ID", "")
	if pane, err = ContextFromEnv(); err != nil || pane.PaneID != "w1:p2" {
		t.Fatalf("ContextFromEnv() = %+v, %v, want w1:p2", pane, err)
	}

	t.Setenv("HERDR_PANE_ID", "")
	if _, err = ContextFromEnv(); err == nil {
		t.Fatal("ContextFromEnv() error = nil, want missing pane error")
	}

	t.Setenv("HERDR_SOCKET_PATH", "")
	if _, err = ContextFromEnv(); err == nil {
		t.Fatal("ContextFromEnv() error = nil, want missing socket error")
	}
}

// testClient serves one request from a Herdr-shaped socket, echoing the request id back the way
// Herdr does and reporting the raw request line.
func testClient(t *testing.T, reply string, requests chan<- string) Client {
	t.Helper()
	// Unix socket paths are short by definition, and t.TempDir() names itself after the test.
	testDir, err := os.MkdirTemp("/tmp", "gty-herdr-")
	if err != nil {
		t.Fatalf("MkdirTemp() error = %v", err)
	}
	t.Cleanup(func() { _ = os.RemoveAll(testDir) })
	listener, err := net.Listen("unix", filepath.Join(testDir, "herdr.sock"))
	if err != nil {
		t.Fatalf("Listen() error = %v", err)
	}
	t.Cleanup(func() { _ = listener.Close() })
	go func() {
		conn, acceptErr := listener.Accept()
		if acceptErr != nil {
			return
		}
		defer func() { _ = conn.Close() }()
		line, readErr := bufio.NewReader(conn).ReadString('\n')
		if readErr != nil {
			return
		}
		requests <- strings.TrimSpace(line)
		_, _ = conn.Write([]byte(withRequestID(line, reply) + "\n"))
	}()
	return Client{SocketPath: listener.Addr().String()}
}

func withRequestID(request string, reply string) string {
	var identified struct {
		ID string `json:"id"`
	}
	if err := json.Unmarshal([]byte(request), &identified); err != nil {
		return reply
	}
	var decoded map[string]json.RawMessage
	if err := json.Unmarshal([]byte(reply), &decoded); err != nil {
		return reply
	}
	if _, present := decoded["id"]; present {
		return reply
	}
	decoded["id"] = json.RawMessage(strconv.Quote(identified.ID))
	encoded, err := json.Marshal(decoded)
	if err != nil {
		return reply
	}
	return string(encoded)
}
