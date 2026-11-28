#include "flutter_window.h"

#include <flutter/standard_method_codec.h>

#include <optional>
#include <variant>

#include "flutter/generated_plugin_registrant.h"
#include "window_state.h"

namespace {

constexpr char kWindowChannelName[] = "moe.dihe.alisten/window";

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  SetupWindowChannel();
  tray_icon_.Create(GetHandle());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::SetupWindowChannel() {
  window_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), kWindowChannelName,
          &flutter::StandardMethodCodec::GetInstance());
  window_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "setMinimizeToTrayOnClose") {
          const auto* enabled =
              call.arguments() ? std::get_if<bool>(call.arguments()) : nullptr;
          if (enabled == nullptr) {
            result->Error("INVALID_ARGUMENT", "Expected a boolean");
            return;
          }
          minimize_to_tray_on_close_ = *enabled;
          result->Success();
          return;
        }
        if (call.method_name() == "showWindow") {
          RestoreFromTray();
          result->Success();
          return;
        }
        if (call.method_name() == "minimizeWindow") {
          HWND hwnd = GetHandle();
          if (hwnd != nullptr) {
            ::ShowWindow(hwnd, SW_MINIMIZE);
          }
          result->Success();
          return;
        }
        if (call.method_name() == "toggleMaximize") {
          HWND hwnd = GetHandle();
          if (hwnd != nullptr) {
            ::ShowWindow(hwnd, ::IsZoomed(hwnd) ? SW_RESTORE : SW_MAXIMIZE);
          }
          result->Success();
          return;
        }
        if (call.method_name() == "closeWindow") {
          HWND hwnd = GetHandle();
          if (hwnd != nullptr) {
            ::PostMessage(hwnd, WM_CLOSE, 0, 0);
          }
          result->Success();
          return;
        }
        if (call.method_name() == "startDragging") {
          HWND hwnd = GetHandle();
          if (hwnd != nullptr) {
            ::ReleaseCapture();
            ::PostMessage(hwnd, WM_NCLBUTTONDOWN, HTCAPTION, 0);
          }
          result->Success();
          return;
        }
        if (call.method_name() == "showSystemMenu") {
          HWND hwnd = GetHandle();
          result->Success();
          if (hwnd != nullptr) {
            HMENU menu = ::GetSystemMenu(hwnd, FALSE);
            if (menu != nullptr) {
              const bool maximized = ::IsZoomed(hwnd) != 0;
              ::EnableMenuItem(
                  menu, SC_RESTORE,
                  MF_BYCOMMAND | (maximized ? MF_ENABLED : MF_GRAYED));
              ::EnableMenuItem(
                  menu, SC_MOVE,
                  MF_BYCOMMAND | (maximized ? MF_GRAYED : MF_ENABLED));
              ::EnableMenuItem(
                  menu, SC_SIZE,
                  MF_BYCOMMAND | (maximized ? MF_GRAYED : MF_ENABLED));
              ::EnableMenuItem(menu, SC_MINIMIZE, MF_BYCOMMAND | MF_ENABLED);
              ::EnableMenuItem(
                  menu, SC_MAXIMIZE,
                  MF_BYCOMMAND | (maximized ? MF_GRAYED : MF_ENABLED));
              POINT cursor{};
              ::GetCursorPos(&cursor);
              const UINT cmd = static_cast<UINT>(::TrackPopupMenu(
                  menu, TPM_RETURNCMD | TPM_RIGHTBUTTON, cursor.x, cursor.y, 0,
                  hwnd, nullptr));
              if (cmd != 0) {
                ::PostMessage(hwnd, WM_SYSCOMMAND, cmd, 0);
              }
            }
          }
          return;
        }
        if (call.method_name() == "isMaximized") {
          HWND hwnd = GetHandle();
          const bool maximized = hwnd != nullptr && ::IsZoomed(hwnd) != 0;
          last_maximized_ = maximized;
          result->Success(flutter::EncodableValue(maximized));
          return;
        }
        result->NotImplemented();
      });
}

void FlutterWindow::NotifyMaximizedChanged(bool maximized) {
  if (last_maximized_ == maximized) {
    return;
  }
  last_maximized_ = maximized;
  if (window_channel_) {
    window_channel_->InvokeMethod(
        "maximizedChanged",
        std::make_unique<flutter::EncodableValue>(maximized));
  }
}

void FlutterWindow::RestoreFromTray() {
  HWND hwnd = GetHandle();
  if (hwnd == nullptr) {
    return;
  }
  if (!::IsWindowVisible(hwnd)) {
    ::ShowWindow(hwnd, hidden_maximized_ ? SW_SHOWMAXIMIZED : SW_SHOWNORMAL);
  } else if (::IsIconic(hwnd)) {
    ::ShowWindow(hwnd, SW_RESTORE);
  }
  ::SetForegroundWindow(hwnd);
}

void FlutterWindow::ExitApp() {
  HWND hwnd = GetHandle();
  quitting_ = true;
  if (hwnd != nullptr) {
    SaveWindowState(hwnd, hidden_maximized_);
    tray_icon_.Destroy();
    ::DestroyWindow(hwnd);
  }
}

void FlutterWindow::OnDestroy() {
  tray_icon_.Destroy();
  window_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  if (tray_icon_.taskbar_created_message() != 0 &&
      message == tray_icon_.taskbar_created_message()) {
    tray_icon_.Recreate();
    return 0;
  }

  switch (message) {
    case WM_SIZE:
      if (wparam == SIZE_MAXIMIZED || wparam == SIZE_RESTORED) {
        NotifyMaximizedChanged(wparam == SIZE_MAXIMIZED);
      }
      break;

    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;

    case TrayIcon::kCallbackMessage:
      switch (LOWORD(lparam)) {
        case WM_LBUTTONUP:
        case WM_LBUTTONDBLCLK:
          RestoreFromTray();
          return 0;
        case WM_RBUTTONUP:
        case WM_CONTEXTMENU:
          tray_icon_.ShowContextMenu();
          return 0;
      }
      break;

    case WM_COMMAND:
      switch (LOWORD(wparam)) {
        case TrayIcon::kMenuOpenId:
          RestoreFromTray();
          return 0;
        case TrayIcon::kMenuExitId:
          ExitApp();
          return 0;
      }
      break;

    case WM_CLOSE:
      SaveWindowState(hwnd, hidden_maximized_);
      if (minimize_to_tray_on_close_ && !quitting_ && tray_icon_.IsCreated()) {
        hidden_maximized_ = RestoresMaximized(hwnd);
        ::ShowWindow(hwnd, SW_HIDE);
        return 0;
      }
      tray_icon_.Destroy();
      break;

    case WM_ENDSESSION:
      if (wparam != FALSE) {
        SaveWindowState(hwnd, hidden_maximized_);
        tray_icon_.Destroy();
      }
      break;

    case WM_DESTROY:
      tray_icon_.Destroy();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
