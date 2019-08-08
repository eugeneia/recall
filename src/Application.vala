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
 * TODO: Parse/show number of results
 * TODO: Add sort by mtime toggle
 * TODO: Make files in iconview dragable?
 * TODO: Add settings gear/window
 */

using Gee;
using Gtk;
using Gdk;
using Granite;
using Services;
using Widgets;

private const string APP_ID = "com.github.eugeneia.recall";

public class Recall : Gtk.Application {

    public Recall () {
        Object (
            application_id: APP_ID,
            flags: ApplicationFlags.HANDLES_COMMAND_LINE
        );
    }

    public static GLib.Settings settings;
    static construct {
        settings = new GLib.Settings (APP_ID + ".settings");
    }

    private MainWindow main_window { get; set; }
    private MainWindow main_window_init () {
        var window = new MainWindow (this);
        window.set_titlebar (header);
        window.add (notebook);
        return window;
    }

    private HeaderBar header { get; set; }
    private HeaderBar header_init () {
        /*
         * Header: windowctl | folder | search | spinner | settings?
         */
        var header = new HeaderBar ();
        header.show_close_button = true;
        header.pack_start (folder);
        header.custom_title = search;
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
        if (initial_prefix == null)
            folder.set_current_folder (Paths.home_folder.get_path ());
        else
            folder.set_current_folder (initial_prefix);
        folder.file_set.connect (() => {
            previous_query = null; // force new query
            do_search (search.buffer.text);
        });
        return folder;
    }

    private SearchEntry search { get; set; }
    private SearchEntry search_init () {
        var search = new SearchEntry ();
        search.max_width_chars = 200;
        search.placeholder_text = _("Search for files related to…");
        search.search_changed.connect (() => do_search (search.buffer.text));
        return search;
    }

    private Spinner spinner { get; set; }
    private Spinner spinner_init () {
        return new Spinner ();
    }

    private enum pages { welcome, results, no_results }
    private Notebook notebook { get; set; }
    private Notebook notebook_init () {
        var notebook = new Notebook ();
        notebook.show_border = false;
        notebook.show_tabs = false;
        notebook.insert_page (welcome, null, pages.welcome);
        notebook.insert_page (layout, null, pages.results);
        notebook.insert_page (no_results, null, pages.no_results);
        notebook.page = pages.welcome;
        Timeout.add_seconds (3, () => {
            /* Periodically update welcome info (index status). */
            if (notebook.page == pages.welcome)
                welcome_set_indexing (welcome);
            return Source.CONTINUE;
        });
        return notebook;
    }

    private ScrolledWindow layout { get; set; }
    private ScrolledWindow layout_init () {
        var layout = new ScrolledWindow (null, null);
        layout.add (results);
        return layout;
    }

    private Welcome welcome { get; set; }
    private Welcome welcome_init () {
        var welcome = new Welcome
            ("Recall", "Search your document library quickly.");
        var query_note = welcome.append (
            "system-search",
            "Search as you type",
            "Recall uses a powerful query language, you could look up files\n" +
            "containing vanilla OR banana cherry."
        );
        var open_note = welcome.append (
            "document-open",
            "Open results with a single click",
            "Or show them in Files with a right click."
        );
        welcome.set_item_sensitivity (open_note, false);
        welcome_set_indexing (welcome);
        welcome.activated.connect ((index) => {
            var query_docs = "file:///usr/share/recoll/doc/usermanual.html#RCL.SEARCH.LANG";
            try { AppInfo.launch_default_for_uri (query_docs, null); }
            catch (Error e) {}
        });

        return welcome;
    }

    private int? welcome_indexing = null;
    private void welcome_set_indexing (Welcome welcome) {
        if (welcome_indexing != null)
            welcome.remove_item (welcome_indexing);
        int nfiles; index_status(out nfiles);
        welcome_indexing = welcome.append (
            "scanner",
            "Get results instantly",
            "A database supporting fast lookup of all your files contents is\n" +
            "being compiled in real-time as we speak.\n\n" +
            "%d files have been scanned so far.".printf (nfiles)
        );
        welcome.set_item_sensitivity (welcome_indexing, false);
        welcome.show_all ();
    }

    private int index_status (out int nfiles) {
        int status = 0;
        nfiles = 0;
        try {
            var @idxstatus = File.new_build_filename
                (confdir_path, "idxstatus.txt")
                .read ();
            var stream = new DataInputStream (@idxstatus);
            var line = stream.read_line ();
            while (line != null) {
                var field = Regex.split_simple (" = ", line);
                if (field[0] == "phase")
                    status = int.parse (field[1]);
                if (field[0] == "totfiles")
                    nfiles = int.parse (field[1]);
                line = stream.read_line ();
            }
        } catch (Error e) {
        }
        return status;
    }

