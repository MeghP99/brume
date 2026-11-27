# SpaceMouse

SpaceMouse is a native macOS app for mapping modified mouse clicks and scrolls to window and Space actions. It uses SwiftUI and macOS Liquid Glass and keeps all shortcut settings on the Mac.

## Build and run

Requires macOS 26 or later and the Apple Command Line Tools with a macOS 26+ SDK.

```sh
./build.sh
open .build/SpaceMouse.app
```

Select **Start shortcuts** and grant SpaceMouse access under **System Settings → Privacy & Security → Accessibility**. Return to SpaceMouse and select **Start shortcuts** again. If the earlier SpaceMouse launch agent is loaded, the app asks before temporarily pausing it. Pausing the app's shortcuts or quitting restores the earlier agent. Closing the app window keeps the app available from the menu bar.

Try the shortcuts while another app has focus. The shortcut editor itself passes through normal mouse input.

## Starter shortcuts

| Input | Action |
| --- | --- |
| Control + scroll up | Next Space |
| Control + scroll down | Previous Space |
| Control + left-click | Tile left |
| Control + right-click | Tile right |
| Control + middle-click | Toggle full screen |
| Option + left-click | Tile top |
| Option + right-click | Tile bottom |
| Option + middle-click | Fill the desktop without entering full screen |
| Control + Option + middle-click | Fill the desktop without entering full screen |

The starter set also includes disabled bindings for Mission Control and the two mouse side buttons.

## Customization

Click **Add** or click an existing shortcut to choose its modifier, mouse input, and action. The gear button opens scroll timing and Accessibility settings. Options include Mission Control, App Exposé, center, fill, and restore window size. If a gesture is already assigned, the editor shows a warning and identifies its current action. Choose **Replace shortcut** to remove that binding and save the new one.

Space switching and Mission Control use the corresponding macOS keyboard shortcuts. Window tiling uses the active app’s native Window → Move & Resize commands. Availability depends on the active window and the app's menus. For now the tiling menu lookup supports English menus, and scroll bindings use a physical mouse wheel. Fn can be selected on keyboards that report Fn on mouse events.

The default Control + left-click binding replaces macOS’s context-menu gesture while the shortcuts are active. Use a regular right-click to open context menus.

## Run the shortcut tests

```sh
./test.sh
```

The tests create Core Graphics mouse events and pass them through the same handler the app uses. They cover each starter binding, mouse releases and drags, wheel-burst timing, optional actions, conflict replacement, and the emitted keyboard event flags. The tests run without Accessibility permission and leave your windows and Spaces alone. To check the live behavior, start shortcuts in the app and try the bindings in another app with a normal resizable window.
