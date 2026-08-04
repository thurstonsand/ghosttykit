package herdr

import (
	"errors"
	"strings"
	"testing"
)

func TestNavigateDecisionTable(t *testing.T) {
	cases := []struct {
		name      string
		client    fakeClient
		wantCalls []string
		wantError string
	}{
		{
			name:      "neovim pane receives the original key",
			client:    fakeClient{foreground: []string{"zsh", "nvim"}, neighbor: "w1:p2"},
			wantCalls: []string{"process_info", "send_keys ctrl+h"},
		},
		{
			name:      "shell pane with a neighbor moves inside herdr",
			client:    fakeClient{foreground: []string{"zsh"}, neighbor: "w1:p2"},
			wantCalls: []string{"process_info", "neighbor left", "focus left"},
		},
		{
			name:      "shell pane at the herdr edge signals outward",
			client:    fakeClient{foreground: []string{"zsh"}},
			wantCalls: []string{"process_info", "neighbor left", "set_title gty-nav:v1:left", "clear_title"},
		},
		{
			name:      "absolute process paths still count as neovim",
			client:    fakeClient{foreground: []string{"/opt/homebrew/bin/nvim"}},
			wantCalls: []string{"process_info", "send_keys ctrl+h"},
		},
		{
			name:      "process inspection failure moves nothing",
			client:    fakeClient{processInfoError: errors.New("socket closed")},
			wantCalls: []string{"process_info"},
			wantError: "socket closed",
		},
		{
			name:      "neighbor failure is not an edge",
			client:    fakeClient{foreground: []string{"zsh"}, neighborError: errors.New("not_found")},
			wantCalls: []string{"process_info", "neighbor left"},
			wantError: "not_found",
		},
		{
			name:      "focus that reports no change fails",
			client:    fakeClient{foreground: []string{"zsh"}, neighbor: "w1:p2", focusUnchanged: true},
			wantCalls: []string{"process_info", "neighbor left", "focus left"},
			wantError: "did not focus the left pane (no_neighbor)",
		},
		{
			name:      "no foreground client leaves the sentinel unsent",
			client:    fakeClient{foreground: []string{"zsh"}, titleUnchanged: true},
			wantCalls: []string{"process_info", "neighbor left", "set_title gty-nav:v1:left"},
			wantError: "did not signal left navigation to a client (no_foreground_client)",
		},
	}
	for _, testCase := range cases {
		t.Run(testCase.name, func(t *testing.T) {
			client := testCase.client
			err := Navigator{API: &client, PaneID: "w1:p1"}.Navigate(Left)
			switch {
			case testCase.wantError == "" && err != nil:
				t.Fatalf("Navigate() error = %v, want nil", err)
			case testCase.wantError != "" && err == nil:
				t.Fatalf("Navigate() error = nil, want %q", testCase.wantError)
			case testCase.wantError != "" && !strings.Contains(err.Error(), testCase.wantError):
				t.Fatalf("Navigate() error = %v, want %q", err, testCase.wantError)
			}
			if got := strings.Join(client.calls, "; "); got != strings.Join(testCase.wantCalls, "; ") {
				t.Fatalf("calls = %q, want %q", got, strings.Join(testCase.wantCalls, "; "))
			}
		})
	}
}

func TestNavigateSendsTheDirectionKeyNeovimExpects(t *testing.T) {
	for direction, key := range map[Direction]string{Left: "ctrl+h", Down: "ctrl+j", Up: "ctrl+k", Right: "ctrl+l"} {
		client := fakeClient{foreground: []string{"nvim"}}
		if err := (Navigator{API: &client, PaneID: "w1:p1"}).Navigate(direction); err != nil {
			t.Fatalf("Navigate(%s) error = %v", direction, err)
		}
		if want := "send_keys " + key; client.calls[1] != want {
			t.Fatalf("Navigate(%s) sent %q, want %q", direction, client.calls[1], want)
		}
	}
}

func TestParseDirectionRejectsUnknownValues(t *testing.T) {
	for _, value := range []string{"left", "down", "up", "right"} {
		if _, err := ParseDirection(value); err != nil {
			t.Fatalf("ParseDirection(%q) error = %v", value, err)
		}
	}
	if _, err := ParseDirection("sideways"); err == nil {
		t.Fatal("ParseDirection(sideways) error = nil, want error")
	}
}

// fakeClient records the ladder's requests and answers them from a fixed pane arrangement.
type fakeClient struct {
	foreground       []string
	neighbor         string
	focusUnchanged   bool
	titleUnchanged   bool
	processInfoError error
	neighborError    error
	calls            []string
}

func (f *fakeClient) ProcessInfo(paneID string) (ProcessInfo, error) {
	f.calls = append(f.calls, "process_info")
	if f.processInfoError != nil {
		return ProcessInfo{}, f.processInfoError
	}
	info := ProcessInfo{PaneID: paneID}
	for index, name := range f.foreground {
		info.ForegroundProcesses = append(info.ForegroundProcesses, Process{PID: index + 1, Name: name})
	}
	return info, nil
}

func (f *fakeClient) Neighbor(paneID string, direction Direction) (Neighbor, error) {
	f.calls = append(f.calls, "neighbor "+string(direction))
	if f.neighborError != nil {
		return Neighbor{}, f.neighborError
	}
	return Neighbor{PaneID: paneID, NeighborPaneID: f.neighbor}, nil
}

func (f *fakeClient) FocusDirection(_ string, direction Direction) (Focus, error) {
	f.calls = append(f.calls, "focus "+string(direction))
	if f.focusUnchanged {
		return Focus{Reason: "no_neighbor"}, nil
	}
	return Focus{Changed: true, FocusedPaneID: f.neighbor}, nil
}

func (f *fakeClient) SendKeys(_ string, keys []string) error {
	f.calls = append(f.calls, "send_keys "+strings.Join(keys, " "))
	return nil
}

func (f *fakeClient) SetWindowTitle(title string) (WindowTitle, error) {
	f.calls = append(f.calls, "set_title "+title)
	if f.titleUnchanged {
		return WindowTitle{Reason: "no_foreground_client"}, nil
	}
	return WindowTitle{Changed: true, Reason: "set"}, nil
}

func (f *fakeClient) ClearWindowTitle() (WindowTitle, error) {
	f.calls = append(f.calls, "clear_title")
	return WindowTitle{Changed: true, Reason: "cleared"}, nil
}

func (f *fakeClient) Ping() (Pong, error) {
	f.calls = append(f.calls, "ping")
	return Pong{Version: "0.7.5", Protocol: 17}, nil
}
