# Be sure to restart your server when you modify this file.

# Define an application-wide content security policy.
# See the Securing Rails Applications Guide for more information:
# https://guides.rubyonrails.org/security.html#content-security-policy-header

Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.font_src :self, :data
    policy.img_src :self, :data, :blob
    policy.object_src :none
    policy.script_src :self
    # Existing views use a small number of inline style attributes.
    policy.style_src :self, :unsafe_inline
    policy.base_uri :self
    policy.form_action :self
    policy.frame_ancestors :none
  end


  config.content_security_policy_nonce_generator = ->(request) { request.session.id.to_s }
  config.content_security_policy_nonce_directives = %w[script-src]
  config.content_security_policy_nonce_auto = true
end
