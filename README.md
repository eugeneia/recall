# Recall

Full-text file search for your document library.

Simple [recoll](https://www.lesbonscomptes.com/recoll/) frontend for
[ElementaryOS](https://elementary.io/).

## Known Issues

- Recall starts recollindex for real-time indexing automatically, and installs
  an autostart entry. If recollindex exits after the initial index update, you
  might have to increase the sysctl variable `fs.inotify.max_user_watches`.
  