package herdr

import (
	"fmt"
	"path"

	"github.com/thurstonsand/ghosttykit/cli/gty/internal/osc"
)

// Direction is a navigation direction, spelled the same way by Ghostty, Herdr, and this CLI.
type Direction string

// Navigation directions.
const (
	Left  Direction = "left"
	Down  Direction = "down"
	Up    Direction = "up"
	Right Direction = "right"
)

// ParseDirection validates a direction argument.
func ParseDirection(value string) (Direction, error) {
	direction := Direction(value)
	if _, known := nvimKeys[direction]; !known {
		return "", fmt.Errorf("unknown direction %q: want left, down, up, or right", value)
	}
	return direction, nil
}

// Navigator runs the innermost-first navigation ladder for one keypress: a Neovim window first,
// then a Herdr pane, then the outer Ghostty split. Herdr keybindings are its only caller; a
// Neovim already holding the key runs the remaining layers itself through ghosttykit.nvim.
type Navigator struct {
	API    API
	PaneID string
}

// Navigate moves one layer, or signals the outer layer when Herdr is at its edge. Every API
// failure ends the ladder where it stands, because moving outward on uncertain state would skip a
// layer the user expected to navigate.
func (n Navigator) Navigate(direction Direction) error {
	info, err := n.API.ProcessInfo(n.PaneID)
	if err != nil {
		return err
	}
	if info.RunsNvim() {
		return n.API.SendKeys(n.PaneID, []string{nvimKeys[direction]})
	}

	neighbor, err := n.API.Neighbor(n.PaneID, direction)
	if err != nil {
		return err
	}
	if neighbor.NeighborPaneID == "" {
		return n.signalOuterLayer(direction)
	}

	focus, err := n.API.FocusDirection(n.PaneID, direction)
	if err != nil {
		return err
	}
	if !focus.Changed {
		return fmt.Errorf("herdr did not focus the %s pane (%s)", direction, describeReason(focus.Reason))
	}
	return nil
}

// signalOuterLayer asks Herdr's foreground client to carry the direction outward as a window
// title. A gty herdr attach client removes that title from its SSH stream and focuses the Ghostty
// split itself; the clear that follows restores the normal title everywhere else.
// ghosttykit.nvim spells the same sentinel in nvim/lua/ghosttykit/nvim/herdr.lua.
func (n Navigator) signalOuterLayer(direction Direction) error {
	title, err := n.API.SetWindowTitle(osc.NavigationTitle(string(direction)))
	if err != nil {
		return err
	}
	if !title.Changed {
		return fmt.Errorf("herdr did not signal %s navigation to a client (%s)", direction, describeReason(title.Reason))
	}
	if _, err := n.API.ClearWindowTitle(); err != nil {
		return err
	}
	return nil
}

// RunsNvim reports whether the pane's foreground holds a Neovim that should receive the key.
func (p ProcessInfo) RunsNvim() bool {
	for _, process := range p.ForegroundProcesses {
		if nvimProcessNames[path.Base(process.Name)] {
			return true
		}
	}
	return false
}

func describeReason(reason string) string {
	if reason == "" {
		return "no reason given"
	}
	return reason
}

// nvimKeys is the key Herdr sends into a Neovim pane for each direction, and the set of
// directions this command accepts.
var nvimKeys = map[Direction]string{
	Left:  "ctrl+h",
	Down:  "ctrl+j",
	Up:    "ctrl+k",
	Right: "ctrl+l",
}

// nvimProcessNames are the foreground process names that defer a key to an inner Neovim. Pane
// titles, command-line fragments, and agent metadata are deliberately not consulted.
var nvimProcessNames = map[string]bool{
	"nvim": true,
}
