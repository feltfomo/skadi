#!@nu@
# compiles one theme stylesheet against the shared design layer.
# --palette exposes the template's --skadi-* roles as `@use "palette"`, so the sheet may use only
# the roles that template defines.
def main [input: path, output: path, --palette: path] {
    let load_path = ($env.SKADI_SASS_LOAD_PATH? | default "@share@")
    let generated = (mktemp --directory)
    if $palette != null {
        let roles = (
            open --raw $palette | lines
            | parse --regex '^\s*--skadi-(?<name>[a-z-]+):'
            | get name | str replace --all '-' '_'
        )
        if ($roles | is-empty) {
            rm --recursive $generated
            error make { msg: $"no --skadi-* roles found in ($palette)" }
        }
        '@forward "skadi/css" with ($available: (' + ($roles | str join ', ') + "));\n"
        | save ($generated | path join "_palette.scss")
    }

    # deprecated sass syntax fails the build instead of breaking silently on a sass upgrade
    let result = (
        ^@sass@ --no-source-map --style=expanded --no-charset
            $"--load-path=($load_path)" $"--load-path=($generated)"
            --fatal-deprecation=import
            --fatal-deprecation=global-builtin
            --fatal-deprecation=if-function
            $input $output
        | complete
    )
    rm --recursive $generated
    print --no-newline --stderr $result.stderr
    exit $result.exit_code
}
