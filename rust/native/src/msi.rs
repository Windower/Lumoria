use std::collections::{HashMap, HashSet};
use std::fs::File;
use std::io;
use std::os::raw::{c_char, c_int};

use msi::{Package, Row, Select, Value};
use serde_json::{Map, Value as Json, json};

use crate::ffi::{confine_dest, cstr, result_int, result_string};

const SYSTEM_FOLDERS: &[&str] = &[
    "TARGETDIR",
    "ProgramFilesFolder",
    "ProgramFiles64Folder",
    "CommonFilesFolder",
    "CommonFiles64Folder",
    "CommonAppDataFolder",
    "AppDataFolder",
    "LocalAppDataFolder",
    "DesktopFolder",
    "ProgramMenuFolder",
    "StartMenuFolder",
    "StartupFolder",
    "WindowsFolder",
    "SystemFolder",
    "System64Folder",
    "FontsFolder",
    "TempFolder",
    "PersonalFolder",
    "FavoritesFolder",
    "SendToFolder",
    "TemplateFolder",
    "AdminToolsFolder",
    "MyPicturesFolder",
    "NetHoodFolder",
    "PrintHoodFolder",
    "RecentFolder",
    "WindowsVolume",
];

fn cell<'a>(row: &'a Row, column: &str) -> Option<&'a Value> {
    row.has_column(column).then(|| &row[column])
}

fn text(row: &Row, column: &str) -> String {
    match cell(row, column) {
        Some(Value::Str(s)) => s.clone(),
        Some(Value::Int(i)) => i.to_string(),
        _ => String::new(),
    }
}

fn int(row: &Row, column: &str) -> Option<i32> {
    match cell(row, column) {
        Some(Value::Int(i)) => Some(*i),
        _ => None,
    }
}

fn rows(package: &mut Package<File>, table: &str) -> io::Result<Vec<Row>> {
    if !package.has_table(table) {
        return Ok(Vec::new());
    }
    Ok(package.select_rows(Select::table(table))?.collect())
}

/// Netfx 4.x packages still use the pre-standard Assembly / AssemblyName table names.
fn assembly_rows(package: &mut Package<File>) -> io::Result<Vec<Row>> {
    let modern = rows(package, "MsiAssembly")?;
    if !modern.is_empty() {
        return Ok(modern);
    }
    rows(package, "Assembly")
}

fn assembly_name_rows(package: &mut Package<File>) -> io::Result<Vec<Row>> {
    let modern = rows(package, "MsiAssemblyName")?;
    if !modern.is_empty() {
        return Ok(modern);
    }
    rows(package, "AssemblyName")
}

/// DefaultDir is target[:source], each side short|long; a lone dot means "same as parent".
fn dir_names(default_dir: &str) -> (Option<String>, Option<String>) {
    let mut parts = default_dir.splitn(2, ':');
    let target = long_name(parts.next().unwrap_or(""));
    let source = parts.next().map(long_name).unwrap_or_else(|| target.clone());
    (target, source)
}

fn long_name(name: &str) -> Option<String> {
    let long = name.rsplit('|').next().unwrap_or("");
    if long.is_empty() || long == "." { None } else { Some(long.to_string()) }
}

struct Directory {
    parent: String,
    name: Option<String>,
    source: Option<String>,
    /// Directory id this one was redirected to by a SetDirectory custom action.
    alias: Option<String>,
}

fn source_path(id: &str, dirs: &HashMap<String, Directory>) -> String {
    let mut parts = Vec::new();
    let mut current = id;
    while let Some(dir) = dirs.get(current) {
        if let Some(source) = &dir.source {
            parts.push(source.clone());
        }
        if dir.parent.is_empty() {
            break;
        }
        current = &dir.parent;
    }
    parts.reverse();
    parts.join("\\")
}

struct Component {
    directory: String,
    keypath: String,
    win64: bool,
}

const COMPONENT_64BIT: i32 = 0x100;
const FILE_NONCOMPRESSED: i32 = 0x2000;
const FILE_COMPRESSED: i32 = 0x4000;
const WORD_COUNT_COMPRESSED: i32 = 0x2;
const ASSEMBLY_WIN32: i32 = 1;

fn resolve_directory(id: &str, dirs: &HashMap<String, Directory>) -> Json {
    let mut parts = Vec::new();
    let mut current = id;
    for _ in 0..dirs.len() + 1 {
        if SYSTEM_FOLDERS.contains(&current) {
            parts.reverse();
            return json!({ "root": current, "path": parts.join("\\"), "system_root": true });
        }
        let Some(dir) = dirs.get(current) else {
            return Json::Null;
        };
        if let Some(alias) = &dir.alias {
            current = alias;
            continue;
        }
        if let Some(name) = &dir.name {
            parts.push(name.clone());
        }
        if dir.parent.is_empty() {
            parts.reverse();
            return json!({ "root": current, "path": parts.join("\\") });
        }
        current = &dir.parent;
    }
    Json::Null
}

