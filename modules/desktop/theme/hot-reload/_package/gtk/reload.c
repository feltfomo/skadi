/*
 * SPDX-FileCopyrightText: 2020 Carson Black <uhhadd@gmail.com>
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only
 *
 * Adapted from KDE/kde-gtk-config color-reload-module/reloader.c.
 */

#include <gtk/gtk.h>
#include <gio/gio.h>
#include <gmodule.h>

#if GTK_CHECK_VERSION(4, 0, 0)
#define CONFIG_DIRECTORY "gtk-4.0"
#else
#define CONFIG_DIRECTORY "gtk-3.0"
#endif

static GtkCssProvider *current_provider;
static GFileMonitor *monitor;
static gchar *palette_path;
static guint pending_reload;

static gboolean
complete_palette(const gchar *contents)
{
    static const gchar *required[] = {
        "skadi_primary", "skadi_on_primary", "skadi_surface",
        "skadi_surface_container_low", "skadi_surface_container",
        "skadi_surface_container_high", "skadi_on_surface",
        "skadi_on_surface_variant", "skadi_outline_variant", "skadi_error",
        "skadi_on_error", "skadi_error_container", "skadi_on_error_container",
        "skadi_secondary", "skadi_on_secondary", "skadi_secondary_container",
        "skadi_on_secondary_container", "skadi_tertiary", "skadi_on_tertiary",
        "skadi_tertiary_container", "skadi_on_tertiary_container"
    };
    GRegex *comments = g_regex_new("/\\*.*?\\*/", G_REGEX_DOTALL, 0, NULL);
    gchar *raw = g_regex_replace_literal(comments, contents, -1, 0, "", 0, NULL);
    GRegex *definitions = g_regex_new(
        "@define-color\\s+(skadi_[a-z_]+)\\s+#[0-9a-fA-F]{6}\\s*;",
        0, 0, NULL);
    GHashTable *names = g_hash_table_new_full(g_str_hash, g_str_equal, g_free, NULL);
    GMatchInfo *matches;
    gchar *remainder = g_regex_replace_literal(definitions, raw, -1, 0, "", 0, NULL);
    gboolean complete = g_regex_match_simple("^\\s*$", remainder, G_REGEX_DOTALL, 0);

    g_regex_match(definitions, raw, 0, &matches);
    while (g_match_info_matches(matches)) {
        gchar *name = g_match_info_fetch(matches, 1);
        if (g_hash_table_contains(names, name))
            complete = FALSE;
        g_hash_table_add(names, name);
        g_match_info_next(matches, NULL);
    }
    for (guint index = 0; index < G_N_ELEMENTS(required); ++index) {
        if (!g_hash_table_contains(names, required[index])) {
            complete = FALSE;
            break;
        }
    }
    g_match_info_free(matches);
    g_hash_table_unref(names);
    g_regex_unref(definitions);
    g_regex_unref(comments);
    g_free(remainder);
    g_free(raw);
    return complete;
}

static void
parsing_error(GtkCssProvider *provider, GtkCssSection *section,
              const GError *error, gpointer data)
{
    (void)provider;
    (void)section;
    (void)error;
    *(gboolean *)data = TRUE;
}

static gboolean
load_candidate(GtkCssProvider *candidate, const gchar *contents, gsize length)
{
    gboolean invalid = FALSE;
    gulong handler = g_signal_connect(candidate, "parsing-error", G_CALLBACK(parsing_error), &invalid);
#if GTK_CHECK_VERSION(4, 0, 0)
    (void)length;
    gtk_css_provider_load_from_string(candidate, contents);
    gboolean loaded = TRUE;
#else
    gboolean loaded = gtk_css_provider_load_from_data(candidate, contents, length, NULL);
#endif
    g_signal_handler_disconnect(candidate, handler);
    return loaded && !invalid;
}

