use crate::error::AppResult;

pub struct KugouEngine;

impl KugouEngine {
    pub async fn new(_data_dir: String) -> Self {
        Self
    }

    pub async fn request(&mut self, _method: &str, _path: &str, _query: &str, _body: Option<&str>) -> AppResult<String> {
        Ok(String::from("null"))
    }

    pub fn set_session_fields(&mut self, _userid: &str, _token: &str, _t1: &str) {}
}
