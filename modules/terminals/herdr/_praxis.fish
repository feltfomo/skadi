function parse_sessions --argument-names mode
    command jq --raw-input --slurp --raw-output --arg mode "$mode" '
        if utf8bytelength > 262144 then error("Herdr session response is too large") else fromjson end |
        if type != "object" or (.sessions | type) != "array" then
            error("invalid Herdr session response")
        elif any(.sessions[]; type != "object" or (.name | type) != "string" or (.running | type) != "boolean") then
            error("invalid Herdr session record")
        elif any(.sessions[]; (.name | test("^[A-Za-z0-9_.-]{1,64}$") | not) or .name == "." or .name == "..") then
            error("invalid Herdr session name")
        else .sessions | map(select(.running or $mode == "new") | .name) | unique | .[] end'
end

function session_names --argument-names target local_machine machine mode
    if test "$machine" = "$local_machine"
        command timeout --foreground --kill-after=1s 12s env -u HERDR_SOCKET_PATH -u HERDR_CLIENT_SOCKET_PATH -u HERDR_FLEET_CONFIG -u HERDR_CLIENT_STATE_DIR herdr session list --json | command head --bytes=262145 | parse_sessions "$mode"
        set --function query_status $pipestatus
    else
        command timeout --foreground --kill-after=1s 12s ssh -o BatchMode=yes -o ConnectTimeout=8 -o ConnectionAttempts=1 -- "$target" 'herdr session list --json' | command head --bytes=262145 | parse_sessions "$mode"
        set --function query_status $pipestatus
    end
    if test "$query_status[1]" -ne 0; or test "$query_status[2]" -ne 0; or test "$query_status[3]" -ne 0
        return 1
    end
end

if test (count $argv) -lt 3; or test (count $argv) -gt 4
    printf '%s\n' 'usage: herdr helper machines.json list|attach|new machine [session]' >&2
    exit 2
end

set --local cohort_file "$argv[1]"
set --erase argv[1]
set --local mode "$argv[1]"
set --local machine "$argv[2]"
set --local selected "$argv[3]"
if not contains -- "$mode" list attach new
    printf '%s\n' 'unknown Herdr helper action' >&2
    exit 2
end
if test "$mode" = list; and test -n "$selected"
    printf '%s\n' 'session listing does not accept a session name' >&2
    exit 2
end

