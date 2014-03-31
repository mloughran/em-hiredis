module EM::Hiredis
  class ArrayHash
    NULL_ARRAY = [].freeze
    def initialize
      @h = {}
    end

    def add(key, value)
      @h[key] ||= []
      @h[key].push(value)
    end

    def remove(key, value)
      a = @h[key]
      return unless a
      a.delete(value)
    ensure
      @h.delete(key) if a && a.empty?
    end

    def list(key)
      @h[key] || NULL_ARRAY
    end
    alias [] list

    def shift(key)
      a = @h[key]
      return unless a
      a.shift
    ensure
      @h.delete(key) if a && a.empty?
    end

    def has?(key)
      @h.has?(key)
    end
    alias has_key? has?

    def delete(key)
      @h.delete(key)
    end
  end
end
