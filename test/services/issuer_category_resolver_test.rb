require "test_helper"

class IssuerCategoryResolverTest < ActiveSupport::TestCase
  setup do
    @invoices = categories(:invoices)
    @alice = users(:alice)
    @admin = users(:admin)
  end

  test "matches exact category name" do
    category = IssuerCategoryResolver.new("Invoices", user: @alice, confidence: 0.9, auto_create: false).call
    assert_equal @invoices, category
  end

  test "matches issuer slug for auto issuer categories" do
    cat = Category.create!(
      name: "Deutsche Telekom AG",
      slug: "issuer-deutsche-telekom-ag",
      directory_path: "issuers/deutsche-telekom-ag",
      keywords: "Deutsche Telekom AG",
      auto_create: true,
      user: @alice
    )
    found = IssuerCategoryResolver.new("Deutsche Telekom AG", user: @alice, confidence: 0.9, auto_create: false).call
    assert_equal cat, found
  end

  test "does not leak another users issuer category" do
    Category.create!(
      name: "Deutsche Telekom AG",
      slug: "issuer-deutsche-telekom-ag",
      directory_path: "issuers/deutsche-telekom-ag",
      keywords: "Deutsche Telekom AG",
      auto_create: true,
      user: @admin
    )

    found = IssuerCategoryResolver.new("Deutsche Telekom AG", user: @alice, confidence: 0.9, auto_create: false).call
    assert_nil found
  end

  test "creates issuer categories owned by the document user" do
    alice_cat = IssuerCategoryResolver.new("Stadtwerke München", user: @alice, confidence: 0.9, auto_create: true).call
    admin_cat = IssuerCategoryResolver.new("Stadtwerke München", user: @admin, confidence: 0.9, auto_create: true).call

    assert_equal @alice, alice_cat.user
    assert_equal @admin, admin_cat.user
    refute_equal alice_cat.id, admin_cat.id
    assert_equal "issuer-stadtwerke-munchen", alice_cat.slug
  end

  test "does not match short keyword fragments" do
    @invoices.update!(keywords: "ag, co, bill")
    found = IssuerCategoryResolver.new("AG Chemie", user: @alice, confidence: 0.9, auto_create: false).call
    refute_equal @invoices, found
  end

  test "matches long keyword as whole token" do
    @invoices.update!(keywords: "telekom, invoice")
    found = IssuerCategoryResolver.new("Letter from Telekom customer service", user: @alice, confidence: 0.9, auto_create: false).call
    assert_equal @invoices, found
  end
end
