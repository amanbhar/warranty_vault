# Backend: Ruby on Rails API
# Dockerfile for warranty_vault_api

FROM ruby:3.3.0

# Install system dependencies
RUN apt-get update -qq && apt-get install -y \
  build-essential \
  libpq-dev \
  nodejs \
  yarn \
  libjemalloc2 \
  netcat-openbsd \
  && rm -rf /var/lib/apt/lists/*

# Set working directory — must match the volume mount in docker-compose (/rails)
WORKDIR /rails

# Install bundler
RUN gem install bundler

# Copy Gemfile first for layer caching
COPY Gemfile Gemfile.lock ./

# Install gems into the system gem path (shared with bundle_cache volume)
RUN bundle install

# Copy application code
COPY . .

# Copy and setup entrypoint script
COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Expose port 3005
EXPOSE 3005

# Use entrypoint script to wait for services and run migrations
ENTRYPOINT ["docker-entrypoint.sh"]

# Start Rails server on port 3005, bound to all interfaces
CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0", "-p", "3005"]
