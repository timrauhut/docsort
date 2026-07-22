# Classifies a document into a Category using:
# 1) explicit ClassificationRules (regex)
# 2) local Ollama LLM (if available)
# 3) keyword fallback over category keywords
#
# Also detects the issuing company/brand (letterhead) for filing context.
class DocumentClassifier
  Result = Struct.new(
    :category, :confidence, :summary, :tags, :classifier_used, :raw,
    :issuer, :issuer_confidence,
    keyword_init: true
  )

  def initialize(document, ollama: OllamaClient.new)
    @document = document
    @ollama = ollama
  end

  def call(text: nil)
    text = text.presence || TextExtractor.new(@document).call
    categories = Category.ordered.to_a
    issuer_info = IssuerDetector.new(@document, text: text).call

    if categories.empty?
      return Result.new(
        category: nil,
        confidence: 0.0,
        summary: "No categories configured",
        tags: [],
        classifier_used: "none",
        raw: {},
        issuer: issuer_info[:issuer],
        issuer_confidence: issuer_info[:confidence]
      )
    end

    result =
      if (rule_hit = apply_rules(text))
        rule_hit
      elsif @ollama.available?
        begin
          classify_with_ollama(text, categories, issuer_info)
        rescue OllamaClient::Error => e
          Rails.logger.warn("Ollama classification failed, falling back: #{e.message}")
          classify_with_keywords(text, categories)
        end
      else
        classify_with_keywords(text, categories)
      end

    # Prefer model-provided issuer when present
    if result.raw.is_a?(Hash) && result.raw["issuer"].present?
      result.issuer = result.raw["issuer"].to_s.strip
      result.issuer_confidence = [
        result.issuer_confidence.to_f,
        result.raw["issuer_confidence"].to_f,
        0.75
      ].max
    else
      result.issuer ||= issuer_info[:issuer]
      result.issuer_confidence ||= issuer_info[:confidence]
    end

    # If type category is weak/unsorted but issuer maps to a category, prefer issuer category
    maybe_promote_issuer_category!(result)

    result
  end

  private

  def apply_rules(text)
    haystack = [ @document.original_filename, text ].compact.join("\n")

    ClassificationRule.active.by_priority.find_each do |rule|
      next unless rule.matches?(haystack)

      return Result.new(
        category: rule.category,
        confidence: 0.95,
        summary: "Matched rule: #{rule.name}",
        tags: [ "rule:#{rule.name.parameterize}" ],
        classifier_used: "rule",
        raw: { rule_id: rule.id, pattern: rule.pattern },
        issuer: nil,
        issuer_confidence: nil
      )
    end
    nil
  end

  def classify_with_ollama(text, categories, issuer_info)
    catalog = categories.map do |c|
      {
        slug: c.slug,
        name: c.name,
        description: c.description,
        keywords: c.keyword_list
      }
    end

    system = <<~PROMPT
      You are a document classification assistant for a personal archive.
      1) Pick the single best category slug from the catalog.
      2) Identify the issuing company or brand (letterhead / sender / "from"), if any.
      Respond with JSON only:
      {
        "category_slug": "<slug from catalog>",
        "confidence": <0.0 to 1.0>,
        "summary": "<one sentence summary>",
        "tags": ["tag1", "tag2"],
        "issuer": "<company or brand name or empty string>",
        "issuer_confidence": <0.0 to 1.0>,
        "suggested_filename": "<optional cleaner filename with extension>"
      }
      Issuer examples: "Deutsche Telekom", "Amazon", "Stadtwerke München", "Allianz".
      If nothing fits well, use the closest category and lower confidence.
    PROMPT

    user = {
      categories: catalog,
      filename: @document.original_filename,
      content_type: @document.content_type,
      heuristic_issuer: issuer_info[:issuer],
      document_text: text.to_s.truncate(8000)
    }.to_json

    parsed = @ollama.chat(system: system, user: user, format_json: true)
    slug = parsed["category_slug"].to_s
    category = categories.find { |c| c.slug == slug } ||
               categories.find { |c| c.name.casecmp?(slug) } ||
               categories.find { |c| c.slug == "unsorted" } ||
               categories.first

    Result.new(
      category: category,
      confidence: parsed["confidence"].to_f.clamp(0.0, 1.0),
      summary: parsed["summary"].to_s.presence || "Classified by local model",
      tags: Array(parsed["tags"]).map(&:to_s),
      classifier_used: "ollama:#{Rails.application.config.x.ollama.model}",
      raw: parsed,
      issuer: parsed["issuer"].presence,
      issuer_confidence: parsed["issuer_confidence"]&.to_f
    )
  end

  def classify_with_keywords(text, categories)
    haystack = [ @document.original_filename, text ].compact.join(" ").downcase
    scores = categories.map do |category|
      score = category.keyword_list.sum do |keyword|
        haystack.include?(keyword.downcase) ? keyword.length : 0
      end
      score += 5 if haystack.include?(category.slug.tr("-", " ")) || haystack.include?(category.slug)
      [ category, score ]
    end

    best, score = scores.max_by { |(_, s)| s }
    unsorted = categories.find { |c| c.slug == "unsorted" }

    if score.to_i <= 0
      return Result.new(
        category: unsorted || best,
        confidence: 0.2,
        summary: "No strong keyword match; placed in #{(unsorted || best)&.name}",
        tags: [ "keyword-fallback" ],
        classifier_used: "keywords",
        raw: { scores: scores.map { |c, s| [ c.slug, s ] }.to_h }
      )
    end

    max_possible = [ best.keyword_list.map(&:length).sum, 1 ].max
    confidence = (score.to_f / max_possible).clamp(0.3, 0.85)

    Result.new(
      category: best,
      confidence: confidence,
      summary: "Keyword match for #{best.name}",
      tags: [ "keyword-fallback", best.slug ],
      classifier_used: "keywords",
      raw: { scores: scores.map { |c, s| [ c.slug, s ] }.to_h }
    )
  end

  def maybe_promote_issuer_category!(result)
    return if result.issuer.blank?
    return if result.issuer_confidence.to_f < 0.5

    issuer_category = IssuerCategoryResolver.new(
      result.issuer,
      confidence: result.issuer_confidence
    ).call

    return unless issuer_category

    weak = result.category.nil? ||
           result.category.slug == "unsorted" ||
           result.confidence.to_f < 0.45

    # Always tag issuer; only switch category when type match is weak
    # or the resolved category is an issuer-* auto category and type was unsorted
    if weak || (issuer_category.slug.start_with?("issuer-") && result.category&.slug == "unsorted")
      result.category = issuer_category
      result.confidence = [ result.confidence.to_f, result.issuer_confidence.to_f ].max
      result.tags = Array(result.tags) | [ "issuer:#{result.issuer.to_s.parameterize}" ]
      result.summary = [ result.summary, "Issuer: #{result.issuer}" ].compact.join(" · ")
    else
      result.tags = Array(result.tags) | [ "issuer:#{result.issuer.to_s.parameterize}" ]
    end
  end
end
