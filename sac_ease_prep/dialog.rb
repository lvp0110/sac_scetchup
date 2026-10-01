# encoding: UTF-8
# frozen_string_literal: true

require "json"

module SAC
  module EasePrep
    module Dialog
      module_function

      def open
        if Sketchup.version.to_i < 19
          UI.messagebox("SAC EASE нужен SketchUp 2019 или новее.")
          return
        end
        dialog = build
        @dialog = dialog
        dialog.show
      end

      def build
        dialog = UI::HtmlDialog.new(
          dialog_title: "SAC EASE — подготовка модели",
          preferences_key: "sac_ease_prep_dialog",
          scrollable: false,
          resizable: true,
          width: 1080,
          height: 760,
          style: UI::HtmlDialog::STYLE_DIALOG
        )
        dialog.set_file(File.join(File.dirname(__FILE__), "ui", "index.html"))
        dialog.set_on_closed { @dialog = nil }
        dialog.add_action_callback("command") do |_context, raw|
          handle(dialog, raw)
        end
        dialog
      end

      def handle(dialog, raw)
        command = JSON.parse(raw.to_s)
        model = Sketchup.active_model
        case command["action"]
        when "bootstrap"
          settings = Settings.load
          push(dialog, "bootstrap", { "settings" => settings.to_h, "categories" => CATEGORIES, "version" => VERSION })
        when "check"
          run_check(dialog, model, command["settings"])
        when "fix"
          return unless @result
          Fixes.apply_issue(model, @result, command["id"])
          run_check(dialog, model, nil)
        when "fix_safe"
          settings = current_settings(command["settings"])
          Fixes.apply_safe(model, settings)
          run_check(dialog, model, settings.to_h)
        when "focus"
          if @result
            Fixes.focus(model, @result, command["id"])
            Highlight.apply(model, highlight_pids(command["id"]))
          end
        when "tags"
          Fixes.create_tags(model)
          push(dialog, "status", { "text" => "Набор тегов создан: Стены, Пол, Потолок, Окна, Двери, Зрители, Сцена.", "level" => "ok" })
        when "purge"
          Fixes.purge(model)
          run_check(dialog, model, nil)
        when "export"
          export_model(dialog, model, command["settings"])
        else
          push(dialog, "status", { "text" => "Неизвестная команда.", "level" => "error" })
        end
      rescue StandardError => e
        push(dialog, "status", { "text" => "#{e.class}: #{e.message}", "level" => "error" })
        puts "SAC EASE: #{e.class}: #{e.message}"
        puts e.backtrace.first(12).join("\n")
      end

      def run_check(dialog, model, raw_settings)
        settings = current_settings(raw_settings)
        settings.save
        Sketchup.status_text = "SAC EASE: проверка модели..."
        @result = Analyzer.analyze(model, settings)
        Highlight.apply(model, @result.error_pids)
        Sketchup.status_text = ""
        push(dialog, "report", { "report" => @result.data, "settings" => settings.to_h })
      end

      def export_model(dialog, model, raw_settings)
        settings = current_settings(raw_settings)
        result = Exporter.export(model, settings)
        if result["cancelled"]
          push(dialog, "status", { "text" => "Экспорт отменён.", "level" => "info" })
        elsif result["ok"]
          push(dialog, "status", { "text" => "Файл #{result["format"]} записан: #{result["path"]}", "level" => "ok" })
        else
          push(dialog, "status", { "text" => result["message"], "level" => "error" })
        end
      end

      def highlight_pids(issue_id)
        base = @result ? @result.error_pids : []
        issue = @result.data["issues"].find { |item| item["id"] == issue_id }
        extra = issue ? Array(issue["focus_pids"]) : []
        plan = @result.plans[issue_id]
        extra = plan["face_pids"] || plan["edge_pids"] || plan["pids"] || extra if plan
        (base + Array(extra)).uniq
      end

      def current_settings(raw)
        settings = raw.is_a?(Hash) ? Settings.from_hash(raw) : (@settings || Settings.load)
        @settings = settings
        settings
      end

      def push(dialog, type, payload)
        return unless dialog
        json = JSON.generate({ "type" => type }.merge(payload)).gsub("<", "\\u003c")
        dialog.execute_script("window.SAC && window.SAC.receive(#{json})")
      end
    end
  end
end
