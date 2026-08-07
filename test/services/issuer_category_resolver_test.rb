require "test_helper"

class IssuerCategoryResolverTest < ActiveSupport::TestCase
  setup do
    @invoices = categories(:invoices)
  end

  test "matches exact category name" do
    category = IssuerCategoryResolver.new("Invoices", confidence: 0.9, auto_create: false).call
    assert_equal @invoices, category
  end

  test "matches issuer slug for auto issuer categories" do
    cat = Category.create!(
      name: "Deutsche Telekom AG",
      slug: "issuer-deutsche-telekom-ag",
      directory_path: "issuers/deutsche-telekom-ag",
      keywords: "Deutsche Telekom AG",
      auto_create: true
    )
    found = IssuerCategoryResolver.new("Deutsche Telekom AG", confidence: 0.9, auto_create: false).call
    assert_equal cat, found
  end

  test "does not match short keyword fragments" do
    @invoices.update!(keywords: "ag, co, bill")
    found = IssuerCategoryResolver.new("AG Chemie", confidence: 0.9, auto_create: false).call
    refute_equal @invoices, found
  end

  test "matches long keyword as whole token" do
    @invoices.update!(keywords: "telekom, invoice")
    found = IssuerCategoryResolver.new("Letter from Telekom customer service", confidence: 0.9, auto_create: false).call
    assert_equal @invoices, found
  end
end
