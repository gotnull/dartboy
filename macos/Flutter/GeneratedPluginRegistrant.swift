//
//  Generated file. Do not edit.
//

import FlutterMacOS
import Foundation

import desktop_window
import gamepads_darwin
import screen_retriever
import window_manager

func RegisterGeneratedPlugins(registry: FlutterPluginRegistry) {
  DesktopWindowPlugin.register(with: registry.registrar(forPlugin: "DesktopWindowPlugin"))
  GamepadsDarwinPlugin.register(with: registry.registrar(forPlugin: "GamepadsDarwinPlugin"))
  ScreenRetrieverPlugin.register(with: registry.registrar(forPlugin: "ScreenRetrieverPlugin"))
  WindowManagerPlugin.register(with: registry.registrar(forPlugin: "WindowManagerPlugin"))
}
