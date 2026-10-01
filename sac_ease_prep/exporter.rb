# encoding: UTF-8
# frozen_string_literal: true

module SAC
  module EasePrep
    module Exporter
      module_function

      def export(model, settings)
        extension = settings.ease4? ? ".dxf" : ".dwg"
        version_label = settings.ease4? ? "EASE 4" : "EASE 5"
        filename = "acoustic_model#{extension}"
        path = UI.savepanel("Экспорт для #{version_label}", "", filename)
        return { "ok" => false, "cancelled" => true } if path.nil? || path.empty?
        path = "#{path}#{extension}" unless path.downcase.end_with?(extension)
        options = {
          show_summary: false,
          acad_version: "acad_2013",
          faces_flag: true,
          construction_geometry: false,
          dimensions: false,
          text: false,
          edges: false,
          materials: false
        }
        ok = model.export(path, options)
        if ok
          { "ok" => true, "path" => path, "format" => extension.sub(".", "").upcase }
        else
          {
            "ok" => false,
            "message" => "SketchUp не записал файл. Экспорт DWG и DXF есть в SketchUp Pro."
          }
        end
      end
    end
  end
end