static void
swap_provider(GtkCssProvider *candidate)
{
    GSList *displays = gdk_display_manager_list_displays(gdk_display_manager_get());
    for (GSList *entry = displays; entry != NULL; entry = entry->next) {
        GdkDisplay *display = entry->data;
#if GTK_CHECK_VERSION(4, 0, 0)
        /* at USER + 1 these @define-color values win over the gtk.css copies GtkSettings never reloads. */
        gtk_style_context_add_provider_for_display(display, GTK_STYLE_PROVIDER(candidate),
                                                   GTK_STYLE_PROVIDER_PRIORITY_USER + 1);
        if (current_provider != NULL)
            gtk_style_context_remove_provider_for_display(display, GTK_STYLE_PROVIDER(current_provider));
#else
        for (gint index = 0; index < gdk_display_get_n_screens(display); ++index) {
            GdkScreen *screen = gdk_display_get_screen(display, index);
            gtk_style_context_add_provider_for_screen(screen, GTK_STYLE_PROVIDER(candidate),
                                                      GTK_STYLE_PROVIDER_PRIORITY_USER + 1);
            if (current_provider != NULL)
                gtk_style_context_remove_provider_for_screen(screen, GTK_STYLE_PROVIDER(current_provider));
        }
#endif
    }
    g_slist_free(displays);
    g_clear_object(&current_provider);
    current_provider = candidate;
}

static gboolean
reload_palette(gpointer data)
{
    (void)data;
    gchar *contents = NULL;
    gsize length = 0;
    pending_reload = 0;
    if (!g_file_get_contents(palette_path, &contents, &length, NULL))
        return G_SOURCE_REMOVE;
    if (!g_utf8_validate(contents, length, NULL) || !complete_palette(contents)) {
        g_free(contents);
        return G_SOURCE_REMOVE;
    }

    GtkCssProvider *candidate = gtk_css_provider_new();
    gboolean loaded = load_candidate(candidate, contents, length);
    g_free(contents);
    if (!loaded) {
        g_object_unref(candidate);
        return G_SOURCE_REMOVE;
    }
    swap_provider(candidate);
    return G_SOURCE_REMOVE;
}

static void
queue_reload(void)
{
    if (pending_reload != 0)
        g_source_remove(pending_reload);
    pending_reload = g_timeout_add(75, reload_palette, NULL);
}

static gboolean
is_palette(GFile *file)
{
    if (file == NULL)
        return FALSE;
    gchar *name = g_file_get_basename(file);
    gboolean matches = g_strcmp0(name, "reactive.css") == 0;
    g_free(name);
    return matches;
}

static void
file_changed(GFileMonitor *source, GFile *file, GFile *other,
             GFileMonitorEvent event, gpointer data)
{
    (void)source;
    (void)event;
    (void)data;
    if (is_palette(file) || is_palette(other))
        queue_reload();
}

static void
display_opened(GdkDisplayManager *manager, GdkDisplay *display, gpointer data)
{
    (void)manager;
    (void)display;
    (void)data;
    queue_reload();
}

static void
start_watching(void)
{
    if (palette_path != NULL)
        return;
    gchar *directory = g_build_filename(g_get_user_config_dir(), CONFIG_DIRECTORY, NULL);
    palette_path = g_build_filename(directory, "reactive.css", NULL);
    GFile *file = g_file_new_for_path(directory);
    /* watch the directory because renderers publish by replacing the palette inode. */
    monitor = g_file_monitor_directory(file, G_FILE_MONITOR_WATCH_MOVES, NULL, NULL);
    g_object_unref(file);
    g_free(directory);
    if (monitor != NULL)
        g_signal_connect(monitor, "changed", G_CALLBACK(file_changed), NULL);
    g_signal_connect(gdk_display_manager_get(), "display-opened", G_CALLBACK(display_opened), NULL);
    queue_reload();
}

#if GTK_CHECK_VERSION(4, 0, 0)
/*
 * gtk 4 has no gtk-modules, but gtk_init scans GTK_PATH/4.0.0/immodules as GIO
 * modules (checked against GTK 4.22.4). This registers no input method; it only
 * uses that load hook.
 */
G_MODULE_EXPORT void
g_io_module_load(GIOModule *module)
{
    /* gio's directory scan unuses, and so dlcloses, the module after load; this use keeps it resident. */
    g_type_module_use(G_TYPE_MODULE(module));
    start_watching();
}

G_MODULE_EXPORT void
g_io_module_unload(GIOModule *module)
{
    (void)module;
}
#else
G_MODULE_EXPORT void
gtk_module_init(gint *argc, gchar ***argv)
{
    (void)argc;
    (void)argv;
    start_watching();
}
#endif
