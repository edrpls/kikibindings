# kikibindings

My KDE Plasma global shortcuts. They install as a single **Kikibindings**
group in System Settings > Shortcuts, with one entry per shortcut.

| Shortcut | Default key | Runs |
|---|---|---|
| Vicinae Clipboard History | Meta+Ctrl+Alt+Shift+C | `vicinae deeplink "vicinae://launch/clipboard/history?toggle=true"` |
| Vicinae Emoji Search | Meta+Ctrl+Alt+Shift+Space | `vicinae deeplink "vicinae://launch/core/search-emojis?toggle=true"` |

Requires KDE Plasma 6.0.3 or newer (earlier versions, including Plasma 5,
can't load shortcuts this way), bash 4.4+, and the programs the shortcuts
run ([Vicinae](https://vicinae.com) for the ones above). The script uses
`kwriteconfig6`, `kreadconfig6`, `kbuildsycoca6` and `gdbus`, which every
Plasma 6 desktop has, plus GNU coreutils. The version check needs
`plasmashell` on the `PATH` and is skipped without it.

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
  by default aren't seen. Inside a session, a default key the script can't
  check (media and volume keys, `Menu`, keypad keys, or any key when
  kglobalaccel doesn't answer) is also left unbound. An unbound shortcut
  counts as your choice: it stays unbound until you give it a key.
- Keys you change in System Settings are kept across updates, and
  *Reset to default* goes back to the key in the table above (once
  `./install.sh` has been run since your last `git pull`).
- If Plasma doesn't pick up an update, the script says so and exits with an
  error; log out and back in to load it.
- Re-running when nothing changed only makes sure Plasma has the shortcuts
  loaded with the right keys, which also repairs an interrupted run.
- When the file changed, the old copy is saved to
  `~/.local/state/kikibindings/` first (the last 10 are kept).

`./install.sh --uninstall` removes the group, including any keys you
customised for it, after saving a backup the same way. If the file is
already gone, it still clears those keys.

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
  shows it (`Meta+Ctrl+Alt+Shift+T`, `Meta+F5`, `Ctrl+Alt+Space`). Give a
  single key (no commas, so the comma key can't be a default), made of
  modifiers plus a letter, digit, punctuation, `F1`–`F35`, `Space`,
  `Return`, `Tab`, `Esc`, arrows, `Home`/`End`, `PgUp`/`PgDown`, `Ins`/`Del`
  or `Print`; for other keys, leave the default out and bind it in System
  Settings. At least one shortcut in the file needs a default key, or Plasma
  won't load the group.
- Put URLs and other arguments with special characters in double quotes,
  and write a literal `%` as `%%` (`%20` → `%%20`), since `%` starts a
  field code in `Exec`.
  Don't make the shortcut with System Settings > Shortcuts > *Add Command*
  and copy it over: that dialog breaks URLs that have a query string
  (`?toggle=true`).
- Don't rename an action id once it's in use; custom keys are stored by id.

Then check it with `desktop-file-validate net.local.kikibindings.desktop`,
run `./install.sh`, and add a row to the table above.

## License

[MIT](LICENSE)
