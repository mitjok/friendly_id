# encoding: utf-8
Module.send :include, Module.new {
  def test(name, &block)
    define_method("test_#{name.gsub(/[^a-z0-9]/i, "_")}".to_sym, &block)
  end
  alias :should :test
}

module FriendlyId
  module Test

    # Tests for any model that implements FriendlyId. Any test that tests model
    # features should include this module.
    module Generic

      def setup
        klass.send delete_all_method
      end

      def teardown
        klass.send delete_all_method
      end

      def instance
        raise NotImplementedError
      end

      def klass
        raise NotImplementedError
      end

      def other_class
        raise NotImplementedError
      end

      def find_method
        raise NotImplementedError
      end

      def create_method
        raise NotImplementedError
      end

      def update_method
        raise NotImplementedError
      end

      def validation_exceptions
        return RuntimeError
      end

      def assert_validation_error
        if validation_exceptions
          assert_raise(*[validation_exceptions].flatten) do
            yield
          end
        else  # DataMapper does not raise Validation Errors
          i = yield
          if i.kind_of?(TrueClass) || i.kind_of?(FalseClass)
            assert !i
          else
            instance = i
            assert !instance.errors.empty?
          end
        end
      end

      test "models should have a friendly id config" do
        assert_not_nil klass.friendly_id_config
      end

      test "instances should have a friendly id by default" do
        assert_not_nil instance.friendly_id
      end

      test "instances should have a friendly id status" do
        assert_not_nil instance.friendly_id_status
      end

      test "instances should be findable by their friendly id" do
        assert_equal instance, klass.send(find_method, instance.friendly_id)
      end

      test "instances should be findable by their numeric id as an integer" do
        assert_equal instance, klass.send(find_method, instance.id.to_i)
      end

      test "instances should be findable by their numeric id as a string" do
        assert_equal instance, klass.send(find_method, instance.id.to_s)
      end

      test "instances should be findable by a numeric friendly_id" do
        instance = klass.send(create_method, :name => "206")
        assert_equal instance, klass.send(find_method, "206")
      end

      test "creation should raise an error if the friendly_id text is reserved" do
        assert_validation_error do
          klass.send(create_method, :name => "new")
        end
      end

      test "creation should raise an error if the friendly_id text is an empty string" do
        assert_validation_error do
          klass.send(create_method, :name => "")
        end
      end

      test "creation should raise an error if the friendly_id text is a blank string" do
        assert_validation_error do
          klass.send(create_method, :name => "   ")
        end
      end

      test "creation should raise an error if the friendly_id text is nil and allow_nil is false" do
        assert_validation_error do
          klass.send(create_method, :name => nil)
        end
      end

      test "creation should succeed if the friendly_id text is nil and allow_nil is true" do
        klass.friendly_id_config.stubs(:allow_nil?).returns(true)
        assert klass.send(create_method, :name => nil)
      end

      test "creation should succeed if the friendly_id text is empty and allow_nil is true" do
        klass.friendly_id_config.stubs(:allow_nil?).returns(true)
        begin
          assert klass.send(create_method, :name => "")
        rescue ActiveRecord::RecordInvalid => e
          raise unless e.message =~ /Name can't be blank/ # Test not applicable in this case
        end
      end

      test "creation should succeed if the friendly_id text converts to empty and allow_nil is true" do
        klass.friendly_id_config.stubs(:allow_nil?).returns(true)
        assert klass.send(create_method, :name => "*")
      end

      test "should allow the same friendly_id across models" do
        other_instance = other_class.send(create_method, :name => instance.name)
        assert_equal other_instance.friendly_id, instance.friendly_id
      end

      test "reserved words can be specified as a regular expression" do
        klass.friendly_id_config.stubs(:reserved_words).returns(/jo/)
        assert_validation_error do
          klass.send(create_method, :name => "joe")
        end
      end

      test "should not raise reserved error unless regexp matches" do
        klass.friendly_id_config.stubs(:reserved_words).returns(/ddsadad/)
        assert_nothing_raised do
          klass.send(create_method, :name => "joe")
        end
      end

    end

    module Simple

      test "should allow friendly_id to be nillable if allow_nil is true" do
        klass.friendly_id_config.stubs(:allow_nil?).returns(true)
        instance = klass.send(create_method, :name => "hello")
        assert instance.friendly_id
        instance.name = nil
        assert instance.send(save_method)
      end

    end

    # Tests for any model that implements slugs.
    module Slugged

      test "should have a slug" do
        assert_not_nil instance.slug
      end

      test "should not make a new slug unless the friendly_id method value has changed" do
        instance.note = instance.note.to_s << " updated"
        instance.send save_method
        assert_equal 1, instance.slugs.size
      end

      test "should make a new slug if the friendly_id method value has changed" do
        instance.name = "Changed title"
        instance.send save_method
        slugs = if instance.slugs.respond_to?(:reload)
          instance.slugs.reload
        else
          instance.slugs(true)
        end
        assert_equal 2, slugs.size
      end

      test "should be able to reuse an old friendly_id without incrementing the sequence" do
        old_title = instance.name
        old_friendly_id = instance.friendly_id
        instance.name = "A changed title"
        instance.send save_method
        instance.name = old_title
        instance.send save_method
        assert_equal old_friendly_id, instance.friendly_id
      end

      test "should increment the slug sequence for duplicate friendly ids" do
        instance2 = klass.send(create_method, :name => instance.name)
        assert_match(/2\z/, instance2.friendly_id)
      end

      test "should find instance with a sequenced friendly_id" do
        instance2 = klass.send(create_method, :name => instance.name)
        assert_equal instance2, klass.send(find_method, instance2.friendly_id)
      end

      test "should indicate correct status when found with a sequence" do
        instance2 = klass.send(create_method, :name => instance.name)
        instance2 = klass.send(find_method, instance2.friendly_id)
        assert instance2.friendly_id_status.best?
      end

      test "should indicate correct status when found by a numeric friendly_id" do
        instance = klass.send(create_method, :name => "100")
        instance2 = klass.send(find_method, "100")
        assert instance2.friendly_id_status.best?, "status expected to be best but isn't."
        assert instance2.friendly_id_status.current?, "status expected to be current but isn't."
      end

      test "should remain findable by previous slugs" do
        old_friendly_id = instance.friendly_id
        instance.name = "#{old_friendly_id} updated"
        instance.send(save_method)
        assert_not_equal old_friendly_id, instance.friendly_id
        assert_equal instance, klass.send(find_method, old_friendly_id)
      end

      test "should not create a slug when allow_nil is true and friendy_id text is blank" do
        klass.friendly_id_config.stubs(:allow_nil?).returns(true)
        instance = klass.send(create_method, :name => nil)
        assert_nil instance.slug
      end

      test "should not allow friendly_id to be nillable even if allow_nil is true" do
        klass.friendly_id_config.stubs(:allow_nil?).returns(true)
        instance = klass.send(create_method, :name => "hello")
        assert instance.friendly_id
        instance.name = nil
        assert_validation_error do
          instance.send(save_method)
        end
      end

      test "should approximate ascii if configured" do
        klass.friendly_id_config.stubs(:approximate_ascii?).returns(true)
        instance = klass.send(create_method, :name => "Cañón")
        assert_equal "canon", instance.friendly_id
      end

      test "should approximate ascii with options if configured" do
        klass.friendly_id_config.stubs(:approximate_ascii?).returns(true)
        klass.friendly_id_config.stubs(:ascii_approximation_options).returns(:spanish)
        instance = klass.send(create_method, :name => "Cañón")
        assert_equal "canion", instance.friendly_id
      end
    end

    # Tests for FriendlyId::Status.
    module Status

      test "should default to not friendly" do
        assert !status.friendly?
      end

      test "should default to numeric" do
        assert status.numeric?
      end

    end

    # Tests for FriendlyId::Status for a model that uses slugs.
    module SluggedStatus

      test "should be friendly if slug is set" do
        status.slug = Slug.new
        assert status.friendly?
      end

      test "should be friendly if name is set" do
        status.name = "name"
        assert status.friendly?
      end

      test "should be current if current slug is set" do
        status.slug = instance.slug
        assert status.current?
      end

      test "should not be current if non-current slug is set" do
        status.slug = Slug.new(:sluggable => instance)
        assert !status.current?
      end

      test "should be best if it is current" do
        status.slug = instance.slug
        assert status.best?
      end

      test "should be best if it is numeric, but record has no slug" do
        instance.slugs = []
        instance.slug = nil
        assert status.best?
      end

      [:record, :name].each do |symbol|
        test "should have #{symbol} after find using friendly_id" do
          instance2 = klass.send(find_method, instance.friendly_id)
          assert_not_nil instance2.friendly_id_status.send(symbol)
        end
      end

      def status
        @status ||= instance.friendly_id_status
      end

      def klass
        raise NotImplementedError
      end

      def instance
        raise NotImplementedError
      end

    end

    # Tests for models to ensure that they properly implement using the
    # +normalize_friendly_id+ method to allow developers to hook into the
    # slug string generation.
    module CustomNormalizer

      test "should invoke the custom normalizer" do
        assert_equal "JOE SCHMOE", klass.send(create_method, :name => "Joe Schmoe").friendly_id
      end

      test "should respect the max_length option" do
        klass.friendly_id_config.stubs(:max_length).returns(3)
        assert_equal "JOE", klass.send(create_method, :name => "Joe Schmoe").friendly_id
      end

      test "should raise an error if the friendly_id text is reserved" do
        klass.friendly_id_config.stubs(:reserved_words).returns(["JOE"])
        if validation_exceptions
          assert_raise(*[validation_exceptions].flatten) do
            klass.send(create_method, :name => "Joe")
          end
        else  # DataMapper does not raise Validation Errors
          instance = klass.send(create_method, :name => "Joe")
          assert !instance.errors.empty?
        end
      end

    end
  end
end
