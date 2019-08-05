/*
 * Copyright (c) 2019 Max Rottenkolber (https://mr.gy)
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public
 * License along with this program; if not, write to the
 * Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
 * Boston, MA 02110-1301 USA
 *
 * Authored by: Max Rottenkolber <max@mr.gy>
 */

/*
 * FIXME: escape ampersand entities in tooltip (text?)
 * TODO: Show path, title, ellipsis in IconView, full path in tooltip?
 * TODO: Make files in iconview dragable, add show in file manager action
 * TODO: Show welcome screen, index status
 * TODO: Add settings gear/window
 */

using Gee;
using Gtk;
using Gdk;
using Granite.Services;

private const string APP_ID = "com.github.eugeneia.recall";

public class Recall : Gtk.Application {

    public Recall () {
        Object (
            application_id: APP_ID,
            flags: ApplicationFlags.FLAGS_NONE
        );
    }

    public static GLib.Settings settings;
    static construct {
        settings = new GLib.Settings (APP_ID + ".settings");
    }

    private void bin_replace (Bin bin, Widget? widget) {
        Widget? child = bin.get_child ();
        if (child == widget) return;
        if (child != null) bin.remove (child);
        if (widget != null) bin.add (widget);
    }

    private MainWindow main_window { get; set; }
    private MainWindow main_window_init () {
        var window = new MainWindow (this);
        window.set_titlebar (header);
        window.add (layout);
        return window;
    }

    private HeaderBar header { get; set; }
    private HeaderBar header_init () {
        /*
         * Header: windowctl | folder | search | spinner | settings?
         */
        var header = new HeaderBar ();
        header.show_close_button = true;
        header.has_subtitle = false;
        header.pack_start (padding_widget (24));
        header.pack_start (folder);
        header.custom_title = search;
        header.pack_end (padding_widget (24));
        header.pack_end (spinner);
        return header;
    }

    private FileChooserButton folder { get; set; }
    private FileChooserButton folder_init () {
        /* Selector for search root folder. */
        var folder = new FileChooserButton (
            _("Select folder"),
            FileChooserAction.SELECT_FOLDER
        );
        folder.create_folders = false;
        folder.set_current_folder (Paths.home_folder.get_path ());
        folder.file_set.connect (() => {
            previous_query = null; // force new query
            do_search (search.buffer.text);
        });
        return folder;
    }

    private SearchEntry search { get; set; }
    private SearchEntry search_init () {
        var search = new SearchEntry ();
        search.max_width_chars = 100;
        search.placeholder_text = _("Search for files related to…");
        search.search_changed.connect (() => do_search (search.buffer.text));
        return search;
    }

    private Spinner spinner { get; set; }
    private Spinner spinner_init () {
        return new Spinner ();
    }

    private Layout padding_widget (int width) {
        var layout = new Layout ();
        layout.margin_start = width;
        return layout;
    }

    private ScrolledWindow layout { get; set; }
    private ScrolledWindow layout_init () {
        return new ScrolledWindow (null, null);
    }

    private enum result { icon, uri, title }
    private IconView results { get; set; }
    private IconView results_init () {
        var results = new IconView ();

		results.set_pixbuf_column (result.icon);
		results.set_tooltip_column (result.uri);
		results.set_text_column (result.title);

        results.item_orientation = Orientation.HORIZONTAL;
        results.activate_on_single_click = true;

        results.item_activated.connect ((path) => {
            TreeIter item;
            results.model.get_iter (out item, path);
            Value uri;
            results.model.get_value (item, result.uri, out uri);
            try { AppInfo.launch_default_for_uri (uri as string, null); }
            catch (Error e) {}
        });

        return results;
    }

    private Label no_results { get; set; }
    private Label no_results_init () {
        var no_results = new Label (null);
        no_results.set_markup(
        "<span color='grey' style='italic'>%s :-/</span>"
            .printf(_("No results."))
        );
        return no_results;
    }

    private Gtk.ListStore new_results () {
        Type[] result = {
            typeof (Gdk.Pixbuf), // result.icon
            typeof (string),     // result.uri
            typeof (string)      // result.title
        };
        return new Gtk.ListStore.newv (result);
    }
    private void results_add
        (Gtk.ListStore list, Gdk.Pixbuf icon, string uri, string title) {
        TreeIter item;
        list.append (out item);
        list.set (item,
            result.icon, icon,
            result.uri, uri,
            result.title, title,
        -1);
    }

