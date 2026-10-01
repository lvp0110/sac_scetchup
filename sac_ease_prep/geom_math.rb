# encoding: UTF-8
# frozen_string_literal: true

module SAC
  module EasePrep
    # Чистая геометрия без API SketchUp, чтобы правила можно было проверять отдельно.
    module GeomMath
      TOL = 1.0e-8
      INCH_TO_M = 0.0254

      module_function

      def sub(a, b)
        [a[0] - b[0], a[1] - b[1], a[2] - b[2]]
      end

      def add(a, b)
        [a[0] + b[0], a[1] + b[1], a[2] + b[2]]
      end

      def scale(a, k)
        [a[0] * k, a[1] * k, a[2] * k]
      end

      def dot(a, b)
        (a[0] * b[0]) + (a[1] * b[1]) + (a[2] * b[2])
      end

      def cross(a, b)
        [
          (a[1] * b[2]) - (a[2] * b[1]),
          (a[2] * b[0]) - (a[0] * b[2]),
          (a[0] * b[1]) - (a[1] * b[0])
        ]
      end

      def length(a)
        Math.sqrt(dot(a, a))
      end

      def distance(a, b)
        length(sub(a, b))
      end

      def centroid(points)
        return [0.0, 0.0, 0.0] if points.empty?
        n = points.length.to_f
        sx = sy = sz = 0.0
        points.each do |p|
          sx += p[0]
          sy += p[1]
          sz += p[2]
        end
        [sx / n, sy / n, sz / n]
      end

      def newell_normal(points)
        nx = ny = nz = 0.0
        n = points.length
        n.times do |i|
          p1 = points[i]
          p2 = points[(i + 1) % n]
          nx += (p1[1] - p2[1]) * (p1[2] + p2[2])
          ny += (p1[2] - p2[2]) * (p1[0] + p2[0])
          nz += (p1[0] - p2[0]) * (p1[1] + p2[1])
        end
        [nx, ny, nz]
      end

      # Выпуклый многоугольник в своей плоскости. Точки идут по контуру.
      def polygon_convex?(points)
        return true if points.length <= 3
        normal = newell_normal(points)
        return true if length(normal) <= TOL
        sign = 0
        n = points.length
        n.times do |i|
          a = points[i]
          b = points[(i + 1) % n]
          c = points[(i + 2) % n]
          turn = dot(cross(sub(b, a), sub(c, b)), normal)
          next if turn.abs <= TOL
          sgn = turn.positive? ? 1 : -1
          return false if sign != 0 && sgn != sign
          sign = sgn
        end
        true
      end

      # Сумма по треугольникам. Итог нужно поделить на 6, чтобы получить объём.
      def triple(p0, p1, p2)
        (p0[0] * ((p1[1] * p2[2]) - (p1[2] * p2[1]))) -
          (p0[1] * ((p1[0] * p2[2]) - (p1[2] * p2[0]))) +
          (p0[2] * ((p1[0] * p2[1]) - (p1[1] * p2[0])))
      end

      def signed_volume(triangles)
        sum = 0.0
        triangles.each do |p0, p1, p2|
          sum += triple(p0, p1, p2)
        end
        sum / 6.0
      end

      def triangle_area(p0, p1, p2)
        length(cross(sub(p1, p0), sub(p2, p0))) * 0.5
      end

      def plane_from(p0, p1, p2)
        n = cross(sub(p1, p0), sub(p2, p0))
        len = length(n)
        return nil if len <= TOL
        n = scale(n, 1.0 / len)
        d = -dot(n, p0)
        [n[0], n[1], n[2], d]
      end

      def plane_distance(point, plane)
        a, b, c, d = plane
        ((a * point[0]) + (b * point[1]) + (c * point[2]) + d).abs
      end

      def coplanar?(points, tolerance)
        return true if points.length < 4
        plane = nil
        anchor = points[0]
        points.each_with_index do |p1, i|
          points.each_with_index do |p2, j|
            next if j <= i
            plane = plane_from(anchor, p1, p2)
            break if plane
          end
          break if plane
        end
        return true unless plane
        points.all? { |p| plane_distance(p, plane) <= tolerance }
      end

      # Пары индексов точек, которые ближе tolerance, но не совпадают.
      def proximity_pairs(points, tolerance)
        return [] if points.length < 2 || tolerance <= 0
        cell = tolerance
        grid = Hash.new { |h, k| h[k] = [] }
        points.each_with_index do |p, i|
          key = cell_key(p, cell)
          grid[key] << i
        end
        pairs = []
        points.each_with_index do |p, i|
          cx, cy, cz = cell_key(p, cell)
          (-1..1).each do |dx|
            (-1..1).each do |dy|
              (-1..1).each do |dz|
                bucket = grid[[cx + dx, cy + dy, cz + dz]]
                next unless bucket
                bucket.each do |j|
                  next if j <= i
                  dist = distance(p, points[j])
                  pairs << [i, j, dist] if dist > TOL && dist <= tolerance
                end
              end
            end
          end
        end
        pairs
      end

      def cell_key(point, cell)
        [
          (point[0] / cell).floor,
          (point[1] / cell).floor,
          (point[2] / cell).floor
        ]
      end

      def inches_to_m(length)
        length.to_f * INCH_TO_M
      end

      def sq_inches_to_m2(area)
        area.to_f * INCH_TO_M * INCH_TO_M
      end

      def cu_inches_to_m3(volume)
        volume.to_f * INCH_TO_M * INCH_TO_M * INCH_TO_M
      end

      def m2_to_sq_inches(area)
        area.to_f / (INCH_TO_M * INCH_TO_M)
      end
    end
  end
end