set --local machines (command jq --slurp --compact-output '
    if length != 1 or (.[0] | type) != "array" then error("invalid machine configuration") else .[0] end |
    if length < 1 or length > 8 or any(.[];
        type != "object" or (keys - ["id", "label", "target"] | length != 0) or
        (.id | type) != "string" or (.id | test("^[A-Za-z0-9_.-]{1,64}$") | not) or
        (.label | type) != "string" or (.label | length) < 1 or (.label | length) > 128 or
        (.label | explode | any(. < 32 or . == 127)) or
        (.target | type) != "string" or (.target | length) == 0 or
        (.target | startswith("-")) or (.target | explode | any(. < 32 or . == 127))) or
        ([.[].id] | length != (unique | length)) then error("invalid machine configuration") else . end
    ' "$cohort_file")
or exit $status
set --local local_machine (command uname -n)
or exit $status
set local_machine (string split --fields 1 . -- "$local_machine")
if not printf '%s\n' "$machines" | command jq --exit-status --arg local "$local_machine" --arg machine "$machine" \
        'any(.[]; .id == $local) and any(.[]; .id == $machine)' >/dev/null
    printf '%s\n' 'This computer or destination is not in the configured Herdr machines.' >&2
    exit 2
end
set --local target (printf '%s\n' "$machines" | command jq --raw-output --arg machine "$machine" '.[] | select(.id == $machine) | .target')
or exit $status

if test "$mode" = new
    if not string match --quiet --regex '\A[A-Za-z0-9_.-]{1,64}\z' -- "$selected"; or contains -- "$selected" . .. default
        printf '%s\n' "A new session needs 1-64 ASCII letters, numbers, '.', '_' or '-'; '.', '..' and 'default' are reserved." >&2
        exit 2
    end
end

set --local sessions (session_names "$target" "$local_machine" "$machine" "$mode")
or exit $status
if test "$mode" = new; and contains -- "$selected" $sessions
    printf 'Session %s already exists on %s; use Herdr directly to attach or resume it.\n' "$selected" "$machine" >&2
    exit 1
end
if test "$mode" = list
    if test (count $sessions) -gt 0
        printf '%s\n' $sessions
    end
    exit 0
end
if test "$mode" = attach; and test (count $sessions) -eq 0
    printf 'No running Herdr sessions on %s.\n' "$machine" >&2
    exit 1
end
if test "$mode" = attach; and test -z "$selected"
    if not isatty stdin; or not isatty stdout
        printf '%s\n' 'The session picker needs a terminal; use praxis herdr sessions to list sessions.' >&2
        exit 1
    end
    set selected (printf '%s\n' $sessions | command env FZF_DEFAULT_OPTS= FZF_DEFAULT_OPTS_FILE= fzf --no-multi --prompt="$machine session> " --header='Running sessions; Esc cancels')
    set --local picker_status $status
    switch $picker_status
        case 1 130
            exit 0
        case 0
        case '*'
            exit $picker_status
    end
    set sessions (session_names "$target" "$local_machine" "$machine" attach)
    or exit $status
end
if test "$mode" = attach; and not contains -- "$selected" $sessions
    printf 'No running session named %s on %s.\n' "$selected" "$machine" >&2
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
set --local connection_hash (printf '%s\0%s\0%s\0%s' fleet-v1 "$local_machine" "$target" "$selected" | command sha256sum | string split --fields 1 ' ')
or exit $status
set --local state_dir "$state_root/herdr/connections/$connection_hash"
set --local actual_dir (command env -u HERDR_FLEET_CONFIG HERDR_CLIENT_STATE_DIR="$state_dir" herdr machine state-dir 2>/dev/null)
set --local probe_status $status
set --local fleet_version (command env -u HERDR_FLEET_CONFIG HERDR_CLIENT_STATE_DIR="$state_dir" herdr machine fleet-version 2>/dev/null)
set --local fleet_status $status
if test "$probe_status" -ne 0; or test (count $actual_dir) -ne 1; or test "$actual_dir" != "$state_dir"; or test "$fleet_status" -ne 0; or test (count $fleet_version) -ne 1; or test "$fleet_version" != 1
    printf '%s\n' 'This Herdr binary cannot open combined machine windows. Use a fresh nix run /etc/skadi#praxis invocation or rebuild before connecting.' >&2
    exit 1
end

set --local origin_session default
if test "$machine" = "$local_machine"
    set origin_session "$selected"
else if set --query HERDR_SESSION; and test -n "$HERDR_SESSION"
    set --local local_sessions (session_names "" "$local_machine" "$local_machine" attach)
    or exit $status
    if contains -- "$HERDR_SESSION" $local_sessions
        set origin_session "$HERDR_SESSION"
    end
end

set --local config_file "$state_dir/fleet.json"
if test -L "$config_file"; or begin
        test -e "$config_file"; and not command jq --exit-status --slurp '
            def identifier: type == "string" and test("^[A-Za-z0-9_.-]{1,64}$");
            def session: identifier and . != "." and . != "..";
            def target: . == null or (type == "string" and length > 0 and
                (startswith("-") | not) and (explode | all(. >= 32 and . != 127)));
            def machine: type == "object" and keys == ["id", "label", "target"] and
                (.id | identifier) and (.label | type == "string" and length > 0 and length <= 128 and
                (explode | all(. >= 32 and . != 127))) and (.target | target);
            length == 1 and (.[0] | type == "object" and .version == 1 and
                keys == ["local_machine", "machines", "origin_session", "selected", "version"] and
                (.local_machine | identifier) and (.origin_session | session) and
                (.selected | type == "object" and keys == ["machine", "session"] and
                    (.machine | identifier) and (.session | session)) and
                (.machines | type == "array" and length > 0 and length <= 8 and all(.[]; machine) and
                    ([.[].id] | length == (unique | length))) and
                ([.machines[] | select(.target == null) | .id] == [.local_machine]) and
                (.selected.machine as $selected | any(.machines[]; .id == $selected)))
        ' "$config_file" >/dev/null
    end
    printf '%s\n' 'Unsupported Herdr machine configuration; leaving the saved state unchanged.' >&2
    exit 1
end

if test "$mode" = new; and test "$machine" != "$local_machine"
    command env -u HERDR_FLEET_CONFIG -u HERDR_CLIENT_STATE_DIR herdr machine fleet-create "$target" "$selected"
    or exit $status
end

command mkdir -p -- "$state_dir"
or exit $status
set --local temporary (command mktemp "$state_dir/.fleet.XXXXXXXXXX")
or exit $status
command jq --null-input --arg local "$local_machine" --arg origin "$origin_session" \
    --arg machine "$machine" --arg session "$selected" --argjson machines "$machines" \
    '{version: 1, local_machine: $local, origin_session: $origin,
      selected: {machine: $machine, session: $session},
      machines: ($machines | map(if .id == $local then .target = null else . end))}' >"$temporary"
or exit $status
command mv --no-target-directory -- "$temporary" "$config_file"
or exit $status
set --local client_args
if test "$mode" = attach; and test "$machine" = "$local_machine"
    set client_args client
end
exec env -u HERDR_SOCKET_PATH -u HERDR_CLIENT_SOCKET_PATH HERDR_CLIENT_STATE_DIR="$state_dir" HERDR_FLEET_CONFIG="$config_file" herdr --session "$origin_session" $client_args
