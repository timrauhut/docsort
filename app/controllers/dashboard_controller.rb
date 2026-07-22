class DashboardController < ApplicationController
  def show
    @stats = {
      total: Document.count,
      pending: Document.pending.count,
      classified: Document.classified.count,
      failed: Document.failed.count,
      categories: Category.count
    }
    @recent = Document.includes(:category).recent.limit(12)
    @categories = Category.ordered.includes(:documents)
    @ollama = ollama_status
  end

  private

  def ollama_status
    client = OllamaClient.new
    if client.available?
      { available: true, host: Rails.application.config.x.ollama.host, model: Rails.application.config.x.ollama.model, models: client.models }
    else
      { available: false, host: Rails.application.config.x.ollama.host, model: Rails.application.config.x.ollama.model, models: [] }
    end
  rescue StandardError => e
    { available: false, host: Rails.application.config.x.ollama.host, model: Rails.application.config.x.ollama.model, error: e.message, models: [] }
  end
end
