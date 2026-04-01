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
        apply_large_address_aware_patch (entry, launched_host_exe, logger);
    }

    private void apply_large_address_aware_patch (
        Models.PrefixEntry entry,
        string launched_host_exe,
        RuntimeLog logger
    ) throws Error {
        var desired_enabled = Utils.Preferences.resolve_large_address_aware (entry.large_address_aware);
        var target_exe = resolve_playonline_host_exe (entry);

        if (Path.get_basename (launched_host_exe).down () != "pol.exe") {
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

    private string resolve_playonline_host_exe (Models.PrefixEntry entry) throws Error {
        var pfx_path = install_prefix_path (entry.path);
        string exe;
        string[] args;
        var launcher_specs = Models.LauncherSpec.load_all_from_resource ();
        resolve_launcher_exe (entry, launcher_specs, "pol", out exe, out args);

        var host_exe = resolve_host_path (exe, pfx_path);
        if (!FileUtils.test (host_exe, FileTest.EXISTS)) {
            throw new IOError.FAILED ("PlayOnline executable not found for patching: %s", host_exe);
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
            throw new IOError.FAILED ("Invalid PE file (too small): %s", exe_path);
        }
        if (data[0] != 'M' || data[1] != 'Z') {
            throw new IOError.FAILED ("Invalid PE file (missing MZ header): %s", exe_path);
        }

        var pe_offset = (int) read_le32 (data, DOS_E_LFANEW_OFFSET);
        var min_size = pe_offset + 4 + COFF_CHARACTERISTICS_OFFSET + 2;
        if (pe_offset < 0 || min_size > data.length) {
            throw new IOError.FAILED ("Invalid PE file (bad PE header offset): %s", exe_path);
        }

        if (data[pe_offset] != 'P'
            || data[pe_offset + 1] != 'E'
            || data[pe_offset + 2] != 0
            || data[pe_offset + 3] != 0) {
            throw new IOError.FAILED ("Invalid PE file (missing PE signature): %s", exe_path);
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
        FileUtils.set_data (exe_path, data);

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
