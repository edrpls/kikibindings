# kikibindings

KDE Plasma global shortcuts. All of them live in one file,
`net.local.kikibindings.desktop`: each `[Desktop Action]` is a shortcut, and
Plasma shows the file as one "Kikibindings" group. `install.sh` installs it.
README.md explains the format and how to add a shortcut.

## Review rule (required)

Before any new branch is pushed, including the repo's first push, a panel of
AI reviewers reviews it, and confirmed findings are fixed first. If those
fixes change how `install.sh` behaves, review the fixes again.

- **Panel:** three Sonnet reviewers run in parallel as subagents (Agent
  tool, `model: sonnet`), each with its own focus:
  - (a) `install.sh` correctness and edge cases;
  - (b) KDE / kglobalaccel / KService behaviour;
  - (c) docs, consistency and publish-readiness.
- **Opus or Fable by complexity:** use your judgment, and for a focus the
  change makes complex, use an Opus (`model: opus`) or Fable
  (`model: fable`) reviewer instead of Sonnet. Typical reasons: a large
  rewrite of `install.sh`, a change to what it writes or deletes outside the
  repo, anything that runs at login, or Sonnet reviewers contradicting each
  other on a blocker. Pick Fable over Opus when the change could affect
  shortcuts outside the Kikibindings group, or when an Opus review was split
  on a blocker.
- **Reviewers are read-only.** They may run `install.sh` only in a sandbox
  (see Testing), and may make read-only D-Bus queries.
- **Record:** in the PR description, or in the commit message when there is
  no PR, list the models and the number of reviewers, the findings, and what
  was done about each. Findings that weren't fixed are listed as declined,
  with the reason.

## Conventions

- The file name `net.local.kikibindings.desktop` is the kglobalaccel
  component id, and action ids are the keys users' custom bindings are
  stored under. Don't rename either.
- `X-KDE-GlobalShortcutType=Service` keeps the group from getting a useless
  "launch Kikibindings" entry; the top-level `Exec=true` exists only to make
  the file valid.
- Quote URLs in `Exec=`. Never create entries through System Settings >
  Shortcuts > Add Command: it mangles URLs with query strings.
- `install.sh` must stay idempotent and must never change a binding the user
  set. The only thing it writes to `kglobalshortcutsrc` is `none` for a
  shortcut that is new (or whose default changed) when its default key is
  taken. kglobalaccel only reads the file when
  it loads the component, so updates unload and reload the component.
- kglobalaccel only writes keys that differ from the default, so the
  user's custom keys are exactly the entries under
  `[services][net.local.kikibindings.desktop]`; uninstall deletes those.
- Keep the README table in sync with the `.desktop` file.

## Testing

```sh
S=$(mktemp -d)
XDG_CONFIG_HOME=$S/cfg XDG_DATA_HOME=$S/data XDG_STATE_HOME=$S/state \
  KIKIBINDINGS_NO_SESSION=1 bash ./install.sh [--dry-run|--list|--uninstall]
```

`KIKIBINDINGS_NO_SESSION=1` (exactly `1`) skips all D-Bus calls and the KService cache
rebuild, so the live desktop isn't touched. Check `desktop-file-validate
net.local.kikibindings.desktop` after editing the file. Test the live path
(update that adds and removes an action, uninstall, reinstall) only on your
own session, and restore it afterwards.
