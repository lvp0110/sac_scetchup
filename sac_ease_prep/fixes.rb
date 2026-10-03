# encoding: UTF-8
# frozen_string_literal: true

module SAC
  module EasePrep
    module Fixes
      SAFE_FIRST = %w[erase_stray weld close_loops merge].freeze
      TAG_FLOOR = "Пол".freeze
      TAG_CEILING = "Потолок".freeze
      TAG_WALLS = "Стены".freeze
      PRESET_TAGS = [TAG_WALLS, TAG_FLOOR, TAG_CEILING, "Окна $ Окна", "Двери", "Зрители", "Сцена"].freeze

      module_function

      def apply_safe(model, settings)
        Support.with_operation(model, "SAC EASE: безопасные исправления") do
          first = Analyzer.analyze(model, settings)
          SAFE_FIRST.each do |type|
            plans(first, type).each { |plan| apply_plan(model, plan) }
          end
          second = Analyzer.analyze(model, settings)
          plans(second, "clear_materials").each { |plan| apply_plan(model, plan) } if settings.remove_materials
          plans(second, "reverse").each { |plan| apply_plan(model, plan) }
          plans(second, "make_twofold").each { |plan| apply_plan(model, plan) }
          plans(second, "triangulate").each { |plan| apply_plan(model, plan) }
        end
      end

      def apply_issue(model, result, issue_id)
        plan = result.plans[issue_id]
        return false unless plan
        Support.with_operation(model, "SAC EASE: исправление") do
          apply_plan(model, plan)
        end
        true
      end

      def create_tags(model)
        Support.with_operation(model, "SAC EASE: теги") do
          PRESET_TAGS.each { |name| ensure_layer(model, name) }
        end
      end

      def purge(model)
        Support.with_operation(model, "SAC EASE: очистка неиспользуемого") do
          model.materials.purge_unused
          model.layers.purge_unused
          model.definitions.purge_unused
          model.styles.purge_unused if model.respond_to?(:styles) && model.styles.respond_to?(:purge_unused)
        end
      end

      def focus(model, result, issue_id)
        issue = result.data["issues"].find { |item| item["id"] == issue_id }
        return unless issue
        pids = issue["focus_pids"]
        plan = result.plans[issue_id]
        pids = plan["face_pids"] || plan["edge_pids"] || plan["pids"] if pids.nil? || pids.empty?
        entities = Support.live_entities(model, Array(pids).first(80))
        return if entities.empty?
        path = Support.instance_path_for(entities.first)
        model.active_path = path.empty? ? nil : path
        active = model.active_entities
        selectable = entities.select do |entity|
          parent = entity.parent
          parent.respond_to?(:entities) && parent.entities == active
        end
        selectable = entities if selectable.empty?
        model.selection.clear
        model.selection.add(selectable)
        model.active_view.zoom(selectable)
      end

      def plans(result, type)
        result.plans.values.select { |plan| plan["type"] == type }
      end

      def apply_plan(model, plan)
        case plan["type"]
        when "erase_stray", "erase_objects", "erase_hidden", "erase_annotations"
          erase_pids(model, plan["pids"])
        when "weld"
          weld_pairs(model, plan["pairs"])
        when "close_loops"
          close_loops(model, plan["edge_pids"])
        when "merge"
          merge_edges(model, plan["edge_pids"])
        when "triangulate"
          triangulate_faces(model, plan["face_pids"])
        when "reverse"
          reverse_faces(model, plan["face_pids"])
        when "clear_materials"
          clear_materials(model, plan["face_pids"])
        when "thicken"
          thicken_faces(model, plan["face_pids"], plan["distance"])
        when "assign_tags"
          assign_tags(model, plan["face_pids"])
        when "make_twofold"
          make_twofold(model, plan["face_pids"])
        when "split_hole"
          split_holed_faces(model, plan["face_pids"])
        end
      end

      def erase_pids(model, pids)
        grouped = Hash.new { |hash, key| hash[key] = [] }
        Support.live_entities(model, pids).each do |entity|
          entities = Support.entities_of(entity)
          grouped[entities] << entity if entities
        end
        grouped.each do |entities, list|
          list.uniq!
          list.reject! { |entity| entity.respond_to?(:valid?) && !entity.valid? }
          entities.erase_entities(list) unless list.empty?
        end
      end

      def weld_pairs(model, pairs)
        Array(pairs).each do |first_pid, second_pid|
          first = Support.live_entity(model, first_pid)
          second = Support.live_entity(model, second_pid)
          next unless first.is_a?(Sketchup::Vertex) && second.is_a?(Sketchup::Vertex)
          next if first.position.distance(second.position) <= 1.0e-6
          entities = Support.entities_of(first)
          next unless entities
          entities.add_line(first.position, second.position)
        rescue StandardError
          next
        end
      end

      def close_loops(model, edge_pids)
        Support.live_entities(model, edge_pids).each do |edge|
          next unless edge.is_a?(Sketchup::Edge)
          next unless edge.valid?
          edge.find_faces
        rescue StandardError
          next
        end
      end

      def merge_edges(model, edge_pids)
        Support.live_entities(model, edge_pids).each do |edge|
          next unless edge.is_a?(Sketchup::Edge) && edge.valid?
          faces = edge.faces
          next unless faces.length == 2
          first, second = faces
          next unless first.normal.samedirection?(second.normal)
          next unless Support.faces_coplanar?(first, second)
          edge.erase!
        rescue StandardError
          next
        end
      end

      def triangulate_faces(model, face_pids)
        Support.live_entities(model, face_pids).each do |face|
          next unless face.is_a?(Sketchup::Face) && face.valid?
          triangulate_face(face)
        end
      end

      def triangulate_face(face)
        mesh = face.mesh
        entities = Support.entities_of(face)
        mesh.polygons.each do |polygon|
          points = polygon.map { |index| mesh.point_at(index.abs) }
          points.each_with_index do |start_point, index|
            end_point = points[(index + 1) % points.length]
            next if start_point.distance(end_point) <= 1.0e-6
            entities.add_line(start_point, end_point)
          rescue StandardError
            next
          end
        end
      end

      def reverse_faces(model, face_pids)
        Support.live_entities(model, face_pids).each do |face|
          next unless face.is_a?(Sketchup::Face) && face.valid?
          face.reverse!
        end
      end

      def clear_materials(model, face_pids)
        Support.live_entities(model, face_pids).each do |face|
          next unless face.is_a?(Sketchup::Face) && face.valid?
          face.material = nil
          face.back_material = nil
        end
      end

      def thicken_faces(model, face_pids, distance)
        length = distance.to_f
        return if length <= 0
        Support.live_entities(model, face_pids).each do |face|
          next unless face.is_a?(Sketchup::Face) && face.valid?
          face.pushpull(length)
        rescue StandardError
          next
        end
      end

      def assign_tags(model, face_pids)
        floor = ensure_layer(model, TAG_FLOOR)
        ceiling = ensure_layer(model, TAG_CEILING)
        walls = ensure_layer(model, TAG_WALLS)
        Support.live_entities(model, face_pids).each do |face|
          next unless face.is_a?(Sketchup::Face) && face.valid?
          next unless Support.untagged?(face.layer, model)
          normal = world_normal(face)
          # Лицевая сторона смотрит из зала наружу: у пола вниз, у потолка вверх.
          face.layer = if normal.z < -0.7
                         floor
                       elsif normal.z > 0.7
                         ceiling
                       else
                         walls
                       end
        end
      end

      def world_normal(face)
        transform = Geom::Transformation.new
        Support.instance_path_for(face).each { |instance| transform *= instance.transformation }
        Support.world_normal(face, transform)
      end

      def make_twofold(model, face_pids)
        Support.live_entities(model, face_pids).each do |face|
          next unless face.is_a?(Sketchup::Face) && face.valid?
          label = if Support.untagged?(face.layer, model)
                    "Грань"
                  else
                    face.layer.name.to_s
                  end
          face.layer = ensure_layer(model, GeomMath.two_fold_name(label))
        end
      end

      def split_holed_faces(model, face_pids)
        Support.live_entities(model, face_pids).each do |face|
          next unless face.is_a?(Sketchup::Face) && face.valid?
          pairs = split_pairs(face)
          entities = Support.entities_of(face)
          next unless entities
          pairs.each do |start_point, end_point|
            entities.add_line(start_point, end_point)
          rescue StandardError
            next
          end
        end
      end

      def split_pairs(face)
        pairs = []
        outer = face.outer_loop.vertices
        face.loops.each do |loop|
          next if loop.outer?
          best = nil
          best_dist = nil
          outer.each do |outer_vertex|
            loop.vertices.each do |inner_vertex|
              distance = outer_vertex.position.distance(inner_vertex.position)
              next if best_dist && distance >= best_dist
              best_dist = distance
              best = [outer_vertex.position, inner_vertex.position]
            end
          end
          pairs << best if best && best_dist && best_dist > 1.0e-6
        end
        pairs
      end

      def ensure_layer(model, name)
        model.layers[name] || model.layers.add(name)
      end
    end
  end
end
