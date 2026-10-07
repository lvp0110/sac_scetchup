# encoding: UTF-8
# frozen_string_literal: true

module SAC
  module EasePrep
    class Result
      attr_reader :data, :plans, :error_pids

      def initialize(data, plans, error_pids)
        @data = data
        @plans = plans
        @error_pids = error_pids
      end
    end

    class Analyzer
      def self.analyze(model, settings)
        new(model, settings).analyze
      end

      def initialize(model, settings)
        @model = model
        @settings = settings
        @issues = []
        @plans = {}
        @error_pids = []
        @seq = 0
      end

      def analyze
        occurrences = Scanner.collect(@model, @settings)
        if @settings.scope == "selection" && occurrences.empty?
          return finish(blocked: "Ничего не выделено. Выделите зал или переключите область на всю модель.")
        end

        containers = build_containers(occurrences)
        shells = containers.flat_map { |container| container[:shells] }
        assign_roles(shells)
        stats = build_stats(occurrences, containers, shells)

        check_containers(containers)
        check_watertight(shells)
        check_group_gaps(containers)
        check_holes(containers)
        check_orientation(shells)
        check_two_fold(shells)
        check_two_fold_names(containers)
        check_thickness(shells)
        check_detail(occurrences, shells)
        check_materials(containers)
        check_annotations(occurrences)

        finish(stats: stats, shells: shell_rows(shells), tags: tag_rows(containers))
      end

      private

      def build_containers(occurrences)
        grouped = {}
        occurrences.each do |occurrence|
          key = occurrence.entities.object_id
          grouped[key] ||= { occurrence: occurrence, copies: [] }
          grouped[key][:copies] << occurrence
        end
        grouped.map do |_key, entry|
          occurrence = entry[:occurrence]
          faces = occurrence.entities.grep(Sketchup::Face).select(&:valid?)
          edges = occurrence.entities.grep(Sketchup::Edge).select(&:valid?)
          shells = shells_for(faces, occurrence, entry[:copies])
          {
            occurrence: occurrence,
            copies: entry[:copies],
            faces: faces,
            edges: edges,
            shells: shells,
            locked: entry[:copies].any?(&:locked)
          }
        end
      end

      def shells_for(faces, occurrence, copies)
        components(faces).map do |shell_faces|
          gaps, holes = partition_boundary(shell_faces)
          # Отверстие внутри грани — не щель: EASE закрывает его покрытием Coat of.
          closed = gaps.empty? && manifold?(shell_faces)
          open_manifold = !gaps.empty? && manifold?(shell_faces)
          area = shell_faces.inject(0.0) { |sum, face| sum + face.area(occurrence.transform).to_f }
          {
            faces: shell_faces,
            boundary: gaps,
            holes: holes,
            closed: closed,
            open_manifold: open_manifold,
            nonmanifold: !manifold?(shell_faces),
            area: area,
            occurrence: occurrence,
            copies: copies,
            role: :other,
            volume: nil
          }
        end
      end

      def components(faces)
        return [] if faces.empty?
        index = {}
        faces.each { |face| index[face.persistent_id] = face }
        neighbors = Hash.new { |hash, key| hash[key] = [] }
        faces.each do |face|
          face.edges.each do |edge|
            edge.faces.each do |other|
              next if other == face
              next unless index[other.persistent_id]
              neighbors[face.persistent_id] << other
            end
          end
        end
        visited = {}
        shells = []
        faces.each do |face|
          next if visited[face.persistent_id]
          stack = [face]
          shell = []
          until stack.empty?
            current = stack.pop
            next if visited[current.persistent_id]
            visited[current.persistent_id] = true
            shell << current
            neighbors[current.persistent_id].each do |other|
              stack << other unless visited[other.persistent_id]
            end
          end
          shells << shell
        end
        shells
      end

      def partition_boundary(faces)
        counts = Hash.new(0)
        edges = {}
        inner = {}
        faces.each do |face|
          face.edges.each do |edge|
            counts[edge.persistent_id] += 1
            edges[edge.persistent_id] = edge
          end
          face.loops.each do |loop|
            next if loop.outer?
            loop.edges.each { |edge| inner[edge.persistent_id] = true }
          end
        end
        gaps = []
        holes = []
        counts.each do |pid, count|
          next unless count == 1
          if inner[pid]
            holes << edges[pid]
          else
            gaps << edges[pid]
          end
        end
        [gaps, holes]
      end

      def manifold?(faces)
        counts = Hash.new(0)
        faces.each { |face| face.edges.each { |edge| counts[edge.persistent_id] += 1 } }
        counts.values.all? { |count| count <= 2 }
      end

      def assign_roles(shells)
        closed = shells.select { |shell| shell[:closed] }
        if closed.any?
          room = closed.max_by { |shell| shell_volume(shell).abs }
          room[:role] = :room
          room[:volume] = shell_volume(room)
          closed.each { |shell| shell[:volume] = shell_volume(shell) unless shell.equal?(room) }
        else
          open = shells.select { |shell| shell[:open_manifold] || shell[:boundary].any? }
          room = open.max_by { |shell| shell[:area] }
          room[:role] = :room if room
        end
        shells.each do |shell|
          shell[:volume] = shell_volume(shell) if shell[:closed] && shell[:volume].nil?
        end
      end

      def shell_volume(shell)
        volume_with_parity(shell[:faces], shell[:occurrence].transform, Hash.new(0))
      end

      def build_stats(occurrences, containers, shells)
        unique_faces = containers.inject(0) { |sum, container| sum + container[:faces].length }
        copy_faces = occurrences.inject(0) { |sum, item| sum + item.entities.grep(Sketchup::Face).length }
        room = shells.find { |shell| shell[:role] == :room && shell[:closed] }
        {
          "faces" => unique_faces,
          "face_copies" => copy_faces,
          "containers" => containers.count { |container| container[:faces].any? },
          "closed" => !room.nil?,
          "room_volume_m3" => room ? GeomMath.cu_inches_to_m3(room[:volume]) : nil,
          "ease_version" => @settings.ease_version
        }
      end

      def check_containers(containers)
        with_faces = containers.count { |container| container[:faces].any? }
        return if with_faces <= 1
        add_issue(
          "watertight",
          "warning",
          "Геометрия разрезана на группы",
          "#{with_faces} отдельных объектов с гранями. Общая оболочка зала не склеивается через границы групп. Для одного помещения держите наружные стены в одной группе.",
          count: with_faces
        )
      end

      def check_watertight(shells)
        if shells.empty?
          add_issue("watertight", "error", "В модели нет граней", "Импортировать в EASE нечего.")
          return
        end
        shells.each do |shell|
          if shell[:nonmanifold]
            edges = nonmanifold_edges(shell[:faces])
            add_issue(
              "watertight",
              "error",
              "Неманифолд: к ребру сходится больше двух граней",
              "#{shell_title(shell)}: #{edges.length} рёбер с тремя и более гранями. EASE не сможет однозначно посчитать отражение. Разведите оболочки.",
              count: edges.length,
              focus: edges
            )
          end
          next unless shell[:role] == :room
          if shell[:closed]
            volume = GeomMath.cu_inches_to_m3(shell[:volume].abs)
            next if volume > 0.001
            add_issue(
              "watertight",
              "error",
              "Замкнутый объём почти нулевой",
              "#{shell_title(shell)} формально закрыт, но объём #{format('%.3f', volume)} м³. Проверьте, не схлопнута ли оболочка."
            )
            next
          end
          report_boundary(shell)
        end
      end

      def report_boundary(shell)
        clusters = edge_clusters(shell[:boundary])
        length = shell[:boundary].inject(0.0) { |sum, edge| sum + world_edge_length(edge, shell[:occurrence].transform) }
        add_issue(
          "watertight",
          "error",
          "Объём зала не замкнут",
          "#{shell_title(shell)}: #{clusters.length} разрывов, длина открытого контура #{Support.format_m(length)}. Лучи через эти рёбра уйдут в бесконечность, Room Volume не посчитается.",
          count: shell[:boundary].length,
          focus: shell[:boundary]
        )
        clusters.each do |cluster|
          kind = cluster_kind(cluster)
          if kind == :planar_loop
            add_issue(
              "watertight",
              "warning",
              "Плоский проём можно закрыть гранью",
              "Замкнутый плоский контур из #{cluster.length} рёбер. Окно закройте гранью на слое «Материал $ Материал». Дверь — грань самой оболочки, без символа $.",
              count: cluster.length,
              focus: cluster,
              fix: "close_loops",
              plan: { "edge_pids" => pids(cluster) }
            )
          elsif kind == :chain
            add_issue(
              "watertight",
              "warning",
              "Щель не лежит в одной плоскости",
              "Открытая цепочка из #{cluster.length} рёбер. Её нельзя закрыть одной гранью — сомкните вершины или достройте угол.",
              count: cluster.length,
              focus: cluster
            )
          end
        end
        report_welds(shell)
      end

      def report_welds(shell)
        vertices = {}
        shell[:boundary].each do |edge|
          [edge.start, edge.end].each { |vertex| vertices[vertex.persistent_id] = vertex }
        end
        points = []
        ids = []
        transform = shell[:occurrence].transform
        vertices.each_value do |vertex|
          ids << vertex.persistent_id
          points << Support.point_array(vertex.position.transform(transform))
        end
        pairs = GeomMath.proximity_pairs(points, @settings.weld_gap.to_f)
        return if pairs.empty?
        add_issue(
          "watertight",
          "warning",
          "Вершины границы почти совпадают, но не сварены",
          "#{pairs.length} пар ближе #{@settings.weld_mm} мм. Это типичная щель после раздельного моделирования стен.",
          count: pairs.length,
          focus: shell[:boundary].first(40),
          fix: "weld",
          plan: {
            "entities_token" => shell[:occurrence].entities.object_id,
            "pairs" => pairs.map { |i, j, _dist| [ids[i], ids[j]] }
          }
        )
        edge_pids
      end

      def check_group_gaps(containers)
        points = []
        containers.each do |container|
          container[:shells].each do |shell|
            next if shell[:boundary].empty?
            shell[:boundary].each do |edge|
              [edge.start, edge.end].each do |vertex|
                world = vertex.position.transform(container[:occurrence].transform)
                points << {
                  point: Support.point_array(world),
                  token: container[:occurrence].entities.object_id,
                  edge: edge
                }
              end
            end
          end
        end
        return if points.length < 2
        pairs = GeomMath.proximity_pairs(points.map { |item| item[:point] }, @settings.weld_gap.to_f)
        cross = pairs.select { |i, j, _dist| points[i][:token] != points[j][:token] }
        return if cross.empty?
        edges = cross.flat_map { |i, j, _dist| [points[i][:edge], points[j][:edge]] }.uniq
        add_issue(
          "watertight",
          "error",
          "Щель между разными группами",
          "#{cross.length} пар вершин почти совпадают, но лежат в разных группах. Плагин не сваривает их автоматически: объедините оболочку в одну группу.",
          count: cross.length,
          focus: edges
        )
      end

      def check_holes(containers)
        containers.each do |container|
          passage = []
          simple = []
          concave = []
          transform = container[:occurrence].transform
          container[:faces].each do |face|
            if face.loops.any? { |loop| !loop.outer? }
              if passage_face?(face, transform)
                passage << face
              else
                simple << face
              end
            elsif !convex_face?(face)
              concave << face
            end
          end
          report_passage(container, passage)
          report_simple_holes(container, simple)
          report_caps(container)
          if concave.any?
            issue_fix = @settings.triangulate_nonconvex ? "triangulate" : nil
            add_issue(
              "holes",
              "warning",
              "Невыпуклые грани",
              "#{container[:occurrence].label}: #{concave.length} граней невыпуклые. EASE устойчивее на простых выпуклых многоугольниках.",
              count: concave.length,
              focus: concave,
              fix: issue_fix,
              plan: issue_fix ? { "face_pids" => pids(concave) } : nil
            )
          end
          report_curves(container)
          report_smooth_patches(container)
          report_coplanar(container)
        end
      end

      def report_passage(container, faces)
        return if faces.empty?
        blocked = container[:locked]
        add_issue(
          "holes",
          "warning",
          "Отверстие ведёт в соседнюю геометрию",
          "#{container[:occurrence].label}: #{faces.length} граней с внутренним контуром, за которым есть поверхности с обеих сторон. Импорт EASE 4 закроет дырку, и соседняя комната не войдёт в объём зала — разрежьте грань минимум на две части. Колонну и закрытую нишу можно не резать: импорт сделает покрытие Coat of.",
          count: faces.length,
          focus: faces,
          fix: blocked ? nil : "split_hole",
          plan: blocked ? nil : { "face_pids" => pids(faces) }
        )
      end

      def report_simple_holes(container, faces)
        return if faces.empty?
        if @settings.ease4?
          add_issue(
            "holes",
            "warning",
            "Внутренний контур грани",
            "#{container[:occurrence].label}: #{faces.length} граней с отверстием. EASE 4 убирает контур у основной грани и строит меньшую грань с обратной ориентацией и флагом Coat of. Так оставляют колонну и нишу. Окно закройте отдельной гранью на слое «Материал $ Материал».",
            count: faces.length,
            focus: faces
          )
        else
          add_issue(
            "holes",
            "warning",
            "Отверстия внутри граней",
            "#{container[:occurrence].label}: #{faces.length} граней с внутренним контуром. Их не нужно заливать: импорт оставит покрытие в проёме. Режьте грань только если за отверстием есть соседний объём.",
            count: faces.length,
            focus: faces
          )
        end
      end

      def report_caps(container)
        caps = []
        container[:faces].each do |face|
          next unless face.loops.any? { |loop| !loop.outer? }
          caps.concat(cap_faces(face))
        end
        caps.uniq!(&:persistent_id)
        plain = caps.reject { |face| two_fold_face?(face) }
        return if plain.empty?
        add_issue(
          "materials",
          "warning",
          "Грань в проёме без слоя Two-Fold",
          "#{container[:occurrence].label}: #{plain.length} граней закрывают отверстие. Окно положите на слой «Окна $ Окна» — импорт EASE 4 включит Two fold. Дверь оставьте на слое без символа $: она часть наружной оболочки, а не двусторонняя грань.",
          count: plain.length,
          focus: plain
        )
      end

      def cap_faces(face)
        caps = []
        face.loops.each do |loop|
          next if loop.outer?
          loop.edges.each do |edge|
            edge.faces.each do |other|
              next if other == face
              caps << other if Support.faces_coplanar?(face, other)
            end
          end
        end
        caps
      end

      def passage_face?(face, transform)
        normal = Support.world_normal(face, transform)
        limit = passage_limit
        face.loops.each do |loop|
          next if loop.outer?
          origin = hole_origin(loop, transform)
          next unless origin
          forward = ray_hit(origin.offset(normal, 5.mm), normal, limit)
          backward_normal = normal.reverse
          backward = ray_hit(origin.offset(backward_normal, 5.mm), backward_normal, limit)
          return true if forward && backward
        end
        false
      end

      def hole_origin(loop, transform)
        points = loop.vertices.map { |vertex| Support.point_array(vertex.position.transform(transform)) }
        return nil if points.empty?
        Geom::Point3d.new(*GeomMath.centroid(points))
      end

      def passage_limit
        diag = @model.bounds.diagonal.to_f
        diag < 1.mm ? 30.m : diag
      end

      def two_fold_face?(face)
        layer = face.layer
        return false if layer.nil?
        !GeomMath.two_fold_parts(layer.name).nil?
      end

      def report_curves(container)
        curves = {}
        container[:edges].each do |edge|
          curve = edge.curve
          next unless curve
          curves[curve.entityID] = curve
        end
        dense = curves.values.select { |curve| curve.edges.length > @settings.max_curve_segments }
        return if dense.empty?
        edges = dense.flat_map(&:edges)
        add_issue(
          "holes",
          "warning",
          "Кривые разбиты слишком дробно",
          "#{dense.length} дуг длиннее #{@settings.max_curve_segments} сегментов. Купол, свод или арку нужно аппроксимировать меньшим числом плоских граней. Сегменты правятся в Entity Info, автоматически не уменьшаются.",
          count: dense.length,
          focus: edges
        )
      end

      def report_smooth_patches(container)
        faces = container[:faces]
        return if faces.empty?
        index = {}
        faces.each { |face| index[face.persistent_id] = face }
        neighbors = Hash.new { |hash, key| hash[key] = [] }
        faces.each do |face|
          face.edges.each do |edge|
            next unless edge.soft? || edge.smooth?
            edge.faces.each do |other|
              next if other == face || !index[other.persistent_id]
              neighbors[face.persistent_id] << other
            end
          end
        end
        visited = {}
        patches = []
        faces.each do |face|
          next if visited[face.persistent_id]
          stack = [face]
          patch = []
          until stack.empty?
            current = stack.pop
            next if visited[current.persistent_id]
            visited[current.persistent_id] = true
            patch << current
            neighbors[current.persistent_id].each do |other|
              stack << other unless visited[other.persistent_id]
            end
          end
          patches << patch if patch.length > @settings.max_smooth_faces && curved_patch?(patch)
        end
        return if patches.empty?
        sample = patches.flat_map { |patch| patch.first(3) }
        count = patches.inject(0) { |sum, patch| sum + patch.length }
        add_issue(
          "holes",
          "warning",
          "Сглаженные поверхности слишком плотные",
          "#{patches.length} участков, вместе #{count} граней. Это обычно купол или скругление. Оставьте минимум плоских граней, которого хватает на форму.",
          count: count,
          focus: sample
        )
      end

      def report_coplanar(container)
        edges = []
        container[:edges].each do |edge|
          faces = edge.faces
          next unless faces.length == 2
          first, second = faces
          next if first.loops.length > 1 || second.loops.length > 1
          next unless first.normal.samedirection?(second.normal)
          next unless Support.faces_coplanar?(first, second)
          next unless first.layer == second.layer
          next if first.material != second.material
          edges << edge
        end
        return if edges.empty?
        add_issue(
          "holes",
          "warning",
          "Соседние грани лежат в одной плоскости",
          "#{container[:occurrence].label}: #{edges.length} рёбер можно стереть, грани сольются. Для EASE меньше полигонов лучше, если у них один и тот же тег.",
          count: edges.length,
          focus: edges,
          fix: "merge",
          plan: { "edge_pids" => pids(edges) }
        )
      end

      def curved_patch?(faces)
        base = faces.first.normal
        faces.any? { |face| base.angle_between(face.normal) > 5.degrees }
      end

      def check_orientation(shells)
        shells.each do |shell|
          next if shell[:faces].empty? || shell[:nonmanifold]
          room = shell[:role] == :room
          parity = orientation_parity(shell[:faces], shell, room: room)
          next unless parity[:needs_fix]
          reversed = shell[:faces].select { |face| parity[:parity][face.persistent_id] == 1 }
          next if reversed.empty?
          title = if room
                    "Лицевые стороны зала смотрят не наружу"
                  else
                    "Внутреннее тело смотрит гранями внутрь себя"
                  end
          detail = if room
                     "#{shell_title(shell)}: #{reversed.length} граней нужно перевернуть. Снаружи зала должна быть видна светло-серая лицевая сторона. Голубая изнанка снаружи даёт отрицательный объём в Check Data."
                   else
                     "#{shell_title(shell)}: #{reversed.length} граней смотрят внутрь тела. У подиума или колонны лицевая сторона должна смотреть в воздух зала."
                   end
          mirror_states = shell[:copies].map(&:mirrored).uniq
          blocked = shell[:copies].any?(&:locked) || mirror_states.length > 1
          add_issue(
            "orientation",
            "error",
            title,
            detail,
            count: reversed.length,
            focus: reversed,
            fix: blocked ? nil : "reverse",
            plan: blocked ? nil : { "face_pids" => pids(reversed) }
          )
        end
        conflicted = shells.select { |shell| shell[:copies].map(&:mirrored).uniq.length > 1 }
        return if conflicted.empty?
        instances = conflicted.flat_map { |shell| shell[:copies].map { |item| item.path.last } }.compact.uniq
        add_issue(
          "orientation",
          "warning",
          "Есть и обычные, и зеркальные копии одного компонента",
          "Переворот грани в общем определении исправит одну копию и сломает зеркальную. Сделайте копии уникальными (Make Unique) и проверьте их отдельно.",
          count: instances.length,
          focus: instances
        )
      end

      def check_two_fold(shells)
        shells.each do |shell|
          next if shell[:role] == :room
          next if shell[:nonmanifold]
          next unless shell[:open_manifold] || (shell[:boundary].any? && !shell[:closed])
          missing = shell[:faces].reject { |face| two_fold_face?(face) }
          next if missing.empty?
          blocked = shell[:copies].any?(&:locked)
          add_issue(
            "materials",
            "error",
            "Двусторонняя грань без слоя Two-Fold",
            "#{shell_title(shell)}: #{missing.length} граней открыты с обеих сторон. В EASE 4 такой поверхности нужен слой «Лицевой $ Тыльный», например «Экран $ Экран». Импорт сам включит Two fold.",
            count: missing.length,
            focus: missing,
            fix: blocked ? nil : "make_twofold",
            plan: blocked ? nil : { "face_pids" => pids(missing) }
          )
        end
      end

      def check_two_fold_names(containers)
        bad = []
        containers.each do |container|
          container[:faces].each do |face|
            layer = face.layer
            next if layer.nil?
            name = layer.name.to_s
            next unless name.include?("$")
            bad << face if GeomMath.two_fold_parts(name).nil?
          end
        end
        return if bad.empty?
        add_issue(
          "materials",
          "error",
          "Слой Two-Fold назван неполно",
          "Нужен один знак $ и имя материала с каждой стороны: «Окна $ Окна» или «Стена $ Экран». Пустая сторона импорт не примет.",
          count: bad.length,
          focus: bad,
          fix: "make_twofold",
          plan: { "face_pids" => pids(bad) }
        )
      end

      def check_thickness(shells)
        shells.each do |shell|
          next unless shell[:closed]
          next if shell[:role] == :room
          dims = shell_dimensions(shell)
          next if dims.min >= @settings.min_thickness.to_f
          add_issue(
            "thickness",
            "warning",
            "Тело тоньше заданного порога",
            "#{shell_title(shell)}: меньший габарит #{Support.format_m(dims.min)} при пороге #{@settings.min_thickness_mm} мм.",
            count: shell[:faces].length,
            focus: shell[:faces]
          )
        end
      end

      def check_detail(occurrences, shells)
        room_entities = {}
        shells.each do |shell|
          next unless shell[:role] == :room
          room_entities[shell[:occurrence].entities.object_id] = true
        end
        small_faces = []
        short_edges = []
        occurrences.each do |occurrence|
          occurrence.entities.grep(Sketchup::Face).each do |face|
            area = face.area(occurrence.transform).to_f
            small_faces << face if area.positive? && area < @settings.min_area
          end
          occurrence.entities.grep(Sketchup::Edge).each do |edge|
            next if edge.faces.empty?
            length = world_edge_length(edge, occurrence.transform)
            short_edges << edge if length < @settings.min_edge
          end
        end
        small_faces = small_faces.uniq(&:persistent_id)
        short_edges = short_edges.uniq(&:persistent_id)
        if small_faces.any?
          add_issue(
            "detail",
            "warning",
            "Слишком мелкие грани",
            "#{small_faces.length} граней меньше #{@settings.min_area_m2} м². Так выглядят остатки декора. Удаление пробьёт дыру в оболочке, поэтому плагин только показывает их.",
            count: small_faces.length,
            focus: small_faces
          )
        end
        if short_edges.any?
          sample = short_edges.first(80)
          add_issue(
            "detail",
            "warning",
            "Слишком короткие рёбра",
            "#{short_edges.length} рёбер короче #{@settings.min_edge_mm} мм. Часто это переплёт, плинтус или след от скругления.",
            count: short_edges.length,
            focus: sample
          )
        end
        report_objects(occurrences, room_entities)
        report_stray(occurrences)
      end

      def report_objects(occurrences, room_entities)
        flagged = []
        occurrences.each do |occurrence|
          next if occurrence.path.empty?
          instance = occurrence.path.last
          next if flagged.any? { |item| item[:instance] == instance }
          next if room_entities[occurrence.entities.object_id] && occurrence.entities.grep(Sketchup::Face).length > 20 && instance.bounds.diagonal > @settings.small_object * 4
          diag = instance.bounds.diagonal.to_f
          face_count = occurrence.entities.grep(Sketchup::Face).length
          name = occurrence.label
          small = diag < @settings.small_object && face_count.positive?
          busy = face_count >= @settings.detail_face_limit && diag < 2.m
          named = Support.detail_name?(name)
          next unless small || busy || named
          reason = if named
                     "имя похоже на мебель или декор"
                   elsif small
                     "габарит #{Support.format_m(diag)}"
                   else
                     "#{face_count} граней при габарите #{Support.format_m(diag)}"
                   end
          flagged << { instance: instance, reason: reason, faces: face_count }
        end
        return if flagged.empty?
        names = flagged.first(3).map { |item| "#{Scanner.label_for([item[:instance]])} (#{item[:reason]})" }
        add_issue(
          "detail",
          "warning",
          "Похоже на лишнюю детализацию",
          "#{flagged.length} групп или компонентов. Зрительские кресла замените сплошными блоками, декор удалите. Примеры: #{names.join("; ")}.",
          count: flagged.length,
          focus: flagged.map { |item| item[:instance] },
          fix: "erase_objects",
          plan: { "pids" => pids(flagged.map { |item| item[:instance] }) }
        )
      end

      def report_stray(occurrences)
        stray = []
        Scanner.unique(occurrences).each do |occurrence|
          occurrence.entities.grep(Sketchup::Edge).each do |edge|
            stray << edge if edge.faces.empty? && edge.curve.nil?
          end
        end
        # Одинокие рёбра кривых без граней тоже мусор.
        curves = []
        Scanner.unique(occurrences).each do |occurrence|
          occurrence.entities.grep(Sketchup::Edge).each do |edge|
            curve = edge.curve
            next unless curve
            curves << curve if curve.edges.all? { |item| item.faces.empty? }
          end
        end
        stray_edges = (stray + curves.uniq(&:entityID).flat_map(&:edges)).uniq
        return if stray_edges.empty?
        add_issue(
          "detail",
          "warning",
          "Рёбра без граней",
          "#{stray_edges.length} рёбер не принадлежат ни одной грани. В акустическую модель они не входят.",
          count: stray_edges.length,
          focus: stray_edges,
          fix: "erase_stray",
          plan: { "pids" => pids(stray_edges) }
        )
      end

      def check_materials(containers)
        textured = []
        painted = []
        untagged = []
        containers.each do |container|
          container[:faces].each do |face|
            [face.material, face.back_material].compact.each do |material|
              painted << face
              textured << material if material.texture
            end
            untagged << face if Support.untagged?(face.layer, @model)
          end
        end
        painted.uniq!
        textured.uniq!
        if textured.any?
          add_issue(
            "materials",
            "warning",
            "У материалов есть текстуры",
            "Текстуры: #{textured.map(&:display_name).uniq.join(", ")}. EASE они не нужны. Достаточно имени тега.",
            count: textured.length,
            focus: painted,
            fix: "clear_materials",
            plan: { "face_pids" => pids(painted) }
          )
        elsif painted.any?
          add_issue(
            "materials",
            "warning",
            "Граням назначен цвет SketchUp",
            "#{painted.length} граней с материалом. Надёжнее оставить Default и различать поверхности тегами: имя тега EASE читает как акустический материал.",
            count: painted.length,
            focus: painted,
            fix: "clear_materials",
            plan: { "face_pids" => pids(painted) }
          )
        end
        return unless untagged.any?
        add_issue(
          "materials",
          "warning",
          "Грани без акустического тега",
          "#{untagged.length} граней на слое Untagged. Создайте теги вроде Стены, Пол, Потолок, Окна $ Окна, Двери. Автоназначение считает лицевую сторону смотрящей наружу из зала: пол вниз, потолок вверх.",
          count: untagged.length,
          focus: untagged,
          fix: "assign_tags",
          plan: { "face_pids" => pids(untagged) }
        )
      end

      def check_annotations(occurrences)
        hidden_faces = []
        annotations = []
        Scanner.unique(occurrences).each do |occurrence|
          entities = occurrence.entities
          entities.grep(Sketchup::Face).each { |face| hidden_faces << face if face.hidden? }
          [Sketchup::Text, Sketchup::Dimension, Sketchup::Image, Sketchup::ConstructionLine, Sketchup::ConstructionPoint, Sketchup::SectionPlane].each do |klass|
            annotations.concat(entities.grep(klass))
          end
        end
        if hidden_faces.any?
          add_issue(
            "detail",
            "warning",
            "Скрытые грани попадут в экспорт",
            "#{hidden_faces.length} скрытых граней останутся в DWG/DXF. Покажите их и решите, нужны ли они залу.",
            count: hidden_faces.length,
            focus: hidden_faces,
            fix: "erase_hidden",
            plan: { "pids" => pids(hidden_faces) }
          )
        end
        return if annotations.empty?
        add_issue(
          "detail",
          "warning",
          "Аннотации и вспомогательная геометрия",
          "#{annotations.length} размеров, текстов, направляющих или сечений. В экспорт граней они не должны входить. Направляющие и так отключены в настройках экспорта, размеры лучше удалить.",
          count: annotations.length,
          focus: annotations,
          fix: "erase_annotations",
          plan: { "pids" => pids(annotations) }
        )
      end

      def orientation_parity(faces, shell, room:)
        return { parity: {}, needs_fix: false } if faces.empty?
        parity = { faces.first.persistent_id => 0 }
        queue = [faces.first]
        index = {}
        faces.each { |face| index[face.persistent_id] = face }
        visited = { faces.first.persistent_id => true }
        until queue.empty?
          face = queue.shift
          face.edges.each do |edge|
            edge.faces.each do |other|
              next unless index[other.persistent_id]
              next if visited[other.persistent_id]
              consistent = edge.reversed_in?(face) != edge.reversed_in?(other)
              parity[other.persistent_id] = consistent ? parity[face.persistent_id] : 1 - parity[face.persistent_id]
              visited[other.persistent_id] = true
              queue << other
            end
          end
        end
        if shell[:closed]
          volume = volume_with_parity(faces, shell[:occurrence].transform, parity)
          # Положительный объём: лицевые стороны смотрят из оболочки наружу.
          # У зала снаружи видна серая сторона, у внутреннего тела — воздух зала.
          if volume < -1.0e-6
            parity.keys.each { |key| parity[key] = 1 - parity[key] }
          end
        else
          score = ray_score(faces, shell[:occurrence].transform, parity)
          flip = room ? score > 0 : score < 0
          if flip
            parity.keys.each { |key| parity[key] = 1 - parity[key] }
          end
        end
        { parity: parity, needs_fix: parity.values.any? { |value| value == 1 } }
      end

      def volume_with_parity(faces, transform, parity)
        sum = 0.0
        faces.each do |face|
          normal = Support.point_array(Support.world_normal(face, transform))
          mesh = face.mesh
          mesh.polygons.each do |polygon|
            points = polygon.map { |index| Support.point_array(mesh.point_at(index.abs).transform(transform)) }
            next if points.length < 3
            origin = points[0]
            (1...(points.length - 1)).each do |index|
              p0, p1, p2 = GeomMath.orient_triangle(origin, points[index], points[index + 1], normal)
              p1, p2 = p2, p1 if parity[face.persistent_id] == 1
              sum += GeomMath.triple(p0, p1, p2)
            end
          end
          face.loops.each do |loop|
            next if loop.outer?
            next unless naked_hole?(loop)
            points = loop.vertices.map { |vertex| Support.point_array(vertex.position.transform(transform)) }
            GeomMath.loop_cap_triangles(points).each do |p0, p1, p2|
              p1, p2 = p2, p1 if parity[face.persistent_id] == 1
              sum += GeomMath.triple(p0, p1, p2)
            end
          end
        end
        sum / 6.0
      end

      def naked_hole?(loop)
        loop.edges.all? { |edge| edge.faces.length == 1 }
      end

      def ray_score(faces, transform, parity)
        step = [1, (faces.length / 12.0).ceil].max
        score = 0
        max_dist = ray_limit(faces, transform)
        faces.each_with_index do |face, index|
          next unless (index % step).zero?
          normal = Support.world_normal(face, transform)
          normal.reverse! if parity[face.persistent_id] == 1
          origin = Support.face_anchor(face).transform(transform)
          forward = ray_hit(origin.offset(normal, 1.mm), normal, max_dist)
          backward = ray_hit(origin.offset(normal.reverse, 1.mm), normal.reverse, max_dist)
          if forward && !backward
            score += 1
          elsif backward && !forward
            score -= 1
          end
        end
        score
      end

      def ray_hit(origin, direction, max_dist)
        vector = direction.clone
        return nil if vector.length <= 1.0e-9
        vector.normalize!
        hit = @model.raytest([origin, vector], false)
        return nil unless hit
        distance = origin.distance(hit[0])
        return nil if distance > max_dist
        hit
      rescue StandardError
        nil
      end

      def ray_limit(faces, transform)
        box = Geom::BoundingBox.new
        faces.each do |face|
          face.vertices.each { |vertex| box.add(vertex.position.transform(transform)) }
        end
        diag = box.diagonal.to_f
        diag < 1.mm ? 10.m : diag * 2.0
      end

      def shell_dimensions(shell)
        box = Geom::BoundingBox.new
        transform = shell[:occurrence].transform
        shell[:faces].each do |face|
          face.vertices.each { |vertex| box.add(vertex.position.transform(transform)) }
        end
        [box.width.to_f, box.height.to_f, box.depth.to_f]
      end

      def convex_face?(face)
        return false if face.loops.length > 1
        points = face.outer_loop.vertices.map { |vertex| Support.point_array(vertex.position) }
        GeomMath.polygon_convex?(points)
      end

      def nonmanifold_edges(faces)
        counts = Hash.new(0)
        edges = {}
        faces.each do |face|
          face.edges.each do |edge|
            counts[edge.persistent_id] += 1
            edges[edge.persistent_id] = edge
          end
        end
        counts.each_with_object([]) do |(pid, count), list|
          list << edges[pid] if count > 2
        end
      end

      def edge_clusters(edges)
        return [] if edges.empty?
        index = {}
        edges.each { |edge| index[edge.persistent_id] = edge }
        vertex_edges = Hash.new { |hash, key| hash[key] = [] }
        edges.each do |edge|
          vertex_edges[edge.start.persistent_id] << edge
          vertex_edges[edge.end.persistent_id] << edge
        end
        visited = {}
        clusters = []
        edges.each do |edge|
          next if visited[edge.persistent_id]
          stack = [edge]
          cluster = []
          until stack.empty?
            current = stack.pop
            next if visited[current.persistent_id]
            visited[current.persistent_id] = true
            cluster << current
            [current.start, current.end].each do |vertex|
              vertex_edges[vertex.persistent_id].each do |other|
                stack << other unless visited[other.persistent_id]
              end
            end
          end
          clusters << cluster
        end
        clusters
      end

      def cluster_kind(cluster)
        degrees = Hash.new(0)
        points = {}
        cluster.each do |edge|
          [edge.start, edge.end].each do |vertex|
            degrees[vertex.persistent_id] += 1
            points[vertex.persistent_id] = Support.point_array(vertex.position)
          end
        end
        return :chain unless degrees.values.all? { |degree| degree == 2 }
        return :loop unless GeomMath.coplanar?(points.values, 1.mm.to_f)
        :planar_loop
      end

      def world_edge_length(edge, transform)
        edge.start.position.transform(transform).distance(edge.end.position.transform(transform))
      end

      def shell_title(shell)
        label = shell[:occurrence].label
        copies = shell[:copies].length
        copies > 1 ? "#{label} (#{copies} копий)" : label
      end

      def tag_rows(containers)
        rows = Hash.new { |hash, key| hash[key] = { "name" => key, "faces" => 0, "area_m2" => 0.0 } }
        containers.each do |container|
          container[:faces].each do |face|
            name = Support.untagged?(face.layer, @model) ? "Без тега" : Support.layer_label(face.layer)
            rows[name]["faces"] += 1
            rows[name]["area_m2"] += GeomMath.sq_inches_to_m2(face.area.to_f)
          end
        end
        rows.values.sort_by { |row| -row["area_m2"] }
      end

      def shell_rows(shells)
        shells.map do |shell|
          {
            "label" => shell_title(shell),
            "role" => shell[:role].to_s,
            "closed" => shell[:closed],
            "faces" => shell[:faces].length,
            "area_m2" => GeomMath.sq_inches_to_m2(shell[:area]),
            "volume_m3" => shell[:volume] ? GeomMath.cu_inches_to_m3(shell[:volume]) : nil
          }
        end
      end

      def pids(entities)
        entities.map(&:persistent_id)
      end

      def add_issue(category, severity, title, detail, count: nil, focus: nil, fix: nil, plan: nil)
        @seq += 1
        id = "#{category}-#{@seq}"
        focus_list = Array(focus).compact.select { |entity| entity.respond_to?(:persistent_id) }
        @error_pids.concat(focus_list.map(&:persistent_id)) if severity == "error"
        issue = {
          "id" => id,
          "category" => category,
          "severity" => severity,
          "title" => title,
          "detail" => detail,
          "count" => count || focus_list.length,
          "fixable" => !fix.nil?,
          "fix_type" => fix,
          "focus_pids" => focus_list.first(60).map(&:persistent_id)
        }
        @issues << issue
        return unless fix
        @plans[id] = (plan || {}).merge("type" => fix)
      end

      def finish(stats: empty_stats, shells: [], tags: [], blocked: nil)
        errors = @issues.count { |issue| issue["severity"] == "error" }
        warnings = @issues.count { |issue| issue["severity"] == "warning" }
        categories = CATEGORIES.map do |category|
          list = @issues.select { |issue| issue["category"] == category["id"] }
          status = if list.any? { |issue| issue["severity"] == "error" }
                     "error"
                   elsif list.any? { |issue| issue["severity"] == "warning" }
                     "warning"
                   else
                     "ok"
                   end
          category.merge("status" => status, "issues" => list.length)
        end
        data = {
          "version" => VERSION,
          "blocked" => blocked,
          "stats" => stats.merge("errors" => errors, "warnings" => warnings),
          "categories" => categories,
          "issues" => @issues,
          "shells" => shells,
          "tags" => tags
        }
        Result.new(data, @plans, @error_pids.uniq)
      end

      def empty_stats
        {
          "faces" => 0,
          "face_copies" => 0,
          "containers" => 0,
          "closed" => false,
          "room_volume_m3" => nil,
          "ease_version" => @settings.ease_version
        }
      end
    end
  end
end
