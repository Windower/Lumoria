#pragma once

#ifdef __cplusplus
extern "C" {
#endif

typedef struct LumoriaJsonSchema LumoriaJsonSchema;

int lumoria_json_schema_register (const char *id, const char *schema_json, char **error);
LumoriaJsonSchema *lumoria_json_schema_new (const char *schema_json, char **error);
int lumoria_json_schema_validate (const LumoriaJsonSchema *schema, const char *json, char **error);
void lumoria_json_schema_free (LumoriaJsonSchema *schema);

char *lumoria_msi_read (const char *path, char **error);
int lumoria_msi_extract_stream (const char *path, const char *stream, const char *out_path, const char *root, char **error);

char *lumoria_7z_list (const char *path, char **error);
int lumoria_7z_extract (const char *path, const char *plan_json, const char *root, char **error);

void lumoria_native_string_free (char *value);

#ifdef __cplusplus
}
#endif
