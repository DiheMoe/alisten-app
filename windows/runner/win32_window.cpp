#include "win32_window.h"

#include <commctrl.h>
#include <dwmapi.h>
#include <flutter_windows.h>
#include <shellapi.h>
#include <windowsx.h>

#include "resource.h"

namespace {

/// Window attribute that enables dark mode window decorations.
///
/// Redefined in case the developer's machine has a Windows SDK older than
/// version 10.0.22000.0.
/// See: https://docs.microsoft.com/windows/win32/api/dwmapi/ne-dwmapi-dwmwindowattribute
#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
#define DWMWA_USE_IMMERSIVE_DARK_MODE 20
#endif

constexpr const wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";

/// Registry key for app theme preference.
///
/// A value of 0 indicates apps should use dark mode. A non-zero or missing
/// value indicates apps should use light mode.
constexpr const wchar_t kGetPreferredBrightnessRegKey[] =
  L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize";
constexpr const wchar_t kGetPreferredBrightnessRegValue[] = L"AppsUseLightTheme";

// The number of Win32Window objects that currently exist.
static int g_active_window_count = 0;

using EnableNonClientDpiScaling = BOOL __stdcall(HWND hwnd);
using GetSystemMetricsForDpiFn = int __stdcall(int index, UINT dpi);

constexpr UINT_PTR kChildHitTestSubclassId = 1;
constexpr int kTopResizeBorderDip = 5;
constexpr int kCornerResizeWidthDip = 8;

// Scale helper to convert logical scaler values to physical using passed in
// scale factor
int Scale(int source, double scale_factor) {
  return static_cast<int>(source * scale_factor);
}

UINT GetWindowDpi(HWND hwnd) {
  HMONITOR monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
  UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  return dpi == 0 ? 96 : dpi;
}

int GetSystemMetricsForDpiSafe(int index, UINT dpi) {
  static auto* fn = reinterpret_cast<GetSystemMetricsForDpiFn*>(
      GetProcAddress(GetModuleHandleW(L"user32.dll"), "GetSystemMetricsForDpi"));
  if (fn != nullptr) {
    return fn(index, dpi);
  }
  return GetSystemMetrics(index);
}

// Only the top resize edge is claimed at Win32 hit-test time so unified top-bar
// buttons remain clickable; empty top-bar dragging is initiated from Flutter.
LRESULT HitTestCustomChrome(HWND hwnd, POINT screen_pt) {
  if (::IsZoomed(hwnd) != 0) {
    return HTCLIENT;
  }
  POINT pt = screen_pt;
  ::ScreenToClient(hwnd, &pt);
  RECT client{};
  ::GetClientRect(hwnd, &client);

  const double scale = GetWindowDpi(hwnd) / 96.0;
  const int top_resize = Scale(kTopResizeBorderDip, scale);
  const int corner_width = Scale(kCornerResizeWidthDip, scale);

  if (pt.y >= 0 && pt.y < top_resize) {
    if (pt.x < corner_width) return HTTOPLEFT;
    if (pt.x >= client.right - corner_width) return HTTOPRIGHT;
    return HTTOP;
  }
  return HTCLIENT;
}

// Windows treats a window whose client area covers a whole monitor as full
// screen and stops an auto-hide taskbar from sliding in over it. A maximized
// window without a system title bar is exactly that, so one pixel is given up
// on the edge the taskbar hides at.
void LeaveRoomForAutoHideTaskbar(HWND hwnd, RECT* client) {
  MONITORINFO monitor_info{};
  monitor_info.cbSize = sizeof(monitor_info);
  if (!GetMonitorInfo(MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST),
                      &monitor_info)) {
    return;
  }
  const auto hides_at = [&monitor_info](UINT edge) {
    APPBARDATA data{};
    data.cbSize = sizeof(data);
    data.uEdge = edge;
    data.rc = monitor_info.rcMonitor;
    return ::SHAppBarMessage(ABM_GETAUTOHIDEBAREX, &data) != 0;
  };
  if (hides_at(ABE_BOTTOM)) {
    client->bottom -= 1;
  } else if (hides_at(ABE_TOP)) {
    client->top += 1;
  } else if (hides_at(ABE_LEFT)) {
    client->left += 1;
  } else if (hides_at(ABE_RIGHT)) {
    client->right -= 1;
  }
}

