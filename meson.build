project(
  'net.windower.Lumoria',
  ['c', 'vala'],
  version: '0.1.0',
  meson_version: '>= 1.0.0',
  license: 'GPL-3.0-or-later',
)

i18n = import('i18n')
gnome = import('gnome')
valac = meson.get_compiler('vala')

app_id = meson.project_name()
src_dir = meson.project_source_root() / 'src'

config_h = configuration_data()
config_h.set_quoted('APP_NAME', meson.project_name().split('.')[2])
config_h.set_quoted('APP_ID', meson.project_name())
config_h.set_quoted('APP_VERSION', meson.project_version())
config_h.set_quoted('LOCALE_DIR', join_paths(get_option('prefix'), get_option('localedir')))
config_h.set_quoted('RESOURCE_BASE', join_paths('/', meson.project_name().replace('.', '/')))
configure_file(output: 'config.h', configuration: config_h)

config_dep = valac.find_library('config', dirs: src_dir)
config_inc = include_directories('.')

add_global_arguments('-DGETTEXT_PACKAGE="@0@"'.format(meson.project_name()), language: 'c')

subdir('data')
subdir('src')
subdir('po')

gnome.post_install(
  gtk_update_icon_cache: true,
  update_desktop_database: true,
)