    /* Perform  search and update results shown in layout. */
    private string? previous_query;
    private void do_search (string query_ws) {
        var query = query_ws.strip (); // strip whitespace prefix/suffix

        /* Do nothing if query has not changed. */
        if (query == previous_query)
            return;
        else
            previous_query = query;

        /* Show empty window if query is empty. */
        if (query.length == 0) {
            bin_replace (layout, null);
            layout.show_all ();
            return;
        }

        /* Otherwise start spinner to indicate query process... */
        spinner.start ();

        /* ...allocate a new list to append results to... */
        int nresults = 0;
        var list = new_results ();
        results.model = list;

        /* ...display the results view... */
        bin_replace (layout, results);
        layout.show_all ();

        /* ...and invoke recoll with the query. */
        IOChannel output;
        var pid = run_recoll (query, out output);
        output.add_watch
            (IOCondition.IN | IOCondition.HUP, (channel, condition) => {
                string line;
                if (condition == IOCondition.HUP)
                    return false;
		        try {
		            channel.read_line (out line, null, null);
		        } catch (Error e) {
		            critical ("Failed to read recoll output: %s", e.message);
		            return false;
		        }
		        Gdk.Pixbuf icon;
		        string uri, title;
		        try {
		            parse_result (line, out icon, out uri, out title);
		            results_add (list, icon, uri, title);
		            nresults++;
		        } catch (Error e) {
		            warning ("Error: failed to parse result: %s", e.message);
		        }
		        return true;
            });
        ChildWatch.add (pid, (pid, status) => {
			Process.close_pid (pid);
			spinner.stop ();
			if (nresults == 0) {
			    bin_replace(layout, no_results);
			    layout.show_all ();
			}
		});
    }

    /* Run recoll query, return stdout as string. */
    private Pid run_recoll (string query, out IOChannel output) {
        string[] cmd = {
            "recoll", "-t", "-q",
            "dir:\"%s\" %s".printf(folder.get_filename (), query)
        };
        string[] env = Environ.get ();
        Pid pid;
        int stdout_fd;
        try {
            Process.spawn_async_with_pipes (
                null, cmd, env,
                SpawnFlags.SEARCH_PATH | SpawnFlags.DO_NOT_REAP_CHILD, null,
                out pid, null, out stdout_fd, null
            );
        } catch (SpawnError e) {
            critical ("Failed to spawn recoll: %s", e.message);
            Process.exit (1);
        }
        output = new IOChannel.unix_new (stdout_fd);
        return pid;
    }

    /* Parse recoll output. */
    private Regex result_grammar { get; set; }
    private Regex result_grammar_init () {
        try {
            return new Regex ("^(.*)\t\\[(.*)\\]\t\\[(.*)\\]\t[0-9]+\tbytes\t$");
        } catch (Error e) {
            critical ("Failed to compile results_grammar.");
            Process.exit (1);
        }
    }

    private void parse_result
        (string line, out Gdk.Pixbuf icon, out string uri, out string title)
        throws ParseResult {
        MatchInfo result;
        if (result_grammar.match (line, 0, out result)) {
            icon = mime_icon (result.fetch (1));
            uri = result.fetch (2);
            title = result.fetch (3);
        } else throw new ParseResult.ERROR ("Could not parse result: %s\n", line);
    }

    /* Get icon for result item by mime type. */
	private Pixbuf default_icon;
    private Pixbuf mime_icon (string mime_type) {
        var theme = IconTheme.get_default ();
        var icon = theme.lookup_by_gicon (
            ContentType.get_icon (mime_type),
            48,
            IconLookupFlags.FORCE_REGULAR
        );
        try {
            return icon.load_icon ();
        } catch (Error e) {
            return default_icon;
        }
    }

    protected override void activate () {
        /* Initialize Paths service. */
        Paths.initialize (APP_ID, "");

        /* Use an application stylesheet (CSS). */
        var provider = new CssProvider ();
        provider.load_from_resource (
            "/com/github/eugeneia/recall/Application.css"
        );
        StyleContext.add_provider_for_screen (
            Gdk.Screen.get_default (),
            provider,
            STYLE_PROVIDER_PRIORITY_APPLICATION
        );

        /* Initialize widgets and models. */
        layout = layout_init ();
        folder = folder_init ();
        search = search_init ();
        spinner = spinner_init ();
        header = header_init ();
        main_window = main_window_init ();
        results = results_init ();
        no_results = no_results_init ();
        result_grammar = result_grammar_init ();

        main_window.show_all ();
    }

    public static int main (string[] args) {
        var app = new Recall ();
        return app.run (args);
    }
}

private class MainWindow : ApplicationWindow {
    public MainWindow (Gtk.Application app) {
        Object (application: app, title: "Recall", icon_name: APP_ID);
    }

    construct {
        int window_x, window_y;
        var rect = Gtk.Allocation ();

        Recall.settings.get ("window-position", "(ii)", out window_x, out window_y);
        Recall.settings.get ("window-size", "(ii)", out rect.width, out rect.height);

        if (window_x != -1 ||  window_y != -1)
            move (window_x, window_y);

        set_allocation (rect);

        if (Recall.settings.get_boolean ("window-maximized"))
            maximize ();

        show_all ();
    }

    private uint configure_id = 0;
    public override bool configure_event (EventConfigure event) {
        if (configure_id != 0)
            GLib.Source.remove (configure_id);

        configure_id = Timeout.add (100, () => {
            configure_id = 0;

            if (is_maximized) {
                Recall.settings.set_boolean ("window-maximized", true);
            } else {
                Recall.settings.set_boolean ("window-maximized", false);

                Rectangle rect;
                get_allocation (out rect);
                Recall.settings.set ("window-size", "(ii)", rect.width, rect.height);

                int root_x, root_y;
                get_position (out root_x, out root_y);
                Recall.settings.set ("window-position", "(ii)", root_x, root_y);
            }

            return false;
        });

        return base.configure_event (event);
    }
}

private errordomain ParseResult { ERROR }