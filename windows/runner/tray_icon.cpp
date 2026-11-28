#include "tray_icon.h"

#include <shellapi.h>

#include "resource.h"

namespace {

constexpr UINT kTrayIconId = 1;
constexpr wchar_t kTrayTooltip[] = L"Alisten";
// \u6253\u5F00 = 打开, \u9000\u51FA = 退出; Unicode escapes avoid MSVC
// codepage issues on non-UTF-8 locales.
constexpr wchar_t kMenuOpenLabel[] = L"\u6253\u5F00 Alisten";
constexpr wchar_t kMenuExitLabel[] = L"\u9000\u51FA";

}  // namespace

TrayIcon::~TrayIcon() {
  Destroy();
}

bool TrayIcon::Create(HWND hwnd) {
  if (hwnd == nullptr) {
    return false;
  }
  Destroy();
  hwnd_ = hwnd;
  if (taskbar_created_message_ == 0) {
    taskbar_created_message_ = ::RegisterWindowMessageW(L"TaskbarCreated");
  }
  icon_ = static_cast<HICON>(::LoadImageW(
      ::GetModuleHandleW(nullptr), MAKEINTRESOURCEW(IDI_APP_ICON), IMAGE_ICON,
      ::GetSystemMetrics(SM_CXSMICON), ::GetSystemMetrics(SM_CYSMICON),
      LR_DEFAULTCOLOR | LR_SHARED));
  if (icon_ == nullptr) {
    icon_ = ::LoadIconW(::GetModuleHandleW(nullptr),
                        MAKEINTRESOURCEW(IDI_APP_ICON));
  }
  created_ = AddIcon();
  return created_;
}

bool TrayIcon::Recreate() {
  if (hwnd_ == nullptr) {
    return false;
  }
  // The shell also broadcasts TaskbarCreated when the DPI of the primary
  // display changes. The icon is still registered then, and adding it a second
  // time fails.
  RemoveIcon();
  created_ = AddIcon();
  return created_;
}

bool TrayIcon::AddIcon() {
  NOTIFYICONDATAW data{};
  data.cbSize = sizeof(data);
  data.hWnd = hwnd_;
  data.uID = kTrayIconId;
  data.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  data.uCallbackMessage = kCallbackMessage;
  data.hIcon = icon_;
  wcsncpy_s(data.szTip, kTrayTooltip, _TRUNCATE);
  return ::Shell_NotifyIconW(NIM_ADD, &data) != FALSE;
}

void TrayIcon::RemoveIcon() {
  NOTIFYICONDATAW data{};
  data.cbSize = sizeof(data);
  data.hWnd = hwnd_;
  data.uID = kTrayIconId;
  ::Shell_NotifyIconW(NIM_DELETE, &data);
}

void TrayIcon::Destroy() {
  if (created_ && hwnd_ != nullptr) {
    RemoveIcon();
  }
  created_ = false;
  icon_ = nullptr;
  hwnd_ = nullptr;
}

void TrayIcon::ShowContextMenu() {
  if (hwnd_ == nullptr) {
    return;
  }
  HMENU menu = ::CreatePopupMenu();
  if (menu == nullptr) {
    return;
  }
  ::AppendMenuW(menu, MF_STRING, kMenuOpenId, kMenuOpenLabel);
  ::AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  ::AppendMenuW(menu, MF_STRING, kMenuExitId, kMenuExitLabel);
  ::SetMenuDefaultItem(menu, kMenuOpenId, FALSE);

  POINT cursor{};
  ::GetCursorPos(&cursor);
  // Required by Win32 so clicking outside the menu dismisses it immediately.
  ::SetForegroundWindow(hwnd_);
  ::TrackPopupMenuEx(menu, TPM_RIGHTBUTTON | TPM_BOTTOMALIGN, cursor.x,
                     cursor.y, hwnd_, nullptr);
  ::PostMessageW(hwnd_, WM_NULL, 0, 0);
  ::DestroyMenu(menu);
}
