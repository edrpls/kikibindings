#!/usr/bin/env bash
# Install the Kikibindings KDE Plasma global shortcuts for the current user.
#
# All shortcuts live in one file, net.local.kikibindings.desktop: each
# [Desktop Action] is one shortcut, and its X-KDE-Shortcuts key is the
# default binding. Plasma's kglobalaccel picks the file up from
# ~/.local/share/applications and shows it as a single "Kikibindings" group
# in System Settings > Shortcuts.
#
# Installing never touches a binding you changed yourself (kglobalaccel keeps
# those in kglobalshortcutsrc). The only thing it adds there is "none" for a
# new shortcut whose default key is already used by something else;
# --uninstall deletes the group's entries.
#
# Re-running is safe; if the installed file is already current, nothing
# happens.

set -euo pipefail

if ((BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 4))); then
	echo "${0##*/} needs bash 4.4 or newer" >&2
	exit 1
fi

usage() {
	cat <<EOF
Usage: ${0##*/} [--dry-run | --list | --uninstall | --help]

Install or update the Kikibindings shortcuts.

Options:
  -n, --dry-run    print what would be done without changing anything
  -l, --list       list the shortcuts and whether they're installed
  -u, --uninstall  remove the shortcuts (your custom keys are forgotten too)
  -h, --help       show this help
EOF
}

mode=install
dry_run=0
while (($#)); do
	case $1 in
	-n | --dry-run) dry_run=1 ;;
	-l | --list) mode=list ;;
	-u | --uninstall) mode=uninstall ;;
	-h | --help) usage; exit 0 ;;
	*) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
	esac
	shift
done

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
id=net.local.kikibindings.desktop
src="$repo_dir/$id"
apps_dir="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
dest="$apps_dir/$id"
backup_dir="${XDG_STATE_HOME:-$HOME/.local/state}/kikibindings"
shortcuts_rc="${XDG_CONFIG_HOME:-$HOME/.config}/kglobalshortcutsrc"

