use std::collections::HashMap;

use serde_json::{json, Value};

use crate::error::{AppError, AppResult};
use crate::kugou::session::KgSession;
use crate::kugou::session_store::FileSessionStore;
use crate::services::{
    album, artist, comment, discover, fm, login, lyric, playlist, report, search, song, user,
    youth,
};

pub struct KugouEngine {
    client: reqwest::Client,
    session: KgSession,
    store: FileSessionStore,
}

impl KugouEngine {
    pub async fn new(data_dir: String) -> Self {
        let _ = rustls::crypto::ring::default_provider().install_default();

        let client = reqwest::Client::builder()
            .timeout(std::time::Duration::from_secs(15))
            .gzip(true)
            .build()
            .expect("failed to build reqwest client");

        let store = FileSessionStore::new(&data_dir);
        let mut session = store.load().unwrap_or_default();
        session.normalize();
        store.save(&session);

        Self {
            client,
            session,
            store,
        }
    }

    pub async fn request(
        &mut self,
        method: &str,
        path: &str,
        query: &str,
        body: Option<&str>,
    ) -> AppResult<String> {
        let params: HashMap<String, String> = if query.is_empty() {
            HashMap::new()
        } else {
            serde_json::from_str(query).unwrap_or_default()
        };

        let result = self.dispatch(method, path, &params, body).await?;
        serde_json::to_string(&result).map_err(|e| AppError::Internal(e.to_string()))
    }

    pub fn set_session_fields(&mut self, userid: &str, token: &str, t1: &str) {
        if userid.is_empty() || token.is_empty() {
            self.session.logout();
        } else {
            self.session.update_auth(userid, token, "", "", t1);
        }
        self.store.save(&self.session);
    }

