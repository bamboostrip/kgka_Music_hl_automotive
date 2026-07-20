use serde_json::{json, Value};

use crate::error::AppResult;
use crate::kugou::{
    config, crypto,
    request::{KgRequest, SignatureType},
    session::KgSession,
    signer,
    transport,
};

pub async fn video_detail(client: &reqwest::Client, session: &KgSession, ids: &str) -> AppResult<Value> {
    let now = chrono::Utc::now().timestamp();
    let mid = crypto::calc_new_mid(&session.dfid);
    let data: Vec<Value> = ids.split(',').filter(|s| !s.trim().is_empty())
        .map(|id| json!({ "video_id": id.trim() })).collect();
    let body = json!({
        "appid": config::APP_ID, "clientver": config::CLIENT_VER, "clienttime": now,
        "mid": mid, "uuid": crypto::md5_str(&format!("{}{}", session.dfid, mid)),
        "dfid": session.dfid, "token": session.token,
        "key": signer::calc_login_key(now), "show_resolution": 1, "data": data
    });
    let req = KgRequest::get("/v1/video")
        .method(reqwest::Method::POST)
        .clear_default_params()
        .router("kmr.service.kugou.com")
        .json_body(body)
        .signature_type(SignatureType::Default);
    transport::send(client, session, &req).await
}

pub async fn longaudio_album_detail(client: &reqwest::Client, session: &KgSession, album_ids: &str) -> AppResult<Value> {
    let data: Vec<Value> = album_ids.split(',').filter(|s| !s.trim().is_empty())
        .map(|id| json!({ "album_id": id.trim() })).collect();
    let body = json!({
        "data": data, "show_album_tag": 1,
        "fields": "album_name,album_id,category,authors,sizable_cover,intro,author_name,trans_param,album_tag,mix_intro,full_intro,is_publish"
    });
    let req = KgRequest::get("/openapi/v2/broadcast")
        .method(reqwest::Method::POST)
        .custom_header("kg-tid", "78")
        .json_body(body)
        .signature_type(SignatureType::Default);
    transport::send(client, session, &req).await
}

pub async fn longaudio_album_audios(client: &reqwest::Client, session: &KgSession, album_id: &str, page: i64, pagesize: i64) -> AppResult<Value> {
    let body = json!({ "album_id": album_id, "area_code": 1, "tagid": 0, "page": page, "pagesize": pagesize });
    let req = KgRequest::get("/longaudio/v2/album_audios")
        .method(reqwest::Method::POST)
        .router("openapi.kugou.com")
        .custom_header("kg-tid", "78")
        .json_body(body)
        .signature_type(SignatureType::Default);
    transport::send(client, session, &req).await
}

pub async fn longaudio_daily_recommend(client: &reqwest::Client, session: &KgSession, page: i64, pagesize: i64) -> AppResult<Value> {
    let req = KgRequest::get("/longaudio/v1/home_new/daily_recommend")
        .method(reqwest::Method::POST)
        .param("module_id", "1").param("size", pagesize.to_string()).param("page", page.to_string())
        .signature_type(SignatureType::Default);
    transport::send(client, session, &req).await
}

pub async fn longaudio_rank_recommend(client: &reqwest::Client, session: &KgSession) -> AppResult<Value> {
    let req = KgRequest::get("/longaudio/v1/home_new/rank_card_recommend")
        .param("platform", "ios")
        .signature_type(SignatureType::Default);
    transport::send(client, session, &req).await
}

pub async fn longaudio_vip_recommend(client: &reqwest::Client, session: &KgSession) -> AppResult<Value> {
    let req = KgRequest::get("/longaudio/v1/home_new/vip_select_recommend")
        .method(reqwest::Method::POST)
        .param("position", "2").param("clientver", "12329")
        .json_body(json!({ "album_playlist": [] }))
        .signature_type(SignatureType::Default);
    transport::send(client, session, &req).await
}

pub async fn longaudio_week_recommend(client: &reqwest::Client, session: &KgSession) -> AppResult<Value> {
    let req = KgRequest::get("/longaudio/v1/home_new/week_new_albums_recommend")
        .method(reqwest::Method::POST)
        .param("clientver", "12329")
        .json_body(json!({ "album_playlist": [] }))
        .signature_type(SignatureType::Default);
    transport::send(client, session, &req).await
}

