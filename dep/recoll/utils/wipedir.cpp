/* Copyright (C) 2004-2019 J.F.Dockes
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation; either version 2 of the License, or
 *   (at your option) any later version.
 *
 *   This program is distributed in the hope that it will be useful,
 *   but WITHOUT ANY WARRANTY; without even the implied warranty of
 *   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *   GNU General Public License for more details.
 *
 *   You should have received a copy of the GNU General Public License
 *   along with this program; if not, write to the
 *   Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */
#include "autoconfig.h"

#include "wipedir.h"

#include <stdio.h>
#include <errno.h>
#include <dirent.h>

#include <cstring>
#include <string>

#include "log.h"
#include "pathut.h"

#ifdef _WIN32
#include "safefcntl.h"
#include "safeunistd.h"
#include "safewindows.h"
#include "safesysstat.h"
#include "transcode.h"

#define STAT _wstati64
#define LSTAT _wstati64
#define STATBUF _stati64
#define ACCESS _waccess
#define OPENDIR _wopendir
#define CLOSEDIR _wclosedir
#define READDIR _wreaddir
#define DIRENT _wdirent
#define DIRHDL _WDIR
#define UNLINK _wunlink
#define RMDIR _wrmdir

#else // Not windows ->

#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>

#define STAT stat
#define LSTAT lstat
#define STATBUF stat
#define ACCESS access
#define OPENDIR opendir
#define CLOSEDIR closedir
#define READDIR readdir
#define DIRENT dirent
#define DIRHDL DIR
#define UNLINK unlink
#define RMDIR rmdir
#endif

using namespace std;

int wipedir(const string& dir, bool selfalso, bool recurse)
{
    struct STATBUF st;
    int statret;
    int ret = -1;

    SYSPATH(dir, sysdir);
    statret = LSTAT(sysdir, &st);
    if (statret == -1) {
	LOGSYSERR("wipedir", "stat", dir);
	return -1;
    }
    if (!S_ISDIR(st.st_mode)) {
	LOGERR("wipedir: " << dir << " not a directory\n");
	return -1;
    }

    if (ACCESS(sysdir, R_OK|W_OK|X_OK) < 0) {
	LOGSYSERR("wipedir", "access", dir);
	return -1;
    }

    DIRHDL *d = OPENDIR(sysdir);
    if (d == 0) {
	LOGSYSERR("wipedir", "opendir", dir);
	return -1;
    }
    int remaining = 0;
    struct DIRENT *ent;
    while ((ent = READDIR(d)) != 0) {
#ifdef _WIN32
        string sdname;
        if (!wchartoutf8(ent->d_name, sdname)) {
            continue;
        }
        const char *dname = sdname.c_str();
#else
        const char *dname = ent->d_name;
#endif
	if (!strcmp(dname, ".") || !strcmp(dname, "..")) 
	    continue;

	string fn = path_cat(dir, dname);

        SYSPATH(fn, sysfn);
	struct STATBUF st;
	int statret = LSTAT(sysfn, &st);
	if (statret == -1) {
	    LOGSYSERR("wipedir", "stat", fn);
	    goto out;
	}
	if (S_ISDIR(st.st_mode)) {
	    if (recurse) {
		int rr = wipedir(fn, true, true);
		if (rr == -1) 
		    goto out;
		else 
		    remaining += rr;
	    } else {
		remaining++;
	    }
	} else {
	    if (UNLINK(sysfn) < 0) {
		LOGSYSERR("wipedir", "unlink", fn);
		goto out;
	    }
	}
    }

    ret = remaining;
    if (selfalso && ret == 0) {
	if (RMDIR(sysdir) < 0) {
	    LOGSYSERR("wipedir", "rmdir", dir);
	    ret = -1;
	}
    }

out:
    if (d)
	CLOSEDIR(d);
    return ret;
}
