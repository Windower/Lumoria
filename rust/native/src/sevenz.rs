use std::collections::HashMap;
use std::fs::File;
use std::io::{self, Cursor};
use std::os::raw::{c_char, c_int};

use memmap2::Mmap;
use sevenz_rust2::{ArchiveReader, Password};
use serde_json::json;

use crate::ffi::{confine_dest, cstr, result_int, result_string};

const SIGNATURE: [u8; 6] = [b'7', b'z', 0xBC, 0xAF, 0x27, 0x1C];
const SFX_SCAN_LIMIT: usize = 16 << 20;

fn open(path: &str) -> Result<(Mmap, usize), String> {
    let file = File::open(path).map_err(|e| format!("{path}: {e}"))?;
    let map = unsafe { Mmap::map(&file) }.map_err(|e| format!("{path}: {e}"))?;
    let window = &map[..map.len().min(SFX_SCAN_LIMIT)];
    let offset = window
        .windows(SIGNATURE.len())
        .position(|w| w == SIGNATURE)
        .ok_or_else(|| format!("{path}: not a 7z archive"))?;
    Ok((map, offset))
}

fn reader(map: &Mmap, offset: usize) -> Result<ArchiveReader<Cursor<&[u8]>>, String> {
    ArchiveReader::new(Cursor::new(&map[offset..]), Password::empty()).map_err(|e| e.to_string())
}

fn list(path: &str) -> Result<String, String> {
    let (map, offset) = open(path)?;
    let reader = reader(&map, offset)?;
    let entries: Vec<_> = reader
        .archive()
        .files
        .iter()
        .filter(|entry| !entry.is_directory())
        .map(|entry| json!({ "name": entry.name(), "size": entry.size() }))
        .collect();
    Ok(json!(entries).to_string())
}

/// plan maps entry names to destination paths. Solid blocks are decoded in order, so
/// unwanted entries are drained rather than skipped.
fn extract(path: &str, plan: &str, root: &str) -> Result<(), String> {
    let plan: HashMap<String, String> = serde_json::from_str(plan).map_err(|e| e.to_string())?;
    let (map, offset) = open(path)?;
    let mut reader = reader(&map, offset)?;
    let mut remaining = plan.len();

    reader
        .for_each_entries(|entry, data| {
            if entry.is_directory() {
                return Ok(true);
            }
            match plan.get(entry.name()) {
                Some(dest) => {
                    let dest = confine_dest(dest, root)
                        .map_err(|e| io::Error::new(io::ErrorKind::InvalidInput, e))?;
                    if let Some(parent) = dest.parent() {
                        std::fs::create_dir_all(parent)?;
                    }
                    let mut out = File::create(dest)?;
                    io::copy(data, &mut out)?;
                    remaining = remaining.saturating_sub(1);
                }
                None => {
                    io::copy(data, &mut io::sink())?;
                }
            }
            Ok(remaining > 0)
        })
        .map_err(|e| e.to_string())?;

    if remaining != 0 {
        return Err(format!(
            "{path}: {remaining} planned file(s) missing from archive"
        ));
    }
    Ok(())
}

#[unsafe(no_mangle)]
pub extern "C" fn lumoria_7z_list(path: *const c_char, error: *mut *mut c_char) -> *mut c_char {
    result_string(error, || list(cstr(path)?))
}

#[unsafe(no_mangle)]
pub extern "C" fn lumoria_7z_extract(
    path: *const c_char,
    plan_json: *const c_char,
    root: *const c_char,
    error: *mut *mut c_char,
) -> c_int {
    result_int(error, || extract(cstr(path)?, cstr(plan_json)?, cstr(root)?))
}