pub async fn ip_resources(client: &reqwest::Client, session: &KgSession, id: &str, ty: &str, page: i64, pagesize: i64) -> AppResult<Value> {
    let normalized = match ty { "audios" | "albums" | "videos" | "author_list" => ty, _ => "audios" };
    let body = json!({ "is_publish": 1, "ip_id": id, "sort": 3, "page": page, "pagesize": pagesize, "query": 1 });
    let req = KgRequest::get(format!("/openapi/v1/ip/{normalized}"))
        .method(reqwest::Method::POST)
        .json_body(body)
        .signature_type(SignatureType::Default);
    transport::send(client, session, &req).await
}

pub async fn ip_detail(client: &reqwest::Client, session: &KgSession, ids: &str) -> AppResult<Value> {
    let data: Vec<Value> = ids.split(',').filter(|s| !s.trim().is_empty())
        .map(|id| json!({ "ip_id": id.trim() })).collect();
    let body = json!({ "data": data, "is_publish": 1 });
    let req = KgRequest::get("/openapi/v1/ip")
        .method(reqwest::Method::POST)
        .json_body(body)
        .signature_type(SignatureType::Default);
    transport::send(client, session, &req).await
}

pub async fn ip_playlist(client: &reqwest::Client, session: &KgSession, id: &str, page: i64, pagesize: i64) -> AppResult<Value> {
    let req = KgRequest::get("/ocean/v6/pubsongs/list_info_for_ip")
        .method(reqwest::Method::POST)
        .param("ip", id).param("page", page.to_string()).param("pagesize", pagesize.to_string())
        .signature_type(SignatureType::Default);
    transport::send(client, session, &req).await
}

pub async fn ip_zone(client: &reqwest::Client, session: &KgSession) -> AppResult<Value> {
    let req = KgRequest::get("/v1/zone/index")
        .router("yuekucategory.kugou.com")
        .signature_type(SignatureType::Default);
    transport::send(client, session, &req).await
}

pub async fn ip_zone_home(client: &reqwest::Client, session: &KgSession, id: &str) -> AppResult<Value> {
    let req = KgRequest::get("/v1/zone/home")
        .router("yuekucategory.kugou.com")
        .param("id", id).param("share", "0")
        .signature_type(SignatureType::Default);
    transport::send(client, session, &req).await
}

pub async fn scene_lists(client: &reqwest::Client, session: &KgSession) -> AppResult<Value> {
    let req = KgRequest::get("/scene/v1/scene/list")
        .signature_type(SignatureType::Default);
    transport::send(client, session, &req).await
}

pub async fn scene_audios(client: &reqwest::Client, session: &KgSession, scene_id: &str, module_id: &str, tag: &str, page: i64, page_size: i64) -> AppResult<Value> {
    let body = json!({ "appid": config::APP_ID, "clientver": config::CLIENT_VER, "token": session.token, "userid": session.userid });
    let req = KgRequest::get("/scene/v1/scene/audio_list")
        .method(reqwest::Method::POST)
        .param("scene_id", scene_id).param("module_id", module_id).param("tag", tag)
        .param("page", page.to_string()).param("page_size", page_size.to_string())
        .json_body(body)
        .signature_type(SignatureType::Default);
    transport::send(client, session, &req).await
}

pub async fn scene_collections(client: &reqwest::Client, session: &KgSession, tag_id: &str, page: i64, page_size: i64) -> AppResult<Value> {
    let body = json!({
        "appid": config::APP_ID, "clientver": config::CLIENT_VER, "token": session.token,
        "userid": session.userid, "tag_id": tag_id, "page": page, "page_size": page_size, "exposed_data": []
    });
    let req = KgRequest::get("/scene/v1/distribution/collection_list")
        .method(reqwest::Method::POST)
        .json_body(body)
        .signature_type(SignatureType::Default);
    transport::send(client, session, &req).await
}

pub async fn scene_lists_v2(client: &reqwest::Client, session: &KgSession, scene_id: &str, page: i64, pagesize: i64, sort: &str) -> AppResult<Value> {
    let sort_type = match sort { "hot" => "2", "new" => "3", _ => "1" };
    let req = KgRequest::get("/scene/v1/scene/list_v2")
        .method(reqwest::Method::POST)
        .param("scene_id", scene_id).param("page", page.to_string()).param("pagesize", pagesize.to_string())
        .param("sort_type", sort_type).param("kugouid", &session.userid)
        .json_body(json!({ "exposure": [] }))
        .signature_type(SignatureType::Default);
    transport::send(client, session, &req).await
}

