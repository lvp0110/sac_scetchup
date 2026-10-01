# encoding: UTF-8
# frozen_string_literal: true

require "json"

module SAC
  module EasePrep
    class Settings
      KEY = "SAC_EASE".freeze

      DEFAULTS = {
        "ease_version" => 5,
        "scope" => "model",
        "min_edge_mm" => 20.0,
        "min_area_m2" => 0.01,
        "min_thickness_mm" => 10.0,
        "weld_mm" => 1.0,
        "max_curve_segments" => 24,
        "max_smooth_faces" => 40,
        "small_object_mm" => 300.0,
        "detail_face_limit" => 40,
        "remove_materials" => true,
        "triangulate_nonconvex" => false
      }.freeze

      attr_accessor :ease_version, :scope, :min_edge_mm, :min_area_m2,
                    :min_thickness_mm, :weld_mm, :max_curve_segments,
                    :max_smooth_faces, :small_object_mm, :detail_face_limit,
                    :remove_materials, :triangulate_nonconvex

      def self.load
        raw = Sketchup.read_default(KEY, "settings", nil)
        hash = raw.is_a?(String) && !raw.empty? ? JSON.parse(raw) : {}
        from_hash(hash)
      rescue StandardError
        from_hash({})
      end

      def self.from_hash(hash)
        data = DEFAULTS.merge(stringify(hash || {}))
        settings = new
        settings.ease_version = data["ease_version"].to_i == 4 ? 4 : 5
        settings.scope = data["scope"].to_s == "selection" ? "selection" : "model"
        settings.min_edge_mm = positive_float(data["min_edge_mm"], DEFAULTS["min_edge_mm"])
        settings.min_area_m2 = positive_float(data["min_area_m2"], DEFAULTS["min_area_m2"])
        settings.min_thickness_mm = positive_float(data["min_thickness_mm"], DEFAULTS["min_thickness_mm"])
        settings.weld_mm = positive_float(data["weld_mm"], DEFAULTS["weld_mm"])
        settings.max_curve_segments = positive_int(data["max_curve_segments"], DEFAULTS["max_curve_segments"])
        settings.max_smooth_faces = positive_int(data["max_smooth_faces"], DEFAULTS["max_smooth_faces"])
        settings.small_object_mm = positive_float(data["small_object_mm"], DEFAULTS["small_object_mm"])
        settings.detail_face_limit = positive_int(data["detail_face_limit"], DEFAULTS["detail_face_limit"])
        settings.remove_materials = truthy(data["remove_materials"])
        settings.triangulate_nonconvex = truthy(data["triangulate_nonconvex"])
        settings
      end

      def self.stringify(hash)
        out = {}
        hash.each { |key, value| out[key.to_s] = value }
        out
      end

      def self.positive_float(value, fallback)
        number = Float(value)
        number.positive? ? number : fallback
      rescue StandardError
        fallback
      end

      def self.positive_int(value, fallback)
        number = Integer(value)
        number.positive? ? number : fallback
      rescue StandardError
        fallback
      end

      def self.truthy(value)
        value == true || value.to_s == "true"
      end

      def to_h
        {
          "ease_version" => ease_version,
          "scope" => scope,
          "min_edge_mm" => min_edge_mm,
          "min_area_m2" => min_area_m2,
          "min_thickness_mm" => min_thickness_mm,
          "weld_mm" => weld_mm,
          "max_curve_segments" => max_curve_segments,
          "max_smooth_faces" => max_smooth_faces,
          "small_object_mm" => small_object_mm,
          "detail_face_limit" => detail_face_limit,
          "remove_materials" => remove_materials,
          "triangulate_nonconvex" => triangulate_nonconvex
        }
      end

      def save
        Sketchup.write_default(KEY, "settings", JSON.generate(to_h))
      end

      def min_edge
        min_edge_mm.mm
      end

      def min_area
        GeomMath.m2_to_sq_inches(min_area_m2)
      end

      def min_thickness
        min_thickness_mm.mm
      end

      def weld_gap
        weld_mm.mm
      end

      def small_object
        small_object_mm.mm
      end

      def ease4?
        ease_version == 4
      end
    end
  end
end
