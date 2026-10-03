# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require_relative "../sac_ease_prep/geom_math"

module SAC
  module EasePrep
    class GeomMathTest < Minitest::Test
      def test_cube_volume_is_positive_when_normals_point_out
        triangles = outward_cube_triangles(1.0)
        volume = GeomMath.signed_volume(triangles)
        assert_in_delta 1.0, volume, 1e-9
      end

      def test_inward_cube_volume_is_negative
        triangles = outward_cube_triangles(1.0).map { |tri| [tri[0], tri[2], tri[1]] }
        volume = GeomMath.signed_volume(triangles)
        assert_in_delta(-1.0, volume, 1e-9)
      end

      def test_convex_square
        square = [[0, 0, 0], [2, 0, 0], [2, 1, 0], [0, 1, 0]]
        assert GeomMath.polygon_convex?(square)
      end

      def test_concave_arrow
        arrow = [[0, 0, 0], [3, 1, 0], [0, 2, 0], [1, 1, 0]]
        refute GeomMath.polygon_convex?(arrow)
      end

      def test_coplanar_and_bent_quad
        flat = [[0, 0, 0], [1, 0, 0], [1, 1, 0], [0, 1, 0.0]]
        bent = [[0, 0, 0], [1, 0, 0], [1, 1, 0], [0, 1, 0.2]]
        assert GeomMath.coplanar?(flat, 1e-6)
        refute GeomMath.coplanar?(bent, 1e-4)
      end

      def test_proximity_finds_only_the_close_pair
        points = [[0, 0, 0], [0.5, 0, 0], [10, 0, 0]]
        pairs = GeomMath.proximity_pairs(points, 1.0)
        assert_equal [[0, 1]], pairs.map { |i, j, _dist| [i, j] }
      end

      def test_two_fold_layer_name
        assert_equal ["Окна", "Окна"], GeomMath.two_fold_parts("Окна $ Окна")
        assert_equal ["FrontMat", "RearMat"], GeomMath.two_fold_parts("  FrontMat $ RearMat ")
        assert_nil GeomMath.two_fold_parts("Двери")
        assert_nil GeomMath.two_fold_parts("Окна $")
        assert_nil GeomMath.two_fold_parts("A $ B $ C")
        assert_equal "Экран $ Экран", GeomMath.two_fold_name("Экран")
        assert_equal "Окна $ Окна", GeomMath.two_fold_name("Окна $")
        assert_equal "Грань $ Грань", GeomMath.two_fold_name(" $ ")
      end

      def test_unit_conversion_roundtrip
        assert_in_delta 1.0, GeomMath.inches_to_m(1.0 / GeomMath::INCH_TO_M), 1e-9
        assert_in_delta 2.0, GeomMath.sq_inches_to_m2(GeomMath.m2_to_sq_inches(2.0)), 1e-9
      end

      def outward_cube_triangles(size)
        s = size
        faces = [
          [[0, 0, 0], [0, s, 0], [s, s, 0], [s, 0, 0]],
          [[0, 0, s], [s, 0, s], [s, s, s], [0, s, s]],
          [[0, 0, 0], [s, 0, 0], [s, 0, s], [0, 0, s]],
          [[0, s, 0], [0, s, s], [s, s, s], [s, s, 0]],
          [[0, 0, 0], [0, 0, s], [0, s, s], [0, s, 0]],
          [[s, 0, 0], [s, s, 0], [s, s, s], [s, 0, s]]
        ]
        faces.flat_map { |quad| [[quad[0], quad[1], quad[2]], [quad[0], quad[2], quad[3]]] }
      end
    end
  end
end
