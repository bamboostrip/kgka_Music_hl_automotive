use thiserror::Error;

#[derive(Error, Debug)]
pub enum AppError {
    #[error("HTTP request failed: {0}")]
    Http(#[from] reqwest::Error),

    #[error("Upstream API error: {0}")]
    Upstream(String),

    #[error("JSON error: {0}")]
    Json(#[from] serde_json::Error),

    #[error("Session error: {0}")]
    Session(String),

    #[error("Unauthorized: {0}")]
    Unauthorized(String),

    #[error("Validation: {0}")]
    Validation(String),

    #[error("Internal: {0}")]
    Internal(String),

    #[error("{0}")]
    Other(String),
}

pub type AppResult<T> = Result<T, AppError>;
