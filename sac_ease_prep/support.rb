# encoding: UTF-8
# frozen_string_literal: true

module SAC
  module EasePrep
    module Support
      module_function

      def with_operation(model, name)
        model.start_operation(name, true)
        result = yield
        model.commit_operation
        result
      rescue StandardError => e
        model.abort_operation
        puts "SAC EASE: #{e.class}: #{e.message}"
        puts e.backtrace.first(12).join("\n")
        raise
      end

      def live_entity(model, pid)
        entity = model.find_entity_by_persistent_id(pid)
        return nil if entity.nil?
        return nil if entity.respond_to?(:valid?) && !entity.valid?
        entity
      rescue StandardError
        nil
      end

      def live_entities(model, pids)
        Array(pids).map { |pid| live_entity(model, pid) }.compact
      end

      def point_array(point)
        [point.x.to_f, point.y.to_f, point.z.to_f]
      end

      def world_point(point, transform)
        point.transform(transform)
      end

      def world_normal(face, transform)
        normal = face.normal.transform(transform)
        return Geom::Vector3d.new(0, 0, 1) if normal.length <= 1.0e-9
        normal.normalize
        normal
      end

      def face_anchor(face)
        points = face.outer_loop.vertices.map { |vertex| point_array(vertex.position) }
        center = GeomMath.centroid(points)
        local = Geom::Point3d.new(*center)
        klass = face.classify_point(local)
        on_face = [Sketchup::Face::PointInside, Sketchup::Face::PointOnFace].include?(klass)
        on_face ? local : face.outer_loop.vertices.first.position
      end

      def entities_of(entity)
        parent = entity.parent
        return parent if defined?(Sketchup::Entities) && parent.is_a?(Sketchup::Entities)
        return parent.entities if parent.respond_to?(:entities)
        nil
      end

      def locked_path?(path)
        path.any? { |instance| instance.respond_to?(:locked?) && instance.locked? }
      end

      def instance_path_for(entity)
        parent = entity.parent
        return [] if parent.is_a?(Sketchup::Model)
        instance = parent.instances.find { |item| item.valid? && !item.deleted? }
        return [] unless instance
        instance_path_for(instance) + [instance]
      end

      def format_m(length_inches)
        format("%.0f мм", GeomMath.inches_to_m(length_inches) * 1000.0)
      end

      def format_m2(area_sq_inches)
        format("%.2f м²", GeomMath.sq_inches_to_m2(area_sq_inches))
      end

      def format_m3(volume_cu_inches)
        format("%.2f м³", GeomMath.cu_inches_to_m3(volume_cu_inches))
      end

      def untagged?(layer, model)
        return true if layer.nil?
        layer == model.layers[0] || layer.name == "Layer0"
      end

      def layer_label(layer)
        return "Без тега" if layer.nil?
        if layer.respond_to?(:display_name) && !layer.display_name.to_s.empty?
          layer.display_name
        else
          layer.name
        end
      end

      # Face#coplanar_with? есть не во всех версиях SketchUp 2019–2021.
      def faces_coplanar?(first, second)
        return first.coplanar_with?(second) if first.respond_to?(:coplanar_with?)
        plane = first.plane
        length = Math.sqrt((plane[0] * plane[0]) + (plane[1] * plane[1]) + (plane[2] * plane[2]))
        return false if length < 1.0e-9
        first_point = first.outer_loop.vertices.first.position
        second.outer_loop.vertices.all? do |vertex|
          point = vertex.position
          value = (plane[0] * point.x) + (plane[1] * point.y) + (plane[2] * point.z) + plane[3]
          (value / length).abs <= 0.001
        end && point_on_plane?(first_point, second)
      end

      def point_on_plane?(point, face)
        plane = face.plane
        length = Math.sqrt((plane[0] * plane[0]) + (plane[1] * plane[1]) + (plane[2] * plane[2]))
        return false if length < 1.0e-9
        value = (plane[0] * point.x) + (plane[1] * point.y) + (plane[2] * point.z) + plane[3]
        (value / length).abs <= 0.001
      end

      def mirrored?(transform)
        xaxis = transform.xaxis
        yaxis = transform.yaxis
        zaxis = transform.zaxis
        xaxis.cross(yaxis).dot(zaxis) < 0
      end

      def detail_name?(name)
        !!(name.to_s =~ /кресл|стул|диван|баляс|плинтус|карниз|ручк|перепл|chair|seat|sofa|handle|cornice|baseboard|baluster|molding/i)
      end
    end
  end
end
