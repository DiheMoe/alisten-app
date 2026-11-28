#ifndef RUNNER_WINDOW_STATE_H_
#define RUNNER_WINDOW_STATE_H_

#include <windows.h>

struct WindowState {
  int width = 1280;
  int height = 840;
  bool maximized = false;
};

// Loads the last saved logical window size and maximized flag from
// %APPDATA%\moe.dihe.alisten\window.ini. Falls back to defaults if missing
// or out of range.
WindowState LoadWindowState();

// Whether the window is maximized, or minimized and due to come back maximized.
bool RestoresMaximized(HWND hwnd);

// Persists the window's normal (unmaximized) logical size and whether it is
// currently maximized. When the window is hidden in the tray, pass the
// maximized flag captured before hiding via |hidden_maximized|.
//
// Not to be called from WM_DESTROY: the system has hidden the window by then,
// so a window closed while visible would be saved with |hidden_maximized|.
void SaveWindowState(HWND hwnd, bool hidden_maximized);

#endif  // RUNNER_WINDOW_STATE_H_
