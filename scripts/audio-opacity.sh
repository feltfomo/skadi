# undim inactive windows while they are playing audio.
#
# pipewire streams map back through their process trees to the owning windows.
# pactl subscribe keeps the script idle until audio state changes.
#
# writeShellApplication supplies the shebang, strict mode, and runtime path.

# reach the running hyprland instance when systemd lacks its signature.
if [ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && [ -d "${XDG_RUNTIME_DIR:-}/hypr" ]; then
	# instance dirs are hex signatures, so ls -t is safe to word-split here
	# shellcheck disable=SC2012
	HYPRLAND_INSTANCE_SIGNATURE="$(ls -t "${XDG_RUNTIME_DIR:-}/hypr" | head -n1)"
	export HYPRLAND_INSTANCE_SIGNATURE
fi

reconcile() {
	# process ids for streams that are playing
	playing="$(pactl -f json list sink-inputs 2>/dev/null \
		| jq -r '.[] | select(.corked==false) | .properties["application.process.id"] // empty' || true)"

	# include parent chains so sandboxed audio maps to the owning window
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

	# enable opaque for matching process ids and disable it for the rest
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