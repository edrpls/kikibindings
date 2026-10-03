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
# shortcut that is new (or whose default key changed) when that key is
# already used by something else; --uninstall deletes the group's entries.
#
# Re-running is safe; if the installed file is already current, it only
# makes sure Plasma has the shortcuts loaded with the right keys.

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

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null && pwd)
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

# First key sequence in an X-KDE-Shortcuts value. kglobalaccel treats every
# comma there as a separator, so the comma key can't be a default.
first_key() {
	echo "${1%%,*}"
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
	# kglobalaccel splits X-KDE-Shortcuts at every comma; this script
	# supports a single default key, which it has to be able to convert.
	if [[ $(desktop_value "$src" "Desktop Action $action" X-KDE-Shortcuts) == *,* ]]; then
		echo "$src: $action: X-KDE-Shortcuts must be a single key (no commas)" >&2
		exit 1
	fi
	if [[ -n ${action_key[$action]} ]] && ! key_to_int "${action_key[$action]}" >/dev/null; then
		echo "$src: $action: unsupported default key '${action_key[$action]}'" >&2
		exit 1
	fi
done
# Plasma only picks the file up if at least one action has a default key.
if [[ -z $(printf '%s' "${action_key[@]}") ]]; then
	echo "$src: at least one shortcut needs an X-KDE-Shortcuts key" >&2
	exit 1
fi

installed_actions=()
# A symlinked install may point at this very file, so it can't tell which
# shortcuts are new; treat them all as new.
if [[ -f $dest && ! -L $dest ]]; then
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
		if [[ -L $dest ]]; then
			status="installed as a symlink; run ${0##*/} to replace it"
		elif is_installed_action "$action"; then
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

kwriteconfig=$(first_cmd kwriteconfig6) || {
	echo "kwriteconfig6 not found; this needs KDE Plasma 6.0.3 or newer" >&2
	exit 1
}
kreadconfig=$(first_cmd kreadconfig6) || {
	echo "kreadconfig6 not found; this needs KDE Plasma 6.0.3 or newer" >&2
	exit 1
}
kbuildsycoca=$(first_cmd kbuildsycoca6 || true)
# Plasma 6.0.3 is the first version whose kglobalaccel loads shortcuts from
# desktop actions and notices new or removed files without a re-login.
# KWin is released with kglobalaccel; plasmashell isn't asked because it
# can crash without a usable display, even for --version. Skipped when
# KWin isn't installed, and for --uninstall, which works on any Plasma 6.
if [[ $mode != uninstall ]] && { version_out=$(kwin_wayland --version 2>/dev/null) ||
	version_out=$(kwin_x11 --version 2>/dev/null); } &&
	[[ $version_out =~ ([0-9]+\.[0-9]+(\.[0-9]+)?) ]]; then
	plasma_version=${BASH_REMATCH[1]}
	if [[ $(printf '%s\n' 6.0.3 "$plasma_version" | sort -V | head -n1) != 6.0.3 ]]; then
		echo "Plasma $plasma_version is too old; this needs Plasma 6.0.3 or newer" >&2
		exit 1
	fi
fi

# KIKIBINDINGS_NO_SESSION=1 (any non-empty value) pretends there is no
# Plasma session: no D-Bus calls and no KService cache rebuild. Use it with a
# throwaway XDG_CONFIG_HOME / XDG_DATA_HOME to test without touching your
# desktop.
have_session=0
if [[ -z ${KIKIBINDINGS_NO_SESSION:-} ]] && command -v gdbus >/dev/null 2>&1 &&
	gdbus introspect --session -d org.kde.kglobalaccel -o /kglobalaccel >/dev/null 2>&1; then
	have_session=1
	if [[ -z $kbuildsycoca ]]; then
		echo "kbuildsycoca6 not found; it's needed to load the shortcuts" >&2
		exit 1
	fi
fi

kga() {
	gdbus call --session -d org.kde.kglobalaccel -o /kglobalaccel \
		-m "org.kde.KGlobalAccel.$1" "${@:2}"
}

# Keys of an action in kglobalaccel's allShortcutInfos output, as sorted
# integers separated by spaces: list 1 is the live keys, list 2 the
# defaults. Prints "missing " if the action isn't there. kglobalaccel shows
# "no key" as [0] in some places, so 0 is dropped.
action_keys() {
	awk -v a="$2" -v which="$3" -v q="'" '
		{ n = split($0, tuples, /\), \(/) }
		END {
			for (i = 1; i <= n; i++) {
				t = tuples[i]
				sub(/^[(\[]+/, "", t)
				if (index(t, q a q ", ") != 1) continue
				found = 1
				# Skip the strings: the key lists follow the last quote.
				sub(".*[" q "\"]", "", t)
				keys = ""
				for (k = 1; k <= which && match(t, /\[[0-9, ]*\]/); k++) {
					keys = substr(t, RSTART + 1, RLENGTH - 2)
					t = substr(t, RSTART + RLENGTH)
				}
				gsub(/,/, "", keys)
				print keys
			}
			if (!found) print "missing"
		}' <<<"$1" | tr ' ' '\n' | sed '/^0*$/d' | sort -n | tr '\n' ' '
}

# Live keys of all Kikibindings shortcuts, or fails.
live_infos() {
	local component
	component=$(kga getComponent "$id" | grep -o "'/[^']*'" | tr -d "'") &&
		gdbus call --session -d org.kde.kglobalaccel -o "$component" \
			-m org.kde.kglobalaccel.Component.allShortcutInfos
}

# True while kglobalaccel has the Kikibindings component loaded.
component_loaded() {
	[[ $(kga allActionsForComponent "['$id']" 2>/dev/null) == *"'$id'"* ]]
}

# True once kglobalaccel has every shortcut in the repo file loaded, with
# the repo's default keys (so an older version doesn't count).
component_complete() {
	local infos action want
	infos=$(live_infos 2>/dev/null) || return 1
	for action in "${actions[@]}"; do
		want=
		[[ -z ${action_key[$action]} ]] || want="$(key_to_int "${action_key[$action]}") "
		[[ $(action_keys "$infos" "$action" 2) == "$want" ]] || return 1
	done
}

# Rebuild the KService cache; kglobalaccel watches it and (un)loads the
# component accordingly. Waits for the component to reach the wanted state
# ("loaded" or "unloaded"). The cache rebuild occasionally goes unnoticed,
# so if nothing happens within 3 s, bump the directory's mtime and rebuild
# once more.
refresh() {
	local want=$1 attempt i
	[[ -n $kbuildsycoca && -z ${KIKIBINDINGS_NO_SESSION:-} ]] || return 0
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
				[[ $want == loaded ]] && component_complete && return 0
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
	bak="$backup_dir/$id.$(date +%Y%m%d-%H%M%S.%N)"
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
# to change.) Defaults are checked with key_to_int when the file is read, so
# the conversion here only fails if that check is ever bypassed; such keys
# count as taken.
key_taken() {
	local seq=$1 keyint
	if ((have_session)); then
		local holders
		keyint=$(key_to_int "$seq") || return 0
		# Holders of this exact key (0) or of chords containing it (1).
		# If kglobalaccel can't be asked, assume the key is taken.
		local type out
		holders=
		for type in 0 1; do
			out=$(kga globalShortcutsByKey "([$keyint],)" "($type,)") || return 0
			holders+="$out"$'\n'
		done
		# One tuple per holder; the third field is the holder's component.
		awk -v id="$id" -v q="'" '
			{
				n = split($0, tuples, /\), \(/)
				for (i = 1; i <= n; i++)
					if (index(tuples[i], q ", " q) && !index(tuples[i], ", " q id q ", ")) found = 1
			}
			END { exit !found }' <<<"$holders"
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

# kglobalaccel doesn't re-read kglobalshortcutsrc, and when it unloads the
# group it keeps the group's old keys in memory. So once the group is
# loaded, sync_live makes each shortcut's live keys match the bindings in
# $binding: the user's binding if there is one (including the "none" this
# script writes for conflicts), otherwise the default.
#
# snapshot_bindings must fill $binding before the group is (re)loaded:
# loading makes kglobalaccel rewrite its config about 500 ms later, from
# memory, which can drop a "none" this script just wrote or bring back keys
# from before an uninstall.
declare -A binding=()
snapshot_bindings() {
	local action
	# kglobalaccel saves key changes 500 ms after they happen; wait so a
	# change just made in System Settings is on disk.
	((!have_session || dry_run)) || sleep 0.6
	for action in "${actions[@]}"; do
		binding[$action]=$(user_binding "$action")
	done
}

sync_live() {
	local component infos action want k ki have wanted keys name action_esc
	local -a want_ints want_keys
	if ! infos=$(live_infos 2>/dev/null); then
		warn "couldn't read the live shortcuts; log out and back in if a key is wrong"
		return 0
	fi
	for action in "${actions[@]}"; do
		want=${binding[$action]}
		[[ -n $want ]] || want=${action_key[$action]}
		want_ints=()
		IFS=$'\t' read -ra want_keys <<<"${want//\\t/$'\t'}"
		for k in "${want_keys[@]}"; do
			[[ -n $k && $k != none ]] || continue
			# A key this script can't convert (keypad, media...) can only be a
			# binding the user set; leave it to kglobalaccel.
			if ! ki=$(key_to_int "$k"); then
				info "${action_name[$action]}: leaving '$k' to Plasma"
				continue 2
			fi
			want_ints+=("$ki")
		done
		have=$(action_keys "$infos" "$action" 1)
		if [[ $have == "missing " ]]; then
			warn "${action_name[$action]} isn't loaded by Plasma yet; log out and back in"
			continue
		fi
		wanted=$(printf '%s\n' "${want_ints[@]}" | sed '/^$/d' | sort -n | tr '\n' ' ')
		[[ $have == "$wanted" ]] && continue
		if ((${#want_ints[@]})); then
			keys="[$(printf '([%s],), ' "${want_ints[@]}")"
			keys="${keys%, }]"
		else
			keys='@a(ai) []'
		fi
		name=${action_name[$action]//\\/\\\\}
		name=${name//\'/\\\'}
		action_esc=${action//\\/\\\\}
		action_esc=${action_esc//\'/\\\'}
		# flags 6 = SetPresent | NoAutoloading: take these keys, not cached ones.
		if kga setShortcutKeys "['$id', '$action_esc', 'Kikibindings', '$name']" "$keys" 6 >/dev/null; then
			want=${want:-none}
			info "${action_name[$action]}: set live key to ${want//$'\t'/, } to match the config"
		else
			warn "couldn't set ${action_name[$action]} live; log out and back in if it's wrong"
		fi
	done
}

# --- uninstall -------------------------------------------------------------

if [[ $mode == uninstall ]]; then
	if [[ -e $dest || -L $dest ]]; then
		echo "Removing $dest"
		backup_installed
		run rm "$dest"
		refresh unloaded || warn "kglobalaccel still has the shortcuts loaded; they'll be gone after you log out"
	else
		echo "Kikibindings is not installed; removing any leftover settings."
	fi
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

if [[ -f $dest && ! -L $dest ]] && cmp -s "$src" "$dest"; then
	if ((have_session)); then
		snapshot_bindings
		if ! component_complete; then
			# A previous run installed the file but Plasma never loaded it,
			# or still has an older version of it loaded.
			echo "Plasma doesn't have the current shortcuts loaded; loading them."
			if component_loaded; then
				run rm "$dest"
				if ! refresh unloaded; then
					run install -m 644 "$src" "$dest"
					warn "kglobalaccel didn't unload the old shortcuts; log out and back in to load the new ones"
					exit 1
				fi
				run install -m 644 "$src" "$dest"
			fi
			if ! refresh loaded; then
				warn "kglobalaccel still didn't load the shortcuts; log out and back in"
				exit 1
			fi
		fi
		# Also repairs a run that stopped before syncing.
		if ((!dry_run)); then
			sync_live
		fi
	fi
	echo "Kikibindings is up to date (${#actions[@]} shortcuts)."
	exit 0
fi

if ((!have_session)); then
	echo "No Plasma session found; the shortcuts will load at your next login."
fi
snapshot_bindings

# Shortcuts that will get a new default key: ones new to this machine, and
# ones whose default changed in the repo, unless the user set their own key.
needs_check() {
	[[ -z ${binding[$1]} ]] || return 1
	! is_installed_action "$1" || [[ $(installed_key "$1") != "${action_key[$1]}" ]]
}

# Record every key in a binding ("A", "A<tab>B", "none") as claimed, by its
# integer value so different spellings of one key match.
claim_keys() {
	local k
	local -a keys
	IFS=$'\t' read -ra keys <<<"${1//\\t/$'\t'}"
	for k in "${keys[@]}"; do
		[[ -n $k && $k != none ]] || continue
		claimed[$(key_to_int "$k" || echo "$k")]=1
	done
}

# Check those keys. If one is taken (or two of them are the same), bind that
# shortcut to "none" instead, so it doesn't fight with the existing one.
declare -A claimed=()
unbound=()
# Keys held by the other Kikibindings shortcuts: every binding the user set
# (installed or not), plus the defaults of installed shortcuts that keep
# them. Bindings left at their default aren't in kglobalshortcutsrc, so work
# those out here.
for action in "${actions[@]}"; do
	key=${binding[$action]}
	if [[ -z $key ]]; then
		is_installed_action "$action" && ! needs_check "$action" || continue
		key=${action_key[$action]}
	fi
	claim_keys "$key"
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
	keyid=$(key_to_int "$key")
	if [[ -n ${claimed[$keyid]:-} ]] || key_taken "$key"; then
		warn "$name: $key is already used by another shortcut, or can't be checked; leaving it unbound"
		info "pick a key in System Settings > Shortcuts > Kikibindings"
		run "$kwriteconfig" --file kglobalshortcutsrc --group services --group "$id" --key "$action" none
		unbound+=("$action")
	else
		claimed[$keyid]=1
	fi
done

# The conflict "none"s belong in the snapshot too (see sync_live).
for action in "${unbound[@]}"; do
	binding[$action]=none
done

if [[ -e $dest || -L $dest ]]; then
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
[[ -L $dest ]] && run rm "$dest"
run install -m 644 "$src" "$dest"

if ! refresh loaded; then
	warn "kglobalaccel didn't load the shortcuts; they should appear after you log out and back in"
	exit 1
fi

# Make the live keys match the config (see sync_live).
if ((have_session && !dry_run)); then
	sync_live
fi

for action in "${actions[@]}"; do
	key=${binding[$action]}
	[[ -n $key ]] || key=${action_key[$action]:-none}
	info "${action_name[$action]}: ${key//$'\t'/, }"
done
echo "Done. Change keys in System Settings > Shortcuts > Kikibindings."