pub async fn scene_module(client: &reqwest::Client, session: &KgSession, scene_id: &str) -> AppResult<Value> {
    let req = KgRequest::get("/scene/v1/scene/module")
        .method(reqwest::Method::POST)
        .param("scene_id", scene_id)
        .signature_type(SignatureType::Default);
    transport::send(client, session, &req).await
}

pub async fn scene_module_info(client: &reqwest::Client, session: &KgSession, scene_id: &str, module_id: &str) -> AppResult<Value> {
    let req = KgRequest::get("/scene/v1/scene/module_info")
        .param("scene_id", scene_id).param("module_id", module_id)
        .signature_type(SignatureType::Default);
    transport::send(client, session, &req).await
}

pub async fn scene_music(client: &reqwest::Client, session: &KgSession, scene_id: &str, page: i64, pagesize: i64) -> AppResult<Value> {
    let req = KgRequest::get("/genesisapi/v1/scene_music/rec_music")
        .method(reqwest::Method::POST)
        .param("scene_id", scene_id).param("page", page.to_string()).param("pagesize", pagesize.to_string())
        .json_body(json!({ "exposure": [] }))
        .signature_type(SignatureType::Default);
    transport::send(client, session, &req).await
}

pub async fn scene_videos(client: &reqwest::Client, session: &KgSession, tag_id: &str, page: i64, page_size: i64) -> AppResult<Value> {
    let body = json!({
        "appid": config::APP_ID, "clientver": config::CLIENT_VER, "token": session.token,
        "userid": session.userid, "tag_id": tag_id, "page": page, "page_size": page_size, "exposed_data": []
    });
    let req = KgRequest::get("/scene/v1/distribution/video_list")
        .method(reqwest::Method::POST)
        .json_body(body)
        .signature_type(SignatureType::Default);
    transport::send(client, session, &req).await
}

pub async fn theme_music(client: &reqwest::Client, session: &KgSession, ids: &str) -> AppResult<Value> {
    let body = json!({
        "platform": "android", "clienttime": chrono::Utc::now().timestamp(),
        "show_theme_category_ids": ids, "userid": session.userid, "module_id": 508
    });
    let req = KgRequest::get("/everydayrec.service/v1/mul_theme_category_recommend")
        .method(reqwest::Method::POST)
        .json_body(body)
        .signature_type(SignatureType::Default);
    transport::send(client, session, &req).await
}

pub async fn theme_playlists(client: &reqwest::Client, session: &KgSession) -> AppResult<Value> {
    let body = json!({
        "platform": "android", "clientver": config::CLIENT_VER,
        "clienttime": chrono::Utc::now().timestamp_millis(),
        "area_code": 1, "module_id": 1, "userid": session.userid
    });
    let req = KgRequest::get("/v2/getthemelist")
        .method(reqwest::Method::POST)
        .router("everydayrec.service.kugou.com")
        .json_body(body)
        .signature_type(SignatureType::Default);
    transport::send(client, session, &req).await
}

pub async fn theme_music_detail(client: &reqwest::Client, session: &KgSession, id: &str) -> AppResult<Value> {
    let body = json!({
        "platform": "android", "clienttime": chrono::Utc::now().timestamp(),
        "theme_category_id": id, "show_theme_category_id": 0,
        "userid": session.userid, "module_id": 508
    });
    let req = KgRequest::get("/everydayrec.service/v1/theme_category_recommend")
        .method(reqwest::Method::POST)
        .json_body(body)
        .signature_type(SignatureType::Default);
    transport::send(client, session, &req).await
}

pub async fn theme_playlist_track(client: &reqwest::Client, session: &KgSession, theme_id: &str) -> AppResult<Value> {
    let body = json!({
        "platform": "android", "clientver": config::CLIENT_VER,
        "clienttime": chrono::Utc::now().timestamp_millis(),
        "area_code": 1, "module_id": 1, "userid": session.userid, "theme_id": theme_id
    });
    let req = KgRequest::get("/v2/gettheme_songidlist")
        .method(reqwest::Method::POST)
        .router("everydayrec.service.kugou.com")
        .json_body(body)
        .signature_type(SignatureType::Default);
    transport::send(client, session, &req).await
}
