# encoding: UTF-8
# frozen_string_literal: true

require "sketchup.rb"
require "extensions.rb"

module SAC
  module EasePrep
    EXTENSION_NAME = "SAC EASE".freeze
    EXTENSION_VERSION = "0.1.1".freeze

    unless file_loaded?(__FILE__)
      extension = SketchupExtension.new(EXTENSION_NAME, "sac_ease_prep/main")
      extension.description = "Готовит модель SketchUp к импорту в EASE: замкнутый объём, лицевые стороны наружу, отверстия, слои Two-Fold, толщина тел, детализация и теги."
      extension.version = EXTENSION_VERSION
      extension.creator = "SAC"
      extension.copyright = "2026 SAC"
      Sketchup.register_extension(extension, true)
      file_loaded(__FILE__)
    end
  end
end