LRESULT CALLBACK ChildHitTestSubclassProc(HWND hwnd, UINT message,
                                          WPARAM wparam, LPARAM lparam,
                                          UINT_PTR subclass_id,
                                          DWORD_PTR /*ref_data*/) {
  if (message == WM_NCHITTEST) {
    HWND parent = ::GetParent(hwnd);
    if (parent != nullptr) {
      POINT pt = {GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
      if (HitTestCustomChrome(parent, pt) != HTCLIENT) {
        return HTTRANSPARENT;
      }
    }
  } else if (message == WM_NCDESTROY) {
    ::RemoveWindowSubclass(hwnd, ChildHitTestSubclassProc, subclass_id);
  }
  return ::DefSubclassProc(hwnd, message, wparam, lparam);
}

// Dynamically loads the |EnableNonClientDpiScaling| from the User32 module.
// This API is only needed for PerMonitor V1 awareness mode.
void EnableFullDpiSupportIfAvailable(HWND hwnd) {
  HMODULE user32_module = LoadLibraryA("User32.dll");
  if (!user32_module) {
    return;
  }
  auto enable_non_client_dpi_scaling =
      reinterpret_cast<EnableNonClientDpiScaling*>(
          GetProcAddress(user32_module, "EnableNonClientDpiScaling"));
  if (enable_non_client_dpi_scaling != nullptr) {
    enable_non_client_dpi_scaling(hwnd);
  }
  FreeLibrary(user32_module);
}

}  // namespace

// Manages the Win32Window's window class registration.
class WindowClassRegistrar {
 public:
  ~WindowClassRegistrar() = default;

  // Returns the singleton registrar instance.
  static WindowClassRegistrar* GetInstance() {
    if (!instance_) {
      instance_ = new WindowClassRegistrar();
    }
    return instance_;
  }

  // Returns the name of the window class, registering the class if it hasn't
  // previously been registered.
  const wchar_t* GetWindowClass();

  // Unregisters the window class. Should only be called if there are no
  // instances of the window.
  void UnregisterWindowClass();

 private:
  WindowClassRegistrar() = default;

  static WindowClassRegistrar* instance_;

  bool class_registered_ = false;
};

WindowClassRegistrar* WindowClassRegistrar::instance_ = nullptr;

const wchar_t* WindowClassRegistrar::GetWindowClass() {
  if (!class_registered_) {
    WNDCLASS window_class{};
    window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
    window_class.lpszClassName = kWindowClassName;
    window_class.style = CS_HREDRAW | CS_VREDRAW;
    window_class.cbClsExtra = 0;
    window_class.cbWndExtra = 0;
    window_class.hInstance = GetModuleHandle(nullptr);
    window_class.hIcon =
        LoadIcon(window_class.hInstance, MAKEINTRESOURCE(IDI_APP_ICON));
    window_class.hbrBackground = 0;
    window_class.lpszMenuName = nullptr;
    window_class.lpfnWndProc = Win32Window::WndProc;
    RegisterClass(&window_class);
    class_registered_ = true;
  }
  return kWindowClassName;
}

void WindowClassRegistrar::UnregisterWindowClass() {
  UnregisterClass(kWindowClassName, nullptr);
  class_registered_ = false;
}

Win32Window::Win32Window() {
  ++g_active_window_count;
}

Win32Window::~Win32Window() {
  --g_active_window_count;
  Destroy();
}

