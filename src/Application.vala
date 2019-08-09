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
         * Header: windowctl | folder | search | settings?
         */
        var header = new HeaderBar ();
        header.show_close_button = true;
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

    private enum Pages { WELCOME, RESULTS }
    private Notebook notebook { get; set; }
    private Notebook notebook_init () {
        var notebook = new Notebook ();
        notebook.show_border = false;
        notebook.show_tabs = false;
        notebook.insert_page (welcome, null, Pages.WELCOME);
        notebook.insert_page (results_overlay, null, Pages.RESULTS);
        notebook.page = Pages.WELCOME;
        Timeout.add_seconds (3, () => {
            /* Periodically update welcome info (index status). */
            if (notebook.page == Pages.WELCOME)
                welcome_set_indexing (welcome);
            return Source.CONTINUE;
        });
        return notebook;
    }

    private OverlayBar results_info { get; set; }
    private OverlayBar results_info_init () {
        var results_info = new OverlayBar (results_overlay);
        return results_info;
    }
    private void results_info_set (int? total_results) {
        if (total_results == null) {
            results_info.label = "Searching";
            results_info.active = true;
            return;
        }
        if (total_results == 0)
            results_info.label = "No result";
        else if (total_results == 1)
            results_info.label = _("One result");
        else
            results_info.label = _("%d results").printf (total_results);
        results_info.active = false;
    }

    private Overlay results_overlay { get; set; }
    private Overlay results_overlay_init () {
        var overlay = new Overlay ();
        overlay.add (results_window);
        return overlay;
    }

    private ScrolledWindow results_window { get; set; }
    private ScrolledWindow results_window_init () {
        var results_window = new ScrolledWindow (null, null);
        results_window.add (results_view);
        results_window.edge_reached.connect (() => results.more ());
        return results_window;
    }

    private Welcome welcome { get; set; }
    private Welcome welcome_init () {
        var welcome = new Welcome
            ("Recall", "Search your document library quickly.");
        welcome.append (
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

    private Results? results = null;
    private IconView results_view { get; set; }
    private IconView results_view_init () {
        var results_view = new IconView ();
        var file_manager = AppInfo.get_default_for_type ("inode/directory", true);

		results_view.set_pixbuf_column (Results.Column.ICON);
		results_view.set_markup_column (Results.Column.TITLE);
		results_view.set_tooltip_column (Results.Column.URI);

        results_view.item_orientation = Orientation.HORIZONTAL;

        results_view.button_release_event.connect ((event) => {
            var path = results_view.get_path_at_pos ((int) event.x, (int) event.y);
            if (path == null) {
                results_view.unselect_all ();
                return true;
            }
            results_view.select_path (path);
            var uri = results.get_uri (path);
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

        return results_view;
    }

    /* Perform  search and update results shown in results_window. */
    private string? previous_query;
    private void do_search (string current_query) {
        /* Cleap up whitespace prefix and suffix from query. If the cleaned up
           query is identical to the previous query we bail (do nothing),
           otherwise save query as previous query and continue. */
        var query = current_query.strip ();
        if (query == previous_query)
            return;
        else
            previous_query = query;

        /* If the query is empty we just show the welcome dialog. */
        if (query.length == 0) {
            notebook.page = Pages.WELCOME;
            return;
        }

        /* If we got a non-empty query we show the results view, indicate
           progress by resetting the info overlay. */
        notebook.page = Pages.RESULTS;
        results_info_set (null);

        /* Allocate a new results collection and store a reference to it in
           this.results for use by results_view. Set the collection as the model
           for our results_view.
           NOTE: if at a later time search_results != this.results, we know that
           this search was superseded by a new search! */
        var search_results = new Results (folder.get_uri ());
        results = search_results;
        results_view.model = search_results.model;

        /* Run recoll query, consume asynchronously results as they become
           available until output is complete or the search is superseded. */
        IOChannel output;
        var pid = run_recoll (query, out output);
        output.add_watch (IOCondition.IN, (channel, condition) => {
            string line;
            if (search_results == results)
		        try {
		            channel.read_line (out line, null, null);
		            search_results.parse (line);
		            return true;
		        } catch (Error e) {
		            critical ("Failed to read recoll output: %s", e.message);
		        }
		    return false;
        });
        /* On completion, indicate total results in info overlay unless the
           search has been superseded. */
        ChildWatch.add (pid, (pid, status) => {
			Process.close_pid (pid);
			if (search_results == results)
			    results_info_set (search_results.total_results);
		});
    }

    /* Run recoll query, return stdout as string. */
    private Pid run_recoll (string query, out IOChannel output) {
        string[] cmd = {
            "recoll", "-c", confdir_path, "-t", "-q",
            "dir:\"%s\"".printf(folder.get_filename ()), query
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
            Posix.pid_t pid = 0;
            try {
                var filestream = pidfile.read ();
                var datastream = new DataInputStream (filestream);
                var line = datastream.read_line ();
                if (line != null)
                    pid = int.parse (line);
            } catch (Error e) {
                warning ("Could not read pidfile: %s", pidfile.get_path ());
            }
            if (pid != 0 && Posix.kill (pid, 0) == 0)
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
        results_view = results_view_init ();
        results_window = results_window_init ();
        results_overlay = results_overlay_init ();
        results_info = results_info_init ();
        notebook = notebook_init ();
        folder = folder_init ();
        search = search_init ();
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

private class Results : Object {

    public Results (string base_uri) {
        this.base_uri = base_uri;
        this.list = new Gtk.ListStore.newv (columns);
        this.result_grammar = result_grammar_init ();
    }

    public string? recoll_query = null;

    public int? total_results = null;

    public TreeModel model { get { return list; } }

    public enum Column { ICON, URI, TITLE, TOOLTIP }

    public string get_uri (TreePath path) {
        TreeIter item;
        list.get_iter (out item, path);
        Value uri;
        list.get_value (item, Column.URI, out uri);
        return uri as string;
    }

    public void parse (string line) {
        if (recoll_query == null) {
            parse_query (line);
            return;
        }
        if (total_results == null) {
            parse_total_results (line);
            return;
        }
        Result? result = parse_result (line);
        if (result != null) {
            results.add (result);
            if (results_added < initial_items)
                more (1);
        }
    }

    public void more (int n = initial_items) {
        while (n > 0 && results_added < results.size) {
            add(results[results_added]);
            results_added++;
            n--;
        }
    }

    private string base_uri { get; set; }

    private static Type[] columns = {
            typeof (Gdk.Pixbuf), // Column.ICON
            typeof (string),     // Column.URI
            typeof (string),     // Column.TITLE
            typeof (string)      // Column.TOOLTIP
    };

    private ArrayList<Result?> results = new ArrayList<Result?> ();
    private int results_added = 0;

    private Gtk.ListStore list { get; set; }
    public const int initial_items = 100;

    private void add (Result result) {
        TreeIter item;
        list.append (out item);
        list.set (item,
            Column.ICON, mime_icon (result.type),
            Column.URI, result.uri,
            Column.TITLE, title_markup (result.uri, result.title),
            Column.TOOLTIP, uri_tooltip (result.uri),
        -1);
    }

    /* Get icon for result item by mime type. */
    private IconTheme icon_theme = IconTheme.get_default ();
	private Pixbuf default_icon;
    private Pixbuf mime_icon (string mime_type) {
        var icon = icon_theme.lookup_by_gicon
            (ContentType.get_icon (mime_type), 48, 0);
        try {
            return icon.load_icon ();
        } catch (Error e) {
            return default_icon;
        }
    }

    /* Render tooltip text for URI. */
    private string uri_tooltip (string uri) {
        string tooltip;
        if (uri.has_prefix ("file://"))
            tooltip = uri.slice(base_uri.length + 1, uri.length);
        else
            tooltip = uri;
        return Markup.escape_text (tooltip);
    }

    /* Render title markup text. */
    private string title_markup (string uri, string title) {
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

    /* Parse recoll output. */
    private struct Result {
        string type;
        string uri;
        string title;
    }
    private Regex result_grammar { get; set; }
    private Regex result_grammar_init () {
        try {
            return new Regex ("^(.*)\t\\[(.*)\\]\t\\[(.*)\\]\t[0-9]+\tbytes\t$");
        } catch (Error e) {
            critical ("Failed to compile results_grammar.");
            Process.exit (1);
        }
    }
    private Result? parse_result (string line) {
        MatchInfo result;
        if (result_grammar.match (line, 0, out result)) {
            return {
                type: result.fetch (1),
                uri: result.fetch (2),
                title: result.fetch (3)
            };
        } else {
            warning ("Error: failed to parse result: %s", line);
            return null;
        }
    }
    private void parse_query (string line) {
        recoll_query = line;
    }
    private void parse_total_results (string line) {
        total_results = int.parse (line);
    }
}