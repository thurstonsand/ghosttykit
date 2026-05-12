// Command gty controls GhosttyKit local and bridged terminal sessions.
package main

import (
	"fmt"
	"os"

	ghosttykit "github.com/thurstonsand/ghosttykit/sdk/go"
)

func main() {
	if len(os.Args) > 1 && os.Args[1] == "version" {
		fmt.Printf("gty %s protocol=%d\n", ghosttykit.Version, ghosttykit.ProtocolVersion)
		return
	}

	fmt.Fprintln(os.Stderr, "gty: command implementation has not been extracted yet")
	os.Exit(2)
}