    private enum result { icon, uri, title, tooltip }
    private IconView results { get; set; }
    private IconView results_init () {
        var results = new IconView ();
        var file_manager = AppInfo.get_default_for_type ("inode/directory", true);

		results.set_pixbuf_column (result.icon);
		results.set_markup_column (result.title);
		results.set_tooltip_column (result.tooltip);

        results.item_orientation = Orientation.HORIZONTAL;

        results.button_release_event.connect ((event) => {
            var path = results.get_path_at_pos ((int) event.x, (int) event.y);
            if (path == null) {
                results.unselect_all ();
                return true;
            }
            results.select_path (path);
            var uri = results_get (path);
            /* On right click, open item in file_manager if its a file. */
            if (event.button == 3)
                if (uri.has_prefix ("file://")) {
                    var args = new GLib.List<string> ();
                    args.append (uri);
                    try { file_manager.launch_uris(args, null); }
                    catch (Error e) {}
                    return true;
                }
            /* Otherwise, try to open item in default application. */
            try  { AppInfo.launch_default_for_uri (uri, null); }
            catch (Error e) {}
            return true;
        });

        return results;
    }

    private string results_get (TreePath path) {
        TreeIter item;
        results.model.get_iter (out item, path);
        Value uri;
        results.model.get_value (item, result.uri, out uri);
        return uri as string;
    }

    private Gtk.ListStore new_results () {
        Type[] result = {
            typeof (Gdk.Pixbuf), // result.icon
            typeof (string),     // result.uri
            typeof (string),     // result.title
            typeof (string)      // result.tooltip
        };
        return new Gtk.ListStore.newv (result);
    }
    private void results_add
        (Gtk.ListStore list, string type, string uri, string title) {
        TreeIter item;
        list.append (out item);
        list.set (item,
            result.icon, mime_icon (type),
            result.uri, uri,
            result.title, title_markup (uri, title),
            result.tooltip, uri_tooltip (uri),
        -1);
    }

    /* Get icon for result item by mime type. */
	private Pixbuf default_icon;
    private Pixbuf mime_icon (string mime_type) {
        var theme = IconTheme.get_default ();
        var icon = theme.lookup_by_gicon
            (ContentType.get_icon (mime_type), 48, 0);
        try {
            return icon.load_icon ();
        } catch (Error e) {
            return default_icon;
        }
    }

    /* Render tooltip text for URI. */
    private string uri_tooltip (string uri) {
        var base_uri = folder.get_uri ();
        string tooltip;
        if (uri.has_prefix ("file://"))
            tooltip = uri.slice(base_uri.length + 1, uri.length);
        else
            tooltip = uri;
        return Markup.escape_text (tooltip);
    }

