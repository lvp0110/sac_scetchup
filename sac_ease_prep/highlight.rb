# encoding: UTF-8
# frozen_string_literal: true

module SAC
  module EasePrep
    # Красная подсветка ошибок поверх модели. Материалы граней не меняются.
    module Highlight
      OVERLAY_ID = "sac.ease.error_highlight".freeze
      MAX_TRIANGLE_POINTS = 60_000
      MAX_LINE_POINTS = 40_000

      module_function

      def apply(model, pids)
        return unless available?(model)
        triangles, lines = geometry(model, pids)
        overlay = overlay_for(model)
        return unless overlay
        overlay.triangles = triangles
        overlay.lines = lines
        overlay.enabled = !(triangles.empty? && lines.empty?)
        model.active_view.invalidate
      rescue Support::GeometryFault
        raise
      rescue StandardError => e
        puts "SAC EASE highlight: #{e.class}: #{e.message}"
      end

      def available?(model)
        defined?(Sketchup::Overlay) && model.respond_to?(:overlays)
      end

      def overlay_for(model)
        found = nil
        model.overlays.each { |item| found = item if item.is_a?(ErrorOverlay) }
        return found if found
        found = ErrorOverlay.new
        model.overlays.add(found)
        found
      rescue StandardError
        nil
      end

      def geometry(model, pids)
        triangles = []
        lines = []
        Array(pids).uniq.each do |pid|
          break if triangles.length >= MAX_TRIANGLE_POINTS && lines.length >= MAX_LINE_POINTS
          entity = Support.live_entity(model, pid)
          next unless entity
          case entity
          when Sketchup::Face
            add_face(entity, triangles, lines)
          when Sketchup::Edge
            add_edge(entity, lines)
          when Sketchup::Group, Sketchup::ComponentInstance
            transforms_for(entity).each do |transform|
              entity.definition.entities.grep(Sketchup::Face).each do |face|
                add_face(face, triangles, lines, [transform])
              end
            end
          end
        end
        [triangles, lines]
      end

      def add_face(face, triangles, lines, transforms = nil)
        transforms ||= transforms_for(face)
        return if transforms.empty?
        mesh = face.mesh
        polygons = mesh.polygons.map { |polygon| polygon.map { |index| mesh.point_at(index.abs) } }
        loops = face.loops.map { |loop| loop.vertices.map { |vertex| Support.vertex_position(vertex) } }
        transforms.each do |transform|
          normal = Support.world_normal(face, transform)
          polygons.each do |points|
            next if points.length < 3
            break if triangles.length >= MAX_TRIANGLE_POINTS
            origin = lift(points[0], transform, normal)
            (1...(points.length - 1)).each do |index|
              triangles << origin
              triangles << lift(points[index], transform, normal)
              triangles << lift(points[index + 1], transform, normal)
            end
          end
          next if lines.length >= MAX_LINE_POINTS
          loops.each do |points|
            points.length.times do |index|
              break if lines.length >= MAX_LINE_POINTS
              lines << lift(points[index], transform, normal)
              lines << lift(points[(index + 1) % points.length], transform, normal)
            end
          end
        end
      rescue Support::GeometryFault
        raise
      rescue StandardError
        nil
      end

      def add_edge(edge, lines)
        return if lines.length >= MAX_LINE_POINTS
        transforms_for(edge).each do |transform|
          start_point, end_point = Support.edge_vertices(edge).map { |vertex| Support.vertex_position(vertex) }
          lines << start_point.transform(transform)
          lines << end_point.transform(transform)
        end
      rescue Support::GeometryFault
        raise
      rescue StandardError
        nil
      end

      def lift(point, transform, normal)
        point.transform(transform).offset(normal, 2.mm)
      end

      def transforms_for(entity)
        if entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
          return ancestor_transforms(entity)
        end
        parent = entity.parent
        return [Geom::Transformation.new] if parent.is_a?(Sketchup::Model)
        instances = parent.respond_to?(:instances) ? parent.instances : []
        instances.flat_map { |instance| ancestor_transforms(instance) }
      end

      def ancestor_transforms(instance, stack = [])
        return [] unless instance.valid?
        key = instance.persistent_id
        return [] if stack.include?(key)
        local = instance.transformation
        parent = instance.parent
        if parent.is_a?(Sketchup::Model)
          [local]
        else
          uppers = parent.respond_to?(:instances) ? parent.instances : []
          uppers.flat_map do |upper|
            ancestor_transforms(upper, stack + [key]).map { |transform| transform * local }
          end
        end
      end
    end

    class ErrorOverlay < Sketchup::Overlay
      attr_accessor :triangles, :lines

      def initialize
        super(Highlight::OVERLAY_ID, "SAC EASE — ошибки")
        @triangles = []
        @lines = []
      end

      def draw(view)
        unless @triangles.empty?
          color = Sketchup::Color.new(214, 36, 28)
          color.alpha = 120
          view.drawing_color = color
          index = 0
          while index < @triangles.length
            view.draw(GL_TRIANGLES, @triangles[index, 9000])
            index += 9000
          end
        end
        return if @lines.empty?
        view.drawing_color = Sketchup::Color.new(170, 12, 8)
        view.line_width = 4
        view.line_stipple = ""
        index = 0
        while index < @lines.length
          view.draw(GL_LINES, @lines[index, 8000])
          index += 8000
        end
      rescue StandardError
        nil
      end
    end if defined?(Sketchup::Overlay)
  end
end
