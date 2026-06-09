# AGENTS.md

With the advent of LLMs and coding harnesses like Claude Code, Codex, and Pi, I and many others find ourselves in the terminal far more often than ever before. I've been experimenting with a lot of different setups, between Neovim, tmux, zellij, Ghostty, iTerm2, and have found that I really just want the most straightforward surface as possible. This project focuses on making Ghostty, with its native windows, tabs, splits, panes, and terminals, work for all of my workflows by building on those primitives as well as Ghostty's control plane (i.e. AppleScript on macOS).

## Project context

See @CONTEXT.md for terminology and architecture vocabulary.

## Ethos

As I used the terminal more and more, I started drifting away from my prior IDE of choice VSCode, since I just wasn't happy with its built-in terminal. I tried iTerm2 for a little while, but had also learned about Ghostty, and really liked it. So I mained Ghostty+nvim, with nvim in its own tab, and agents in their own tabs. This felt inefficient, so I tried out zellij and then tmux to better handle window management, especially with vim-tmux-navigator. But I had this nagging feeling in the back of my mind that it seemed really wasteful to bring in the whole extra abstraction layer of tmux just for window management, especially since Ghostty ostensibly already supported it. I looked into it more, and thought Ghostty had potential to do everything I wanted, but its control plane of AppleScript was a little too awkward to use easily. So I started `ghosttykit` as a way to fit Ghostty with my desired workflows.

## Design

This is a human-first project, as it builds towards improving the human experience of collaborating with coding agents in the Ghostty terminal, which may include editors, coding harnesses, and shells. `ghosttykitd` and the SDKs are the substrate that enable the integrations that make Ghostty an even better developer experience, some of which are contained in this repo (`nvim plugin`, `pi-paste`, `gty ssh`). While it may enable coding agents to effectively automate their own environment, that's a bonus.

Treat `ghosttykitd` as the owner of Ghostty control. Integrations should not affect Ghostty directly. They should use `gty`, an SDK, or the public daemon protocol. If a new Ghostty capability is needed, expose it through the shared protocol/SDK layer instead of hiding it inside one integration.

## Core principles

- Prefer Ghostty capabilities and concepts where they apply
- Be willing to pursue unusual workflow ideas
- But strive to implement them in direct, boring, readable, maintainable code
- Keep the core as small as possible, and prefer composing existing capabilities instead of building new ones
- SDKs and protocols should be flexible enough for new integrations to compose capabilities in workflows I did not predict.
- Never be afraid to suggest deep refactors when it could make the code more direct; backwards compatibility is to be avoided unless instructed otherwise
- Avoid unnecessary abstraction. Be ambitious about structural simplification
- Treat the docs as first class citizens. If there is a change in behavior that a downstream user of the SDK would notice, it should be captured in the relevant doc.

## Code style

See @DEV.md for code style and development commands.
