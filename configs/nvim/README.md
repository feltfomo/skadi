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
| Space t p | Choose a repository, Gradle or Cargo command |
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

The project-command picker offers Odyssey's devenv commands only when they
exist in the shell. Task output is saved under Neovim's state directory in
`tasks/`, grouped by repository. The task list retains the output for review.
Tasks run only when selected.

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
