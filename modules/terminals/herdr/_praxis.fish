function matching_profile --argument-names target session
    command jq --slurp --compact-output --arg target "$target" --arg session "$session" '
    if length != 1 or (.[0] | type) != "array" then error("invalid Herdr machine response") else .[0] end |
    if any(.[]; type != "object" or (.id | type) != "string" or (.id | test("^[0-9a-f]{32}$") | not) or
        (.target | type) != "string" or (.session | type) != "string" or (.enabled | type) != "boolean") then
        error("invalid Herdr machine record")
    else map(select(.target == $target and .session == $session)) end |
    if length > 1 then error("multiple saved machines match this connection") else .[0] end'
end

function session_names --argument-names target mode
    set --local payload (command ssh -o ConnectTimeout=10 -o ConnectionAttempts=1 -- "$target" 'herdr session list --json')
    or return $status

    printf '%s\n' $payload | command jq --slurp --raw-output --arg mode "$mode" '
        if length != 1 then error("expected one Herdr session response") else .[0] end |
        if type != "object" or (.sessions | type) != "array" then
            error("invalid Herdr session response")
        elif any(.sessions[]; type != "object" or (.name | type) != "string" or (.running | type) != "boolean") then
            error("invalid Herdr session record")
        elif any(.sessions[]; (.name | length) == 0 or (.name | explode | any(. < 32 or . == 127))) then
            error("invalid Herdr session name")
        else
            .sessions | map(select(.running or $mode == "new") | .name) | unique | .[]
        end'
end

if test (count $argv) -lt 3; or test (count $argv) -gt 4
    printf '%s\n' 'usage: herdr helper list|attach|new user machine [session]' >&2
    exit 2
end

set --local mode "$argv[1]"
set --local target "$argv[2]@$argv[3]"
if not contains -- "$mode" list attach new
    printf '%s\n' 'unknown Herdr helper action' >&2
    exit 2
end

set --local selected "$argv[4]"
if test "$mode" = new
    if not string match --quiet --regex '\A[A-Za-z0-9_.-]{1,64}\z' -- "$selected"; or contains -- "$selected" . .. default
        printf '%s\n' "A new session needs 1-64 ASCII letters, numbers, '.', '_' or '-'; '.', '..' and 'default' are reserved." >&2
        exit 2
    end
end

set --local sessions (session_names "$target" "$mode")
or exit $status

if test "$mode" = new
    if contains -- "$selected" $sessions
        printf 'Session %s already exists on %s; use Herdr directly to attach or resume it.\n' "$selected" "$argv[3]" >&2
        exit 1
    end
end

if test "$mode" != new; and test (count $sessions) -eq 0
    printf 'No running Herdr sessions on %s.\n' "$argv[3]" >&2
    exit 1
end

if test "$mode" = list
    printf '%s\n' $sessions
    exit 0
end

if test "$mode" = attach; and test -z "$selected"
    if not isatty stdin; or not isatty stdout
        printf '%s\n' 'The session picker needs a terminal; use praxis herdr sessions to list sessions.' >&2
        exit 1
    end

    set selected (printf '%s\n' $sessions | command env FZF_DEFAULT_OPTS= FZF_DEFAULT_OPTS_FILE= fzf --no-multi --prompt="$argv[3] session> " --header='Running sessions; Esc cancels')
    set --local picker_status $status
    switch $picker_status
        case 1 130
            exit 0
        case 0
        case '*'
            exit $picker_status
    end

    set sessions (session_names "$target" attach)
    or exit $status
end

if test "$mode" = attach; and not contains -- "$selected" $sessions
    printf 'No running session named %s on %s.\n' "$selected" "$argv[3]" >&2
    exit 1
end

set --local state_root "$HOME/.local/state"
if set --query XDG_STATE_HOME; and test -n "$XDG_STATE_HOME"
    set state_root "$XDG_STATE_HOME"
end
if not string match --quiet '/*' -- "$state_root"
    printf '%s\n' 'Herdr connection state needs an absolute XDG_STATE_HOME.' >&2
    exit 1
end
set --local connection_hash (printf '%s\0%s' "$target" "$selected" | command sha256sum | string split --fields 1 ' ')
or exit $status
set --local state_dir "$state_root/herdr/connections/$connection_hash"
set --local actual_dir (command env HERDR_CLIENT_STATE_DIR="$state_dir" herdr machine state-dir)
if test "$status" -ne 0; or test (count $actual_dir) -ne 1; or test "$actual_dir" != "$state_dir"
    printf '%s\n' 'This Herdr binary cannot isolate connection state. Use a fresh nix run /etc/skadi#praxis invocation or rebuild before connecting.' >&2
    exit 1
end

set --local selection_file "$state_dir/endpoint-selection.json"
if test -L "$selection_file"; or begin
        test -e "$selection_file"; and not command jq --exit-status --slurp '
            length == 1 and (.[0] |
                type == "object" and (keys - ["version", "selected_profile"] | length == 0) and
                .version == 1 and (.selected_profile == null or
                    (.selected_profile | type == "string" and test("^[0-9a-f]{32}$"))))
        ' "$selection_file" >/dev/null
    end
    printf '%s\n' 'Unsupported Herdr connection selection state; leaving the saved machines unchanged.' >&2
    exit 1
end

set --local catalog (command env HERDR_CLIENT_STATE_DIR="$state_dir" herdr machine list --json)
or exit $status
set --local profile (printf '%s\n' $catalog | matching_profile "$target" "$selected")
or exit $status

if test "$mode" = new; and test "$profile" != null
    printf 'A saved connection already uses %s on %s, but the remote session is gone. Choose another new name or recreate that session in Herdr directly.\n' "$selected" "$argv[3]" >&2
    exit 1
end

if test "$profile" = null
    command env HERDR_CLIENT_STATE_DIR="$state_dir" herdr machine add "$target" --remote-session "$selected"
    or exit $status
    set catalog (command env HERDR_CLIENT_STATE_DIR="$state_dir" herdr machine list --json)
    or exit $status
    set profile (printf '%s\n' $catalog | matching_profile "$target" "$selected")
    or exit $status
end
if test "$profile" = null
    printf '%s\n' 'The saved Herdr connection was not found after setup.' >&2
    exit 1
end
set --local profile_id (printf '%s\n' "$profile" | command jq --exit-status --raw-output '.id | select(type == "string" and test("^[0-9a-f]{32}$"))')
or exit $status
if test (printf '%s\n' "$profile" | command jq --raw-output '.enabled') = false
    command env HERDR_CLIENT_STATE_DIR="$state_dir" herdr machine enable "$profile_id"
    or exit $status
end

command mkdir -p -- "$state_dir"
or exit $status
set --local selection_tmp (command mktemp "$state_dir/.endpoint-selection.XXXXXXXXXX")
or exit $status
command jq --null-input --arg id "$profile_id" '{version: 1, selected_profile: $id}' >"$selection_tmp"
or exit $status
command mv --no-target-directory -- "$selection_tmp" "$selection_file"
or exit $status
exec env HERDR_CLIENT_STATE_DIR="$state_dir" herdr
