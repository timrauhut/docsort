class DashboardController < ApplicationController
  def show
    scope = current_user.documents
    @stats = {
      total: scope.count,
      pending: scope.pending.count,
      classified: scope.classified.count,
      failed: scope.failed.count,
      categories: Category.count
    }
    @recent = scope.includes(:category).recent.limit(12)
    @categories = Category.ordered
    @category_counts = scope.group(:category_id).count
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
