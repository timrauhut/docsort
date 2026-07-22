require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
# require "action_mailbox/engine"
# require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Docsort
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # DocSort: local LLM classification via Ollama
    config.x.ollama.host = ENV.fetch("OLLAMA_HOST", "http://localhost:11434")
    config.x.ollama.model = ENV.fetch("OLLAMA_MODEL", "llama3.2")
    config.x.ollama.timeout = ENV.fetch("OLLAMA_TIMEOUT", "120").to_i

    # Where auto-sorted document copies live (mirrored category tree)
    config.x.sorted_root = ENV.fetch("DOCSORT_SORTED_ROOT", Rails.root.join("storage", "sorted").to_s)
    config.x.inbox_root = ENV.fetch("DOCSORT_INBOX_ROOT", Rails.root.join("storage", "inbox").to_s)

    # Bootstrap admin account (created on seed when no users exist)
    config.x.admin.username = ENV.fetch("DOCSORT_ADMIN_USERNAME", "admin").to_s.strip
    config.x.admin.password = ENV.fetch(
      "DOCSORT_ADMIN_PASSWORD",
      ENV.fetch("WEBDAV_PASSWORD", "changeme")
    ).to_s.strip


    # When an issuer/brand is detected and no type category fits well,
    # auto-create categories under storage/sorted/issuers/<brand>/
    config.x.auto_create_issuer_categories =
      ActiveModel::Type::Boolean.new.cast(ENV.fetch("DOCSORT_AUTO_ISSUER_CATEGORIES", "true"))

    # PDF OCR: auto (text layer first, Tesseract fallback) | all | off
    config.x.ocr.mode = ENV.fetch("DOCSORT_OCR_MODE", "auto")
    config.x.ocr.langs = ENV.fetch("DOCSORT_OCR_LANGS", "eng+deu")
  end
end