/// Tokens that are not properties are left for the installer.
fn format_properties(text: &str, properties: &Map<String, Json>) -> String {
    let mut out = String::new();
    let mut rest = text;
    while let Some(open) = rest.find('[') {
        let Some(close) = rest[open..].find(']') else { break };
        let token = &rest[open + 1..open + close];
        out.push_str(&rest[..open]);
        match properties.get(token) {
            Some(Json::String(value)) => out.push_str(value),
            _ => out.push_str(&rest[open..open + close + 1]),
        }
        rest = &rest[open + close + 1..];
    }
    out.push_str(rest);
    out
}

fn single_token(text: &str) -> Option<&str> {
    let inner = text.strip_prefix('[')?.strip_suffix(']')?;
    (!inner.is_empty() && !inner.contains('[')).then_some(inner)
}

const CUSTOM_ACTION_TYPE_MASK: i32 = 0x3f;
const CUSTOM_ACTION_SET_DIRECTORY: i32 = 35;
const CUSTOM_ACTION_SET_PROPERTY: i32 = 51;

fn apply_custom_actions(
    package: &mut Package<File>,
    dirs: &mut HashMap<String, Directory>,
    properties: &mut Map<String, Json>,
) -> io::Result<Vec<Json>> {
    let mut actions = HashMap::new();
    for row in rows(package, "CustomAction")? {
        let kind = int(&row, "Type").unwrap_or(0) & CUSTOM_ACTION_TYPE_MASK;
        if kind == CUSTOM_ACTION_SET_DIRECTORY || kind == CUSTOM_ACTION_SET_PROPERTY {
            actions.insert(text(&row, "Action"), (text(&row, "Source"), text(&row, "Target")));
        }
    }

    let mut sequence: Vec<(i32, String, String)> = rows(package, "InstallExecuteSequence")?
        .iter()
        .map(|row| (int(row, "Sequence").unwrap_or(0), text(row, "Action"), text(row, "Condition")))
        .collect();
    sequence.sort_by_key(|(order, _, _)| *order);

    let mut skipped_actions = Vec::new();
    for (_, action, condition) in sequence {
        if !condition.trim().is_empty() {
            if actions.contains_key(&action) {
                skipped_actions.push(json!({
                    "action": action,
                    "condition": condition,
                }));
            }
            continue;
        }
        let Some((source, target)) = actions.get(&action) else { continue };
        let value = format_properties(target, properties);
        if dirs.contains_key(source) {
            if let Some(alias) = single_token(&value)
                && (dirs.contains_key(alias) || SYSTEM_FOLDERS.contains(&alias))
                && alias != source
            {
                if let Some(dir) = dirs.get_mut(source) {
                    dir.alias = Some(alias.to_string());
                }
            }
        } else {
            properties.insert(source.clone(), Json::String(value));
        }
    }
    Ok(skipped_actions)
}

