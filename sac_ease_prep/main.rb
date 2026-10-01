# encoding: UTF-8
# frozen_string_literal: true

require "sketchup.rb"

module SAC
  module EasePrep
    ROOT = File.dirname(__FILE__).tr("\\", "/").freeze

    %w[version geom_math settings support scanner analyzer fixes exporter highlight dialog].each do |name|
      Sketchup.require "#{ROOT}/#{name}"
    end

    unless file_loaded?(__FILE__)
      command = UI::Command.new("Подготовка для EASE") { Dialog.open }
      command.tooltip = "SAC EASE — подготовка модели"
      command.status_bar_text = "Замкнутость, отверстия, ориентация граней, толщина, детализация, теги."
      command.menu_text = "Подготовка для EASE"
      command.small_icon = "#{ROOT}/icons/sac_24.png"
      command.large_icon = "#{ROOT}/icons/sac_32.png"

      menu = UI.menu("Extensions")
      submenu = menu.add_submenu("SAC EASE")
      submenu.add_item(command)

      toolbar = UI::Toolbar.new("SAC EASE")
      toolbar.add_item(command)
      if toolbar.get_last_state == TB_NEVER_SHOWN
        toolbar.show
      else
        toolbar.restore
      end

      file_loaded(__FILE__)
    end
  end
end