bool Win32Window::Create(const std::wstring& title,
                         const Point& origin,
                         const Size& size) {
  Destroy();

  const wchar_t* window_class =
      WindowClassRegistrar::GetInstance()->GetWindowClass();

  const POINT target_point = {static_cast<LONG>(origin.x),
                              static_cast<LONG>(origin.y)};
  HMONITOR monitor = MonitorFromPoint(target_point, MONITOR_DEFAULTTONEAREST);
  UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  double scale_factor = dpi / 96.0;

  int width = Scale(size.width, scale_factor);
  int height = Scale(size.height, scale_factor);
  int x = Scale(origin.x, scale_factor);
  int y = Scale(origin.y, scale_factor);
  MONITORINFO monitor_info{};
  monitor_info.cbSize = sizeof(monitor_info);
  if (GetMonitorInfo(monitor, &monitor_info)) {
    const RECT& work = monitor_info.rcWork;
    const int max_width = work.right - work.left;
    const int max_height = work.bottom - work.top;
    if (width > max_width) width = max_width;
    if (height > max_height) height = max_height;
    x = work.left + (max_width - width) / 2;
    y = work.top + (max_height - height) / 2;
  }

  HWND window = CreateWindow(
      window_class, title.c_str(), WS_OVERLAPPEDWINDOW,
      x, y, width, height,
      nullptr, nullptr, GetModuleHandle(nullptr), this);

  if (!window) {
    return false;
  }

  UpdateTheme(window);

  // Extending 1px preserves the native DWM shadow and Win11 rounded corners
  // after WM_NCCALCSIZE removes the system title bar.
  constexpr MARGINS kShadowMargins = {0, 0, 1, 0};
  DwmExtendFrameIntoClientArea(window, &kShadowMargins);
  SetWindowPos(window, nullptr, 0, 0, 0, 0,
               SWP_FRAMECHANGED | SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER |
                   SWP_NOOWNERZORDER);

  return OnCreate();
}

bool Win32Window::Show() {
  return ShowWindow(window_handle_,
                    start_maximized_ ? SW_SHOWMAXIMIZED : SW_SHOWNORMAL);
}

void Win32Window::SetStartMaximized(bool maximized) {
  start_maximized_ = maximized;
}

// static
LRESULT CALLBACK Win32Window::WndProc(HWND const window,
                                      UINT const message,
                                      WPARAM const wparam,
                                      LPARAM const lparam) noexcept {
  if (message == WM_NCCREATE) {
    auto window_struct = reinterpret_cast<CREATESTRUCT*>(lparam);
    SetWindowLongPtr(window, GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(window_struct->lpCreateParams));

    auto that = static_cast<Win32Window*>(window_struct->lpCreateParams);
    EnableFullDpiSupportIfAvailable(window);
    that->window_handle_ = window;
  } else if (Win32Window* that = GetThisFromHandle(window)) {
    return that->MessageHandler(window, message, wparam, lparam);
  }

  return DefWindowProc(window, message, wparam, lparam);
}

