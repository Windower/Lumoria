lumoria_sources = files(
  'main.vala',

  'models/base-spec.vala',
  'models/common.vala',
  'models/prefix-entry.vala',
  'models/prefix-registry.vala',
  'models/runner-spec.vala',
  'models/component-spec.vala',
  'models/installer-spec.vala',
  'models/launcher-spec.vala',
  'models/defaults-spec.vala',
  'models/tool-spec.vala',
  'models/tool-adapters.vala',
  'models/redist-spec.vala',

  'utils/paths.vala',
  'utils/environment.vala',
  'utils/filesystem.vala',
  'utils/web.vala',
  'utils/integrity.vala',
  'utils/preferences.vala',
  'utils/archive.vala',

  'runtime/runner-download.vala',
  'runtime/logging.vala',
  'runtime/wine.vala',
  'runtime/install.vala',
  'runtime/redist.vala',
  'runtime/run.vala',
  'runtime/prelaunch-patches.vala',
  'runtime/launch-resolver.vala',
  'runtime/components.vala',

  'widgets/application.vala',
  'widgets/prefix-row-widget.vala',
  'widgets/services/prefix-launch-service.vala',
  'widgets/icon-registry.vala',
  'widgets/settings-shared.vala',
  'widgets/window.vala',
  'widgets/dialogs/create-prefix-dialog.vala',
  'widgets/dialogs/manage-prefix-dialog.vala',
  'widgets/dialogs/runner-settings-shared.vala',
  'widgets/dialogs/wine-tools-dialog.vala',
  'widgets/dialogs/preferences-dialog.vala',
  'widgets/dialogs/install-dialog.vala',
  'widgets/dialogs/terminal-dialog.vala',

  'widgets/preferences/general-page.vala',
  'widgets/preferences/runtime-page.vala',
  'widgets/preferences/env-vars-editor.vala',
  'widgets/preferences/advanced-page.vala',
  'widgets/preferences/runners-page.vala',
  'widgets/preferences/components-page.vala',
  'widgets/preferences/tool-group.vala',
  'widgets/preferences/version-row.vala',
)

vapi_dir = meson.current_source_dir() / 'vapi'

lumoria_deps = [
  config_dep,
  dependency('gtk4'),
  dependency('glib-2.0'),
  dependency('libadwaita-1', version: '>= 1.6'),
  dependency('json-glib-1.0'),
  dependency('libsoup-3.0'),
  dependency('gee-0.8'),
  dependency('libarchive'),
  dependency('vte-2.91-gtk4'),
]

cc = meson.get_compiler('c')
mspack_c_dep = cc.find_library('mspack')
mspack_shim = files('native/mspack-shim.c')


lumoria_vala_args = [
  '--vapidir', vapi_dir,
  '--pkg', 'posix',
  '--pkg', 'libarchive',
  '--pkg', 'mspack'
]

executable(
  'lumoria',
  lumoria_sources, mspack_shim,
  vala_args: lumoria_vala_args,
  include_directories: config_inc,
  dependencies: [lumoria_deps, mspack_c_dep],
  install: true,
)
