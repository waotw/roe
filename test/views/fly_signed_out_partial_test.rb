require "test_helper"

# "You're not signed in to Fly" is written once, in
# app/views/admin/shared/_fly_signed_out.html.erb, and shown in two places:
# the warning on Settings → Deploy and the card on a deploy it stopped.
class FlySignedOutPartialTest < ActionView::TestCase
  def shown(**locals) = render(partial: "admin/shared/fly_signed_out", locals: locals)

  test "on Settings → Deploy it ends with reloading the page, and the page can toggle it" do
    html = shown(context: :settings)

    assert_includes html, ERB::Util.html_escape(DeployPreflight::FLY_SIGNED_OUT_TITLE)
    assert_includes html, "fly auth login"
    assert_includes html, "Reload this page."
    assert_not_includes html, "Then deploy again."
    assert_includes html, 'id="fly-auth-warning"', "the target switch finds it by this id"
  end

  test "on a stopped deploy it ends with deploying again" do
    html = shown(context: :deploy)

    assert_includes html, ERB::Util.html_escape(DeployPreflight::FLY_SIGNED_OUT_TITLE)
    assert_includes html, "fly auth login"
    assert_includes html, "Then deploy again."
    assert_not_includes html, "Reload this page."
    assert_not_includes html, 'id="fly-auth-warning"', "only the settings warning is toggled"
  end

  test "both link to the troubleshooting section for it" do
    [ :settings, :deploy ].each do |context|
      assert_includes shown(context: context), "/documentation/roe/troubleshoot-deployment#fly-signed-out"
    end
  end

  test "Settings can start it hidden while Kamal is chosen" do
    assert_match(/class="[^"]*\bhidden\b/, shown(context: :settings, hidden: true))
    assert_no_match(/class="[^"]*\bhidden\b/, shown(context: :settings, hidden: false))
  end

  test "a deploy stopped this way shows the partial, not a generic card" do
    @deploy_status = { state: :failed, target: "fly", error: "#{DeployPreflight::FLY_SIGNED_OUT_TITLE}.",
                       log: "[preflight] #{DeployPreflight::FLY_SIGNED_OUT_TITLE}",
                       preflight: [ DeployPreflight.new.fly_signed_out_issue.to_h ] }
    html = render(partial: "admin/updates/deploy_active")

    assert_includes html, "Then deploy again."
    assert_includes html, "fly auth login"
  end
end
