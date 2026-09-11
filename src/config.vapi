[CCode (cheader_filename = "config.h")]
namespace Config {
    [CCode (cname = "APP_ID")]
    public const string APP_ID;
    [CCode (cname = "APP_NAME")]
    public const string APP_NAME;
    [CCode (cname = "APP_VERSION")]
    public const string APP_VERSION;
    [CCode (cname = "LOCALE_DIR")]
    public const string LOCALE_DIR;
    [CCode (cname = "RESOURCE_BASE")]
    public const string RESOURCE_BASE;
    [CCode (cname = "MANIFEST_FORMAT_VERSION")]
    public const int MANIFEST_FORMAT_VERSION;
    [CCode (cname = "CONFIG_FORMAT_VERSION")]
    public const int CONFIG_FORMAT_VERSION;
    [CCode (cname = "MANIFEST_BASE_URL")]
    public const string MANIFEST_BASE_URL;
}
