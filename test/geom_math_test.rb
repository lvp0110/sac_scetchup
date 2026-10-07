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

      def test_triangle_follows_the_face_normal
        kept = GeomMath.orient_triangle([0, 0, 0], [1, 0, 0], [0, 1, 0], [0, 0, 1])
        assert_equal [[0, 0, 0], [1, 0, 0], [0, 1, 0]], kept
        flipped = GeomMath.orient_triangle([0, 0, 0], [1, 0, 0], [0, 1, 0], [0, 0, -1])
        assert_equal [[0, 0, 0], [0, 1, 0], [1, 0, 0]], flipped
      end

      def test_hole_cap_closes_the_missing_floor_patch
        # Пол не через начало координат: иначе его треугольники не дают вклад в объём.
        cube = outward_cube_triangles(1.0).map { |tri| tri.map { |point| [point[0], point[1], point[2] + 2.0] } }
        full = GeomMath.signed_volume(cube)
        hole = [[0.25, 0.25, 2.0], [0.25, 0.75, 2.0], [0.75, 0.75, 2.0], [0.75, 0.25, 2.0]]
        cap = GeomMath.signed_volume(GeomMath.loop_cap_triangles(hole.reverse))
        assert_in_delta GeomMath.signed_volume(quad_triangles(hole)), cap, 1e-9

        open_shell = cube.reject { |tri| tri.all? { |point| (point[2] - 2.0).abs < 1e-9 } }
        open_shell.concat(floor_frame_triangles(2.0))
        open_volume = GeomMath.signed_volume(open_shell)
        assert_in_delta full, open_volume + cap, 1e-9
        refute_in_delta full, open_volume, 1e-4
      end

      def test_unit_conversion_roundtrip
        assert_in_delta 1.0, GeomMath.inches_to_m(1.0 / GeomMath::INCH_TO_M), 1e-9
        assert_in_delta 2.0, GeomMath.sq_inches_to_m2(GeomMath.m2_to_sq_inches(2.0)), 1e-9
      end

      def quad_triangles(quad)
        [[quad[0], quad[1], quad[2]], [quad[0], quad[2], quad[3]]]
      end

      def floor_frame_triangles(z)
        strips = [
          [[0.0, 0.0, z], [0.0, 0.25, z], [1.0, 0.25, z], [1.0, 0.0, z]],
          [[0.0, 0.75, z], [0.0, 1.0, z], [1.0, 1.0, z], [1.0, 0.75, z]],
          [[0.0, 0.25, z], [0.0, 0.75, z], [0.25, 0.75, z], [0.25, 0.25, z]],
          [[0.75, 0.25, z], [0.75, 0.75, z], [1.0, 0.75, z], [1.0, 0.25, z]]
        ]
        strips.flat_map { |quad| quad_triangles(quad) }
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
