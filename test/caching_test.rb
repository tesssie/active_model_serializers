require "test_helper"

class CachingTest < ActiveSupport::TestCase
  class NullStore
    def fetch(key)
      return store[key] if store[key]

      store[key] = yield
    end

    def clear
      store.clear
    end

    def store
      @store ||= {}
    end

    def read(key)
      store[key]
    end
  end

  class Programmer
    def name
      'Adam'
    end

    def skills
      %w(ruby)
    end

    def read_attribute_for_serialization(name)
      send name
    end
  end

  class Parent
    def id
      'parent1'
    end

    def name
      'Kieran'
    end

    def children
      [ Child.new ]
    end

    def read_attribute_for_serialization(name)
      send name
    end
  end

  class Child
    def id
      'child1'
    end

    def name
      'Joshua'
    end

    def parent
      Parent.new
    end

    def read_attribute_for_serialization(name)
      send name
    end
  end

  def test_serializers_have_a_cache_store
    ActiveModel::Serializer.cache = NullStore.new

    assert_kind_of NullStore, ActiveModel::Serializer.cache
  end

  def test_serializers_can_enable_caching
    serializer = Class.new(ActiveModel::Serializer) do
      cached true
    end

    assert serializer.perform_caching
  end

  def test_serializers_use_cache
    serializer = Class.new(ActiveModel::Serializer) do
      cached true
      attributes :name, :skills

      def self.to_s
        'serializer'
      end

      def cache_key
        object.name
      end
    end

    serializer.cache = NullStore.new
    instance = serializer.new Programmer.new

    instance.to_json

    assert_equal(instance.serializable_hash, serializer.cache.read('serializer/Adam/serializable-hash'))
    assert_equal(instance.to_json, serializer.cache.read('serializer/Adam/to-json'))
  end

  def test_array_serializer_uses_cache
    serializer = Class.new(ActiveModel::ArraySerializer) do
      cached true

      def self.to_s
        'array_serializer'
      end

      def cache_key
        'cache-key'
      end
    end

    serializer.cache = NullStore.new
    instance = serializer.new [Programmer.new]

    instance.to_json

    assert_equal instance.serializable_array, serializer.cache.read('array_serializer/cache-key/serializable-array')
    assert_equal instance.to_json, serializer.cache.read('array_serializer/cache-key/to-json')
  end

  def test_cached_serializers_return_associations

    child_serializer = Class.new(ActiveModel::Serializer) do
      cached true
      attributes :name

      def self.to_s
        'child_serializer'
      end

      def cache_key
        object.name
      end
    end

    parent_serializer = Class.new(ActiveModel::Serializer) do
      cached true
      attributes :name

      has_many :children, serializer: child_serializer, embed: :ids, include: true

      def self.to_s
        'parent_serializer'
      end

      def cache_key
        object.name
      end
    end


    parent_serializer.cache = NullStore.new
    child_serializer.cache = NullStore.new

    instance = parent_serializer.new Parent.new, root: :parent

    initial_keys = instance.as_json.keys

    assert_equal(initial_keys, [:children, :parent])

    cached_keys = instance.as_json.keys

    assert_equal(cached_keys, [:children, :parent])
  end
end
