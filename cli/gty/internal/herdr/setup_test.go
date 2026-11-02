package herdr

import (
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	"github.com/pelletier/go-toml/v2"
)

const (
	managedGTY    = `"${XDG_DATA_HOME:-$HOME/.local/share}/ghosttykit/bin/gty"`
	navigateRight = `exec "${XDG_DATA_HOME:-$HOME/.local/share}/ghosttykit/bin/gty" herdr navigate right`
)

// These tests run the real `herdr config check`, pinned in this component's mise tools, because
// Herdr alone decides how keybindings collide.
func ensure(path string) ([]string, error) {
	return EnsureBindings(path, NavigationBindings(managedGTY), "herdr")
}

func TestEnsureBindingsAddsOnlyMissingKeysAndKeepsTheRest(t *testing.T) {
	path := filepath.Join(t.TempDir(), "herdr", "config.toml")
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	original := `# my herdr config
onboarding = false
from_a_newer_herdr = true

[keys]
navigate_pane_left = "ctrl+h"

[[keys.command]]
key = "ctrl+l"
type = "shell"
command = '` + navigateRight + `'

[theme]
name = "gruvbox"`
	writeConfig(t, path, original)

	added, err := ensure(path)
	if err != nil {
		t.Fatal(err)
	}
	if want := []string{"ctrl+h", "ctrl+j", "ctrl+k"}; !reflect.DeepEqual(added, want) {
		t.Fatalf("added = %v, want %v", added, want)
	}
	config := readConfig(t, path)
	if !strings.HasPrefix(config, original+"\n\n[[keys.command]]\n") {
		t.Fatalf("config was not appended to verbatim:\n%s", config)
	}
	var decoded struct {
		Keys struct {
			NavigatePaneLeft string `toml:"navigate_pane_left"`
			Command          []Binding
		} `toml:"keys"`
		Theme struct{ Name string } `toml:"theme"`
	}
	decode(t, config, &decoded)
	keys := make([]string, 0, len(decoded.Keys.Command))
	for _, binding := range decoded.Keys.Command {
		keys = append(keys, binding.Key)
	}
	if !reflect.DeepEqual(keys, []string{"ctrl+l", "ctrl+h", "ctrl+j", "ctrl+k"}) ||
		decoded.Keys.NavigatePaneLeft != "ctrl+h" || decoded.Theme.Name != "gruvbox" {
		t.Fatalf("decoded config = %+v", decoded)
	}

	again, err := ensure(path)
	if err != nil || again != nil || readConfig(t, path) != config {
		t.Fatalf("second run: added %v, err %v, changed %v", again, err, readConfig(t, path) != config)
	}
}

func TestEnsureBindingsCreatesMissingConfig(t *testing.T) {
	path := filepath.Join(t.TempDir(), "herdr", "config.toml")

	added, err := ensure(path)
	if err != nil {
		t.Fatal(err)
	}
	if len(added) != 4 {
		t.Fatalf("added = %v", added)
	}
	var config struct {
		Keys struct{ Command []Binding } `toml:"keys"`
	}
	decode(t, readConfig(t, path), &config)
	right := config.Keys.Command[3]
	if right.Key != "ctrl+l" || right.Type != "shell" || right.Command != navigateRight {
		t.Fatalf("ctrl+l binding = %+v", right)
	}
}

func TestEnsureBindingsRefusesConflictsWithoutWriting(t *testing.T) {
	cases := map[string]string{
		"another command":  "[[keys.command]]\nkey = \"ctrl+k\"\ntype = \"shell\"\ncommand = \"tmux select-pane -U\"\n",
		"a direct action":  "[keys]\nprevious_tab = [\"prefix+p\", \"ctrl+j\"]\n",
		"another spelling": "[keys]\nnext_tab = \"control+k\"\n",
		"inline array":     "[keys]\ncommand = [{ key = \"prefix+g\", type = \"popup\", command = \"lazygit\" }]\n",
		"invalid toml":     "onboarding = = false\n",
	}
	for name, original := range cases {
		t.Run(name, func(t *testing.T) {
			path := filepath.Join(t.TempDir(), "config.toml")
			writeConfig(t, path, original)

			added, err := ensure(path)

			if err == nil {
				t.Fatalf("added %v to a config it should refuse", added)
			}
			if got := readConfig(t, path); got != original {
				t.Fatalf("config changed:\n%s", got)
			}
		})
	}
}

func writeConfig(t *testing.T, path string, content string) {
	t.Helper()
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

func decode(t *testing.T, config string, into any) {
	t.Helper()
	if err := toml.Unmarshal([]byte(config), into); err != nil {
		t.Fatalf("%v\n%s", err, config)
	}
}

func readConfig(t *testing.T, path string) string {
	t.Helper()
	content, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	return string(content)
}
