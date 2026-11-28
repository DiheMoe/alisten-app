#ifndef RUNNER_TRAY_ICON_H_
#define RUNNER_TRAY_ICON_H_

#include <windows.h>

// Thin Win32 wrapper for the application's notification area (system tray) icon
// and right-click context menu.
class TrayIcon {
 public:
  static constexpr UINT kCallbackMessage = WM_APP + 1;
  static constexpr UINT kMenuOpenId = 1001;
  static constexpr UINT kMenuExitId = 1002;

  TrayIcon() = default;
  ~TrayIcon();

  TrayIcon(const TrayIcon&) = delete;
  TrayIcon& operator=(const TrayIcon&) = delete;

  bool Create(HWND hwnd);
  void Destroy();
  bool Recreate();
  bool IsCreated() const { return created_; }

  UINT taskbar_created_message() const { return taskbar_created_message_; }

  void ShowContextMenu();

 private:
  bool AddIcon();
  void RemoveIcon();

  HWND hwnd_ = nullptr;
  HICON icon_ = nullptr;
  UINT taskbar_created_message_ = 0;
  bool created_ = false;
};

#endif  // RUNNER_TRAY_ICON_H_
