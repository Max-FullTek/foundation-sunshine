/**
 * @file src/platform/windows/win_dark_mode.cpp
 * @brief Implementation of Windows dark mode support
 */

#ifdef _WIN32

#include "win_dark_mode.h"

#include <dwmapi.h>
#include <mutex>

namespace win_dark_mode {

  // Undocumented PreferredAppMode enum from uxtheme.dll
  enum class PreferredAppMode {
    Default = 0,     // Use system default (usually light)
    AllowDark = 1,   // Allow dark mode (follow system setting)
    ForceDark = 2,   // Force dark mode regardless of system setting
    ForceLight = 3,  // Force light mode regardless of system setting
    Max = 4,
  };

  // Function pointer types for undocumented uxtheme.dll APIs
  // Windows 11 uses SetPreferredAppMode (ordinal 135).
  using SetPreferredAppModeFn = PreferredAppMode(WINAPI *)(PreferredAppMode);

  // Global function pointer (initialized once)
  static SetPreferredAppModeFn g_SetPreferredAppMode = nullptr;
  static std::once_flag g_init_flag;

  // Static holder for uxtheme.dll handle
  // Design decision: We intentionally keep this handle loaded for the lifetime of the process
  // because the function pointers (g_SetPreferredAppMode) must remain valid. The library is
  // only loaded once via std::call_once, so there's no risk of multiple loads. The OS will
  // automatically clean up when the process exits.
  static HMODULE g_hUxTheme = nullptr;

  /**
   * @brief Initialize the dark mode API function pointers
   *
   * This function loads uxtheme.dll and retrieves the undocumented function pointers.
   * It only runs once and caches the results using std::call_once for thread safety.
   */
  static void
  init_dark_mode_apis() {
    // Load uxtheme.dll
    g_hUxTheme = LoadLibraryW(L"uxtheme.dll");
    if (!g_hUxTheme) {
      return;
    }

    // Get SetPreferredAppMode (ordinal 135)
    g_SetPreferredAppMode =
      reinterpret_cast<SetPreferredAppModeFn>(
        GetProcAddress(g_hUxTheme, MAKEINTRESOURCEA(135)));
  }

  void
  enable_process_dark_mode() {
    // Thread-safe one-time initialization
    std::call_once(g_init_flag, init_dark_mode_apis);

    // Call the function if available
    if (g_SetPreferredAppMode) {
      // Use AllowDark to follow the system's dark/light mode preference
      g_SetPreferredAppMode(PreferredAppMode::AllowDark);
    }
    // Keep the default theme if the undocumented API is unavailable.
  }

}  // namespace win_dark_mode

#endif  // _WIN32
