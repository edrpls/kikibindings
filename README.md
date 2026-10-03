# kikibindings

My KDE Plasma global shortcuts. They install as a single **Kikibindings**
group in System Settings > Shortcuts, with one entry per shortcut.

| Shortcut | Default key | Runs |
|---|---|---|
| Vicinae Clipboard History | Meta+Ctrl+Alt+Shift+C | `vicinae deeplink "vicinae://launch/clipboard/history?toggle=true"` |
| Vicinae Emoji Search | Meta+Ctrl+Alt+Shift+Space | `vicinae deeplink "vicinae://launch/core/search-emojis?toggle=true"` |

Requires Plasma 6 (Plasma 5 is untested) with `kwriteconfig6` and
`kreadconfig6`, bash 4.4+, and the programs the shortcuts run
([Vicinae](https://vicinae.com) for the ones above). `gdbus` and
`kbuildsycoca6`, which every Plasma 6 desktop has, let the shortcuts load
without logging out.

## Install

```sh
git clone https://github.com/edrpls/kikibindings.git
cd kikibindings
./install.sh --list      # -l: the shortcuts and whether they're installed
./install.sh --dry-run   # -n: what would change
./install.sh             # install, or update after a git pull
./install.sh --help      # -h: all options
```

`install.sh` copies `net.local.kikibindings.desktop` to
`~/.local/share/applications` and has Plasma load it, so the shortcuts work
right away. If you run it outside a Plasma session they load at your next
login.

- A new shortcut gets its default key, unless that key is already used by
  something else. Then it's left unbound and you get a warning; pick a key
  in System Settings > Shortcuts > Kikibindings. The same goes for a
  shortcut whose default key changed in the repo. This check is only
  complete inside a Plasma session; without one, keys other shortcuts use
  by default aren't seen.
- Keys you change in System Settings are kept across updates, and
  *Reset to default* goes back to the key in the table above (once
  `./install.sh` has been run since your last `git pull`).
- If Plasma doesn't pick up an update, the script says so and exits with an
  error; log out and back in to load it.
- Re-running when nothing changed does nothing. When the file changed, the
  old copy is saved to `~/.local/state/kikibindings/` first (the last 10
  are kept).

`./install.sh --uninstall` removes the group, including any keys you
customised for it, after saving a backup the same way.

## Adding a shortcut

Add a `[Desktop Action]` group to `net.local.kikibindings.desktop` and list
its id in `Actions=`:

```ini
Actions=vicinae-clipboard;vicinae-emoji;my-thing;

[Desktop Action my-thing]
Name=My Thing
Icon=my-thing
Exec=my-thing --toggle "https://example.com/?a=b"
X-KDE-Shortcuts=Meta+Ctrl+Alt+Shift+T
```

- `Name` is what System Settings shows. The group itself is listed under
  *Applications*.
- `X-KDE-Shortcuts` is the default key, written the way System Settings
  shows it (`Meta+Ctrl+Alt+Shift+T`, `Meta+F5`, `Ctrl+Alt+Space`). Give one
  key; leave it out for a shortcut with no default key.
- Put URLs and other arguments with special characters in double quotes.
  Don't make the shortcut with System Settings > Shortcuts > *Add Command*
  and copy it over: that dialog breaks URLs that have a query string
  (`?toggle=true`).
- Don't rename an action id once it's in use; custom keys are stored by id.

Then check it with `desktop-file-validate net.local.kikibindings.desktop`,
run `./install.sh`, and add a row to the table above.

## License

[MIT](LICENSE)
