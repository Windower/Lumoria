use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_int};
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::path::{Component, Path, PathBuf};
use std::ptr;

pub fn clear_error(slot: *mut *mut c_char) {
    if slot.is_null() {
        return;
    }
    unsafe {
        if !(*slot).is_null() {
            let _ = CString::from_raw(*slot);
        }
        *slot = ptr::null_mut();
    }
}

pub fn set_error(slot: *mut *mut c_char, message: impl AsRef<str>) {
    if slot.is_null() {
        return;
    }
    unsafe {
        if !(*slot).is_null() {
            let _ = CString::from_raw(*slot);
        }
        *slot = CString::new(message.as_ref())
            .map(|value| value.into_raw())
            .unwrap_or(ptr::null_mut());
    }
}

pub fn cstr<'a>(ptr: *const c_char) -> Result<&'a str, String> {
    if ptr.is_null() {
        return Err("null string".into());
    }
    unsafe { CStr::from_ptr(ptr) }
        .to_str()
        .map_err(|e| e.to_string())
}

pub fn into_c_string(value: String) -> *mut c_char {
    CString::new(value)
        .map(|value| value.into_raw())
        .unwrap_or(ptr::null_mut())
}

/// Runs body with panics converted to an error string; unwinding across an extern "C" boundary aborts the host.
pub fn guarded<T>(body: impl FnOnce() -> Result<T, String>) -> Result<T, String> {
    match catch_unwind(AssertUnwindSafe(body)) {
        Ok(result) => result,
        Err(payload) => {
            let message = payload
                .downcast_ref::<&str>()
                .map(|s| s.to_string())
                .or_else(|| payload.downcast_ref::<String>().cloned())
                .unwrap_or_else(|| "panic in native code".to_string());
            Err(message)
        }
    }
}

pub fn result_int(error: *mut *mut c_char, body: impl FnOnce() -> Result<(), String>) -> c_int {
    match guarded(body) {
        Ok(()) => {
            clear_error(error);
            1
        }
        Err(message) => {
            set_error(error, message);
            0
        }
    }
}

pub fn result_ptr<T>(error: *mut *mut c_char, body: impl FnOnce() -> Result<T, String>) -> *mut T {
    match guarded(body) {
        Ok(value) => {
            clear_error(error);
            Box::into_raw(Box::new(value))
        }
        Err(message) => {
            set_error(error, message);
            ptr::null_mut()
        }
    }
}

pub fn confine_dest(dest: &str, root: &str) -> Result<PathBuf, String> {
    let dest = Path::new(dest);
    let root = Path::new(root);
    if dest.components().any(|c| matches!(c, Component::ParentDir)) {
        return Err(format!(
            "{}: destination escapes {}",
            dest.display(),
            root.display()
        ));
    }

    let joined = if dest.is_absolute() {
        dest.to_path_buf()
    } else {
        root.join(dest)
    };
    let root_canon = canonicalize_root(root)?;
    let resolved = resolve_existing_prefix(&joined)?;
    if !resolved.starts_with(&root_canon) {
        return Err(format!(
            "{}: destination escapes {}",
            resolved.display(),
            root.display()
        ));
    }
    Ok(resolved)
}

fn canonicalize_root(root: &Path) -> Result<PathBuf, String> {
    match root.canonicalize() {
        Ok(path) => Ok(path),
        Err(_) if root.is_absolute() => Ok(root.to_path_buf()),
        Err(error) => Err(format!("{}: {error}", root.display())),
    }
}

fn resolve_existing_prefix(path: &Path) -> Result<PathBuf, String> {
    let mut current = path.to_path_buf();
    let mut suffix = Vec::new();
    loop {
        match current.canonicalize() {
            Ok(canon) => {
                let mut resolved = canon;
                for part in suffix.iter().rev() {
                    resolved.push(part);
                }
                return Ok(resolved);
            }
            Err(_) => match current.file_name() {
                Some(name) => {
                    suffix.push(name.to_os_string());
                    match current.parent() {
                        Some(parent) if parent != current.as_path() => {
                            current = parent.to_path_buf();
                        }
                        _ => return Ok(path.to_path_buf()),
                    }
                }
                None => return Ok(path.to_path_buf()),
            },
        }
    }
}

pub fn result_string(error: *mut *mut c_char, body: impl FnOnce() -> Result<String, String>) -> *mut c_char {
    match guarded(body) {
        Ok(value) => {
            clear_error(error);
            into_c_string(value)
        }
        Err(message) => {
            set_error(error, message);
            ptr::null_mut()
        }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn lumoria_native_string_free(value: *mut c_char) {
    if !value.is_null() {
        unsafe {
            let _ = CString::from_raw(value);
        }
    }
}
