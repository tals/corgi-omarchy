# Corgi for Omarchy

[Corgi](https://corgi.computer) in the Omarchy bar. See what your agents are
doing, jump to one that needs you, open detected web links, and keep an eye on
each account's limits and spend.

```sh
omarchy plugin add https://github.com/tals/corgi-omarchy --enable
```

Enabling the plugin opens a terminal that installs Corgi and starts
onboarding. If you close it, click the corgi to try again. If Corgi is
already installed, the plugin uses it.

Once running, click the corgi to open the agent list. Click an agent to
bring its terminal forward, or a link to open it in your browser. Arrow
keys and Enter work too.

Update or remove:

```sh
omarchy plugin update corgi.computer
omarchy plugin remove corgi.computer
```

Requires Omarchy with shell plugin support. Corgi installs to
`~/.local/share/corgi` and keeps itself up to date; updating the plugin brings
a new widget and panel. Removing the plugin removes the Corgi it installed,
keeping your sessions and settings.

For a published test build, use the separate test plugin repository:

```sh
omarchy plugin add https://corgi.computer/test/corgi.computer.git --enable
```

If Corgi is already installed, switch it to the test channel once with
`curl -fsSL https://corgi.computer/test/install.sh | bash`.
Adding or updating a plugin preserves an existing Corgi installation.

Plugin development and release commands are in [HACKING.md](HACKING.md).

Corgi itself: [tals/corgi](https://github.com/tals/corgi). Working on this
plugin: [HACKING.md](HACKING.md). MIT licensed.
