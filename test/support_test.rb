# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require_relative "../sac_ease_prep/support"

module SAC
  module EasePrep
    class SupportTest < Minitest::Test
      def test_options_provider_position_error_is_a_sketchup_glitch
        error = NoMethodError.new("undefined method `position' for #<Sketchup::OptionsProvider:0x000000013cc55138>")
        assert Support.broken_geometry?(error)
        assert_includes Support::BROKEN_GEOMETRY_MESSAGE, "OptionsProvider"
      end

      def test_geometry_fault_is_the_same_glitch
        error = Support::GeometryFault.new(Support::BROKEN_GEOMETRY_MESSAGE)
        assert Support.broken_geometry?(error)
      end

      def test_other_errors_stay_visible
        refute Support.broken_geometry?(NoMethodError.new("undefined method `foo' for nil:NilClass"))
        refute Support.broken_geometry?(StandardError.new("position OptionsProvider"))
      end

      def test_options_provider_is_not_treated_as_a_vertex
        provider = Class.new do
          def self.name
            "Sketchup::OptionsProvider"
          end
        end.new
        assert Support.options_provider?(provider)
        error = assert_raises(Support::GeometryFault) { Support.ensure_vertex!(provider) }
        assert_equal Support::BROKEN_GEOMETRY_MESSAGE, error.message
      end
    end
  end
end
