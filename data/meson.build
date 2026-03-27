gnome.compile_resources(
  app_id,
  app_id + '.gresource.xml',
  gresource_bundle: true,
  install: true,
  install_dir: get_option('datadir') / 'lumoria',
)

desktop_file = i18n.merge_file(
  input: app_id + '.desktop.in',
  output: app_id + '.desktop',
  type: 'desktop',
  po_dir: '../po',
  install: true,
  install_dir: get_option('datadir') / 'applications',
)

desktop_utils = find_program('desktop-file-validate', required: false)
if desktop_utils.found()
  test('Validate desktop file', desktop_utils, args: [desktop_file])
endif

metainfo_file = i18n.merge_file(
  input: app_id + '.metainfo.xml.in',
  output: app_id + '.metainfo.xml',
  po_dir: '../po',
  install: true,
  install_dir: get_option('datadir') / 'metainfo',
)

appstream_util = find_program('appstream-util', required: false)
if appstream_util.found()
  test('Validate appstream file', appstream_util, args: ['validate-relax', '--nonet', metainfo_file])
endif

install_subdir(
  'icons' / 'hicolor',
  install_dir: get_option('prefix') / get_option('datadir') / 'icons',
  strip_directory: false,
)