fn read(path: &str) -> Result<Json, String> {
    let mut package = msi::open(path).map_err(|e| e.to_string())?;
    let err = |e: io::Error| e.to_string();

    let mut properties = Map::new();
    for row in rows(&mut package, "Property").map_err(err)? {
        properties.insert(text(&row, "Property"), Json::String(text(&row, "Value")));
    }

    let mut dirs = HashMap::new();
    for row in rows(&mut package, "Directory").map_err(err)? {
        let (name, source) = dir_names(&text(&row, "DefaultDir"));
        dirs.insert(
            text(&row, "Directory"),
            Directory {
                parent: text(&row, "Directory_Parent"),
                name,
                source,
                alias: None,
            },
        );
    }
    let skipped_actions = apply_custom_actions(&mut package, &mut dirs, &mut properties).map_err(err)?;

    let mut directories = Map::new();
    for id in dirs.keys() {
        let mut resolved = resolve_directory(id, &dirs);
        if let Some(object) = resolved.as_object_mut() {
            object.insert("source".into(), Json::String(source_path(id, &dirs)));
        }
        directories.insert(id.clone(), resolved);
    }

    let mut components = HashMap::new();
    for row in rows(&mut package, "Component").map_err(err)? {
        components.insert(
            text(&row, "Component"),
            Component {
                directory: text(&row, "Directory_"),
                keypath: text(&row, "KeyPath"),
                win64: int(&row, "Attributes").unwrap_or(0) & COMPONENT_64BIT != 0,
            },
        );
    }
    let component_win64 = |row: &Row| {
        components.get(&text(row, "Component_")).is_some_and(|c| c.win64)
    };

    let compressed_by_default = package
        .summary_info()
        .word_count()
        .is_some_and(|flags| flags & WORD_COUNT_COMPRESSED != 0);
    let file_rows = rows(&mut package, "File").map_err(err)?;
    let mut files_by_component: HashMap<String, Vec<String>> = HashMap::new();
    let files: Vec<Json> = file_rows
        .iter()
        .map(|row| {
            let component_id = text(row, "Component_");
            let key = text(row, "File");
            files_by_component.entry(component_id.clone()).or_default().push(key.clone());
            let component = components.get(&component_id);
            let attributes = int(row, "Attributes").unwrap_or(0);
            let compressed = if attributes & FILE_COMPRESSED != 0 {
                true
            } else if attributes & FILE_NONCOMPRESSED != 0 {
                false
            } else {
                compressed_by_default
            };
            json!({
                "key": key,
                "directory": component.map(|c| c.directory.as_str()).unwrap_or(""),
                "name": text(row, "FileName").rsplit('|').next().unwrap_or(""),
                "size": int(row, "FileSize").unwrap_or(0),
                "sequence": int(row, "Sequence").unwrap_or(0),
                "win64": component.is_some_and(|c| c.win64),
                "compressed": compressed,
            })
        })
        .collect();

    let mut identity: HashMap<String, HashMap<String, String>> = HashMap::new();
    for row in assembly_name_rows(&mut package).map_err(err)? {
        identity
            .entry(text(&row, "Component_"))
            .or_default()
            .insert(text(&row, "Name"), text(&row, "Value"));
    }
    let name_of = |component: &str, key: &str| {
        identity
            .get(component)
            .and_then(|fields| {
                fields.get(key).or_else(|| {
                    fields.iter().find_map(|(k, v)| (k.eq_ignore_ascii_case(key)).then_some(v))
                })
            })
            .cloned()
            .unwrap_or_default()
    };
    let assemblies: Vec<Json> = assembly_rows(&mut package)
        .map_err(err)?
        .iter()
        .map(|row| {
            let component = text(row, "Component_");
            json!({
                "component": component,
                "file": components.get(&component).map(|c| c.keypath.as_str()).unwrap_or(""),
                "manifest": text(row, "File_Manifest"),
                "application": text(row, "File_Application"),
                "win32": int(row, "Attributes").unwrap_or(0) == ASSEMBLY_WIN32,
                "name": name_of(&component, "name"),
                "version": name_of(&component, "version"),
                "culture": name_of(&component, "culture"),
                "publicKeyToken": name_of(&component, "publicKeyToken"),
                "processorArchitecture": name_of(&component, "processorArchitecture"),
                "files": files_by_component.get(&component).cloned().unwrap_or_default(),
            })
        })
        .collect();

    let media: Vec<Json> = rows(&mut package, "Media")
        .map_err(err)?
        .iter()
        .map(|row| {
            json!({
                "disk": int(row, "DiskId").unwrap_or(0),
                "last_sequence": int(row, "LastSequence").unwrap_or(0),
                "cabinet": text(row, "Cabinet"),
            })
        })
        .collect();

    let registry: Vec<Json> = rows(&mut package, "Registry")
        .map_err(err)?
        .iter()
        .map(|row| {
            json!({
                "root": int(row, "Root").unwrap_or(-1),
                "key": text(row, "Key"),
                "name": text(row, "Name"),
                "value": text(row, "Value"),
                "win64": component_win64(row),
            })
        })
        .collect();

    let mut create_folders: Vec<String> = Vec::new();
    let mut seen_folders = HashSet::new();
    for row in rows(&mut package, "CreateFolder").map_err(err)? {
        let directory = text(&row, "Directory_");
        if seen_folders.insert(directory.clone()) {
            create_folders.push(directory);
        }
    }

    let mut com_servers: Vec<Json> = Vec::new();
    let mut seen_servers = HashSet::new();
    for row in rows(&mut package, "Class").map_err(err)? {
        if let Some(component) = components.get(&text(&row, "Component_"))
            && !component.keypath.is_empty()
            && seen_servers.insert(component.keypath.clone())
        {
            com_servers.push(json!({ "file": component.keypath, "win64": component.win64 }));
        }
    }

    Ok(json!({
        "properties": properties,
        "directories": directories,
        "files": files,
        "media": media,
        "registry": registry,
        "create_folders": create_folders,
        "com_servers": com_servers,
        "assemblies": assemblies,
        "skipped_actions": skipped_actions,
    }))
}

fn extract_stream(path: &str, stream: &str, out_path: &str, root: &str) -> Result<(), String> {
    let out_path = confine_dest(out_path, root)?;
    let mut package = msi::open(path).map_err(|e| e.to_string())?;
    let name = stream.strip_prefix('#').unwrap_or(stream);
    let mut reader = package.read_stream(name).map_err(|e| e.to_string())?;
    let mut out = File::create(&out_path).map_err(|e| e.to_string())?;
    io::copy(&mut reader, &mut out).map_err(|e| e.to_string())?;
    Ok(())
}

#[unsafe(no_mangle)]
pub extern "C" fn lumoria_msi_read(path: *const c_char, error: *mut *mut c_char) -> *mut c_char {
    result_string(error, || read(cstr(path)?).map(|v| v.to_string()))
}

#[unsafe(no_mangle)]
pub extern "C" fn lumoria_msi_extract_stream(
    path: *const c_char,
    stream: *const c_char,
    out_path: *const c_char,
    root: *const c_char,
    error: *mut *mut c_char,
) -> c_int {
    result_int(error, || {
        extract_stream(cstr(path)?, cstr(stream)?, cstr(out_path)?, cstr(root)?)
    })
}
