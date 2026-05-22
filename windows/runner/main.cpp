#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Check for --uninstall flag before singleton detection so cleanup can run
  // even if another instance is active.
  bool is_uninstall = false;
  {
    int argc;
    wchar_t** argv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
    if (argv != nullptr) {
      for (int i = 1; i < argc; i++) {
        if (std::wstring(argv[i]) == L"--uninstall") {
          is_uninstall = true;
          break;
        }
      }
      ::LocalFree(argv);
    }
  }

  if (!is_uninstall) {
    HWND hwnd = ::FindWindow(L"FLUTTER_RUNNER_WIN32_WINDOW", L"Singcast");
    if (hwnd != NULL) {
      ::ShowWindow(hwnd, SW_NORMAL);
      ::SetForegroundWindow(hwnd);
      return EXIT_FAILURE;
    }
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.CreateAndShow(L"Singcast", origin, size)) {
    return EXIT_FAILURE;
  }
  // Hide window during uninstall — Dart will exit(0) after cleanup.
  if (is_uninstall) {
    ::ShowWindow(window.GetHandle(), SW_HIDE);
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
