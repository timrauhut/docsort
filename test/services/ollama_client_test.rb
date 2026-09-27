require "test_helper"

class OllamaClientTest < ActiveSupport::TestCase
  test "sends explicit context and schema to Ollama" do
    schema = { type: "object", required: [ "summary" ] }
    client, requests = client_with_response('{"summary":"Payment due."}')
    assert_equal "Payment due.", client.chat(system: "Summarize", user: "Document", schema: schema)["summary"]
    assert_equal schema.deep_stringify_keys, requests.first["format"]
    assert_equal 8192, requests.first.dig("options", "num_ctx")
  end

  test "rejects malformed non-object and output-truncated responses" do
    [ '{"summary":', 'prefix {"broken": } suffix', "[]", "null" ].each do |content|
      client, = client_with_response(content)
      assert_raises(OllamaClient::Error) { client.chat(system: "Summarize", user: "Document") }
    end
    client, = client_with_response('{"summary":"Partial"}', reason: "length")
    assert_raises(OllamaClient::Error) { client.chat(system: "Summarize", user: "Document") }
  end

  test "oversized prompts fail before a network request" do
    client, requests = client_with_response("{}")
    assert_raises(OllamaClient::Error) { client.chat(system: "Instructions", user: "x" * 8192) }
    assert_empty requests
  end

  private

  def client_with_response(content, reason: "stop")
    requests = []
    connection = Faraday.new do |f|
      f.adapter :test do |stub|
        stub.post("/api/chat") do |env|
          requests << JSON.parse(env.body)
          [ 200, {}, { "message" => { "content" => content }, "done_reason" => reason } ]
        end
      end
    end
    client = OllamaClient.new
    client.define_singleton_method(:connection) { connection }
    [ client, requests ]
  end
end