LRESULT
Win32Window::MessageHandler(HWND hwnd,
                            UINT const message,
                            WPARAM const wparam,
                            LPARAM const lparam) noexcept {
  switch (message) {
    case WM_NCCALCSIZE:
      if (wparam == TRUE) {
        auto* params = reinterpret_cast<NCCALCSIZE_PARAMS*>(lparam);
        const UINT dpi = GetWindowDpi(hwnd);
        const int frame_x =
            GetSystemMetricsForDpiSafe(SM_CXFRAME, dpi) +
            GetSystemMetricsForDpiSafe(SM_CXPADDEDBORDER, dpi);
        const int frame_y =
            GetSystemMetricsForDpiSafe(SM_CYFRAME, dpi) +
            GetSystemMetricsForDpiSafe(SM_CXPADDEDBORDER, dpi);
        params->rgrc[0].left += frame_x;
        params->rgrc[0].right -= frame_x;
        params->rgrc[0].bottom -= frame_y;
        if (::IsZoomed(hwnd) != 0) {
          params->rgrc[0].top += frame_y;
          LeaveRoomForAutoHideTaskbar(hwnd, &params->rgrc[0]);
        }
        return 0;
      }
      break;

    case WM_NCHITTEST: {
      const LRESULT hit = DefWindowProc(hwnd, message, wparam, lparam);
      if (hit != HTCLIENT) {
        return hit;
      }
      POINT pt = {GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
      return HitTestCustomChrome(hwnd, pt);
    }

    case WM_DESTROY:
      window_handle_ = nullptr;
      Destroy();
      if (quit_on_close_) {
        PostQuitMessage(0);
      }
      return 0;

    case WM_DPICHANGED: {
      auto newRectSize = reinterpret_cast<RECT*>(lparam);
      LONG newWidth = newRectSize->right - newRectSize->left;
      LONG newHeight = newRectSize->bottom - newRectSize->top;

      SetWindowPos(hwnd, nullptr, newRectSize->left, newRectSize->top, newWidth,
                   newHeight, SWP_NOZORDER | SWP_NOACTIVATE);

      return 0;
    }
    case WM_SIZE: {
      RECT rect = GetClientArea();
      if (child_content_ != nullptr) {
        // Size and position the child window.
        MoveWindow(child_content_, rect.left, rect.top, rect.right - rect.left,
                   rect.bottom - rect.top, TRUE);
      }
      return 0;
    }

    case WM_ACTIVATE:
      if (child_content_ != nullptr) {
        SetFocus(child_content_);
      }
      return 0;

    case WM_DWMCOLORIZATIONCOLORCHANGED:
      UpdateTheme(hwnd);
      return 0;

    case WM_GETMINMAXINFO: {
      auto* info = reinterpret_cast<MINMAXINFO*>(lparam);
      HMONITOR monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
      double scale_factor = FlutterDesktopGetDpiForMonitor(monitor) / 96.0;
      LONG min_width = Scale(960, scale_factor);
      LONG min_height = Scale(600, scale_factor);
      // On small or heavily scaled displays the work area is smaller than the
      // minimum size; without this the bottom of the window ends up under the
      // taskbar.
      MONITORINFO monitor_info{};
      monitor_info.cbSize = sizeof(monitor_info);
      if (GetMonitorInfo(monitor, &monitor_info)) {
        const RECT& work = monitor_info.rcWork;
        const LONG max_width = work.right - work.left;
        const LONG max_height = work.bottom - work.top;
        if (min_width > max_width) min_width = max_width;
        if (min_height > max_height) min_height = max_height;
      }
      info->ptMinTrackSize.x = min_width;
      info->ptMinTrackSize.y = min_height;
      return 0;
    }
  }

  return DefWindowProc(window_handle_, message, wparam, lparam);
}

void Win32Window::Destroy() {
  OnDestroy();

  if (window_handle_) {
    DestroyWindow(window_handle_);
    window_handle_ = nullptr;
  }
  if (g_active_window_count == 0) {
    WindowClassRegistrar::GetInstance()->UnregisterWindowClass();
  }
}

Win32Window* Win32Window::GetThisFromHandle(HWND const window) noexcept {
  return reinterpret_cast<Win32Window*>(
      GetWindowLongPtr(window, GWLP_USERDATA));
}

void Win32Window::SetChildContent(HWND content) {
  if (child_content_ != nullptr) {
    ::RemoveWindowSubclass(child_content_, ChildHitTestSubclassProc,
                           kChildHitTestSubclassId);
  }
  child_content_ = content;
  SetParent(content, window_handle_);
  ::SetWindowSubclass(content, ChildHitTestSubclassProc,
                      kChildHitTestSubclassId, 0);
  RECT frame = GetClientArea();

  MoveWindow(content, frame.left, frame.top, frame.right - frame.left,
             frame.bottom - frame.top, true);

  SetFocus(child_content_);
}

RECT Win32Window::GetClientArea() {
  RECT frame;
  GetClientRect(window_handle_, &frame);
  return frame;
}

HWND Win32Window::GetHandle() {
  return window_handle_;
}

void Win32Window::SetQuitOnClose(bool quit_on_close) {
  quit_on_close_ = quit_on_close;
}

bool Win32Window::OnCreate() {
  // No-op; provided for subclasses.
  return true;
}

void Win32Window::OnDestroy() {
  // No-op; provided for subclasses.
}

void Win32Window::UpdateTheme(HWND const window) {
  DWORD light_mode;
  DWORD light_mode_size = sizeof(light_mode);
  LSTATUS result = RegGetValue(HKEY_CURRENT_USER, kGetPreferredBrightnessRegKey,
                               kGetPreferredBrightnessRegValue,
                               RRF_RT_REG_DWORD, nullptr, &light_mode,
                               &light_mode_size);

  if (result == ERROR_SUCCESS) {
    BOOL enable_dark_mode = light_mode == 0;
    DwmSetWindowAttribute(window, DWMWA_USE_IMMERSIVE_DARK_MODE,
                          &enable_dark_mode, sizeof(enable_dark_mode));
  }
}
