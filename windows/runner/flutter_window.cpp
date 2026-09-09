#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"

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

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  // 必须先置标记再析构 controller：析构过程中无障碍桥（AX bridge）拆除
  // 会同步派发嵌套窗口消息（WM_GETOBJECT 类）重入 MessageHandler，此时
  // view 正在析构，若继续进 Flutter 消息分发，GetEngine 会访问已释放
  // 对象导致退出时崩溃（之后 WER 收集转储拖 ~12s 进程才退出）。
  //
  // 仅当 controller 存在时才处理：启动期 Win32Window::Create() 开头会
  // 防御性调用一次 Destroy()→OnDestroy()（此时窗口与 controller 均未
  // 创建），若那里也置位 is_shutting_down_，标志将永久为 true，之后每次
  // WM_CLOSE 都会跳过 Flutter 消息分发（preventClose 拦截随之失效），
  // 窗口被立即销毁并走进上文的崩溃路径。
  if (flutter_controller_ != nullptr) {
    is_shutting_down_ = true;
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  // 销毁期间（is_shutting_down_）跳过：重入消息交给 DefWindowProc 即可。
  if (flutter_controller_ && !is_shutting_down_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }

    switch (message) {
      case WM_FONTCHANGE:
        flutter_controller_->engine()->ReloadSystemFonts();
        break;
    }
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
