# Undim windows that are playing audio while they are inactive.
#
# Watches PipeWire for streams that are actually playing (not paused/corked),
# maps each stream's process back to the window that owns it, and forces that
# window's `opaque` property on so Hyprland's inactive-opacity dimming skips it.
# Driven by `pactl subscribe`, so it idles until audio starts or stops.
#
# No shebang / PATH setup here on purpose: this file is embedded by
# modules/aspects/hyprland.nix via pkgs.writeShellApplication, which prepends the
# bash shebang, `set -euo pipefail`, and a PATH built from runtimeInputs
# (hyprctl, pactl, jq, awk, procps, coreutils).

# Reach the running Hyprland even if systemd did not inherit its signature.
if [ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && [ -d "${XDG_RUNTIME_DIR:-}/hypr" ]; then
	# instance dirs are hex signatures, so ls -t is safe to word-split here
	# shellcheck disable=SC2012
	HYPRLAND_INSTANCE_SIGNATURE="$(ls -t "${XDG_RUNTIME_DIR:-}/hypr" | head -n1)"
	export HYPRLAND_INSTANCE_SIGNATURE
fi

reconcile() {
	# PIDs of streams that are actually playing (not corked / paused).
	playing="$(pactl -f json list sink-inputs 2>/dev/null \
		| jq -r '.[] | select(.corked==false) | .properties["application.process.id"] // empty' || true)"

	# Expand each to its full parent chain, so a browser's sandboxed audio
	# subprocess maps back to the main, window-owning process.
	ancestors=" "
	while read -r pid; do
		[ -n "$pid" ] || continue
		cur="$pid"
		n=0
		while [ -n "$cur" ] && [ "$cur" != "0" ] && [ "$cur" != "1" ] && [ "$n" -lt 32 ]; do
			ancestors="$ancestors$cur "
			cur="$(awk '/^PPid:/{print $2}' "/proc/$cur/status" 2>/dev/null || true)"
			n=$((n + 1))
		done
	done <<< "$playing"

	# opaque ON for any window whose PID is in that set, OFF for the rest.
	{
		hyprctl clients -j 2>/dev/null | jq -r '.[] | "\(.address) \(.pid)"' \
			| while read -r addr cpid; do
				[ -n "$addr" ] || continue
				case "$ancestors" in
					*" $cpid "*) val=1 ;;
					*) val=0 ;;
				esac
				hyprctl dispatch "hl.dsp.window.set_prop({ window = \"address:$addr\", prop = \"opaque\", value = \"$val\" })" >/dev/null 2>&1 || true
			done
	} || true
}

reconcile
pactl subscribe 2>/dev/null | while read -r event; do
	case "$event" in
		*sink-input*) reconcile ;;
	esac
done