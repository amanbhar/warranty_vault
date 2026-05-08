#!/bin/bash
# Wait for database to be ready before starting Rails

set -e

# Remove stale Rails PID
rm -f /rails/tmp/pids/server.pid

echo "Waiting for PostgreSQL..."
while ! nc -z postgres 5432; do
  sleep 0.1
done
echo "PostgreSQL is up!"

echo "Waiting for Redis..."
while ! nc -z redis 6379; do
  sleep 0.1
done
echo "Redis is up!"

# Run database migrations (skipped if SKIP_MIGRATIONS=true)
if [ "$SKIP_MIGRATIONS" != "true" ]; then
  echo "Running database migrations..."
  bundle exec rails db:migrate
else
  echo "Skipping database migrations..."
fi

# Start Rails server
echo "Starting Rails server..."
exec "$@"
