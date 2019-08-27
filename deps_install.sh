#!/bin/sh

# Recall depends on recoll, but recoll ships with a GUI on Ubuntu and
# ElemenatryOS will not accept applications into AppCenter that pull in other
# GUI apps. Hence, we vendor recoll and build/ship it without the QT GUI.
#
# Note: the package will confict with/replace recoll.

set -e

# Packaging tools define DESTDIR, don't install for dev builds
if [ -z "${RECALL_USE_SYSTEM_RECOLL}" ] || [ -z "${DESTDIR}" ]; then
    cd "${MESON_SOURCE_ROOT}/dep/recoll"
    ./configure --prefix="${MESON_INSTALL_PREFIX}" \
                --disable-qtgui --disable-webkit --enable-recollq
    make -j install
    # E: com.github.eugeneia.recall: package-installs-python-pycache-dir
    find "${DESTDIR}${MESON_INSTALL_PREFIX}" \
         -name "__pycache__" -type d -exec rm -r "{}" \; || true
    # E: com.github.eugeneia.recall: non-empty-dependency_libs-in-la-file
    sed -i "/dependency_libs/ s/'.*'/''/" \
        $(find "${DESTDIR}${MESON_INSTALL_PREFIX}" -name '*.la')
fi
