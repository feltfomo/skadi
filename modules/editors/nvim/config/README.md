# Neovim

Start Neovim from the project's development shell. For Odyssey, run this in
its repository root:

```fish
devenv shell -- nvim .
```

The project shell supplies compilers, formatters, linters and language servers
through `PATH`. Neovim keeps its file-search, clipboard and navigation tools.
The selected `nix-development` and `lua-development` aspects provide defaults
for editing configuration files outside a project. `jvm-development` supplies
the Java/Kotlin servers and Java debug bundle; `native-debugging` supplies
CodeLLDB. These are independent selections, not Neovim dependencies.

Projects can override the JVM defaults with `KOTLIN_LSP_DIR` and
`NVIM_JAVA_DEBUG_DIR`. Start a fresh Neovim process inside each project's shell;
changing directories or opening the task picker does not load a new environment
into an existing editor. Language servers are enabled only when their commands
are on `PATH` at startup. After activating a changed system configuration, start a
new login session to load the default environment variables, then run `:Lazy sync`
and restart Neovim to install the pinned plugins.

## Finding your place

The left sidebar shows files. It groups directory chains and follows the
current file. Oil remains available for editing directory contents.
Breadcrumbs above the code show its path and enclosing symbols. The outline
and call views show structure supplied by the language server.

| Key | Action |
| --- | --- |
| Space e | Toggle the file tree |
| Space E | Reveal the current file in the repository tree |
| Space p e | Return the tree to the repository root |
| Space p m | Choose a Gradle module or Rust crate to browse |
| Space p f | Choose a module, then find a file inside it |
| Space p g | Choose a module, then search its contents |
| Space Space | Find a file across the repository |
| Space f g | Search the repository's contents |
| Space f F | Find a file in the current file's module |
| Space f G | Search the current file's module |
| Space p a | Find project documentation |
| Space c b | Navigate the breadcrumbs |
| Space c s | Toggle the symbol outline |
| Space c i | Show incoming calls |
| Space c O | Show outgoing calls |
| Space f s | Search symbols in the current file |
| Space f S | Search workspace symbols |
| Space - | Open Oil |
| Ctrl-h/j/k/l | Move between windows |

Modules come from Gradle and Cargo manifest locations, including untracked
manifests. Gitignored build output stays out of the picker. Browsing and
searching modules doesn't change the editor's working directory or LSP root.
This is a filesystem module view, not IntelliJ's semantic package view.

## Editing and running

`gd` opens a definition, `gr` finds references, `gI` finds implementations and
`gy` opens a type definition. Space c r renames a symbol. Space c a opens code
actions. Ctrl-k in insert mode shows signature help.

Space u h toggles inlay hints, Space u d toggles buffer diagnostics and Space
u t toggles the sticky context headers. Hints start disabled for Kotlin.
Diagnostics expand below the current line. Symbol references highlight under
the cursor; `[r` and `]r` move between them. Large files skip language servers
and Tree-sitter analysis.

Space c f formats explicitly. Kotlin uses ktlint and Rust uses rustfmt on
save. Java formatting is manual, matching Odyssey's repository policy.
Python uses Ruff, C uses clang-format, TOML uses Taplo, and Markdown/YAML use
Prettier on save. The project shell supplies their executables. Saving skips
formatting when the configured formatter is unavailable; Space c f and
`:ConformInfo` remain available to diagnose missing tools.

Nix completion uses the current project's pinned nixpkgs when it has a flake.
NixOS and integrated Home Manager options come from that flake's configuration
for the current hostname. Flakes without that host expose no host options.
Statix and deadnix report Nix findings on save when available on `PATH`.
Python uses Pyright for types
and Ruff for linting. C uses clangd, Nushell uses its built-in server, and
JSON/YAML use SchemaStore schemas. For native projects, clangd needs the build's
compiler flags, normally through `compile_commands.json`, to resolve external
headers and defines accurately.

| Key | Action |
| --- | --- |
| Space s r | Search and replace across the repository with a diff preview |
| Space s w | Prefill search and replace with the current word |
| s / S | Jump to a labelled match / select a syntax node |
| g s a / g s d / g s r | Add / delete / replace surroundings |
| a f / i f | Select around / inside a function |
| a c / i c | Select around / inside a class |
| a a / i a | Select around / inside an argument |
| [f / ]f | Previous / next function |
| [C / ]C | Previous / next class |
| Space c < / Space c > | Swap an argument backward / forward |
| Space q s | Restore the current directory and branch's session |
| Space q S | Choose a saved session |
| Space q l | Restore the last session |
| Space q d | Stop saving the current session |
| Space x q / Space x l | Toggle quickfix / location list |
| Space h v | Review repository changes in Diffview |
| Space h H | Show the current file's history |
| Space h c | Close Diffview |

Sessions save on exit and restore only when requested. In quickfix, `>` expands
source context and `<` collapses it. Editing result text and saving applies the
edits to its source files. Search and replace opens with a preview; Space r in
that buffer applies the replacements.

