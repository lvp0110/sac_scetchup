# encoding: UTF-8
# frozen_string_literal: true

module SAC
  module EasePrep
    # Обход модели. Топология живёт внутри одного Entities (группа или компонент),
    # поэтому каждая такая коллекция — отдельный контейнер.
    module Scanner
      Occurrence = Struct.new(:entities, :transform, :path, :label, :locked, :mirrored)

      module_function

      def collect(model, settings)
        occurrences = []
        roots(model, settings).each do |root|
          case root
          when :model
            walk(model.entities, Geom::Transformation.new, [], occurrences)
          when :active
            path = model.active_path ? model.active_path.to_a : []
            transform = Geom::Transformation.new
            path.each { |instance| transform *= instance.transformation }
            walk(model.active_entities, transform, path, occurrences)
          else
            walk(root.definition.entities, root.transformation, [root], occurrences)
          end
        end
        occurrences
      end

      def roots(model, settings)
        return [:model] unless settings.scope == "selection"
        selection = model.selection.to_a
        groups = selection.grep(Sketchup::Group) + selection.grep(Sketchup::ComponentInstance)
        return groups unless groups.empty?
        return [:active] if selection.any?
        []
      end

      def walk(entities, transform, path, occurrences)
        occurrences << Occurrence.new(
          entities,
          transform,
          path,
          label_for(path),
          Support.locked_path?(path),
          Support.mirrored?(transform)
        )
        definitions = path.map { |instance| instance.definition }
        entities.grep(Sketchup::Group).each do |group|
          next unless group.valid?
          walk(group.entities, transform * group.transformation, path + [group], occurrences)
        end
        entities.grep(Sketchup::ComponentInstance).each do |instance|
          next unless instance.valid?
          definition = instance.definition
          next if definitions.include?(definition)
          walk(definition.entities, transform * instance.transformation, path + [instance], occurrences)
        end
      end

      def label_for(path)
        return "Корень модели" if path.empty?
        instance = path.last
        if instance.is_a?(Sketchup::Group)
          name = instance.name.to_s
          name = instance.definition.name.to_s if name.empty?
          name.empty? ? "Группа" : name
        else
          name = instance.definition.name.to_s
          name.empty? ? "Компонент" : name
        end
      end

      def unique(occurrences)
        seen = {}
        occurrences.each_with_object([]) do |occurrence, list|
          key = occurrence.entities.object_id
          next if seen[key]
          seen[key] = true
          list << occurrence
        end
      end
    end
  end
end
