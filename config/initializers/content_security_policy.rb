# Be sure to restart your server when you modify this file.

# Define an application-wide content security policy.
# See the Securing Rails Applications Guide for more information:
# https://guides.rubyonrails.org/security.html#content-security-policy-header
#
# Currently Roe does NOT enforce a CSP. The block below is kept as a
# ready-to-enable template — uncomment when you're ready to lock things
# down. When you do, the Custom Code feature (Admin → Settings →
# Custom Code) needs two things to keep working:
#
#   1. Inline <script>/<style> from the user's pasted snippets must
#      receive the per-request nonce. Already handled by
#      CustomCodeRenderer.render_field in layouts/site.html.erb.
#
#   2. External <script src=…>/<link href=…> from the user's pasted
#      snippets need their hostnames in the relevant CSP source
#      lists. The ->{ CustomCodeRenderer.allowlist_hosts } proc below
#      surfaces them — Rails evaluates it per-request, so adding a
#      new external script in the admin takes effect on the next
#      page load without a deploy.

# Rails.application.configure do
#   config.content_security_policy do |policy|
#     policy.default_src :self, :https
#     policy.font_src    :self, :https, :data, -> { CustomCodeRenderer.allowlist_hosts }
#     policy.img_src     :self, :https, :data, -> { CustomCodeRenderer.allowlist_hosts }
#     policy.object_src  :none
#     policy.script_src  :self, :https, -> { CustomCodeRenderer.allowlist_hosts }
#     policy.style_src   :self, :https, -> { CustomCodeRenderer.allowlist_hosts }
#     # Specify URI for violation reports
#     # policy.report_uri "/csp-violation-report-endpoint"
#   end
#
#   # Generate session nonces for permitted importmap, inline scripts, and inline styles.
#   config.content_security_policy_nonce_generator = ->(request) { request.session.id.to_s }
#   config.content_security_policy_nonce_directives = %w(script-src style-src)
#
#   # Automatically add `nonce` to `javascript_tag`, `javascript_include_tag`, and `stylesheet_link_tag`
#   # if the corresponding directives are specified in `content_security_policy_nonce_directives`.
#   # config.content_security_policy_nonce_auto = true
#
#   # Report violations without enforcing the policy.
#   # config.content_security_policy_report_only = true
# end
