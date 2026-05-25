// Package remote implements GhosttyKit remote SSH bridge behavior.
package remote

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"os"
	"path/filepath"
	"strconv"
	"time"

	"github.com/google/uuid"
)

// InitResult describes the prepared remote runtime.
type InitResult struct {
	RuntimeDir string `json:"runtimeDir"`
	SocketPath string `json:"socketPath"`
}

// Init runs the remote-init helper and writes its JSON result.
func Init(stdout io.Writer) error {
	result, err := PrepareRuntime()
	if err != nil {
		return err
	}
	return json.NewEncoder(stdout).Encode(result)
}

// PrepareRuntime creates the remote runtime directory and allocates a socket path.
func PrepareRuntime() (InitResult, error) {
	dir, err := runtimeDir()
	if err != nil {
		return InitResult{}, err
	}
	if err = os.MkdirAll(dir, 0o700); err != nil {
		return InitResult{}, fmt.Errorf("create runtime dir: %w", err)
	}
	if err = os.Chmod(dir, 0o700); err != nil {
		return InitResult{}, fmt.Errorf("secure runtime dir: %w", err)
	}
	if err = cleanupDeadSockets(dir); err != nil {
		return InitResult{}, err
	}
	name := randomSocketName()
	return InitResult{RuntimeDir: dir, SocketPath: filepath.Join(dir, name)}, nil
}

func runtimeDir() (string, error) {
	if value := os.Getenv("XDG_RUNTIME_DIR"); value != "" {
		dir := filepath.Join(value, "gty")
		if err := os.MkdirAll(dir, 0o700); err == nil {
			return dir, nil
		}
	}
	uid := os.Getuid()
	if uid < 0 {
		return "", errors.New("cannot determine uid")
	}
	return filepath.Join(os.TempDir(), "gty-"+strconv.Itoa(uid)), nil
}

func cleanupDeadSockets(dir string) error {
	entries, err := filepath.Glob(filepath.Join(dir, "bridge-*.sock"))
	if err != nil {
		return err
	}
	for _, path := range entries {
		if socketAlive(path) {
			continue
		}
		if err := os.Remove(path); err != nil && !errors.Is(err, os.ErrNotExist) {
			return fmt.Errorf("remove dead socket %s: %w", path, err)
		}
	}
	return nil
}

func socketAlive(path string) bool {
	conn, err := net.DialTimeout("unix", path, 100*time.Millisecond)
	if err != nil {
		return false
	}
	_ = conn.Close()
	return true
}

func randomSocketName() string {
	return "bridge-" + uuid.NewString() + ".sock"
}

func decodeInitResult(out string, result *InitResult) error {
	if err := json.Unmarshal([]byte(out), result); err != nil {
		return fmt.Errorf("decode remote-init reply: %w", err)
	}
	if result.SocketPath == "" {
		return errors.New("remote-init returned empty socket path")
	}
	return nil
}
