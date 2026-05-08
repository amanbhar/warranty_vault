# frozen_string_literal: true

# Caching service for performance optimization
# Works with both Redis and MemoryStore
class CacheService
  CACHE_VERSION = "v1"
  DEFAULT_TTL = 5.minutes
  USER_CACHE_KEYS = Set.new

  class << self
    # Fetch from cache or execute block
    def fetch(key, ttl: DEFAULT_TTL, &block)
      cache_key = versioned_key(key)

      Rails.cache.fetch(cache_key, expires_in: ttl, race_condition_ttl: 30.seconds) do
        yield
      end
    end

    # Write to cache
    def write(key, value, ttl: DEFAULT_TTL)
      cache_key = versioned_key(key)
      Rails.cache.write(cache_key, value, expires_in: ttl)
      track_key(key)
    end

    # Read from cache
    def read(key)
      cache_key = versioned_key(key)
      Rails.cache.read(cache_key)
    end

    # Delete from cache
    def delete(key)
      cache_key = versioned_key(key)
      Rails.cache.delete(cache_key)
      untrack_key(key)
    end

    # Clear all cache for a pattern
    def delete_pattern(pattern)
      if Rails.cache.class.name.include?("Redis")
        # Redis supports pattern deletion
        keys = Rails.cache.redis.keys("#{CACHE_VERSION}:#{pattern}*")
        Rails.cache.redis.del(*keys) if keys.any?
      else
        # MemoryStore: delete tracked keys that match pattern
        pattern_regex = Regexp.new(pattern.gsub("*", ".*"))
        keys_to_delete = USER_CACHE_KEYS.select { |k| k =~ pattern_regex }
        keys_to_delete.each { |k| delete(k) }
      end
    end

    # Clear user-specific cache
    def clear_user_cache(user_id)
      delete_pattern("user:#{user_id}")
    end

    private

    def versioned_key(key)
      "#{CACHE_VERSION}:#{key}"
    end

    def track_key(key)
      USER_CACHE_KEYS.add(key)
    end

    def untrack_key(key)
      USER_CACHE_KEYS.delete(key)
    end
  end
end
