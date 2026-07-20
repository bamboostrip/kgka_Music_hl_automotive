//! 酷狗会话 —— 对应 .NET 的 `Protocol/Session/KgSession.cs` + `KgSessionManager`。
//!
//! 一个 [`KgSession`] 承载当前调用方的设备身份 + 登录态：
//! - 设备身份：`dfid` / `mid` / `uuid` / `install_guid` / `install_mac` / `install_dev`
//! - 登录态：`userid` / `token` / `vip_type` / `vip_token` / `t1`
//!
//! 匿名会话：`userid="0"`、`token=""`、`dfid="-"`。
//! 登录会话：登录成功后由 [`KgSession::update_auth`] 写回。
//! 设备注册后：`dfid/mid/uuid` 被真实值替换（不再为 `-`）。

use crate::kugou::crypto;

/// 酷狗会话状态。
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct KgSession {
    pub userid: String,
    pub token: String,
    pub vip_type: String,
    pub vip_token: String,
    pub dfid: String,
    pub mid: String,
    pub uuid: String,
    pub install_dev: String,
    pub install_mac: String,
    pub install_guid: String,
    pub t1: String,
}

impl Default for KgSession {
    /// 与 .NET KgSession 的字段默认值一致。
    fn default() -> Self {
        Self {
            userid: "0".into(),
            token: String::new(),
            vip_type: "0".into(),
            vip_token: String::new(),
            dfid: "-".into(),
            mid: "-".into(),
            uuid: "-".into(),
            install_dev: String::new(),
            install_mac: String::new(),
            install_guid: String::new(),
            t1: String::new(),
        }
    }
}

impl KgSession {
    /// 是否已登录（对应 .NET IsLoggedIn）：userid 非 "0" 且 token 非空。
    pub fn is_logged_in(&self) -> bool {
        self.userid != "0" && !self.token.is_empty()
    }

    /// 用 InstallGuid 派生 mid（CalcNewMid），并据此派生 uuid（md5(dfid+mid)）。
    /// 对应 SignatureHandler 里的设备身份解析（不读 session.mid，而是现算）。
    ///
    /// 注意：.NET 用的是 dfid 派生 mid/uuid（不是 install_guid）；这里 dfid 可以为 `-`。
    pub fn derive_device_identity(d5_dfid: &str) -> (String, String) {
        let mid = crypto::calc_new_mid(d5_dfid);
        let uuid = crypto::md5_str(&format!("{}{}", d5_dfid, mid));
        (mid, uuid)
    }

    /// 规范化一个新建/从库读出的 session：补齐缺失的设备指纹字段，
    /// 并在 mid 缺失时用 install_guid 派生。对应 KgSessionManager 构造函数的归一化逻辑。
    pub fn normalize(&mut self) {
        if self.install_guid.is_empty() {
            self.install_guid = uuid::Uuid::new_v4().simple().to_string();
        }
        if self.install_mac.is_empty() {
            self.install_mac = uuid::Uuid::new_v4().simple().to_string();
        }
        if self.install_dev.is_empty() {
            self.install_dev = crypto::random_string(16);
        }
        if self.mid.is_empty() || self.mid == "-" || self.mid.len() < 30 {
            self.mid = crypto::calc_new_mid(&self.install_guid);
        }
        if self.dfid.is_empty() {
            self.dfid = "-".into();
        }
        if self.dfid == "-" {
            self.uuid = "-".into();
        }
    }

    /// 登录成功后写回凭证。对应 KgSessionManager.UpdateAuth。
    pub fn update_auth(
        &mut self,
        userid: impl Into<String>,
        token: impl Into<String>,
        vip_type: impl Into<String>,
        vip_token: impl Into<String>,
        t1: impl Into<String>,
    ) {
        self.userid = userid.into();
        self.token = token.into();
        self.vip_type = vip_type.into();
        self.vip_token = vip_token.into();
        self.t1 = t1.into();
    }

    /// 登出：清空凭证 + 重置 dfid。对应 KgSessionManager.Logout（保留 install 设备指纹）。
    pub fn logout(&mut self) {
        self.userid = "0".into();
        self.token.clear();
        self.vip_type = "0".into();
        self.vip_token.clear();
        self.t1.clear();
        self.dfid = "-".into();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn anonymous_session_defaults() {
        let s = KgSession::default();
        assert!(!s.is_logged_in());
        assert_eq!(s.userid, "0");
        assert_eq!(s.dfid, "-");
    }

    #[test]
    fn normalize_fills_device_fingerprints() {
        let mut s = KgSession::default();
        s.normalize();
        assert_eq!(s.install_guid.len(), 32);
        assert_eq!(s.install_dev.len(), 16);
        assert_ne!(s.mid, "-");
        assert!(s.mid.chars().all(|c| c.is_ascii_digit()));
        assert_eq!(s.uuid, "-");
    }

    #[test]
    fn derive_identity_for_real_dfid() {
        let (mid, uuid) = KgSession::derive_device_identity("somereald5");
        assert!(mid.chars().all(|c| c.is_ascii_digit()));
        assert_eq!(uuid.len(), 32);
        assert_eq!(uuid, crypto::md5_str(&format!("somereald5{}", mid)));
    }

    #[test]
    fn login_state_toggle() {
        let mut s = KgSession::default();
        s.update_auth("12345", "tok", "1", "viptok", "t1val");
        assert!(s.is_logged_in());
        s.logout();
        assert!(!s.is_logged_in());
        assert_eq!(s.userid, "0");
    }
}
