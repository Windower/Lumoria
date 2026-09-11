namespace Lumoria.Runtime {

    private const uint16 IMAGE_FILE_LARGE_ADDRESS_AWARE = 0x0020;
    private const int DOS_E_LFANEW_OFFSET = 0x3c;
    private const int COFF_CHARACTERISTICS_OFFSET = 18;

    private enum LargeAddressAwarePatchResult {
        PATCHED_ENABLED,
        PATCHED_DISABLED,
        ALREADY_ENABLED,
        ALREADY_DISABLED,
        SKIPPED
    }

    public void apply_prelaunch_patches (
        Models.PrefixEntry entry,
        string launched_host_exe,
        RuntimeLog logger
    ) throws Error {
        var installer = Models.ManifestRepository.shared ().require_installer (
            entry.installer_id
        );
        foreach (var patch in installer.patches) {
            if (patch.patch_type == "pe_characteristic"
                && patch.setting == Models.InstallerPatch.SETTING_LARGE_ADDRESS_AWARE
                && patch.flag == "IMAGE_FILE_LARGE_ADDRESS_AWARE") {
                apply_large_address_aware_patch (
                    entry,
                    installer,
                    patch,
                    launched_host_exe,
                    entry.large_address_aware == true,
                    logger
                );
                continue;
            }
            throw new LumoriaError.INVALID_MANIFEST (
                "Unsupported installer patch operation: %s", patch.id
            );
        }
    }

    private void apply_large_address_aware_patch (
        Models.PrefixEntry entry,
        Models.InstallerManifest installer,
        Models.InstallerPatch patch,
        string launched_host_exe,
        bool desired_enabled,
        RuntimeLog logger
    ) throws Error {
        var target_exe = resolve_patch_target (
            entry, installer, patch, desired_enabled
        );
        if (target_exe == "") return;

        if (Path.get_basename (launched_host_exe).down () != Path.get_basename (target_exe).down ()) {
            logger.typed (LogType.PATCH,
                "checking large_address_aware on %s before launching %s".printf (
                    Path.get_basename (target_exe),
                    Path.get_basename (launched_host_exe)
                )
            );
        }

        var result = set_large_address_aware_state (target_exe, desired_enabled);
        switch (result) {
            case LargeAddressAwarePatchResult.PATCHED_ENABLED:
                logger.typed (LogType.PATCH, "enabled large_address_aware on %s".printf (target_exe));
                break;
            case LargeAddressAwarePatchResult.PATCHED_DISABLED:
                logger.typed (LogType.PATCH, "disabled large_address_aware on %s".printf (target_exe));
                break;
            case LargeAddressAwarePatchResult.ALREADY_ENABLED:
                logger.typed (LogType.PATCH, "large_address_aware already enabled on %s".printf (target_exe));
                break;
            case LargeAddressAwarePatchResult.ALREADY_DISABLED:
                logger.typed (LogType.PATCH, "large_address_aware already disabled on %s".printf (target_exe));
                break;
            case LargeAddressAwarePatchResult.SKIPPED:
                logger.typed (LogType.PATCH, "skip large_address_aware on %s".printf (target_exe));
                break;
            default:
                break;
        }
    }

    private string resolve_patch_target (
        Models.PrefixEntry entry,
        Models.InstallerManifest installer,
        Models.InstallerPatch patch,
        bool require_existing
    ) throws Error {
        var pfx_path = PrefixPaths.from_entry (entry).wine_prefix;
        if (patch.target == "") {
            throw new LumoriaError.INVALID_MANIFEST (
                "Installer patch '%s' has no target", patch.id
            );
        }

        var arch = effective_wine_arch (entry);
        var vars = build_launch_vars (pfx_path, entry, installer, arch);
        var target = Utils.expand_vars (patch.target, vars);
        var host_exe = resolve_host_path (target, pfx_path).replace ("\\", "/");
        if (arch == "win32") {
            host_exe = host_exe.replace ("/drive_c/Program Files (x86)/", "/drive_c/Program Files/");
        }

        if (!FileUtils.test (host_exe, FileTest.EXISTS)) {
            if (!require_existing) return "";
            throw new LumoriaError.NOT_FOUND (
                "Installer patch target executable not found: %s", host_exe
            );
        }

        return host_exe;
    }

    private LargeAddressAwarePatchResult set_large_address_aware_state (
        string exe_path,
        bool enabled
    ) throws Error {
        uint8[] data;
        FileUtils.get_data (exe_path, out data);

        if (data.length < DOS_E_LFANEW_OFFSET + 4) {
            throw new LumoriaError.FAILED ("Invalid PE file (too small): %s", exe_path);
        }
        if (data[0] != 'M' || data[1] != 'Z') {
            throw new LumoriaError.FAILED ("Invalid PE file (missing MZ header): %s", exe_path);
        }

        var pe_offset = (int) read_le32 (data, DOS_E_LFANEW_OFFSET);
        var min_size = pe_offset + 4 + COFF_CHARACTERISTICS_OFFSET + 2;
        if (pe_offset < 0 || min_size > data.length) {
            throw new LumoriaError.FAILED ("Invalid PE file (bad PE header offset): %s", exe_path);
        }

        if (data[pe_offset] != 'P'
            || data[pe_offset + 1] != 'E'
            || data[pe_offset + 2] != 0
            || data[pe_offset + 3] != 0) {
            throw new LumoriaError.FAILED ("Invalid PE file (missing PE signature): %s", exe_path);
        }

        var characteristics_offset = pe_offset + 4 + COFF_CHARACTERISTICS_OFFSET;
        var characteristics = read_le16 (data, characteristics_offset);
        var currently_enabled = (characteristics & IMAGE_FILE_LARGE_ADDRESS_AWARE) != 0;

        if (currently_enabled == enabled) {
            return enabled
                ? LargeAddressAwarePatchResult.ALREADY_ENABLED
                : LargeAddressAwarePatchResult.ALREADY_DISABLED;
        }

        if (enabled) {
            characteristics |= IMAGE_FILE_LARGE_ADDRESS_AWARE;
        } else {
            characteristics &= (uint16) ~IMAGE_FILE_LARGE_ADDRESS_AWARE;
        }

        write_le16 (data, characteristics_offset, characteristics);
        Posix.Stat st;
        var mode = Posix.stat (exe_path, out st) == 0 ? (int) (st.st_mode & 0777) : -1;
        Utils.write_bytes_atomic (exe_path, data, mode);

        return enabled
            ? LargeAddressAwarePatchResult.PATCHED_ENABLED
            : LargeAddressAwarePatchResult.PATCHED_DISABLED;
    }

    private uint16 read_le16 (uint8[] data, int offset) {
        return (uint16) ((uint16) data[offset] | ((uint16) data[offset + 1] << 8));
    }

    private uint32 read_le32 (uint8[] data, int offset) {
        return (uint32) (
            (uint32) data[offset]
            | ((uint32) data[offset + 1] << 8)
            | ((uint32) data[offset + 2] << 16)
            | ((uint32) data[offset + 3] << 24)
        );
    }

    private void write_le16 (uint8[] data, int offset, uint16 value) {
        data[offset] = (uint8) (value & 0xff);
        data[offset + 1] = (uint8) ((value >> 8) & 0xff);
    }
}
