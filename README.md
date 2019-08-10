# Recall

Full-text file search for your document library.

Simple [recoll](https://www.lesbonscomptes.com/recoll/) frontend for
[ElementaryOS](https://elementary.io/).

## Notes

- Recall manages a dedicated recoll configuration directory in
  `~/.config/com.github.eugeneia.recall` (i.e., it does not overlap with the
  default recall configuration directory)

## Known Issues

- Recall starts recollindex for real-time indexing automatically, and installs
  an autostart entry. If recollindex exits after the initial index update, you
  might have to increase the sysctl variable `fs.inotify.max_user_watches`.
  (Recall installs an extentsion in `/etc/sysctl.d` that sets it to
  approximately twice the default.)