info() { printf '  %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }

# Run a command, or just print it in dry-run mode.
run() {
	if ((dry_run)); then
		printf '  [dry-run] %s\n' "$*"
	else
		"$@"
	fi
}

first_cmd() {
	local c
	for c in "$@"; do
		command -v "$c" >/dev/null 2>&1 && { echo "$c"; return 0; }
	done
	return 1
}

# Value of a key in a group of a .desktop file.
desktop_value() {
	local file=$1 group=$2 key=$3
	awk -v group="[$group]" -v key="$key" '
		{ sub(/\r$/, "") }
		/^\[/ { in_group = ($0 == group); next }
		in_group && index($0, key "=") == 1 { print substr($0, length(key) + 2); exit }
	' "$file"
}

# Action ids listed in the file's Actions= key, one per line.
desktop_actions() {
	desktop_value "$1" "Desktop Entry" Actions | tr ';' '\n' | sed '/^$/d'
}

# First key sequence in an X-KDE-Shortcuts value. Several are separated by
# commas; a trailing "," after a modifier is the comma key itself.
first_key() {
	local value=$1
	if [[ $value == *+,* ]]; then
		echo "${value%%+,*}+,"
	else
		echo "${value%%,*}"
	fi
}

# Convert a key sequence such as "Meta+Ctrl+Alt+Shift+C" to the integer Qt
# uses on D-Bus (modifier flags | key code). Fails on keys it doesn't know.
key_to_int() {
	local seq=$1 mods=0 key part n
	[[ -n $seq ]] || return 1
	if [[ $seq == *++ || $seq == + ]]; then
		key=+
		seq=${seq%+}
	else
		key=${seq##*+}
	fi
	seq=${seq%"$key"}
	local -a parts=()
	[[ -n $seq ]] && IFS=+ read -ra parts <<<"${seq%+}"
	for part in "${parts[@]}"; do
		case ${part,,} in
		shift) ((mods |= 0x02000000)) ;;
		ctrl | control) ((mods |= 0x04000000)) ;;
		alt) ((mods |= 0x08000000)) ;;
		meta | super | win) ((mods |= 0x10000000)) ;;
		*) return 1 ;;
		esac
	done
	case ${key,,} in
	space) n=0x20 ;;
	plus) n=0x2b ;;
	esc | escape) n=0x01000000 ;;
	tab) n=0x01000001 ;;
	backspace) n=0x01000003 ;;
	return) n=0x01000004 ;;
	enter) n=0x01000005 ;;
	ins | insert) n=0x01000006 ;;
	del | delete) n=0x01000007 ;;
	pause) n=0x01000008 ;;
	print) n=0x01000009 ;;
	home) n=0x01000010 ;;
	end) n=0x01000011 ;;
	left) n=0x01000012 ;;
	up) n=0x01000013 ;;
	right) n=0x01000014 ;;
	down) n=0x01000015 ;;
	pgup | pageup) n=0x01000016 ;;
	pgdown | pagedown) n=0x01000017 ;;
	f[1-9] | f[1-2][0-9] | f3[0-5]) n=$((0x01000030 + ${key:1} - 1)) ;;
	*)
		# Single printable character: Qt's key code is its (uppercase) code point.
		[[ ${#key} -eq 1 && $key == [[:graph:]] ]] || return 1
		printf -v n '%d' "'${key^^}"
		;;
	esac
	echo $((mods | n))
}

# --- inspect the repo file -------------------------------------------------

[[ -f $src ]] || { echo "Missing $src" >&2; exit 1; }
mapfile -t actions < <(desktop_actions "$src")
((${#actions[@]})) || { echo "No Actions= in $src" >&2; exit 1; }

declare -A action_name action_key
for action in "${actions[@]}"; do
	action_name[$action]=$(desktop_value "$src" "Desktop Action $action" Name)
	action_key[$action]=$(first_key "$(desktop_value "$src" "Desktop Action $action" X-KDE-Shortcuts)")
	if [[ -z ${action_name[$action]} ]]; then
		echo "$src: [Desktop Action $action] is missing or has no Name" >&2
		exit 1
	fi
done

installed_actions=()
if [[ -f $dest ]]; then
	mapfile -t installed_actions < <(desktop_actions "$dest")
fi
is_installed_action() {
	local a
	for a in "${installed_actions[@]}"; do [[ $a == "$1" ]] && return 0; done
	return 1
}

# Default key of an action in the installed copy of the file.
installed_key() {
	first_key "$(desktop_value "$dest" "Desktop Action $1" X-KDE-Shortcuts)"
}

if [[ $mode == list ]]; then
	printf '%-22s %-28s %-28s %s\n' ACTION NAME "DEFAULT KEY" STATUS
	for action in "${actions[@]}"; do
		status="not installed"
		key=${action_key[$action]:-(none)}
		if is_installed_action "$action"; then
			status=installed
			old=$(installed_key "$action")
			if [[ $old != "${action_key[$action]}" ]]; then
				status="installed with default ${old:-(none)}"
			fi
		fi
		printf '%-22s %-28s %-28s %s\n' "$action" "${action_name[$action]}" "$key" "$status"
	done
	if [[ -f $dest ]] && ! cmp -s "$src" "$dest"; then
		echo "The installed file differs from the repo; run ${0##*/} to update it."
	fi
	exit 0
fi

# --- tools and session -----------------------------------------------------

kwriteconfig=$(first_cmd kwriteconfig6 kwriteconfig5) || {
	echo "kwriteconfig6 not found; is this a KDE Plasma system?" >&2
	exit 1
}
kreadconfig=$(first_cmd kreadconfig6 kreadconfig5) || {
	echo "kreadconfig6 not found; is this a KDE Plasma system?" >&2
	exit 1
}
kbuildsycoca=$(first_cmd kbuildsycoca6 kbuildsycoca5 || true)

# KIKIBINDINGS_NO_SESSION=1 pretends there is no Plasma session: no D-Bus
# calls and no KService cache rebuild. Use it with a throwaway
# XDG_CONFIG_HOME / XDG_DATA_HOME to test without touching your desktop.
have_session=0
if [[ ${KIKIBINDINGS_NO_SESSION:-} != 1 ]] && command -v gdbus >/dev/null 2>&1 &&
	gdbus introspect --session -d org.kde.kglobalaccel -o /kglobalaccel >/dev/null 2>&1; then
	have_session=1
fi

kga() {
	gdbus call --session -d org.kde.kglobalaccel -o /kglobalaccel \
		-m "org.kde.KGlobalAccel.$1" "${@:2}"
}

# True while kglobalaccel has the Kikibindings component loaded.
component_loaded() {
	[[ $(kga allActionsForComponent "['$id']" 2>/dev/null) == *"'$id'"* ]]
}

# Rebuild the KService cache; kglobalaccel watches it and (un)loads the
# component accordingly. Waits for the component to reach the wanted state
# ("loaded" or "unloaded"). The cache rebuild occasionally goes unnoticed,
# so if nothing happens within 3 s, bump the directory's mtime and rebuild
# once more.
refresh() {
	local want=$1 attempt i
	[[ -n $kbuildsycoca && ${KIKIBINDINGS_NO_SESSION:-} != 1 ]] || return 0
	if ((dry_run)); then
		run "$kbuildsycoca"
		return 0
	fi
	for attempt in 1 2; do
		((attempt == 1)) || touch "$apps_dir"
		"$kbuildsycoca" >/dev/null 2>&1 || true
		((have_session)) || return 0
		for ((i = 0; i < 30 * attempt; i++)); do
			if component_loaded; then
				[[ $want == loaded ]] && return 0
			else
				[[ $want == unloaded ]] && return 0
			fi
			sleep 0.1
		done
	done
	return 1
}

# Back up the installed file (if any) before replacing or removing it.
# Keeps the 10 most recent backups.
backup_installed() {
	[[ -f $dest ]] || return 0
	local bak old
	bak="$backup_dir/$id.$(date +%Y%m%d-%H%M%S)"
	if ((dry_run)); then
		printf '  [dry-run] back up %s to %s\n' "$dest" "$bak"
		return 0
	fi
	mkdir -p "$backup_dir"
	cp "$dest" "$bak"
	info "previous file saved as $bak"
	while read -r old; do
		rm -f "$old"
	done < <(ls -1t "$backup_dir/$id".* 2>/dev/null | tail -n +11)
}

# The binding the user has set for an action, if any ("none" counts).
user_binding() {
	"$kreadconfig" --file kglobalshortcutsrc --group services --group "$id" --key "$1"
}

# True if a shortcut outside Kikibindings already uses this key sequence.
# (Kikibindings' own keys are tracked in $claimed, since they may be about
# to change.) Keys key_to_int can't convert count as taken in a session,
# because the config scan below can't see everything.
key_taken() {
	local seq=$1 keyint
	if ((have_session)); then
		keyint=$(key_to_int "$seq") || return 0
		# One tuple per holder; the third field is the holder's component.
		kga getGlobalShortcutsByKey "$keyint" | awk -v id="$id" -v q="'" '
			{ n = split($0, tuples, /\), \(/) }
			END {
				for (i = 1; i <= n; i++)
					if (index(tuples[i], q ", " q) && !index(tuples[i], ", " q id q ", ")) exit 0
				exit 1
			}'
		return
	fi
	# No session: look for it as an active binding in the config. Entries are
	# "action=key[\tkey...],default,description", with \t written literally.
	# Shortcuts left at their default aren't listed, so this can miss some.
	[[ -f $shortcuts_rc ]] || return 1
	awk -v seq="$seq" '
		/^\[/ || !/=/ { next }
		{
			value = substr($0, index($0, "=") + 1)
			split(value, fields, ",")
			n = split(fields[1], keys, /\\t|\t/)
			for (i = 1; i <= n; i++) if (keys[i] == seq) found = 1
		}
		END { exit !found }
	' "$shortcuts_rc"
}

# --- uninstall -------------------------------------------------------------

if [[ $mode == uninstall ]]; then
	if [[ ! -f $dest ]]; then
		echo "Kikibindings is not installed."
		exit 0
	fi
	echo "Removing $dest"
	backup_installed
	run rm "$dest"
	refresh unloaded || warn "kglobalaccel still has the shortcuts loaded; they'll be gone after you log out"
	# Forget every custom key in the group, including ones for shortcuts
	# that have since been removed from the file.
	if [[ -f $shortcuts_rc ]]; then
		while read -r key; do
			run "$kwriteconfig" --file kglobalshortcutsrc --group services --group "$id" --key "$key" --delete
		done < <(awk -v group="[services][$id]" '
			/^\[/ { in_group = ($0 == group); next }
			in_group && /=/ { print substr($0, 1, index($0, "=") - 1) }
		' "$shortcuts_rc")
	fi
	echo "Done."
	exit 0
fi

# --- install / update ------------------------------------------------------

if [[ -f $dest ]] && cmp -s "$src" "$dest"; then
	if ((have_session)) && ! component_loaded; then
		# A previous run installed the file but Plasma never loaded it.
		echo "Kikibindings is installed but not loaded; loading it."
		if ! refresh loaded; then
			warn "kglobalaccel still didn't load the shortcuts; log out and back in"
			exit 1
		fi
	fi
	echo "Kikibindings is up to date (${#actions[@]} shortcuts)."
	exit 0
fi

if ((!have_session)); then
	echo "No Plasma session found; the shortcuts will load at your next login."
fi

# Shortcuts that will get a new default key: ones new to this machine, and
# ones whose default changed in the repo, unless the user set their own key.
needs_check() {
	[[ -z $(user_binding "$1") ]] || return 1
	! is_installed_action "$1" || [[ $(installed_key "$1") != "${action_key[$1]}" ]]
}

# Check those keys. If one is taken (or two of them are the same), bind that
# shortcut to "none" instead, so it doesn't fight with the existing one.
declare -A claimed=()
unbound=()
# Keys held by the other installed Kikibindings shortcuts. Bindings left at
# their default aren't in kglobalshortcutsrc, so work them out here.
for action in "${actions[@]}"; do
	is_installed_action "$action" || continue
	needs_check "$action" && continue
	key=$(user_binding "$action")
	[[ -n $key ]] || key=${action_key[$action]}
	[[ -n $key && $key != none ]] && claimed[$key]=1
done
for action in "${actions[@]}"; do
	key=${action_key[$action]}
	name=${action_name[$action]}
	needs_check "$action" || continue
	exec_line=$(desktop_value "$src" "Desktop Action $action" Exec)
	program=${exec_line%% *}
	if [[ -n $program ]] && ! command -v "$program" >/dev/null 2>&1; then
		warn "$name: '$program' is not in PATH; the shortcut won't do anything until it is"
	fi
	[[ -n $key ]] || continue
	if [[ -n ${claimed[$key]:-} ]] || key_taken "$key"; then
		warn "$name: $key is already used by another shortcut, or can't be checked; leaving it unbound"
		info "pick a key in System Settings > Shortcuts > Kikibindings"
		run "$kwriteconfig" --file kglobalshortcutsrc --group services --group "$id" --key "$action" none
		unbound+=("$action")
	else
		claimed[$key]=1
	fi
done

if [[ -f $dest ]]; then
	echo "Updating $dest"
	backup_installed
	# kglobalaccel only reads the file when it first loads the component, so
	# unload it first to make it see new or changed shortcuts.
	if ((have_session)) && component_loaded; then
		run rm "$dest"
		if ! refresh unloaded; then
			run install -m 644 "$src" "$dest"
			warn "kglobalaccel didn't unload the old shortcuts; log out and back in to load the new ones"
			exit 1
		fi
	fi
else
	echo "Installing $dest"
fi
run mkdir -p "$apps_dir"
run install -m 644 "$src" "$dest"

if ! refresh loaded; then
	warn "kglobalaccel didn't load the shortcuts; they should appear after you log out and back in"
	exit 1
fi

# kglobalaccel doesn't re-read kglobalshortcutsrc, so tell it about the
# "none" bindings directly (flags 6 = SetPresent | NoAutoloading).
if ((have_session && !dry_run)); then
	for action in "${unbound[@]}"; do
		name=${action_name[$action]//\\/\\\\}
		name=${name//\'/\\\'}
		action_esc=${action//\\/\\\\}
		action_esc=${action_esc//\'/\\\'}
		kga setShortcut "['$id', '$action_esc', 'Kikibindings', '$name']" '@ai []' 6 >/dev/null ||
			warn "couldn't unbind ${action_name[$action]} live; it will be unbound after re-login"
	done
fi

for action in "${actions[@]}"; do
	key=$(user_binding "$action")
	[[ " ${unbound[*]} " == *" $action "* ]] && key=none
	[[ -n $key ]] || key=${action_key[$action]:-none}
	info "${action_name[$action]}: $key"
done
echo "Done. Change keys in System Settings > Shortcuts > Kikibindings."
