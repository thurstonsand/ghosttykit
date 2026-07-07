#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "smoke-real-daemon: macOS is required" >&2
  exit 2
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GTY_BIN="${GTY_BIN:-$repo_root/cli/gty/gty}"
GHOSTTYKITD_BIN="${GHOSTTYKITD_BIN:-$repo_root/daemon/ghosttykitd/ghosttykitd}"
# The daemon resolves gty as a sibling binary; in-repo they live apart, so pin it for spawn wrapping.
export GTY_BIN

bridge_mode=0
for arg in "$@"; do
  case "$arg" in
    --bridge)
      bridge_mode=1
      ;;
    -h|--help)
      echo "usage: $0 [--bridge]" >&2
      exit 0
      ;;
    *)
      echo "smoke-real-daemon: unknown argument: $arg" >&2
      echo "usage: $0 [--bridge]" >&2
      exit 2
      ;;
  esac
done

if [[ ! -x "$GTY_BIN" ]]; then
  echo "smoke-real-daemon: gty not found at $GTY_BIN; run just build-go or set GTY_BIN" >&2
  exit 2
fi
if [[ ! -x "$GHOSTTYKITD_BIN" ]]; then
  echo "smoke-real-daemon: ghosttykitd not found at $GHOSTTYKITD_BIN; run just build-swift or set GHOSTTYKITD_BIN" >&2
  exit 2
fi

if [[ "$(osascript -e 'application "Ghostty" is running')" != "true" ]]; then
  echo "smoke-real-daemon: Ghostty is not running" >&2
  exit 2
fi

daemon_pid=""
daemon_log=""
daemon_socket=""
fake_ssh_dir=""

start_local_daemon() {
  daemon_socket="$(mktemp -u /tmp/ghosttykit-smoke.XXXXXX).sock"
  daemon_log="$(mktemp /tmp/ghosttykit-smoke-log.XXXXXX)"
  GTY_SOCK="$daemon_socket" "$GHOSTTYKITD_BIN" >"$daemon_log" 2>&1 &
  daemon_pid="$!"
  export GTY_SOCK="$daemon_socket"

  for _ in {1..100}; do
    [[ -S "$daemon_socket" ]] && return
    if ! kill -0 "$daemon_pid" 2>/dev/null; then
      echo "smoke-real-daemon: ghosttykitd exited before socket was ready" >&2
      cat "$daemon_log" >&2
      exit 1
    fi
    sleep 0.1
  done

  echo "smoke-real-daemon: ghosttykitd did not create socket $daemon_socket" >&2
  cat "$daemon_log" >&2
  exit 1
}

if [[ -z "${GTY_SOCK:-}" ]]; then
  start_local_daemon
fi

SMOKE_TTY="${GTY_SMOKE_TTY:-/dev/ghosttykit-smoke-$$}"
export GTY_TTY="$SMOKE_TTY"

run() {
  printf '→ %s\n' "$*" >&2
  if [[ "$bridge_mode" -eq 1 ]]; then
    "$GTY_BIN" ssh --require-bridge --debug-no-bootstrap ghosttykit-smoke -- "$GTY_BIN" "$@"
    return
  fi
  "$GTY_BIN" "$@"
}

setup_fake_ssh() {
  fake_ssh_dir="$(mktemp -d /tmp/ghosttykit-smoke-ssh.XXXXXX)"
  cat >"$fake_ssh_dir/ssh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

remote_forward=""
args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o)
      shift 2
      ;;
    -R)
      remote_forward="$2"
      shift 2
      ;;
    -t)
      shift
      ;;
    --)
      shift
      break
      ;;
    *)
      args+=("$1")
      shift
      ;;
  esac
done

