use crate::kugou::session::KgSession;
use std::path::PathBuf;

pub struct FileSessionStore {
    path: PathBuf,
}

impl FileSessionStore {
    pub fn new(data_dir: &str) -> Self {
        let path = PathBuf::from(data_dir).join("kg_session.json");
        Self { path }
    }

    pub fn load(&self) -> Option<KgSession> {
        let content = std::fs::read_to_string(&self.path).ok()?;
        serde_json::from_str(&content).ok()
    }

    pub fn save(&self, session: &KgSession) {
        if let Some(parent) = self.path.parent() {
            let _ = std::fs::create_dir_all(parent);
        }
        if let Ok(json) = serde_json::to_string_pretty(session) {
            let _ = std::fs::write(&self.path, json);
        }
    }

    #[allow(dead_code)]
    pub fn clear(&self) {
        let _ = std::fs::remove_file(&self.path);
    }
}
