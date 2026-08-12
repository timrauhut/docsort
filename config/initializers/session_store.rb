Rails.application.config.session_store :cookie_store,
  key: ENV.fetch("DOCSORT_SESSION_COOKIE", "_docsort_session"),
  same_site: :lax
