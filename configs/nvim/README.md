# Neovim

Start Neovim from the project's development shell. For Odyssey, run this in
its repository root:

```fish
devenv shell -- nvim .
```

The shell supplies Odyssey's JDK 25, Rust toolchain and runtime environment.
The Neovim package supplies the language servers, Java debug bundle and
CodeLLDB. After activating a changed system configuration, run `:Lazy sync`
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

Space c f formats explicitly. Kotlin uses ktlint and Rust uses rustfmt on
save. Java formatting is manual, matching Odyssey's repository policy.

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

Space d b sets a breakpoint, Space d c starts or continues debugging, Space
d i/o/O steps into/over/out, Space d e inspects an expression and Space d q
stops the session. Space d u toggles the variables, watches and stack windows.

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
running `:Lazy sync`. Language servers and debugger binaries come from Nix.

The official Kotlin server is an EAP build. The pinned version 263.7084.0
expires on November 13, 2026. Update its version and archive hash in
`pkgs/kotlin-lsp/default.nix` before that date, then rebuild. `:checkhealth kotlin` reports the installed build and licence status.

For import problems, inspect `:KotlinBuildLog`, `:KotlinShowLogs` or
`:LspInfo`. Run `:checkhealth` for missing executables. Java and Kotlin keep
separate analysis clients, while Rustaceanvim owns rust-analyzer.
