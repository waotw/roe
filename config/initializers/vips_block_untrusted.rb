# Refuse libvips' untrusted loaders.
#
# libvips reads image formats through "loaders", many backed by third-party
# libraries that have never been fuzzed. Handed a crafted file, those can be
# made to read arbitrary files off the filesystem — the flaw behind
# CVE-2026-66066, which was reported against Active Storage's variant
# processing.
#
# Roe does not use Active Storage variants, so patching Rails does NOT close
# this: Roe drives libvips itself (ImageVariantGenerator, ImageDimensions,
# Admin::MediumController, SubstackImporter::MediaHandler). Blocking the
# untrusted loaders is therefore the fix here, not a stopgap. Roe's riskiest
# input is the Substack importer, which downloads images from arbitrary remote
# URLs — nobody vets those the way an admin vets a file they picked.
#
# HOW, given libvips is optional:
#
# `ruby-vips` is `require: false` and pulled in lazily at the point of use, so
# an install with no libvips still boots. This must not change that — hence the
# environment variable rather than a require. libvips reads VIPS_BLOCK_UNTRUSTED
# when the library initialises, which happens on the first lazy `require`, well
# after this file runs. Every call site is covered without naming any of them.
#
# The direct call is for the case where something already loaded vips before
# this initializer; then the variable would be too late. Guarded, because
# `block_untrusted` needs libvips >= 8.13 and ruby-vips >= 2.2.1 — on anything
# older it raises, and a hardening step must never be what stops Roe booting.
#
# Set VIPS_BLOCK_UNTRUSTED=0 to opt out (there is no good reason to).

ENV["VIPS_BLOCK_UNTRUSTED"] ||= "1"

if defined?(::Vips) && ::Vips.respond_to?(:block_untrusted)
  begin
    ::Vips.block_untrusted(true)
  rescue StandardError => e
    Rails.logger.warn "[vips] could not block untrusted loaders: #{e.class} #{e.message}"
  end
end
