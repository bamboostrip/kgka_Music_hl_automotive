use serde_json::{json, Value};

use crate::error::AppResult;
use crate::kugou::{
    config, crypto,
    request::{KgRequest, SignatureType},
    session::KgSession,
    transport,
};

pub async fn register_device(
    client: &reqwest::Client,
    _session_key: &str,
    session: &KgSession,
) -> AppResult<bool> {
    if !session.dfid.is_empty() && session.dfid != "-" {
        return Ok(true);
    }

    let client_time = chrono::Utc::now().timestamp();

    let hardware = json!({
        "availableRamSize": 4983533568_i64, "availableRomSize": 48114719_i64, "availableSDSize": 48114717_i64,
        "basebandVer": "", "batteryLevel": 100, "batteryStatus": 3,
        "brand": "Redmi", "buildSerial": "unknown", "device": "marble",
        "imei": session.install_guid, "imsi": "",
        "manufacturer": "Xiaomi", "uuid": session.install_guid,
        "accelerometer": false, "accelerometerValue": "", "gravity": false, "gravityValue": "",
        "gyroscope": false, "gyroscopeValue": "", "light": false, "lightValue": "",
        "magnetic": false, "magneticValue": "", "orientation": false, "orientationValue": "",
        "pressure": false, "pressureValue": "", "step_counter": false, "step_counterValue": "",
        "temperature": false, "temperatureValue": ""
    });

    let aes = crypto::playlist_aes_encrypt(&hardware.to_string());

    let p_data = json!({ "aes": aes.temp_key, "uid": session.userid, "token": session.token });
    let p = crypto::rsa_encrypt_pkcs1(&p_data.to_string(), true).to_uppercase();

    let req = KgRequest::get("/risk/v2/r_register_dev")
        .method(reqwest::Method::POST)
        .base_url("https://userservice.kugou.com")
        .param("part", "1")
        .param("platid", "1")
        .param("p", p)
        .param("clientver", config::CLIENT_VER)
        .param("clienttime", client_time.to_string())
        .param("appid", config::APP_ID)
        .raw_body(aes.cipher_text)
        .not_signature()
        .signature_type(SignatureType::Default);

    let req = req.specific_dfid("-");
    let resp = transport::send(client, session, &req).await?;

    let encrypted = resp
        .get("__raw_base64__")
        .and_then(|v| v.as_str())
        .or_else(|| resp.as_str());
    if let Some(enc) = encrypted.filter(|s| !s.is_empty()) {
        if let Ok(decrypted) = serde_json::from_str::<Value>(&crypto::playlist_aes_decrypt(enc, &aes.temp_key)) {
            if let Some(d5) = decrypted.get("dfid").and_then(|v| v.as_str()).filter(|s| !s.is_empty()) {
                tracing::info!(dfid = %d5, "[device] 注册成功");
                return Ok(true);
            }
        }
    }
    tracing::warn!("[device] 注册失败，未能解析 dfid");
    Ok(false)
}
