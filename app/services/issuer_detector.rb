# Detects the company / brand that issued a letter or document.
# Uses letterhead cues, "from" lines, signatures, and common legal suffixes.
class IssuerDetector
  LEGAL_SUFFIX = /
    (?:
      GmbH|AG|SE|KG|OHG|UG|e\.?\s*V\.?|
      Inc\.?|Incorporated|Corp\.?|Corporation|LLC|L\.L\.C\.?|Ltd\.?|Limited|
      PLC|P\.L\.C\.?|SA|S\.A\.?|SAS|BV|N\.V\.?|Pty\.?\s*Ltd\.?|
      Co\.?|Company|Group|Bank|Versicherung|Insurance|Telecom|Mobile
    )
  /ix

  FROM_LINE = /
    (?:
      ^\s*(?:from|absender|von|sender|issued\s+by|letter\s+from)\s*[:\-]\s*(.+)$ |
      ^\s*(?:yours?\s+(?:sincerely|faithfully)|mit\s+freundlichen\s+gr[uü]ßen|hochachtungsvoll)\s*[,]?\s*$
    )
  /ix

  LETTERHEAD_HINTS = /
    (?:customer\s+service|kundenservice|rechnung|invoice|vertrag|contract|
     reference\s*no|kundennummer|account\s+number|www\.[a-z0-9.-]+\.[a-z]{2,})
  /ix

  def initialize(document, text: nil)
    @document = document
    @text = text.to_s
  end

  def call
    candidates = []

    candidates.concat(from_filename)
    candidates.concat(from_from_lines)
    candidates.concat(from_legal_entities)
    candidates.concat(from_domain_mentions)

    best = candidates
      .map { |name| normalize(name) }
      .reject { |name| name.blank? || noise?(name) }
      .tally
      .max_by { |name, count| [ count, name.length ] }

    return empty_result if best.nil?

    name, count = best
    confidence = (0.35 + (count * 0.15) + (name.match?(LEGAL_SUFFIX) ? 0.2 : 0)).clamp(0.0, 0.92)

    {
      issuer: name,
      confidence: confidence.round(3),
      slug: name.parameterize
    }
  end

  private

  def empty_result
    { issuer: nil, confidence: 0.0, slug: nil }
  end

  def haystack
    @haystack ||= [ @document.original_filename, @text ].compact.join("\n")
  end

  def from_filename
    base = File.basename(@document.original_filename.to_s, ".*")
    # e.g. telekom-invoice-2024.pdf, letter_from_acme_corp
    parts = base.split(/[_\-\s.]+/).reject { |p| p.match?(/\A\d+\z/) || p.length < 3 }
    return [] if parts.length < 2

    # Prefer first non-generic token if it looks like a brand
    generic = %w[invoice receipt letter scan document scanned final copy pdf img]
    brand = parts.find { |p| !generic.include?(p.downcase) }
    brand ? [ brand ] : []
  end

  def from_from_lines
    found = []
    haystack.each_line do |line|
      if (m = line.match(/^\s*(?:from|absender|von|sender|issued\s+by)\s*[:\-]\s*(.+)$/i))
        found << m[1]
      end
    end
    found
  end

  def from_legal_entities
    # Capture "Something Something GmbH" style names
    haystack.scan(
      /([A-ZÄÖÜ][\wÄÖÜäöüß&.'-]{1,40}(?:\s+[A-ZÄÖÜ][\wÄÖÜäöüß&.'-]{1,30}){0,4}\s+#{LEGAL_SUFFIX.source})/o
    ).flatten
  end

  def from_domain_mentions
    domains = haystack.scan(%r{(?:https?://|www\.)([a-z0-9-]+)\.[a-z]{2,}}i).flatten
    domains.map do |host|
      next if %w[google gmail outlook microsoft apple github].include?(host.downcase)

      host.tr("-", " ").split.map(&:capitalize).join(" ")
    end.compact
  end

  def normalize(name)
    name.to_s
      .gsub(/\s+/, " ")
      .gsub(/[|•·].*$/, "")
      .gsub(/[,;].*$/, "")
      .strip
      .sub(/\A["']+/, "")
      .sub(/["']+\z/, "")
      .truncate(80, omission: "")
  end

  def noise?(name)
    return true if name.length < 2 || name.length > 80
    return true if name.match?(/\A\d+\z/)
    return true if name.match?(/\A(page|seite|tel|fax|email|http)\b/i)
    return true if %w[pdf doc docx scan image unknown].include?(name.downcase)

    false
  end
end
