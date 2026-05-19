import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// 通过 OpenProcessToken + GetTokenInformation(TokenElevation)
/// 检测当前进程是否以管理员身份运行，无需 PowerShell。
bool isWindowsAdmin() {
  final hProcess = GetCurrentProcess();
  final phToken = malloc<IntPtr>();
  try {
    if (OpenProcessToken(hProcess, TOKEN_QUERY, phToken) == 0) return false;
    final token = phToken.value;
    final elevation = malloc<Uint32>();
    final returnLength = malloc<Uint32>();
    try {
      final ok = GetTokenInformation(
        token,
        TokenElevation,
        elevation.cast(),
        sizeOf<Uint32>(),
        returnLength,
      );
      return ok != 0 && elevation.value != 0;
    } finally {
      malloc.free(elevation);
      malloc.free(returnLength);
      CloseHandle(token);
    }
  } finally {
    malloc.free(phToken);
  }
}

/// 通过 ShellExecuteExW + "runas" 以管理员身份启动新进程。
/// 触发 UAC 弹窗，返回 true 表示调用成功（UAC 已批准），false 表示失败或用户拒绝。
bool runElevated({required String exe, String? args, String? workingDir}) {
  CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);

  final verbPtr = 'runas'.toNativeUtf16();
  final filePtr = exe.toNativeUtf16();
  final paramsPtr = args?.toNativeUtf16();
  final dirPtr = workingDir?.toNativeUtf16();

  try {
    final sei = calloc<SHELLEXECUTEINFO>();
    sei.ref.cbSize = sizeOf<SHELLEXECUTEINFO>();
    sei.ref.fMask = 0x00000100 | 0x00000040; // SEE_MASK_NOASYNC | SEE_MASK_NOCLOSEPROCESS
    sei.ref.lpVerb = verbPtr;
    sei.ref.lpFile = filePtr;
    if (paramsPtr != null) sei.ref.lpParameters = paramsPtr;
    if (dirPtr != null) sei.ref.lpDirectory = dirPtr;
    sei.ref.nShow = SW_NORMAL;

    final ok = ShellExecuteEx(sei) != 0;
    if (ok && sei.ref.hProcess != 0) CloseHandle(sei.ref.hProcess);
    calloc.free(sei);
    return ok;
  } finally {
    malloc.free(verbPtr);
    malloc.free(filePtr);
    if (paramsPtr != null) malloc.free(paramsPtr);
    if (dirPtr != null) malloc.free(dirPtr);
  }
}
