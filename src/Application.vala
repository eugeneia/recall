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

using Gee;
using Gtk;
using Gdk;
using Granite.Services;

struct Result {
    string mime;
    string uri;
    string title;
}

public class Recall : Gtk.Application {

    public Recall () {
        Object (
            application_id: "com.github.eugeneia.recall",
            flags: ApplicationFlags.FLAGS_NONE
        );
    }

    private Gtk.Window main_window { get; set; }
    private Gtk.Window main_window_init () {
        var window = new ApplicationWindow (this);
        window.set_titlebar (header);
        window.default_width = 600;
        window.default_height = 300;
        window.title = "Recall";
        window.add (layout);
        return window;
    }

    private HeaderBar header { get; set; }
    private HeaderBar header_init () {
        /*
         * Header: window buttons | search folder | search bar | settings gear?
         */
        var header = new HeaderBar ();
        header.show_close_button = true;
        header.has_subtitle = false;
        header.pack_start (folder);
        header.custom_title = search;
        return header;
    }

    private FileChooserButton folder { get; set; }
    private FileChooserButton folder_init () {
        /* Selector for search root folder. */
        var folder = new FileChooserButton (
            _("Select folder"),
            FileChooserAction.SELECT_FOLDER
        );

        /* Need to initialize Granite.Services.Paths to get homedir. */
        Paths.initialize (application_id, "");
        folder.set_current_folder (Paths.home_folder.get_path ());

        folder.file_set.connect (() => do_search (search.buffer.text));

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

    private ScrolledWindow layout { get; set; }
    private ScrolledWindow layout_init () {
        return new ScrolledWindow (null, null);
    }

    /* Run recoll query, return stdout as string. */
    private string recoll_query (string query) {
        string[] args = {
            "recoll", "-t", "-q",
            "dir:%s %s".printf(folder.get_filename (), query)
        };
        string[] env = Environ.get ();
        string stdout;
        int status;

        try {
            Process.spawn_sync (
                "/", args, env, SpawnFlags.SEARCH_PATH,
                null, out stdout, null,
                out status
            );
            if (status != 0)
                throw new SpawnError.FAILED ("error while invoking recoll");
        } catch (SpawnError e) {
            stderr.printf("Error: %s\n", e.message);
        }
        return stdout;
    }

    /* Parse recoll query. */
    private ArrayList<Result?> parse_results (string query_output) {
        var results = new ArrayList<Result?> ();
        var result_exp = new Regex (
            "^([a-z-]+\\/[a-z-]+)\t\\[(.*)\\]\t\\[(.*)\\]\t[0-9]+\tbytes\t$"
        );
        string[] lines = Regex.split_simple ("\n", query_output);
        for (int i = 2; i < (lines.length - 1); i++) {
            MatchInfo result;
            if (result_exp.match (lines[i], 0, out result))
                results.add ({
                    result.fetch(1),
                    result.fetch(2),
                    result.fetch(3)
                });
            else
                stderr.printf("Could not parse result: %s\n", lines[i]);
        }
        return results;
    }

    /* Clear results in layout. */
    private void results_clear () {
        layout.forall ((result) => {
            layout.remove (result);
        });
    }

    /* Show results in layout. */
    private void results_show (ArrayList<Result?> results) {
        var view = results_view ();
        view.item_orientation = Orientation.HORIZONTAL;
        view.activate_on_single_click = true;

        var model = results_model (results);

        view.model = model;
        view.item_activated.connect ((path) => {
            string? uri = result_uri (model, path);
            try { AppInfo.launch_default_for_uri (uri, null); }
            catch (Error e) {}
        });

        layout.add (view);
        layout.show_all ();
    }

    /* Create IconView for results model. */
    private IconView results_view () {
        var view = new IconView ();
		view.set_pixbuf_column (0);
		view.set_tooltip_column (1);
		view.set_text_column (2);
		return view;
    }

    /* Convert results to ListStore. */
    private Gtk.ListStore results_model (ArrayList<Result?> results) {
        var list = new Gtk.ListStore (3,
            typeof (Gdk.Pixbuf), // Mime icon
            typeof (string),     // URI
            typeof (string)      // Title
        );
        TreeIter item;
        foreach (var result in results) {
            list.append (out item);
            list.set (item,
                0, mime_icon (result.mime),
                1, result.uri,
                2, result.title,
            -1);
        }
        return list;
    }

    /* Get URI for path in ListStore. */
    private string? result_uri (Gtk.ListStore results, TreePath path) {
        TreeIter item;
        results.get_iter (out item, path);
        Value uri;
        results.get_value (item, 1, out uri);
        return uri as string;
    }

    /* Get icon for result item by mime type. */
	private Pixbuf default_icon;
    private Pixbuf mime_icon (string mime_type) {
        var theme = IconTheme.get_default ();
        var icon = theme.lookup_by_gicon (
            ContentType.get_icon (mime_type),
            32,
            IconLookupFlags.FORCE_SVG
        );
        try {
            return icon.load_icon ();
        } catch (Error e) {
            return default_icon;
        }
    }

    /* Indicate no available results in layout. */
    private void results_none () {
        var no_results = new Label (null);
        no_results.set_markup(
        "<span color='grey' style='italic'>No results. :-/</span>"
        );
        layout.add (no_results);
        layout.show_all ();
    }

    /* Perform  search and update results shown in layout. */
    private void do_search (string query) {
        query = query._strip ();
        results_clear ();
        if (query.length > 0) {
            var results = parse_results (recoll_query (query));
            if (results.size > 0)
                results_show (results);
            else
                results_none ();
        }
    }

    protected override void activate () {
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

        /* Initialize widgets. */
        layout = layout_init ();
        folder = folder_init ();
        search = search_init ();
        header = header_init ();
        main_window = main_window_init ();

        main_window.show_all ();
    }

    public static int main (string[] args) {
        var app = new Recall ();
        return app.run (args);
    }
}
