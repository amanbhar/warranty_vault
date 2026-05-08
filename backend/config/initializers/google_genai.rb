# frozen_string_literal: true

# Workaround for google-genai gem's Zeitwerk naming conflict (v0.1.1)
# The gem defines Google::Genai in lib/google/genai.rb, but Zeitwerk expects Genai at the top level
# due to how the gem's internal loader is initialized.
# By loading the library manually and avoiding its internal Zeitwerk setup, we bypass the error.

begin
  gem_spec = Gem.loaded_specs["google-genai"]
  if gem_spec
    gem_root = gem_spec.full_gem_path

    # Define common namespaces
    module Google
      module Genai
      end
    end

    # Load all files in the gem's lib/google/genai directory
    # Client is the main interface we use
    require "#{gem_root}/lib/google/genai/version"
    require "#{gem_root}/lib/google/genai/errors"
    require "#{gem_root}/lib/google/genai/types"
    require "#{gem_root}/lib/google/genai/api_client"
    require "#{gem_root}/lib/google/genai/client"
    require "#{gem_root}/lib/google/genai/models"
    require "#{gem_root}/lib/google/genai/chats"
    require "#{gem_root}/lib/google/genai/files"
    require "#{gem_root}/lib/google/genai/tunings"
    require "#{gem_root}/lib/google/genai/caches"
    require "#{gem_root}/lib/google/genai/batches"
    require "#{gem_root}/lib/google/genai/operations"
    require "#{gem_root}/lib/google/genai/tokens"
    require "#{gem_root}/lib/google/genai/live"

    Rails.logger.info "[GoogleGenaiFix] Successfully manually loaded google-genai gem components"
  end
rescue LoadError => e
  Rails.logger.error "[GoogleGenaiFix] Failed to manually load google-genai: #{e.message}"
rescue => e
  Rails.logger.error "[GoogleGenaiFix] Unexpected error during google-genai manual load: #{e.message}"
end
