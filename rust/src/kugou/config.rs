//! 酷狗协议硬编码常量 —— 1:1 对应 .NET 的 `util/KuGouConfig.cs` + `util/Constants.cs`。
//!
//! 这些值是酷狗客户端固定下来的，**不可随意修改**，错一个字节签名全崩。
//! 来源见每个常量上方的注释（指向 .NET 字段）。

/// KuGouConfig.AppId（Lite 客户端，绝大多数接口用这个）
pub const APP_ID: &str = "3116";
/// KuGouConfig.ClientVer（Lite 客户端版本）
pub const CLIENT_VER: &str = "11440";
/// KuGouConfig.Version
pub const VERSION: &str = "11440";

/// KuGouConfig.OfficialAppId（正式版 Android 客户端，评论/听歌识曲用）
pub const OFFICIAL_APP_ID: &str = "1005";
/// KuGouConfig.OfficialClientVer
pub const OFFICIAL_CLIENT_VER: &str = "20489";

/// KuGouConfig.UserAgent
pub const USER_AGENT: &str = "Android15-1070-11083-46-0-DiscoveryDRADProtocol-wifi";

// ===== 签名 salts =====
/// KuGouConfig.LiteSalt —— Default / V5 / Register 签名的主 salt
pub const LITE_SALT: &str = "LnT6xpN3khm36zse0QzvmgTZ3waWdRSA";
/// KuGouConfig.OfficialSalt —— OfficialAndroid 签名的 salt
pub const OFFICIAL_SALT: &str = "OIlwieks28dk2k092lksi2UIkp";
/// KuGouConfig.V5KeySalt —— V5 播放链接额外 `key` 参数的 salt
pub const V5_KEY_SALT: &str = "185672dd44712f60bb1736df5a377e82";
/// KuGouConfig.WebSignatureSalt —— Web（扫码登录/迷你乐库）签名的 salt
pub const WEB_SIGNATURE_SALT: &str = "NVPh5oo715z5DIWAeQlhMDsWXXQV4hwt";

// ===== 设备身份占位符 =====
/// KuGouConfig.Dfid —— 初始占位，真实 dfid 由 register/dev 从酷狗拿
pub const DFID_PLACEHOLDER: &str = "-";
/// KuGouConfig.Mid
pub const MID_PLACEHOLDER: &str = "";
/// KuGouConfig.Uuid
pub const UUID_PLACEHOLDER: &str = "-";

// ===== 固定反风控 header（SignatureHandler.cs 始终注入）=====
pub const KG_RC: &str = "1";
pub const KG_THASH: &str = "5d816a0";
pub const KG_REC: &str = "1";
pub const KG_RF: &str = "B9EDA08A64250DEFFBCADDEE00F8F25F";

// ===== 散落的特殊常量（迁移时逐个核对，这里先集中登记）=====
/// RawCommentApi 的评论业务 code 常量
pub const COMMENT_SONG_CODE: &str = "fc4be23b4e972707f36b8a828a93ba8a";
pub const COMMENT_PLAYLIST_CODE: &str = "ca53b96fe5a1d9c22d71c8f522ef7c4f";
pub const COMMENT_ALBUM_CODE: &str = "94f1792ced1df89aa68a7939eaf2efca";

// ===== RSA 公钥（Constants.cs）=====
// 1024 位 RSA，指数 65537。登录 pk 用 PublicLiteRasKey（默认 isLite=true）。
//
// 注：Phase 4 实现登录裸 RSA 模幂时直接用这里的 PEM，无需解析成裸数字。

/// Constants.PublicLiteRasKey（Lite，**默认**，登录 pk 用）
pub const PUBLIC_LITE_RSA_KEY_PEM: &str = "-----BEGIN PUBLIC KEY-----\nMIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDECi0Np2UR87scwrvTr72L6oO01rBbbBPriSDFPxr3Z5syug0O24QyQO8bg27+0+4kBzTBTBOZ/WWU0WryL1JSXRTXLgFVxtzIY41Pe7lPOgsfTCn5kZcvKhYKJesKnnJDNr5/abvTGf+rHG3YRwsCHcQ08/q6ifSioBszvb3QiwIDAQAB\n-----END PUBLIC KEY-----";

/// Constants.PublicRasKey（正式版，isLite=false 时用）
pub const PUBLIC_RSA_KEY_PEM: &str = "-----BEGIN PUBLIC KEY-----\nMIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDIAG7QOELSYoIJvTFJhMpe1s/gbjDJX51HBNnEl5HXqTW6lQ7LC8jr9fWZTwusknp+sVGzwd40MwP6U5yDE27M/X1+UR4tvOGOqp94TJtQ1EPnWGWXngpeIW5GxoQGao1rmYWAu6oi1z9XkChrsUdC6DJE5E221wf/4WLFxwAtRQIDAQAB\n-----END PUBLIC KEY-----";

/// 默认上游网关。对应 .NET KgHttpTransport.cs:18 的 `https://gateway.kugou.com`。
pub const DEFAULT_GATEWAY: &str = "https://gateway.kugou.com";
