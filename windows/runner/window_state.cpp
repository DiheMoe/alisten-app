#include "window_state.h"

#include <flutter_windows.h>
#include <shlobj.h>

#include <cmath>
#include <string>

namespace {

constexpr int kMinWidth = 960;
constexpr int kMinHeight = 600;
constexpr int kMaxSide = 16384;

constexpr wchar_t kAppDirName[] = L"moe.dihe.alisten";
constexpr wchar_t kFileName[] = L"window.ini";
constexpr wchar_t kSection[] = L"window";

std::wstring GetWindowStateDir() {
  PWSTR app_data = nullptr;
  const HRESULT hr = ::SHGetKnownFolderPath(
      FOLDERID_RoamingAppData, KF_FLAG_CREATE, nullptr, &app_data);
  if (FAILED(hr) || app_data == nullptr) {
    if (app_data != nullptr) {
      ::CoTaskMemFree(app_data);
    }
    return L"";
  }
  std::wstring dir(app_data);
  ::CoTaskMemFree(app_data);
  dir.push_back(L'\\');
  dir.append(kAppDirName);
  return dir;
}

std::wstring GetWindowStatePath() {
  const std::wstring dir = GetWindowStateDir();
  if (dir.empty()) {
    return L"";
  }
  return dir + L"\\" + kFileName;
}

bool IsValidSide(int value, int min_value) {
  return value >= min_value && value <= kMaxSide;
}

}  // namespace

WindowState LoadWindowState() {
  WindowState state;
  const std::wstring path = GetWindowStatePath();
  if (path.empty()) {
    return state;
  }

  const int width = static_cast<int>(
      ::GetPrivateProfileIntW(kSection, L"width", 0, path.c_str()));
  const int height = static_cast<int>(
      ::GetPrivateProfileIntW(kSection, L"height", 0, path.c_str()));
  if (IsValidSide(width, kMinWidth) && IsValidSide(height, kMinHeight)) {
    state.width = width;
    state.height = height;
  }

  const UINT maximized =
      ::GetPrivateProfileIntW(kSection, L"maximized", 0, path.c_str());
  state.maximized = maximized != 0;
  return state;
}

bool RestoresMaximized(HWND hwnd) {
  WINDOWPLACEMENT placement{};
  placement.length = sizeof(placement);
  if (!::GetWindowPlacement(hwnd, &placement)) {
    return false;
  }
  return placement.showCmd == SW_SHOWMAXIMIZED ||
         (placement.showCmd == SW_SHOWMINIMIZED &&
          (placement.flags & WPF_RESTORETOMAXIMIZED) != 0);
}

void SaveWindowState(HWND hwnd, bool hidden_maximized) {
  if (hwnd == nullptr) {
    return;
  }

  WINDOWPLACEMENT placement{};
  placement.length = sizeof(placement);
  if (!::GetWindowPlacement(hwnd, &placement)) {
    return;
  }

  const std::wstring dir = GetWindowStateDir();
  if (dir.empty()) {
    return;
  }
  ::CreateDirectoryW(dir.c_str(), nullptr);
  const std::wstring path = dir + L"\\" + kFileName;

  const bool maximized =
      ::IsWindowVisible(hwnd) ? RestoresMaximized(hwnd) : hidden_maximized;
  ::WritePrivateProfileStringW(kSection, L"maximized",
                               maximized ? L"1" : L"0", path.c_str());

  const RECT& normal = placement.rcNormalPosition;
  HMONITOR monitor =
      ::MonitorFromRect(&normal, MONITOR_DEFAULTTONEAREST);
  if (monitor == nullptr) {
    monitor = ::MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
  }
  const UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  const double scale = dpi > 0 ? static_cast<double>(dpi) / 96.0 : 1.0;

  const int logical_width = static_cast<int>(
      std::lround(static_cast<double>(normal.right - normal.left) / scale));
  const int logical_height = static_cast<int>(
      std::lround(static_cast<double>(normal.bottom - normal.top) / scale));
  // A work area smaller than the minimum size shrinks the window below it.
  // Such a size is not worth restoring, but the maximized flag above still is.
  if (!IsValidSide(logical_width, kMinWidth) ||
      !IsValidSide(logical_height, kMinHeight)) {
    return;
  }

  const std::wstring width_str = std::to_wstring(logical_width);
  const std::wstring height_str = std::to_wstring(logical_height);
  ::WritePrivateProfileStringW(kSection, L"width", width_str.c_str(),
                               path.c_str());
  ::WritePrivateProfileStringW(kSection, L"height", height_str.c_str(),
                               path.c_str());
}
