# Thin client for a local Ollama instance (https://ollama.com).
class OllamaClient
  class Error < StandardError; end
  class Unavailable < Error; end

  def initialize(
    host: Rails.application.config.x.ollama.host,
    model: Rails.application.config.x.ollama.model,
    timeout: Rails.application.config.x.ollama.timeout
  )
    @host = host.to_s.chomp("/")
    @model = model
    @timeout = timeout
  end

  def available?
    response = connection.get("/api/tags")
    response.success?
  rescue StandardError
    false
  end

  def models
    response = connection.get("/api/tags")
    raise Unavailable, "Ollama not reachable at #{@host}" unless response.success?

    (response.body["models"] || []).map { |m| m["name"] }
  rescue Faraday::Error => e
    raise Unavailable, e.message
  end

  def chat(system:, user:, format_json: true, num_predict: 384)
    body = {
      model: @model,
      stream: false,
      messages: [
        { role: "system", content: system },
        { role: "user", content: user }
      ],
      # Keep responses short — Pi/1B models otherwise ramble for minutes
      options: {
        num_predict: num_predict,
        temperature: 0.1
      }
    }
    body[:format] = "json" if format_json

    response = connection.post("/api/chat") do |req|
      req.headers["Content-Type"] = "application/json"
      req.body = body.to_json
    end

    unless response.success?
      raise Error, "Ollama error #{response.status}: #{response.body}"
    end

    content = response.body.dig("message", "content").to_s
    format_json ? parse_json(content) : content
  rescue Faraday::ConnectionFailed, Faraday::TimeoutError => e
    raise Unavailable, e.message
  end

  private

  def connection
    @connection ||= Faraday.new(url: @host) do |f|
      f.options.timeout = @timeout
      f.options.open_timeout = 5
      f.response :json, content_type: /\bjson$/
      f.adapter Faraday.default_adapter
    end
  end

  def parse_json(content)
    JSON.parse(content)
  rescue JSON::ParserError
    # Models sometimes wrap JSON in markdown fences
    if content =~ /\{[\s\S]*\}/
      JSON.parse(Regexp.last_match[0])
    else
      raise Error, "Could not parse model JSON: #{content.truncate(200)}"
    end
  end
end