    async fn dispatch(
        &mut self,
        method: &str,
        path: &str,
        params: &HashMap<String, String>,
        body: Option<&str>,
    ) -> AppResult<Value> {
        let client = &self.client;
        let session = &self.session;

        match (method, path) {
            ("POST", "/captcha/sent") => {
                let mobile = params.get("mobile").map(|s| s.as_str()).unwrap_or("");
                login::send_sms_code(client, session, mobile).await
            }
            ("POST", "/login/cellphone") => {
                let mobile = params.get("mobile").map(|s| s.as_str()).unwrap_or("");
                let code = params.get("code").map(|s| s.as_str()).unwrap_or("");
                let userid = params.get("userid").map(|s| s.as_str());
                let resp =
                    login::login_by_mobile(client, "", session, mobile, code, userid).await?;
                self.persist_login(&resp);
                Ok(resp)
            }
            ("POST", "/login/token") => {
                let resp = login::refresh_token(client, "", session).await?;
                self.persist_login(&resp);
                Ok(resp)
            }
            ("POST", "/login/logout") => {
                login::logout(client, "", session).await;
                self.session.logout();
                self.store.save(&self.session);
                Ok(json!(null))
            }
            ("GET", "/login/qr/key") => login::get_qr_key(client, session).await,
            ("GET", "/login/qr/check") => {
                let key = params.get("key").map(|s| s.as_str()).unwrap_or("");
                let resp = login::check_qr_status(client, "", session, key).await?;
                self.persist_login(&resp);
                Ok(resp)
            }

            ("GET", "/search") => {
                let keyword = params.get("keyword").map(|s| s.as_str()).unwrap_or("");
                let page = params
                    .get("page")
                    .and_then(|s| s.parse().ok())
                    .unwrap_or(1i64);
                let pagesize = params
                    .get("pagesize")
                    .and_then(|s| s.parse().ok())
                    .unwrap_or(30i64);
                let search_type = params.get("type").map(|s| s.as_str()).unwrap_or("song");
                search::search_raw(client, session, keyword, page, pagesize, search_type).await
            }
            ("GET", "/search/hot") => search::search_hot(client, session).await,
            ("GET", "/search/suggest") => {
                let keyword = params.get("keyword").map(|s| s.as_str()).unwrap_or("");
                search::search_suggest(client, session, keyword, 0, 0, 0, 10).await
            }

            ("GET", "/song/url") => {
                let hash = params.get("hash").map(|s| s.as_str()).unwrap_or("");
                let quality = params.get("quality").map(|s| s.as_str());
                let album_id = params.get("album_id").map(|s| s.as_str());
                let album_audio_id = params.get("album_audio_id").map(|s| s.as_str());
                let free_part = params
                    .get("free_part")
                    .map(|s| s == "1" || s == "true")
                    .unwrap_or(false);
                song::get_play_url(client, session, hash, quality, album_id, album_audio_id, free_part)
                    .await
            }

            ("GET", "/search/lyric") => {
                let hash = params.get("hash").map(|s| s.as_str());
                let album_audio_id = params.get("album_audio_id").map(|s| s.as_str());
                let keyword = params.get("keyword").map(|s| s.as_str());
                let man = params.get("man").map(|s| s.as_str());
                lyric::search_lyric(client, session, hash, album_audio_id, keyword, man).await
            }
            ("GET", "/lyric") => {
                let id = params.get("id").map(|s| s.as_str()).unwrap_or("");
                let accesskey = params.get("accesskey").map(|s| s.as_str()).unwrap_or("");
                let fmt = params.get("fmt").map(|s| s.as_str()).unwrap_or("krc");
                let decode = params
                    .get("decode")
                    .map(|s| s != "0" && s != "false")
                    .unwrap_or(true);
                lyric::get_lyric(client, session, id, accesskey, fmt, decode).await
            }

            ("GET", "/user/detail") => user::user_detail(client, session).await,
            ("GET", "/user/playlist") => {
                let page = params
                    .get("page")
                    .and_then(|s| s.parse().ok())
                    .unwrap_or(1i64);
                let pagesize = params
                    .get("pagesize")
                    .and_then(|s| s.parse().ok())
                    .unwrap_or(30i64);
                user::user_playlist(client, session, page, pagesize).await
            }
            ("GET", "/user/cloud") => {
                let page = params
                    .get("page")
                    .and_then(|s| s.parse().ok())
                    .unwrap_or(1i64);
                let pagesize = params
                    .get("pagesize")
                    .and_then(|s| s.parse().ok())
                    .unwrap_or(30i64);
                user::user_cloud(client, session, page, pagesize).await
            }
            ("GET", "/user/cloud/url") => {
                let hash = params.get("hash").map(|s| s.as_str()).unwrap_or("");
                let album_audio_id = params.get("album_audio_id").map(|s| s.as_str());
                let audio_id = params.get("audio_id").map(|s| s.as_str());
                let name = params.get("name").map(|s| s.as_str());
                user::user_cloud_url(client, session, hash, album_audio_id, audio_id, name).await
            }

            ("GET", "/top/playlist") => {
                let category_id = params
                    .get("category_id")
                    .and_then(|s| s.parse().ok())
                    .unwrap_or(0i64);
                let page = params
                    .get("page")
                    .and_then(|s| s.parse().ok())
                    .unwrap_or(1i64);
                discover::recommend_playlists(client, session, category_id, page).await
            }
            ("GET", "/top/song") => {
                let rank_id = params
                    .get("rank_id")
                    .and_then(|s| s.parse().ok())
                    .unwrap_or(0i64);
                let page = params
                    .get("page")
                    .and_then(|s| s.parse().ok())
                    .unwrap_or(1i64);
                discover::new_songs(client, session, rank_id, page).await
            }
            ("GET", "/top/album") => {
                let page = params
                    .get("page")
                    .and_then(|s| s.parse().ok())
                    .unwrap_or(1i64);
                let pagesize = params
                    .get("pagesize")
                    .and_then(|s| s.parse().ok())
                    .unwrap_or(30i64);
                discover::top_album(client, session, page, pagesize).await
            }
            ("GET", "/recommend/songs") => discover::recommend_songs(client, session).await,
            ("GET", "/ai/recommend") => {
                let album_audio_ids =
                    params.get("album_audio_ids").map(|s| s.as_str()).unwrap_or("");
                discover::ai_recommend(client, session, album_audio_ids).await
            }
            ("GET", "/personal/fm") => {
                let hash = params.get("hash").map(|s| s.as_str());
                let songid = params.get("songid").map(|s| s.as_str());
                let playtime = params.get("playtime").and_then(|s| s.parse().ok());
                let action = params.get("action").map(|s| s.as_str()).unwrap_or("refresh");
                let mode = params.get("mode").map(|s| s.as_str()).unwrap_or("normal");
                let song_pool_id = params
                    .get("song_pool_id")
                    .and_then(|s| s.parse().ok())
                    .unwrap_or(0i64);
                let is_overplay = params
                    .get("is_overplay")
                    .map(|s| s == "1" || s == "true")
                    .unwrap_or(false);
                let remain_song_cnt = params
                    .get("remain_song_cnt")
                    .and_then(|s| s.parse().ok())
                    .unwrap_or(0i64);
                discover::personal_fm(
                    client,
                    session,
                    hash,
                    songid,
                    playtime,
                    action,
                    mode,
                    song_pool_id,
                    is_overplay,
                    remain_song_cnt,
                )
                .await
            }

            ("GET", "/album/shop") => album::album_shop(client, session).await,
            ("GET", "/album/songs") => {
                let album_id = params.get("album_id").map(|s| s.as_str()).unwrap_or("");
                let page = params
                    .get("page")
                    .and_then(|s| s.parse().ok())
                    .unwrap_or(1i64);
                let pagesize = params
                    .get("pagesize")
                    .and_then(|s| s.parse().ok())
                    .unwrap_or(30i64);
                album::album_songs(client, session, album_id, page, pagesize).await
            }

            ("GET", "/fm/recommend") => fm::fm_recommend(client, session).await,
            ("GET", "/fm/songs") => {
                let fm_ids = params.get("fm_ids").map(|s| s.as_str()).unwrap_or("");
                let fmtype = params
                    .get("fmtype")
                    .and_then(|s| s.parse().ok())
                    .unwrap_or(2i64);
                let offset = params
                    .get("offset")
                    .and_then(|s| s.parse().ok())
                    .unwrap_or(0i64);
                let size = params
                    .get("size")
                    .and_then(|s| s.parse().ok())
                    .unwrap_or(30i64);
                fm::fm_songs(client, session, fm_ids, fmtype, offset, size).await
            }
            ("GET", "/fm/class") => fm::fm_class(client, session).await,
            ("GET", "/fm/image") => {
                let fm_ids = params.get("fm_ids").map(|s| s.as_str()).unwrap_or("");
                fm::fm_image(client, session, fm_ids).await
            }

            ("GET", "/playlist/detail") => {
                let id = params.get("id").map(|s| s.as_str()).unwrap_or("");
                playlist::playlist_info(client, session, id).await
            }
            ("GET", "/playlist/track/all") => {
                let id = params.get("id").map(|s| s.as_str()).unwrap_or("");
                let begin_idx = params
                    .get("begin_idx")
                    .and_then(|s| s.parse().ok())
                    .unwrap_or(0i64);
                let pagesize = params
                    .get("pagesize")
                    .and_then(|s| s.parse().ok())
                    .unwrap_or(30i64);
                playlist::playlist_tracks(client, session, id, begin_idx, pagesize).await
            }
            ("POST", "/playlist/create") => {
                let body_val: Value =
                    serde_json::from_str(body.unwrap_or("{}")).unwrap_or_default();
                let name = body_val
                    .get("name")
                    .and_then(|v| v.as_str())
                    .unwrap_or("新歌单");
                let is_pri = body_val
                    .get("is_pri")
                    .and_then(|v| v.as_i64())
                    .unwrap_or(0);
                playlist::create_playlist(client, session, name, is_pri).await
            }
            ("POST", "/playlist/add") => {
                let body_val: Value =
                    serde_json::from_str(body.unwrap_or("{}")).unwrap_or_default();
                let name = body_val
                    .get("name")
                    .and_then(|v| v.as_str())
                    .unwrap_or("");
                let global_collection_id = body_val
                    .get("global_collection_id")
                    .and_then(|v| v.as_str())
                    .unwrap_or("");
                playlist::collect_playlist(client, session, name, global_collection_id).await
            }
            ("POST", "/playlist/del") => {
                let body_val: Value =
                    serde_json::from_str(body.unwrap_or("{}")).unwrap_or_default();
                let listid = body_val
                    .get("listid")
                    .and_then(|v| v.as_str())
                    .unwrap_or("");
                playlist::delete_playlist(client, session, listid).await
            }
            ("POST", "/playlist/tracks/add") => {
                let body_val: Value =
                    serde_json::from_str(body.unwrap_or("{}")).unwrap_or_default();
                let listid = body_val
                    .get("listid")
                    .and_then(|v| v.as_str())
                    .unwrap_or("");
                let songs: Vec<playlist::AddSongItem> = body_val
                    .get("songs")
                    .and_then(|v| serde_json::from_value(v.clone()).ok())
                    .unwrap_or_default();
                playlist::add_tracks(client, session, listid, &songs).await
            }
            ("POST", "/playlist/tracks/del") => {
                let body_val: Value =
                    serde_json::from_str(body.unwrap_or("{}")).unwrap_or_default();
                let listid = body_val
                    .get("listid")
                    .and_then(|v| v.as_str())
                    .unwrap_or("");
                let file_ids: Vec<i64> = body_val
                    .get("file_ids")
                    .and_then(|v| serde_json::from_value(v.clone()).ok())
                    .unwrap_or_default();
                playlist::remove_tracks(client, session, listid, &file_ids).await
            }

            ("GET", "/artist/detail") => {
                let id = params.get("id").map(|s| s.as_str()).unwrap_or("");
                artist::artist_detail(client, session, id).await
            }
            ("GET", "/artist/audios") => {
                let id = params.get("id").map(|s| s.as_str()).unwrap_or("");
                let page = params
                    .get("page")
                    .and_then(|s| s.parse().ok())
                    .unwrap_or(1i64);
                let pagesize = params
                    .get("pagesize")
                    .and_then(|s| s.parse().ok())
                    .unwrap_or(30i64);
                let sort = params.get("sort").map(|s| s.as_str()).unwrap_or("hot");
                artist::artist_audios(client, session, id, page, pagesize, sort).await
            }

            ("GET", "/comment/music") => {
                let mixsongid = params.get("mixsongid").map(|s| s.as_str()).unwrap_or("");
                let page = params
                    .get("page")
                    .and_then(|s| s.parse().ok())
                    .unwrap_or(1i64);
                let pagesize = params
                    .get("pagesize")
                    .and_then(|s| s.parse().ok())
                    .unwrap_or(20i64);
                let show_classify = params
                    .get("show_classify")
                    .and_then(|s| s.parse().ok())
                    .unwrap_or(1i64);
                let show_hotword_list = params
                    .get("show_hotword_list")
                    .and_then(|s| s.parse().ok())
                    .unwrap_or(1i64);
                comment::music_comments(
                    client,
                    session,
                    mixsongid,
                    page,
                    pagesize,
                    show_classify,
                    show_hotword_list,
                )
                .await
            }

            ("GET", "/youth/month/vip/record") => youth::month_vip_record(client, session).await,
            ("GET", "/youth/day/vip") => youth::receive_one_day_vip(client, session).await,
            ("GET", "/youth/day/vip/upgrade") => youth::upgrade_vip(client, session).await,

            ("POST", "/listen/timeadd") => report::listen_time_add(client, session).await,

            _ => Err(AppError::Other(format!(
                "Unknown route: {} {}",
                method, path
            ))),
        }
    }

    fn persist_login(&mut self, resp: &Value) {
        let userid = resp
            .get("userid")
            .and_then(|v| v.as_i64().map(|i| i.to_string()).or_else(|| v.as_str().map(|s| s.to_string())))
            .unwrap_or_default();
        let token = resp
            .get("token")
            .and_then(|v| v.as_str())
            .unwrap_or("");
        if userid.is_empty() || userid == "0" || token.is_empty() {
            return;
        }
        let vip_type = resp
            .get("vip_type")
            .and_then(|v| v.as_i64().map(|i| i.to_string()).or_else(|| v.as_str().map(|s| s.to_string())))
            .unwrap_or_else(|| "0".to_string());
        let vip_token = resp
            .get("vip_token")
            .and_then(|v| v.as_str())
            .unwrap_or("");
        let t1 = resp
            .get("t1")
            .and_then(|v| v.as_str())
            .unwrap_or("");
        self.session
            .update_auth(&userid, token, &vip_type, vip_token, t1);
        self.store.save(&self.session);
    }
}
