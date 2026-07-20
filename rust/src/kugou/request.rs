//! 上游请求描述 —— 1:1 对应 .NET 的 `Protocol/Transport/KgRequest.cs`。
//!
//! 一个 [`KgRequest`] 描述"要怎么打酷狗"，但**不含签名**——签名由 transport 层在
//! 发送前注入（对应 .NET 的 `KgSignatureHandler`）。这里只承载 raw api 构造好的
//! 路径/参数/body/签名策略/路由覆盖等信息。

use std::collections::BTreeMap;

use reqwest::Method;

/// 签名策略（对应 SignatureType 枚举）。
///
/// 实际活跃的有 4 种：`Default`（绝大多数）、`V5`（播放链接，额外加 key）、
/// `Web`（扫码登录/迷你乐库，body 不参与签名）、`OfficialAndroid`（评论/听歌识曲）。
/// `Register` / `None` 实际只是 [`KgRequest::not_signature`] / [`KgRequest::clear_default_params`]
/// 开关的载体（源码中 Register 从未被用作签名类型）。
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub enum SignatureType {
    /// V3/V4 常规签名（绝大多数端点）
    #[default]
    Default,
    /// 正式版 Android 签名（评论、听歌识曲），用 OfficialSalt + 官方 appid/clientver
    OfficialAndroid,
    /// V5 获取播放链接专用：Default 签名 + 额外 key 参数
    V5,
    /// Web（扫码登录/迷你乐库），body 不参与签名
    Web,
    /// 枚举保留值；实际等价于 Default（源码未单独处理）
    Register,
    /// 不签名（但仍注入默认参数，除非 clear_default_params）
    None,
}

/// 一个待发送的上游请求描述。
#[derive(Debug, Clone)]
pub struct KgRequest {
    /// HTTP 方法
    pub method: Method,
    /// API 路径，例如 `/v3/search/song`
    pub path: String,
    /// 查询参数（不含签名，签名由 transport 注入）
    pub params: BTreeMap<String, String>,
    /// JSON body（GET 忽略）
    pub body: Option<serde_json::Value>,
    /// 签名策略
    pub signature_type: SignatureType,
    /// 只使用 params 中显式给出的参数，不注入默认 appid/dfid/mid/...（对应 clearDefaultParams）
    pub clear_default_params: bool,
    /// 保留默认参数但不追加 signature（对应 notSignature）
    pub not_signature: bool,
    /// 指定 x-router header，例如 `complexsearch.kugou.com`
    pub specific_router: Option<String>,
    /// 覆盖用的 dfid（很少用，GetPlayUrlAsync 里临时 24 字符 dfid 用到）
    pub specific_dfid: Option<String>,
    /// 指定 BaseUrl（不指定则走默认 gateway）
    pub base_url: Option<String>,
    /// 原始字符串 body（用于注册接口发 Base64 文本）
    pub raw_body: Option<String>,
    /// 二进制 body（用于云盘接口发 AES 后的 bytes / 听歌识曲 PCM）
    pub binary_body: Option<Vec<u8>>,
    /// Content-Type
    pub content_type: String,
    /// 自定义 header
    pub custom_headers: Option<BTreeMap<String, String>>,
    /// 覆盖 session 字段（例如播放链接临时 dfid、userid/token）
    pub session_overrides: Option<BTreeMap<String, String>>,
}

impl KgRequest {
    /// 用 GET + 给定 path 创建，其余字段取默认值（最常见形态）。
    pub fn get(path: impl Into<String>) -> Self {
        Self {
            method: Method::GET,
            path: path.into(),
            params: BTreeMap::new(),
            body: None,
            signature_type: SignatureType::Default,
            clear_default_params: false,
            not_signature: false,
            specific_router: None,
            specific_dfid: None,
            base_url: None,
            raw_body: None,
            binary_body: None,
            content_type: "application/json".into(),
            custom_headers: None,
            session_overrides: None,
        }
    }

    /// 链式设置 method。
    pub fn method(mut self, method: Method) -> Self {
        self.method = method;
        self
    }

    /// 链式插入一个查询参数。
    pub fn param(mut self, key: impl Into<String>, value: impl Into<String>) -> Self {
        self.params.insert(key.into(), value.into());
        self
    }

    /// 链式设置签名策略。
    pub fn signature_type(mut self, t: SignatureType) -> Self {
        self.signature_type = t;
        self
    }

    /// 链式设置 x-router。
    pub fn router(mut self, router: impl Into<String>) -> Self {
        self.specific_router = Some(router.into());
        self
    }

    /// 链式设置 base_url。
    pub fn base_url(mut self, url: impl Into<String>) -> Self {
        self.base_url = Some(url.into());
        self
    }

    /// 链式设置 JSON body（method 会自动改成 POST）。
    pub fn json_body(mut self, value: serde_json::Value) -> Self {
        self.body = Some(value);
        self.method = Method::POST;
        self
    }

    /// 链式设置 raw string body。
    pub fn raw_body(mut self, raw: impl Into<String>) -> Self {
        self.raw_body = Some(raw.into());
        self.method = Method::POST;
        self
    }

    /// 链式设置二进制 body。
    pub fn binary_body(mut self, bytes: Vec<u8>) -> Self {
        self.binary_body = Some(bytes);
        self.method = Method::POST;
        self
    }

    /// 链式覆盖 dfid。
    pub fn specific_dfid(mut self, dfid: impl Into<String>) -> Self {
        self.specific_dfid = Some(dfid.into());
        self
    }

    /// 链式开启 clear_default_params。
    pub fn clear_default_params(mut self) -> Self {
        self.clear_default_params = true;
        self
    }

    /// 链式开启 not_signature。
    pub fn not_signature(mut self) -> Self {
        self.not_signature = true;
        self
    }

    /// 链式追加一个自定义 header（多次调用会累积）。
    pub fn custom_header(mut self, key: impl Into<String>, value: impl Into<String>) -> Self {
        self.custom_headers
            .get_or_insert_with(BTreeMap::new)
            .insert(key.into(), value.into());
        self
    }

    /// 链式覆盖 session 字段（如临时 dfid/userid/token）。
    pub fn session_override(mut self, key: impl Into<String>, value: impl Into<String>) -> Self {
        self.session_overrides
            .get_or_insert_with(BTreeMap::new)
            .insert(key.into(), value.into());
        self
    }
}