    /* Render title markup text. */
    private string title_markup (string uri, string title) {
        var base_uri = folder.get_uri ();
        var path_start = base_uri.length + 1;
        var last_folder = uri.last_index_of ("/");
        var path_end = last_folder > path_start ? last_folder : path_start;
        var relative_path = uri.slice (path_start, path_end);
        var format =
            "<span color='#333333'>%s</span> "
            + "<span size='smaller' color='#7e8087' style='italic'>%s</span>";
        return format.printf
            (Markup.escape_text (title), Markup.escape_text (relative_path));
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

    /* Perform  search and update results shown in layout. */
    private string? previous_query;
    private void do_search (string query_ws) {
        var query = query_ws.strip (); // strip whitespace prefix/suffix

        /* Do nothing if query has not changed. */
        if (query == previous_query)
            return;
        else
            previous_query = query;

        /* Show welcome dialog if query is empty. */
        if (query.length == 0) {
            notebook.page = pages.welcome;
            return;
        }

        /* Otherwise start spinner to indicate query process... */
        spinner.start ();

        /* ...allocate a new list to append results to... */
        int nresults = 0;
        var list = new_results ();
        results.model = list;

        /* ...display the results view... */
        notebook.page = pages.results;

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
		        string type, uri, title;
		        try {
		            parse_result (line, out type, out uri, out title);
		            results_add (list, type, uri, title);
		            nresults++;
		        } catch (Error e) {
		            warning ("Error: failed to parse result: %s", e.message);
		        }
		        return true;
            });
        ChildWatch.add (pid, (pid, status) => {
			Process.close_pid (pid);
			spinner.stop ();
			if (nresults == 0)
			    notebook.page = pages.no_results;
		});
    }

    /* Run recoll query, return stdout as string. */
    private Pid run_recoll (string query, out IOChannel output) {
        string[] cmd = {
            "recoll", "-t", "-q", "-c", confdir_path,
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
        (string line, out string type, out string uri, out string title)
        throws ParseResult {
        MatchInfo result;
        if (result_grammar.match (line, 0, out result)) {
            type = result.fetch (1);
            uri = result.fetch (2);
            title = result.fetch (3);
        } else throw new ParseResult.ERROR ("Could not parse result: %s\n", line);
    }

    private string confdir_path { get; set; }
    private void autoconfigure () {
        Paths.ensure_directory_exists (Paths.user_config_folder);
        confdir_path = Paths.user_config_folder.get_path ();
        /* Autogenerate recoll.conf in confdir. */
        var recoll_conf = File.new_build_filename (confdir_path, "recoll.conf");
        if (!recoll_conf.query_exists ())
            try { create_conf (recoll_conf); }
            catch (Error e) {
                critical ("Failed to create %s: %s",
                    recoll_conf.get_path (), e.message);
                Process.exit (1);
            }
        /* Autosetup autostart of recollindex for confdir. */
        var index_autostart = File.new_build_filename (
            Paths.xdg_config_home_folder.get_path (),
            "autostart",
            APP_ID+".desktop"
        );
        if (!index_autostart.query_exists ())
            try { create_autostart (index_autostart); }
            catch (Error e) {
                critical ("Failed to create %s: %s",
                    recoll_conf.get_path (), e.message);
                Process.exit (1);
            }
        /* Spawn recollindex if its not already running. */
        if (!recollindex_isalive ()) {
            try { spawn_recollindex (); }
            catch (SpawnError e) {
                critical ("Failed to spawn recollindex: %s", e.message);
                Process.exit (1);
            }
        }
    }

    private void create_conf (File file) throws Error {
        var filestream = file.create_readwrite (0);
        var datastream = new DataOutputStream (filestream.output_stream);
        datastream.put_string (
            "skippedNames = .*\n"
        );
    }

    private void create_autostart (File file) throws Error {
        var filestream = file.create_readwrite (0);
        var datastream = new DataOutputStream (filestream.output_stream);
        datastream.put_string (
            "[Desktop Entry]\n" +
            "Name=Recall Indexer\n" +
            "GenericName=%s\n".printf(_("Document Search Indexing")) +
            "Comment=%s\n".printf(_("Automatically index docments in real-time")) +
            "Categories=Utility;FileTools;\n" +
            "Exec=recollindex -c %s -D -x -m\n".printf(confdir_path) +
            "Icon=%s\n".printf(APP_ID) +
            "Terminal=false\n" +
            "Type=Application\n" +
            "Keywords=Search;Document;Full;Text;Index;Lookup:Query;Recoll;Xapian;Files;Find;\n" +
            "X-GNOME-Autostart-enabled=true\n"
        );
    }

    private void spawn_recollindex () throws SpawnError {
        string[] cmd = { "recollindex", "-c", confdir_path, "-m", "-w", "0" };
        string[] env = Environ.get ();
        Process.spawn_sync (null, cmd, env, SpawnFlags.SEARCH_PATH, null);
    }

    private bool recollindex_isalive () {
        var pidfile = File.new_build_filename (confdir_path, "index.pid");
        if (pidfile.query_exists ()) {
            Posix.pid_t? pid = null;
            try {
                var filestream = pidfile.read ();
                var datastream = new DataInputStream (filestream);
                pid = int.parse (datastream.read_line ());
            } catch (Error e) {
                warning ("Could not read pidfile: %s", pidfile.get_path ());
            }
            if (pid != null && Posix.kill (pid, 0) == 0)
                return true;
        }
        return false;
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

        /* Autoconfigure recollindex. */
        autoconfigure ();

        /* Initialize widgets and models. */
        welcome = welcome_init ();
        results = results_init ();
        result_grammar = result_grammar_init ();
        layout = layout_init ();
        no_results = no_results_init ();
        notebook = notebook_init ();
        folder = folder_init ();
        search = search_init ();
        spinner = spinner_init ();
        header = header_init ();
        main_window = main_window_init ();

        main_window.show_all ();
    }

    string? initial_prefix;
    public override int command_line (ApplicationCommandLine cmd) {
        var arg = cmd.get_arguments ()[1];
        if (arg != null) {
            var file = cmd.create_file_for_arg (arg);
            initial_prefix = file.get_path ();
        }
        activate ();
        return 0;
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