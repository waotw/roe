# syntax=docker/dockerfile:1
# check=error=true

ARG RUBY_VERSION=3.2.2
FROM ruby:$RUBY_VERSION-slim AS base

LABEL fly_launch_runtime="rails"

# Rails app lives here
WORKDIR /rails

# Update gems and bundler
RUN gem update --system --no-document && \
    gem install -N bundler

# Install base packages
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl libjemalloc2 libvips sqlite3 && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Set production environment
ENV BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test" \
    RAILS_ENV="production"


# Throw-away build stage to reduce size of final image
FROM base AS build

# Install packages needed to build gems
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential libffi-dev libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Install application gems
COPY Gemfile Gemfile.lock ./
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile --gemfile

# Copy application code
COPY . .

# Precompile bootsnap code for faster boot times
RUN bundle exec bootsnap precompile app/ lib/

# Force cache invalidation for the asset-build steps below. Earlier
# broken builds poisoned the registry-side build cache (kamal uses
# --cache-from registry by default), causing every subsequent
# `kamal deploy` to reuse a cached precompile layer that never
# included tailwind in the manifest. Bumping this comment forces
# the next build to rebuild from this layer onward.
ARG ASSET_BUILD_REV=2026-05-15
RUN echo "asset build rev: ${ASSET_BUILD_REV}"

# Build Tailwind CSS, then precompile assets. Two separate RUN steps
# rather than one combined `tailwindcss:build assets:precompile` so
# they execute as independent processes — eliminates any chance of
# precompile reading a stale file list before tailwindcss:build's
# output lands. Each step's exit code is checked independently.
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails tailwindcss:build
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile


# Final stage for app image
FROM base

# Install packages needed for deployment
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y libvips gosu rsync && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Copy built artifacts: gems, application
COPY --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"

# Stage VERSION + root companion files from the build stage rather
# than re-reading them from the build context. The build stage's
# COPY . . at line 43 already pulled everything in; we just forward
# from there. Two wins:
#
#   1. The build context only has to be readable in ONE place (the
#      build stage). The final stage's cache-key computation reads
#      from the build stage's image layers, not from the context —
#      which sidesteps "ref ... not found" failures from BuildKit
#      with remote builders that handle context transfer flakily.
#
#   2. If VERSION genuinely isn't in the build context (e.g.,
#      PerformDeployJob#prepare_version_file silently failed), the
#      build fails LOUDLY at this line with a clear error pointing
#      at the staging step — instead of failing at a cache-key
#      check that takes ten minutes to diagnose.
COPY --from=build /rails/VERSION /rails/VERSION
COPY --from=build /rails/roe.sh /rails/README.md /rails/AGENTS.md /rails/

# Set up versioned directory structure
# /rails/current/ - Current Roe version (Rails app)
# /rails/site/ - User content (symlinked to /data/site for persistence)
RUN mkdir -p /rails/current && \
    mkdir -p /data/db /data/site && \
    ln -s /data/site /rails/site

# Copy Rails app to current/ directory
COPY --from=build /rails /rails/current

# Run and own only the runtime files as a non-root user for security
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash && \
    chown -R 1000:1000 /rails/current/db /rails/current/log /rails/current/storage /rails/current/tmp /data

USER root

# Deployment options
ENV DATABASE_URL="sqlite3:///data/site/db/production/production.sqlite3"

# Entrypoint prepares the database.
ENTRYPOINT ["/rails/current/bin/docker-entrypoint"]

# Start server via Thruster by default, this can be overwritten at runtime
EXPOSE 8080
VOLUME /data
WORKDIR /rails/current
CMD ["./bin/thrust", "./bin/rails", "server"]
# rebuild 1778798348
# bust 1778801469
