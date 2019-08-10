project('com.github.eugeneia.recall', 'vala', 'c')

gnome = import('gnome')
i18n = import('i18n')

# Set our translation domain
add_global_arguments('-DGETTEXT_PACKAGE="@0@"'.format (meson.project_name()), language:'c')

# Build resources
asresources = gnome.compile_resources (
    'as-resources', join_paths ('data', 'gresource.xml'),
    source_dir: 'data',
    c_name: 'as'
)

# Install GSettings schemas
install_data(
    join_paths ('data', meson.project_name() + '.gschema.xml'),
    install_dir: join_paths(get_option('datadir'), 'glib-2.0', 'schemas')
)

# Install /etc/sysctl.d config
install_data(
    join_paths ('data', meson.project_name() + '.sysctl.conf'),
    rename: '30-' + meson.project_name() + '.conf',
    install_dir: join_paths(get_option('sysconfdir'), 'sysctl.d')
)

# Install icons
icon_sizes = ['48', '64', '128']
foreach i : icon_sizes
    install_data(
        join_paths('data/icons', i + '.svg'),
        install_dir: join_paths(get_option('datadir'), 'icons', 'hicolor', i + 'x' + i, 'apps'),
        rename: meson.project_name() + '.svg'
    )
    install_data(
        join_paths('data/icons', i + '.svg'),
        install_dir: join_paths(get_option('datadir'), 'icons', 'hicolor', i + 'x' + i + '@2', 'apps'),
        rename: meson.project_name() + '.svg'
    )
endforeach

# Create a new executable, list the files we want to compile, list the dependencies we need, and install
executable(
    meson.project_name(),
    'src/Application.vala',
    asresources,
    dependencies: [
        dependency('gtk+-3.0'),
        dependency('granite'),
        meson.get_compiler('vala').find_library('posix')
    ],
    install: true
)

#Translate and install our .desktop file
i18n.merge_file(
    input: join_paths('data', meson.project_name() + '.desktop.in'),
    output: meson.project_name() + '.desktop',
    po_dir: join_paths(meson.source_root(), 'po'),
    type: 'desktop',
    install: true,
    install_dir: join_paths(get_option('datadir'), 'applications')
)

#Translate and install our .contract file
i18n.merge_file(
    input: join_paths('data', meson.project_name() + '.contract.in'),
    output: meson.project_name() + '.contract',
    po_dir: join_paths(meson.source_root(), 'po'),
    type: 'desktop',
    install: true,
    install_dir: join_paths(get_option('datadir'), 'contractor')
)

#Translate and install our .appdata file
i18n.merge_file(
    input: join_paths('data', meson.project_name() + '.appdata.xml.in'),
    output: meson.project_name() + '.appdata.xml',
    po_dir: join_paths(meson.source_root(), 'po'),
    install: true,
    install_dir: join_paths(get_option('datadir'), 'metainfo')
)

subdir('po')

# Post-install actions
meson.add_install_script('post_install.py')
