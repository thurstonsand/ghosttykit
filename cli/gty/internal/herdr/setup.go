package herdr

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/pelletier/go-toml/v2"
)

// Binding is one Herdr `[[keys.command]]` entry.
type Binding struct {
	Key         string `toml:"key"`
	Type        string `toml:"type"`
	Command     string `toml:"command"`
	Description string `toml:"description"`
}

// NavigationBindings are the keybindings `gty herdr navigate` needs, running the gty that gtyPath
// names. Herdr runs shell commands detached from any interactive PATH, so the path is explicit.
func NavigationBindings(gtyPath string) []Binding {
	keys := []struct {
		key       string
		direction Direction
	}{{"ctrl+h", Left}, {"ctrl+j", Down}, {"ctrl+k", Up}, {"ctrl+l", Right}}
	bindings := make([]Binding, 0, len(keys))
	for _, k := range keys {
		bindings = append(bindings, Binding{
			Key:         k.key,
			Type:        "shell",
			Command:     "exec " + gtyPath + " herdr navigate " + string(k.direction),
			Description: "navigate " + string(k.direction),
		})
	}
	return bindings
}

// ConfigPath resolves Herdr's config file the way Herdr does on Linux and macOS.
func ConfigPath() (string, error) {
	if path := os.Getenv("HERDR_CONFIG_PATH"); path != "" {
		return path, nil
	}
	if dir := os.Getenv("XDG_CONFIG_HOME"); dir != "" {
		return filepath.Join(dir, "herdr", "config.toml"), nil
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(home, ".config", "herdr", "config.toml"), nil
}

// EnsureBindings appends whichever bindings the config lacks and returns their keys. Herdr itself
// judges the result: when `herdr config check` reports that any of these keys would be disabled
// or the config ignored, it writes nothing and fails. Appending rather than rewriting keeps the
// user's comments and layout, and follows a config that is a symlink into a dotfiles checkout.
func EnsureBindings(configPath string, bindings []Binding, herdrBin string) ([]string, error) {
	existing, err := os.ReadFile(configPath)
	if err != nil && !errors.Is(err, fs.ErrNotExist) {
		return nil, err
	}
	missing, err := missingBindings(existing, bindings)
	if err != nil {
		return nil, fmt.Errorf("%s: %w", configPath, err)
	}
	addition, err := encodeBindings(existing, missing)
	if err != nil {
		return nil, err
	}
	if err = checkBindings(herdrBin, append(existing, addition...), bindings); err != nil {
		return nil, fmt.Errorf("%s: %w", configPath, err)
	}
	if len(missing) == 0 {
		return nil, nil
	}

	if err = os.MkdirAll(filepath.Dir(configPath), 0o755); err != nil {
		return nil, err
	}
	file, err := os.OpenFile(configPath, os.O_WRONLY|os.O_APPEND|os.O_CREATE, 0o644)
	if err != nil {
		return nil, err
	}
	if _, err = file.Write(addition); err != nil {
		_ = file.Close()
		return nil, err
	}
	if err = file.Close(); err != nil {
		return nil, err
	}
	keys := make([]string, 0, len(missing))
	for _, binding := range missing {
		keys = append(keys, binding.Key)
	}
	return keys, nil
}

// RunningSessions lists the Herdr sessions whose servers are running.
func RunningSessions(herdrBin string) ([]string, error) {
	out, err := exec.Command(herdrBin, "session", "list", "--json").Output()
	if err != nil {
		return nil, fmt.Errorf("%s is not runnable: %w", herdrBin, commandError(err))
	}
	var list struct {
		Sessions []struct {
			Name    string `json:"name"`
			Running bool   `json:"running"`
		} `json:"sessions"`
	}
	if err := json.Unmarshal(out, &list); err != nil {
		return nil, fmt.Errorf("decode herdr session list: %w", err)
	}
	var running []string
	for _, session := range list.Sessions {
		if session.Running {
			running = append(running, session.Name)
		}
	}
	return running, nil
}

// ReloadConfig reloads one running session's config. Custom command keybindings belong to the
// server, so a running server does not see new bindings until it reloads.
func ReloadConfig(herdrBin string, session string) error {
	out, err := exec.Command(herdrBin, "--session", session, "server", "reload-config").CombinedOutput()
	if err != nil {
		return fmt.Errorf("reload Herdr session %s: %s", session, strings.TrimSpace(string(out)))
	}
	return nil
}

// missingBindings finds the bindings the config does not already hold exactly. A key bound to
// something else counts as missing; checkBindings then reports the collision as Herdr sees it.
func missingBindings(config []byte, bindings []Binding) ([]Binding, error) {
	var decoded struct {
		Keys struct {
			Command []Binding `toml:"command"`
		} `toml:"keys"`
	}
	if err := toml.Unmarshal(config, &decoded); err != nil {
		return nil, fmt.Errorf("parse Herdr config: %w", err)
	}
	var missing []Binding
	for _, want := range bindings {
		found := false
		for _, have := range decoded.Keys.Command {
			if have.Key == want.Key && have.Type == want.Type && have.Command == want.Command {
				found = true
			}
		}
		if !found {
			missing = append(missing, want)
		}
	}
	return missing, nil
}

func encodeBindings(existing []byte, bindings []Binding) ([]byte, error) {
	var out bytes.Buffer
	for _, binding := range bindings {
		entry, err := toml.Marshal(binding)
		if err != nil {
			return nil, err
		}
		if out.Len() > 0 || len(existing) > 0 {
			out.WriteString("\n")
		}
		out.WriteString("[[keys.command]]\n")
		out.Write(entry)
	}
	if out.Len() > 0 && len(existing) > 0 && !bytes.HasSuffix(existing, []byte("\n")) {
		return append([]byte("\n"), out.Bytes()...), nil
	}
	return out.Bytes(), nil
}

// checkBindings runs `herdr config check` on candidate. Herdr normalizes key spellings and
// resolves collisions itself, so only it can say whether these keys will run. Its other
// diagnostics, such as an unknown key from a newer Herdr, do not concern these bindings.
func checkBindings(herdrBin string, candidate []byte, bindings []Binding) error {
	file, err := os.CreateTemp("", "herdr-config-*.toml")
	if err != nil {
		return err
	}
	defer func() { _ = os.Remove(file.Name()) }()
	if _, err = file.Write(candidate); err != nil {
		_ = file.Close()
		return err
	}
	if err = file.Close(); err != nil {
		return err
	}

	check := exec.Command(herdrBin, "config", "check")
	check.Env = append(os.Environ(), "HERDR_CONFIG_PATH="+file.Name())
	out, err := check.Output()
	if err == nil {
		return nil
	}
	if _, failed := errors.AsType[*exec.ExitError](err); !failed {
		return fmt.Errorf("%s is not runnable: %w", herdrBin, err)
	}
	var problems []string
	for line := range strings.Lines(string(out)) {
		line = strings.TrimSpace(line)
		if strings.HasSuffix(line, "using defaults") {
			return fmt.Errorf("herdr config check rejects the config with these keybindings:\n%s", strings.TrimSpace(string(out)))
		}
		for _, binding := range bindings {
			if strings.HasPrefix(line, binding.Key+":") {
				problems = append(problems, line)
			}
		}
	}
	if len(problems) > 0 {
		return fmt.Errorf("keybindings collide in Herdr: %s", strings.Join(problems, "; "))
	}
	return nil
}

func commandError(err error) error {
	if exitErr, ok := errors.AsType[*exec.ExitError](err); ok && len(exitErr.Stderr) > 0 {
		return errors.New(strings.TrimSpace(string(exitErr.Stderr)))
	}
	return err
}
