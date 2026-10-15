# Cambia Rails.cache por un MemoryStore dentro del bloque y lo restaura siempre.
module CacheHelpers
  def with_memory_cache
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    yield Rails.cache
  ensure
    Rails.cache = original
  end
end
