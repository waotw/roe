# frozen_string_literal: true

require "test_helper"

# Roe builds on the deploying computer, not on the server.
#
# The generated config used to name the deploy server as a remote buildx node.
# That asked one small droplet to build and serve at the same moment, needed
# memory a 1GB box doesn't have, and — when local Docker was off — made Kamal
# fail with "Permission denied (publickey)" against the server, which reads as
# a broken deploy key rather than a stopped daemon.
class DeployConfigGeneratorBuilderTest < ActiveSupport::TestCase
  def generated_kamal_config
    File.read(Rails.root.join("config", "deploy.yml"))
  rescue Errno::ENOENT
    skip "no generated deploy.yml on this machine"
  end

  test "the generator emits no remote builder" do
    source = File.read(Rails.root.join("app", "services", "deploy_config_generator.rb"))
    builder = source[/^\s*builder:.*?^\s*boot:/m]

    assert builder.present?, "couldn't find the builder block"
    assert_no_match(/^\s*remote:\s*ssh/, builder,
                    "a remote builder is back in the generated config")
    assert_match(/arch: amd64/, builder, "the target arch still has to be pinned")
  end

  # Pruning the server cleared a cache nothing used while leaving the real one
  # untouched, so the button silently did nothing.
  test "the cache reset prunes locally, not over SSH" do
    source = File.read(Rails.root.join("app", "jobs", "perform_deploy_job.rb"))
    method = source[/def clear_build_cache.*?^  end/m]

    assert method.present?, "clear_build_cache is gone"
    assert_match(/"docker", "buildx", "prune"/, method)
    assert_no_match(/"ssh"/, method, "it's pruning the wrong machine again")
  end
end
