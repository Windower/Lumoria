[CCode (cheader_filename = "native/mspack-shim.h", lower_case_cprefix = "lum_cab_")]
namespace MsPack {

    [CCode (cname = "MSPACK_ERR_OK")]
    public const int ERR_OK;

    [Compact]
    [CCode (cname = "struct mscab_decompressor", free_function = "lum_cab_free")]
    public class CabDecompressor {
        [CCode (cname = "lum_cab_new")]
        public CabDecompressor ();

        [CCode (cname = "lum_cab_search")]
        public Cabinet? search (string filename);

        [CCode (cname = "lum_cab_open")]
        public Cabinet? open (string filename);

        [CCode (cname = "lum_cab_close")]
        public void close (Cabinet cab);

        [CCode (cname = "lum_cab_extract")]
        public int extract (CabFile file, string output);

        [CCode (cname = "lum_cab_last_error")]
        public int last_error ();
    }

    [Compact]
    [CCode (cname = "struct mscabd_cabinet", free_function = "")]
    public class Cabinet {
        [CCode (cname = "lum_cab_get_files")]
        public unowned CabFile? get_files ();

        [CCode (cname = "lum_cab_get_next")]
        public unowned Cabinet? get_next ();
    }

    [Compact]
    [CCode (cname = "struct mscabd_file", free_function = "")]
    public class CabFile {
        [CCode (cname = "lum_cabf_get_filename")]
        public unowned string? get_filename ();

        [CCode (cname = "lum_cabf_get_length")]
        public uint get_length ();

        [CCode (cname = "lum_cabf_get_next")]
        public unowned CabFile? get_next ();
    }
}
