use std::collections::HashMap;
use std::os::raw::{c_char, c_int};
use std::sync::{Mutex, MutexGuard, OnceLock};

use jsonschema::{Draft, Retrieve, Uri, Validator};
use serde_json::Value;

use crate::ffi::{cstr, result_int, result_ptr, set_error};

fn documents() -> &'static Mutex<HashMap<String, Value>> {
    static DOCS: OnceLock<Mutex<HashMap<String, Value>>> = OnceLock::new();
    DOCS.get_or_init(|| Mutex::new(HashMap::new()))
}

fn lock_documents() -> Result<MutexGuard<'static, HashMap<String, Value>>, String> {
    documents()
        .lock()
        .map_err(|_| "schema registry lock poisoned".into())
}

fn insert_document(id: &str, value: Value) -> Result<(), String> {
    let mut docs = lock_documents()?;
    if let Some(schema_id) = value.get("$id").and_then(|v| v.as_str()) {
        docs.insert(schema_id.to_string(), value.clone());
    }
    if let Some(name) = id.rsplit('/').next() {
        docs.insert(name.to_string(), value.clone());
    }
    docs.insert(id.to_string(), value);
    Ok(())
}

fn snapshot() -> Result<HashMap<String, Value>, String> {
    Ok(lock_documents()?.clone())
}

#[derive(Clone)]
struct SchemaRetriever {
    docs: HashMap<String, Value>,
}

impl Retrieve for SchemaRetriever {
    fn retrieve(
        &self,
        uri: &Uri<String>,
    ) -> Result<Value, Box<dyn std::error::Error + Send + Sync>> {
        let key = uri.as_str();
        if let Some(value) = self.docs.get(key) {
            return Ok(value.clone());
        }
        let name = key.rsplit('/').next().unwrap_or(key);
        self.docs
            .get(name)
            .cloned()
            .ok_or_else(|| format!("unknown schema {key}").into())
    }
}

pub struct LumoriaJsonSchema {
    validator: Validator,
}

#[unsafe(no_mangle)]
pub extern "C" fn lumoria_json_schema_register(
    id: *const c_char,
    schema_json: *const c_char,
    error: *mut *mut c_char,
) -> c_int {
    result_int(error, || register(id, schema_json))
}

fn register(id: *const c_char, schema_json: *const c_char) -> Result<(), String> {
    let id = cstr(id)?;
    let value: Value = serde_json::from_str(cstr(schema_json)?).map_err(|e| e.to_string())?;
    insert_document(id, value)
}

#[unsafe(no_mangle)]
pub extern "C" fn lumoria_json_schema_new(
    schema_json: *const c_char,
    error: *mut *mut c_char,
) -> *mut LumoriaJsonSchema {
    result_ptr(error, || compile(schema_json))
}

fn compile(schema_json: *const c_char) -> Result<LumoriaJsonSchema, String> {
    let schema: Value = serde_json::from_str(cstr(schema_json)?).map_err(|e| e.to_string())?;
    let validator = jsonschema::options()
        .with_draft(Draft::Draft202012)
        .with_retriever(SchemaRetriever { docs: snapshot()? })
        .build(&schema)
        .map_err(|e| e.to_string())?;
    Ok(LumoriaJsonSchema { validator })
}

#[unsafe(no_mangle)]
pub extern "C" fn lumoria_json_schema_validate(
    schema: *const LumoriaJsonSchema,
    json: *const c_char,
    error: *mut *mut c_char,
) -> c_int {
    if schema.is_null() {
        set_error(error, "null schema");
        return 0;
    }
    result_int(error, || {
        let instance: Value = serde_json::from_str(cstr(json)?).map_err(|e| e.to_string())?;
        if let Some(err) = unsafe { &*schema }.validator.iter_errors(&instance).next() {
            return Err(format!("{}: {}", err.instance_path, err));
        }
        Ok(())
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn lumoria_json_schema_free(schema: *mut LumoriaJsonSchema) {
    if !schema.is_null() {
        unsafe {
            drop(Box::from_raw(schema));
        }
    }
}
