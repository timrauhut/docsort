module ApplicationHelper
  def nav_link(label, path)
    active = current_page?(path)
    classes = active ? "nav-pill is-active" : "nav-pill"
    link_to label, path, class: classes
  end

  def flash_class(type)
    case type.to_s
    when "notice" then "flash flash-notice"
    when "alert" then "flash flash-alert"
    else "flash"
    end
  end

  def confidence_label(value)
    return "—" if value.nil?

    "#{(value * 100).round}%"
  end

  def status_badge(document)
    content_tag(:span, document.status, class: "badge badge-#{document.status}")
  end

  def category_swatch(category, size: 10)
    return "" unless category

    content_tag(:span, "", class: "cat-swatch shrink-0",
      style: "--cat:#{category.color};width:#{size}px;height:#{size}px")
  end

  # Soft tinted pill (ink text) — matches chartreuse/paper layout better than solid neon fills
  def category_pill(category, label: nil)
    return "" unless category

    content_tag(:span, label || category.name, class: "pill pill-cat",
      style: "--cat:#{category.color}")
  end

  def category_stripe_style(category)
    return "" unless category

    "--cat:#{category.color}"
  end
end

