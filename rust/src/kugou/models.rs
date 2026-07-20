//! 业务 DTO —— 对应 .NET 的 `Abstractions/Models/`。
//!
//! Phase 1 只迁搜索/歌曲样板域用到的：[`SongInfo`] / [`SingerLite`] /
//! [`SearchResultData`] / [`PlayUrlData`]。其余模型随后续 Phase 逐个补。
//!
//! 字段映射靠 `#[serde(rename = "...")]` 1:1 对应 .NET 的 `[JsonPropertyName]`。

use serde::{Deserialize, Serialize};

/// 把封面图 URL 里的 `{size}` 占位替换成给定尺寸（.NET SongInfo.Cover 的 getter 逻辑）。
/// .NET 固定替换为 "400"。其它模型（PlaylistSong.Cover 等）会替换成 150/250。
pub fn resolve_size_placeholder(url: &str, size: &str) -> String {
    url.replace("{size}", size)
}

/// 歌手精简信息（SongInfo.Singers / PlaylistSong.singerinfo 共用）。
/// 对应 .NET SingerLite。
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct SingerLite {
    /// .NET: id（SingerId）
    #[serde(default, rename = "id")]
    pub id: String,
    /// .NET: name
    #[serde(default, rename = "name")]
    pub name: String,
    /// .NET: avatar → SingerPic（含 {size} 占位）
    #[serde(default, rename = "avatar")]
    pub singer_pic: String,
}

/// 搜索结果中的单首歌曲。对应 .NET SongInfo。
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct SongInfo {
    /// .NET: FileHash
    #[serde(default, rename = "FileHash")]
    pub hash: String,
    /// .NET: FileName
    #[serde(default, rename = "FileName")]
    pub name: String,
    /// .NET: SingerName
    #[serde(default, rename = "SingerName")]
    pub singer: String,
    /// .NET: Singers
    #[serde(default, rename = "Singers")]
    pub singers: Vec<SingerLite>,
    /// .NET: AlbumID
    #[serde(default, rename = "AlbumID")]
    pub album_id: String,
    /// .NET: AlbumName
    #[serde(default, rename = "AlbumName")]
    pub album_name: String,
    /// .NET: Duration（秒）
    #[serde(default, rename = "Duration")]
    pub duration: i64,
    /// .NET: Image → Cover（{size} 替换成 400）。
    /// 反序列化时存原始值，序列化时做替换（与 .NET getter 一致）。
    #[serde(default, rename = "Image")]
    pub image: String,
}

impl SongInfo {
    /// 取已替换 {size} 的封面 URL（对应 .NET SongInfo.Cover getter）。
    pub fn cover(&self) -> String {
        resolve_size_placeholder(&self.image, "400")
    }
}

/// 搜索结果分页数据。对应 .NET SearchResultData。
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct SearchResultData {
    /// .NET: total
    #[serde(default, rename = "total")]
    pub total: i64,
    /// .NET: lists → Songs
    #[serde(default, rename = "lists")]
    pub songs: Vec<SongInfo>,
}

/// 歌曲播放地址结果。对应 .NET PlayUrlData。
///
/// 注意：原始上游响应外层有 status/error_code（由 api_response 解包），
/// 这里只承载 `data` 字段的内容。
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct PlayUrlData {
    /// .NET: url
    #[serde(default, rename = "url")]
    pub urls: Vec<String>,
    /// .NET: hash
    #[serde(default, rename = "hash")]
    pub hash: String,
    /// .NET: priv_status
    #[serde(default, rename = "priv_status")]
    pub priv_status: i64,
    /// .NET: err_code
    #[serde(default, rename = "err_code")]
    pub err_code: i64,
}

impl PlayUrlData {
    /// 是否成功返回可用播放地址（对应 .NET PlayUrlData.IsSuccess）。
    pub fn is_success(&self) -> bool {
        !self.urls.is_empty()
    }
    /// 是否需要 VIP（对应 .NET RequiresVip）。
    pub fn requires_vip(&self) -> bool {
        self.priv_status == 1
    }
    /// 是否需要购买专辑（对应 .NET RequiresAlbumPurchase）。
    pub fn requires_album_purchase(&self) -> bool {
        self.priv_status == 10
    }
}
