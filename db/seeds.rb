puts "Seeding DocSort…"

# --- Admin user (same credentials for web UI + WebDAV) ---
admin_username = Rails.application.config.x.admin.username.to_s.strip.presence || "admin"
# bcrypt / has_secure_password max is 72 bytes
admin_password = Rails.application.config.x.admin.password.to_s.byteslice(0, 72).to_s
admin_password = "changeme" if admin_password.blank?

if User.none?
  admin = User.create!(
    username: admin_username,
    password: admin_password,
    password_confirmation: admin_password,
    admin: true
  )
  admin.ensure_storage!
  puts "  ✓ admin user “#{admin.username}” (web + WebDAV)"
  if admin_password == "changeme"
    puts "  ! default password “changeme” — change it after first login"
  end
else
  puts "  · users present (#{User.count}) — skip admin create"
end

if (orphan_count = Document.where(user_id: nil).count).positive?
  owner = User.find_by(admin: true) || User.order(:id).first
  if owner
    Document.where(user_id: nil).update_all(user_id: owner.id)
    puts "  ✓ assigned #{orphan_count} orphan documents to #{owner.username}"
  end
end

puts "Seeding categories…"

categories = [
  {
    name: "Invoices",
    slug: "invoices",
    directory_path: "finance/invoices",
    description: "Vendor invoices, bills, and payment requests.",
    keywords: "invoice, bill, amount due, payment, tax id, vat, total, due date",
    # Colors harmonized with buzz.xyz (ink #231e1e, chartreuse #d7d72e, paper #eeeeeb)
    color: "#5b7c99",
    position: 10
  },
  {
    name: "Receipts",
    slug: "receipts",
    directory_path: "finance/receipts",
    description: "Purchase receipts and expense proofs.",
    keywords: "receipt, purchased, paid, transaction, store, merchant, cash",
    color: "#3d7a6a",
    position: 20
  },
  {
    name: "Contracts",
    slug: "contracts",
    directory_path: "legal/contracts",
    description: "Agreements, NDAs, and signed contracts.",
    keywords: "agreement, contract, party, terms, signature, nda, clause, effective date",
    color: "#6b5f7a",
    position: 30
  },
  {
    name: "Resumes",
    slug: "resumes",
    directory_path: "hr/resumes",
    description: "CVs, résumés, and career profiles.",
    keywords: "resume, curriculum vitae, experience, education, skills, employment",
    color: "#8a7a32",
    position: 40
  },
  {
    name: "Reports",
    slug: "reports",
    directory_path: "work/reports",
    description: "Business reports, analytics, and status updates.",
    keywords: "report, analysis, metrics, quarterly, findings, summary, kpi",
    color: "#5a6570",
    position: 50
  },
  {
    name: "Correspondence",
    slug: "correspondence",
    directory_path: "personal/correspondence",
    description: "Letters, emails exported as files, formal messages.",
    keywords: "dear, sincerely, letter, email, regarding, invitation",
    color: "#7a5c5c",
    position: 60
  },
  {
    name: "Technical",
    slug: "technical",
    directory_path: "work/technical",
    description: "Specs, READMEs, architecture notes, and code-related docs.",
    keywords: "api, specification, architecture, readme, configuration, deployment, schema",
    color: "#5c5a52",
    position: 70
  },
  {
    name: "Unsorted",
    slug: "unsorted",
    directory_path: "unsorted",
    description: "Fallback bucket when classification is uncertain.",
    keywords: "",
    color: "#9b9b96",
    position: 999
  }
]

categories.each do |attrs|
  category = Category.find_or_initialize_by(slug: attrs[:slug])
  category.assign_attributes(attrs.merge(auto_create: true))
  category.save!
  User.find_each do |user|
    FileUtils.mkdir_p(File.join(user.sorted_root, category.directory_path))
  end
  puts "  ✓ #{category.name} → sorted/<user>/#{category.directory_path}"
end

# Example high-priority rules
if (invoices = Category.find_by(slug: "invoices"))
  ClassificationRule.find_or_create_by!(name: "Filename contains invoice", category: invoices) do |rule|
    rule.pattern = "invoice"
    rule.priority = 10
    rule.active = true
  end
end

if (receipts = Category.find_by(slug: "receipts"))
  ClassificationRule.find_or_create_by!(name: "Filename contains receipt", category: receipts) do |rule|
    rule.pattern = "receipt"
    rule.priority = 10
    rule.active = true
  end
end

FileUtils.mkdir_p(Rails.application.config.x.inbox_root)
FileUtils.mkdir_p(Rails.application.config.x.sorted_root)
User.find_each(&:ensure_storage!)

puts "Done. #{User.count} users, #{Category.count} categories."
