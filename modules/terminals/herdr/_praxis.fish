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
    exec herdr --remote "$target" --session "$selected"
end

if test (count $sessions) -eq 0
    printf 'No running Herdr sessions on %s.\n' "$argv[3]" >&2
    exit 1
end

if test "$mode" = list
    printf '%s\n' $sessions
    exit 0
end

if test -z "$selected"
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

if not contains -- "$selected" $sessions
    printf 'No running session named %s on %s.\n' "$selected" "$argv[3]" >&2
    exit 1
end

exec herdr --remote "$target" --session "$selected"