if [[ $# -lt 1 ]]; then
  exit 0
fi
host="$1"
shift
command="$*"
: "$host"

if [[ "$command" == "command -v gty"* ]]; then
  printf '%s\n' "$GTY_BIN"
  exit 0
fi

if [[ -n "$remote_forward" ]]; then
  remote_socket="${remote_forward%%:*}"
  local_socket="${remote_forward#*:}"
  if [[ "$command" =~ ^GTY_SOCK=[^[:space:]]+[[:space:]](.*)$ ]]; then
    command="GTY_SOCK=$(printf '%q' "$local_socket") ${BASH_REMATCH[1]}"
  fi
fi

exec /bin/sh -lc "$command"
EOF
  chmod 755 "$fake_ssh_dir/ssh"
  export PATH="$fake_ssh_dir:$PATH"
  export GTY_BIN
}

expect() {
  local name="$1"
  local got="$2"
  local want="$3"
  if [[ "$got" != "$want" ]]; then
    echo "smoke-real-daemon: $name = $got, want $want" >&2
    exit 1
  fi
}

expect_nonempty() {
  local name="$1"
  local got="$2"
  if [[ -z "$got" ]]; then
    echo "smoke-real-daemon: $name was empty" >&2
    exit 1
  fi
}

expect_int() {
  local name="$1"
  local got="$2"
  if ! [[ "$got" =~ ^[0-9]+$ ]]; then
    echo "smoke-real-daemon: $name = $got, want integer" >&2
    exit 1
  fi
}

restore_clipboard() {
  if [[ -n "${old_clipboard_file:-}" && -f "$old_clipboard_file" ]]; then
    pbcopy <"$old_clipboard_file" || true
    rm -f "$old_clipboard_file"
  fi
}

cleanup() {
  run key-table deactivate --wait >/dev/null 2>&1 || true
  restore_clipboard
  if [[ -n "$fake_ssh_dir" ]]; then
    rm -rf "$fake_ssh_dir"
  fi
  if [[ -n "$daemon_pid" ]]; then
    kill "$daemon_pid" 2>/dev/null || true
    wait "$daemon_pid" 2>/dev/null || true
    rm -f "$daemon_socket"
  fi
}
trap cleanup EXIT

printf 'GhosttyKit real-daemon smoke test\n' >&2
printf 'mode: %s\n' "$([[ "$bridge_mode" -eq 1 ]] && echo bridge || echo direct)" >&2
printf 'gty: %s\n' "$GTY_BIN" >&2
printf 'ghosttykitd: %s\n' "$GHOSTTYKITD_BIN" >&2
printf 'GTY_SOCK: %s\n' "${GTY_SOCK:-<default>}" >&2
printf 'GTY_TTY: %s\n' "$GTY_TTY" >&2

if [[ "$bridge_mode" -eq 1 ]]; then
  setup_fake_ssh
  printf 'ssh: %s\n' "$fake_ssh_dir/ssh" >&2
fi

run doctor

run clear-cache --all --wait >/dev/null
terminal_id="$(run terminal-id --refresh)"
expect_nonempty terminal-id "$terminal_id"
if [[ "$terminal_id" == "dry-run-terminal" ]]; then
  echo "smoke-real-daemon: endpoint is dry-run, not the real daemon" >&2
  exit 1
fi
printf 'terminal-id: %s\n' "$terminal_id" >&2

cached_terminal_id="$(run terminal-id)"
expect cached-terminal-id "$cached_terminal_id" "$terminal_id"

count_before="$(run tab-terminal-count)"
expect_int tab-terminal-count "$count_before"
printf 'tab-terminal-count before split: %s\n' "$count_before" >&2

old_clipboard_file="$(mktemp -t ghosttykit-clipboard.XXXXXX)"
pbpaste >"$old_clipboard_file" || :
paste_text="ghosttykit smoke paste $(date +%s)"
printf '%s' "$paste_text" | pbcopy
paste_output="$(run paste)"
expect paste "$paste_output" "$paste_text"

run key-table activate nvim --wait >/dev/null
run key-table deactivate --wait >/dev/null

split_tty="$(run split right --focus original --command "/bin/sh -lc 'printf ghosttykit-smoke-split; sleep 8'" --wait)"
expect_nonempty split-tty "$split_tty"
if [[ "$split_tty" != /dev/* ]]; then
  echo "smoke-real-daemon: split-tty = $split_tty, want /dev/* path" >&2
  exit 1
fi
printf 'split tty: %s\n' "$split_tty" >&2
if [[ "$bridge_mode" -eq 0 ]]; then
  split_terminal_id="$(run terminal-id --tty "$split_tty")"
  expect_nonempty split-terminal-id "$split_terminal_id"
  if [[ "$split_terminal_id" == "$terminal_id" ]]; then
    echo "smoke-real-daemon: split terminal id matches origin terminal id" >&2
    exit 1
  fi
fi
count_after_split="$(run tab-terminal-count)"
expect_int tab-terminal-count-after-split "$count_after_split"
if (( count_after_split <= count_before )); then
  echo "smoke-real-daemon: split did not increase terminal count: before=$count_before after=$count_after_split" >&2
  exit 1
fi
printf 'tab-terminal-count after split: %s\n' "$count_after_split" >&2

run focus right --wait >/dev/null
run focus left --wait >/dev/null
run resize right --pixels 10 --wait >/dev/null
run resize left --pixels 10 --wait >/dev/null
run zoom --wait >/dev/null
run zoom --wait >/dev/null
run clear-cache --wait >/dev/null

if [[ "$bridge_mode" -eq 0 ]]; then
  osascript -e "tell application \"Ghostty\" to close terminal id \"$split_terminal_id\"" >/dev/null
  sleep 2

  # A fresh split usually recycles the just-freed pty, whose cache entry is now stale — the
  # spawn claim must overwrite it.
  second_tty="$(run split right --focus original --wait)"
  expect_nonempty second-split-tty "$second_tty"
  second_id="$(run terminal-id --tty "$second_tty")"
  expect_nonempty second-split-terminal-id "$second_id"
  if [[ "$second_tty" == "$split_tty" ]]; then
    if [[ "$second_id" == "$split_terminal_id" ]]; then
      echo "smoke-real-daemon: recycled pty kept its stale binding; claim did not overwrite" >&2
      exit 1
    fi
    printf 'claim overwrote stale binding on recycled pty %s\n' "$second_tty" >&2
  else
    printf 'pty not recycled (%s -> %s); overwrite path not exercised this run\n' "$split_tty" "$second_tty" >&2
  fi

  input_proof="$(mktemp -t ghosttykit-input-proof.XXXXXX)"
  rm -f "$input_proof"
  run input --tty "$second_tty" --submit --wait "printf smoke-input-proof > $input_proof"
  for _ in {1..150}; do
    [[ -f "$input_proof" ]] && break
    sleep 0.1
  done
  expect input-proof "$(cat "$input_proof" 2>/dev/null || true)" "smoke-input-proof"
  rm -f "$input_proof"

  osascript -e "tell application \"Ghostty\" to close terminal id \"$second_id\"" >/dev/null
fi

printf 'smoke-real-daemon: ok\n' >&2
