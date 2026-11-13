# Whiteboard over a tailnet

One Mac shows the boards (the *viewer*, here a MacBook Air). Agents on other
machines (the *hosts*: Macs and Linux boxes on the same Tailscale tailnet)
draw them through Whiteboard's MCP server, and you watch and edit them in
the viewer's Desktop.

This uses upstream's [Remote Hosts](../docs/remote-hosts.md) as it is. Each
host runs its own Whiteboard server next to its code, bound to `127.0.0.1`.
The viewer's Desktop reaches it through SSH to the host's tailnet name.
Nothing listens on the tailnet or the internet, and no token leaves a
machine except inside SSH.

Upstream supports Linux hosts only. This fork adds macOS hosts without
rebuilding Desktop:

- `whiteboard-macos-host`: the `whiteboard` command for a macOS host. With
  Whiteboard.app installed, the stock CLI waits for a local Desktop and
  ignores the server that `remote attach` starts. This wrapper points
  `mcp` and `api` at that server through `DEV_REVIEW_SERVER_DIR`, and starts
  it when the viewer has not attached yet.
- `sync-hosts.sh`: run on the viewer. It copies the viewer's signed
  Whiteboard.app and the wrapper to macOS hosts, installs the Linux server
  tarball pinned in the viewer's `product.json` (sha256 checked) on Linux
  hosts, and lists the hosts in Desktop's settings with
  `"review.remote.install": "never"`. Desktop's probe refuses macOS, and
  `never` skips it.

## Set up

### On the viewer (MacBook Air)

1. Install Whiteboard Desktop and its CLI as usual.
2. Make sure `ssh <alias>` works without prompts for every host. The aliases
   should point at tailnet names, for example
   `Host mac` with `HostName yessets-macbook-pro-23.taile0778.ts.net`.
3. Clone this fork and run:

   ```sh
   tailnet/sync-hosts.sh mac cachy zephyr
   ```

4. Restart Whiteboard Desktop, or wait for it to pick up the settings. Under
   Settings → Remote Hosts each host should read `online`.

Run `tailnet/sync-hosts.sh` with no arguments after Desktop updates itself.
A host on another version shows `incompatible` until you do.

`sync-hosts.sh` rewrites `settings.json` with Python's `json` module, so
comments in that file would make it fail. Desktop writes the file without
comments.

### On each host

Nothing to start: Desktop starts the server over SSH. Connect the agent to
the host's own `whiteboard mcp`, as on any machine:

- Claude Code:
  `claude plugin marketplace add devdotfast/whiteboard && claude plugin install whiteboard@devfast --scope user`,
  or `claude mcp add --scope user whiteboard -- sh -c 'exec "$HOME/.local/bin/whiteboard" mcp'`
- OpenCode:
  `opencode mcp add whiteboard --global -- sh -c 'exec "$HOME/.local/bin/whiteboard" mcp'`

Every board names a git checkout on the machine that draws it
(`target.repositoryPath`), so agents draw boards for repositories on their
own machine.

On a macOS host, do not open Whiteboard.app. Desktop would replace
`~/.local/bin/whiteboard` with its own shim and take over `~/.dev`. If that
happens, quit it and run `sync-hosts.sh <alias>` again from the viewer.

## What does not work on macOS hosts

- Language features (hovers, go to definition) in their boards. The macOS
  app bundle has no VS Code server; Linux hosts have one.
- Ask on a remote board, sharing, and traces: upstream does not support
  these for any remote host yet.

## Trust

The same as upstream's Remote Hosts: a host you add is trusted as much as
the viewer, and SSH is the boundary. Tailscale limits who can reach SSH.
Upstream's [trust model](../docs/remote-hosts.md#trust-model) applies as
written.
