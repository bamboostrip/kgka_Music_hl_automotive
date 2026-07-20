use crate::engine::KugouEngine;
use flutter_rust_bridge::frb;

#[frb(opaque)]
pub struct Engine(KugouEngine);

pub async fn create_engine(data_dir: String) -> Engine {
    Engine(KugouEngine::new(data_dir).await)
}

pub async fn engine_request(
    engine: &mut Engine,
    method: String,
    path: String,
    query: String,
    body: Option<String>,
) -> Result<String, String> {
    engine
        .0
        .request(&method, &path, &query, body.as_deref())
        .await
        .map_err(|e| e.to_string())
}

pub fn engine_set_session(engine: &mut Engine, userid: String, token: String, t1: String) {
    engine.0.set_session_fields(&userid, &token, &t1);
}
