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

    content_tag(:span, "", class: "inline-block rounded-full shrink-0",
      style: "width:#{size}px;height:#{size}px;background:#{category.color};box-shadow:0 0 0 2px rgba(26,22,18,0.06)")
  end
end