| Key | Action |
| --- | --- |
| Space G g | Open the Gradle projects and tasks browser |
| Space t p | Search devenv tasks/scripts and Gradle/Cargo commands |
| Space t o | Float the selected task or latest project command output |
| Space t l | Rerun the last project command, including its arguments |
| Space t t | Open the running/completed task list |
| Space t a | Inspect, rerun or stop a task |
| Space t r | Open Overseer's task templates |
| Space r r | Choose a Rust runnable |
| Space r t | Choose a Rust test |
| Space r d | Choose a Rust debug target |
| Space r e | Expand a Rust macro |
| Space k o | Organize Kotlin imports |
| Space k r | Reload the Kotlin build model |
| Space k d | Open Kotlin debugging |

The project-command picker discovers evaluated devenv tasks and scripts without
parsing Nix source. It works when Neovim starts outside the development shell.
Enter runs the selection in a floating output panel. Task execution belongs to
`devenv tasks run`, including dependencies and caching. Scripts run through
`devenv shell` to get the project's environment. Opening the picker evaluates
configuration but doesn't run the selected task or script. The shell's normal
setup hooks still run when launching a script.

The picker preview shows descriptions, task relationships, the command and
script body when available. Ctrl-e runs a script with arguments entered as a
JSON array, for example `["--name", "two words"]`. Each string is one literal
argument. Shell expansions and pipelines aren't interpreted. Ctrl-a toggles
internal `devenv:` tasks. Ctrl-r refreshes discovery. Discovery runs
asynchronously and caches results for one minute. Saving Nix files or devenv's
YAML/lock file invalidates the project cache. Refresh after changing imported
files outside the project or environment/profile settings.

Gradle wrapper commands and current-crate Cargo commands remain available.
These direct commands use Neovim's environment, so start Neovim in the dev
shell when using them. Space t r keeps Overseer's other task templates; use
Space t p for devenv. Task output is saved under Neovim's state directory in
`tasks/`, grouped by repository. Project commands remain in the task list until
you dispose of them. Space t l refuses to duplicate a still-running command.
Completed project commands populate quickfix with Kotlin, Java/C compiler,
Detekt and Rust error locations. Space x q opens those results. Space t a's
"set quickfix diagnostics" action restores a selected completed task's parsed
results. Full output remains in the task log.

Space d b sets a breakpoint, Space d c starts or continues debugging, Space
d i/o/O steps into/over/out, Space d e inspects an expression and Space d q
stops the session. Space d u toggles the variables, watches and stack windows.
Variable values also appear beside their definitions while debugging, where
the language's Tree-sitter queries support it.

Java offers attachment to a local JVM, defaulting to debug port 5005. The JVM
must already have debugging enabled. Space d m discovers Java main classes.
Use the Gradle browser or project commands for Odyssey's provisioned game
launches; a generic main-class launch doesn't reproduce that environment.

## Markdown and syntax colors

Markdown renders headings, tables, lists, links and code blocks inside the
editor. Space m p opens or closes a live side preview. Space m t toggles
rendering in the current buffer when you want to read the source. Editing
reveals the markup around the cursor. The preview uses terminal text, so it
doesn't reproduce browser layout or render Mermaid diagrams and images.

The UI keeps the wallpaper palette. Syntax colors use mini.hues to generate
distinct hues from its background and foreground, including for neutral
wallpapers. Functions are blue, strings green, keywords purple, types yellow,
and numbers orange. Comments use a darker foreground shade. Tree-sitter and
LSP semantic tokens share those roles. Wallpaper reloads regenerate both.

## Maintenance

Neo-tree comes from Nix with a source patch that preserves loaded sibling
directories when grouping package paths. Lazy loads that copy through
`NVIM_NEO_TREE_DIR`. Its upstream revision stays in `lazy-lock.json`; changing
it also requires updating the source hash in `pkgs/neo-tree/default.nix` and
checking that the grouping patch still applies.
Nix generates its help tags in a separate help directory, which Neovim adds
to its runtime path so Lazy's sync doesn't write into the immutable plugin.

`lazy-lock.json` records the plugin revisions used by this config. Lazy reads
those commits as plugin constraints and writes its mutable working lock to
the state directory, since Furnish deploys immutable configuration files.
To upgrade a plugin, update its recorded commit and validate it before
running `:Lazy sync`. Project shells and the selected development aspects own
language servers and debugger binaries.

The official Kotlin server is an EAP build. The pinned version 263.7084.0
expires on November 13, 2026. Update its version and archive hash in
`modules/dev/jvm/_kotlin-lsp.nix` before that date, then rebuild. `:checkhealth kotlin` reports the installed build and licence status.

For import problems, inspect `:KotlinBuildLog`, `:KotlinShowLogs` or
`:LspInfo`. Run `:checkhealth` for missing executables. Java and Kotlin keep
separate analysis clients, while Rustaceanvim owns rust-analyzer.
