/**
 * @file tests/tools/test_http_safety.cpp
 * @brief Asset path traversal regression tests.
 */
#include <algorithm>
#include <chrono>
#include <filesystem>
#include <fstream>
#include <gtest/gtest.h>

#include "src/confighttp/asset_paths.h"
#ifdef _WIN32
  #include <windows.h>
  #include <winioctl.h>
#endif

namespace {
  namespace fs = std::filesystem;

#ifdef _WIN32
  // Junction creation needs no symlink privilege; use it to exercise canonical
  // escape checks on Windows hosts where symbolic links are unavailable.
  bool
  create_junction(const fs::path &target, const fs::path &link) {
    fs::create_directory(link);
    HANDLE handle = CreateFileW(link.c_str(), GENERIC_WRITE, 0, nullptr, OPEN_EXISTING,
      FILE_FLAG_OPEN_REPARSE_POINT | FILE_FLAG_BACKUP_SEMANTICS, nullptr);
    if (handle == INVALID_HANDLE_VALUE) return false;
    const auto substitute = L"\\??\\" + fs::absolute(target).native();
    const auto display = fs::absolute(target).native();
    struct MountPoint {
      DWORD tag;
      WORD length, reserved;
      WORD substitute_offset, substitute_length, print_offset, print_length;
      wchar_t paths[4096];
    } data {};
    const auto characters = substitute.size() + display.size() + 2;
    if (characters > std::size(data.paths)) {
      CloseHandle(handle);
      return false;
    }
    data.tag = IO_REPARSE_TAG_MOUNT_POINT;
    data.length = static_cast<WORD>(8 + characters * sizeof(wchar_t));
    data.substitute_length = static_cast<WORD>(substitute.size() * sizeof(wchar_t));
    data.print_offset = static_cast<WORD>((substitute.size() + 1) * sizeof(wchar_t));
    data.print_length = static_cast<WORD>(display.size() * sizeof(wchar_t));
    std::copy(substitute.begin(), substitute.end(), data.paths);
    std::copy(display.begin(), display.end(), data.paths + substitute.size() + 1);
    DWORD returned;
    const bool success = DeviceIoControl(handle, FSCTL_SET_REPARSE_POINT, &data, 8 + data.length,
      nullptr, 0, &returned, nullptr);
    CloseHandle(handle);
    return success;
  }
#endif

  class HttpSafety: public testing::Test {
  protected:
    fs::path directory;
    void
    SetUp() override {
      directory = fs::temp_directory_path() / ("sunshine-http-safety-" + std::to_string(std::chrono::steady_clock::now().time_since_epoch().count()));
      fs::create_directories(directory / "assets");
      fs::create_directories(directory / "covers/sub");
      fs::create_directories(directory / "covers-sibling");
      std::ofstream(directory / "assets/box.png") << "placeholder";
      std::ofstream(directory / "assets/logo.png") << "logo";
      std::ofstream(directory / "covers/sub/image.png") << "cover";
      std::ofstream(directory / "covers-sibling/private.png") << "secret";
    }
    void
    TearDown() override {
      std::error_code ec;
      fs::remove_all(directory, ec);
    }
    auto
    resolve(const fs::path &request) {
      return confighttp::assets::resolve_boxart_path(directory / "assets", directory / "covers", request);
    }
  };
}  // namespace

TEST_F(HttpSafety, AllowsFlatAssetsAndNestedCovers) {
  EXPECT_EQ(resolve("logo.png"), fs::weakly_canonical(directory / "assets/logo.png"));
  EXPECT_EQ(resolve("sub/image.png"), fs::weakly_canonical(directory / "covers/sub/image.png"));
  EXPECT_FALSE(resolve("missing.png"));
  EXPECT_TRUE(confighttp::assets::is_child_path(directory / "covers/missing.png", directory / "covers"));
  EXPECT_FALSE(resolve("."));
  EXPECT_FALSE(resolve(""));
}

TEST_F(HttpSafety, RejectsTraversalRootedPathsAndAlternateStreams) {
  EXPECT_FALSE(resolve("../covers-sibling/private.png"));
  EXPECT_FALSE(resolve(directory / "covers-sibling/private.png"));
  EXPECT_FALSE(resolve("/private.png"));
  EXPECT_FALSE(resolve("C:/private.png"));
  EXPECT_FALSE(resolve("C:private.png"));
  EXPECT_FALSE(resolve("sub/image.png:private"));
  EXPECT_FALSE(resolve(fs::path(std::string("sub/image.png\0extra", 19))));
#ifdef _WIN32
  EXPECT_FALSE(resolve("\\\\127.0.0.1\\share\\private.png"));
  EXPECT_FALSE(resolve("\\private.png"));
  EXPECT_FALSE(resolve("..\\covers-sibling\\private.png"));
  EXPECT_FALSE(confighttp::assets::is_child_path("D:/private.png", "C:/covers"));
#endif
  EXPECT_FALSE(confighttp::assets::is_child_path(directory / "covers-sibling/private.png", directory / "covers"));
  EXPECT_FALSE(confighttp::assets::is_child_path({}, directory / "covers"));
}

TEST_F(HttpSafety, RejectsSymlinkEscapesAndAssetSubdirectories) {
  fs::create_directories(directory / "assets/sub");
  std::ofstream(directory / "assets/sub/hidden.png") << "hidden";
  EXPECT_FALSE(resolve("sub/hidden.png"));
  std::error_code ec;
  fs::create_directory_symlink(directory / "covers-sibling", directory / "covers/link", ec);
#ifdef _WIN32
  if (ec) {
    ASSERT_TRUE(create_junction(directory / "covers-sibling", directory / "covers/link"));
    ec.clear();
  }
#endif
  if (ec) GTEST_SKIP() << "Creating symlinks requires privileges: " << ec.message();
  EXPECT_FALSE(resolve("link/private.png"));
}
