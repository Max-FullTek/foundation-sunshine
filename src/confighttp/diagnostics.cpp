/**
 * @file src/confighttp/diagnostics.cpp
 * @brief Web UI diagnostics handlers and routes.
 */
#define BOOST_BIND_GLOBAL_PLACEHOLDERS

#include "diagnostics.h"
#include "src/config.h"
#include "src/confighttp/auth.h"
#include "src/confighttp/common.h"
#include "src/display_device/session.h"
#include "src/entry_handler.h"
#include "src/file_handler.h"
#include "src/logging.h"
#include "src/rtsp.h"
#include <algorithm>
#include <atomic>
#include <boost/algorithm/string.hpp>
#include <boost/property_tree/json_parser.hpp>
#include <chrono>
#include <filesystem>
#include <fstream>
#ifdef _WIN32
  #include "src/display_device/vdd_utils.h"
  #include "src/platform/windows/vulkan_hdr_bridge_session.h"
#endif

using namespace std::literals;
using json = nlohmann::json;

namespace confighttp::diagnostics {
  namespace pt = boost::property_tree;

  using namespace confighttp;

  namespace {
    /**
     * @brief Snapshot of log cache state, swapped atomically via shared_ptr.
     */
    struct LogCacheSnapshot {
      std::shared_ptr<const std::string> content;  ///< Cached log content (nullptr in offset-only mode)
      std::uintmax_t file_size = 0;  ///< Actual file size on disk when snapshot was taken
      std::intmax_t mtime_ns = 0;  ///< File mtime when snapshot was taken
      std::uintmax_t start_offset = 0;  ///< File byte position where content begins
    };

    /**
     * @brief Try to read only the new tail of the log file and append to existing content.
     * @return New content on success, nullptr on any failure (caller should fall back to full read).
     */
    static std::shared_ptr<const std::string>
    try_incremental_log_read(
      const std::filesystem::path &log_path,
      std::uintmax_t prev_size,
      std::uintmax_t current_size,
      const std::shared_ptr<const std::string> &old_content) {
      if (current_size <= prev_size || prev_size == 0 || !old_content) {
        return nullptr;
      }
      std::ifstream in(log_path, std::ios::binary);
      if (!in || !in.seekg(static_cast<std::streamoff>(prev_size))) {
        return nullptr;
      }
      const auto tail_len = current_size - prev_size;
      std::string tail(tail_len, '\0');
      if (!in.read(tail.data(), static_cast<std::streamsize>(tail_len))) {
        return nullptr;
      }
      return std::make_shared<const std::string>(*old_content + tail);
    }

    /**
     * @brief Read a specific byte range [offset, offset+length) from a file.
     * @return Content string on success, nullptr on failure.
     */
    static std::shared_ptr<const std::string>
    read_file_range(const std::filesystem::path &path, std::uintmax_t offset, std::uintmax_t length) {
      std::ifstream in(path, std::ios::binary);
      if (!in || !in.seekg(static_cast<std::streamoff>(offset))) {
        return nullptr;
      }
      std::string content(static_cast<std::size_t>(length), '\0');
      if (!in.read(content.data(), static_cast<std::streamsize>(length))) {
        return nullptr;
      }
      return std::make_shared<const std::string>(std::move(content));
    }

    /**
     * @brief Get the logs from the log file.
     * @param response The HTTP response object.
     * @param request The HTTP request object.
     *
     * Dual mode via X-Log-Offset header:
     *   - Without header: stream full log file from disk (for download)
     *   - With header:    cached or offset-based incremental support (for live viewer)
     *
     * When the log file is small (≤ 4 MB), the entire file is cached in memory for fast serving.
     * When the log file exceeds 4 MB, no content is cached; reads go directly to disk at the
     * client's offset (offset-only mode), avoiding unbounded memory growth.
     *
     * @api_examples{/api/logs| GET| null}
     */
    void
    getLogs(resp_https_t response, req_https_t request) {
      if (!authenticate(response, request)) {
        return;
      }

      // print_req(request);

      const auto log_path = file_handler::path_from_utf8(config::sunshine.log_file);

      // --- Mode 1: No X-Log-Offset header → stream full file from disk (download) ---
      auto offset_it = request->header.find("X-Log-Offset");
      if (offset_it == request->header.end()) {
        web::CaseInsensitiveMultimap headers;
        headers.emplace("Content-Type", "text/plain; charset=utf-8");
        headers.emplace("Content-Disposition", "attachment; filename=\"sunshine.log\"");
        if (!response->write_file(web::StatusCode::ok, log_path, headers))
          response->write(web::StatusCode::internal_server_error, "Failed to open log file");
        return;
      }

      // --- Mode 2: X-Log-Offset present → cached or offset-only mode for live viewer ---

      // When file ≤ MAX_LOG_CACHE_SIZE: cached in memory.  Otherwise: disk reads only.
      static constexpr std::uintmax_t MAX_LOG_CACHE_SIZE = 4 * 1024 * 1024;  // 4 MB
      static constexpr std::uintmax_t MAX_RESPONSE_SIZE = 4 * 1024 * 1024;  // 4 MB

      static std::atomic<std::shared_ptr<const LogCacheSnapshot>> log_cache;

      // Check file status
      std::error_code ec;
      auto current_size = std::filesystem::file_size(log_path, ec);
      if (ec) {
        response->write(web::StatusCode::internal_server_error, "Failed to read log file");
        return;
      }
      auto current_mtime = std::filesystem::last_write_time(log_path, ec);
      if (ec) {
        response->write(web::StatusCode::internal_server_error, "Failed to read log file");
        return;
      }
      auto current_mtime_ns = current_mtime.time_since_epoch().count();

      // Refresh cache if file changed
      auto snapshot = log_cache.load();
      const bool cache_stale = !snapshot || current_size != snapshot->file_size || current_mtime_ns != snapshot->mtime_ns;
      if (cache_stale) {
        auto new_snap = std::make_shared<LogCacheSnapshot>();
        new_snap->file_size = current_size;
        new_snap->mtime_ns = current_mtime_ns;

        if (current_size <= MAX_LOG_CACHE_SIZE) {
          // --- Cached mode: file fits in memory ---
          std::shared_ptr<const std::string> new_content;
          if (snapshot && snapshot->content && snapshot->file_size > 0 && current_size > snapshot->file_size) {
            new_content = try_incremental_log_read(log_path, snapshot->file_size, current_size, snapshot->content);
          }
          if (!new_content) {
            // Use sampled current_size to avoid TOCTOU unsigned underflow at start_offset
            auto read_len = std::min(current_size, MAX_LOG_CACHE_SIZE);
            auto read_start = current_size - read_len;
            new_content = read_file_range(log_path, read_start, read_len);
          }
          if (!new_content) {
            if (current_size > 0) {
              response->write(web::StatusCode::internal_server_error, "Failed to read log file");
              return;
            }
            new_content = std::make_shared<const std::string>();
          }
          new_snap->content = std::move(new_content);
          new_snap->start_offset = current_size - new_snap->content->size();
        }
        else {
          // --- Offset-only mode: file too large, don't cache content ---
          new_snap->content = nullptr;
          new_snap->start_offset = 0;
        }

        // CAS publish: avoid overwriting a newer snapshot from a concurrent thread
        if (!log_cache.compare_exchange_strong(snapshot, new_snap)) {
          // CAS failed: snapshot already updated by compare_exchange_strong
        }
        else {
          snapshot = std::move(new_snap);
        }
      }

      // Parse client offset
      std::uintmax_t client_offset = 0;
      try {
        std::string offset_str(offset_it->second);
        boost::algorithm::trim(offset_str);
        if (!offset_str.empty()) {
          client_offset = std::stoull(offset_str);
        }
      }
      catch (const std::invalid_argument &) {
        client_offset = 0;
      }
      catch (const std::out_of_range &) {
        client_offset = 0;
      }

      web::CaseInsensitiveMultimap headers;
      headers.emplace("Content-Type", "text/plain");
      headers.emplace("X-Log-Size", std::to_string(snapshot->file_size));
      headers.emplace("X-Frame-Options", "DENY");
      headers.emplace("Content-Security-Policy", "frame-ancestors 'none';");

      // No change in logs → 304
      if (client_offset > 0 && client_offset == snapshot->file_size) {
        headers.emplace("X-Log-Range", "unchanged");
        response->write(web::StatusCode::not_modified, headers);
        return;
      }

      if (snapshot->content) {
        // === Cached mode: serve from memory ===
        if (client_offset > 0 && client_offset >= snapshot->start_offset && client_offset < snapshot->file_size) {
          auto cache_pos = client_offset - snapshot->start_offset;
          headers.emplace("X-Log-Range", "incremental");
          auto delta = snapshot->content->substr(static_cast<std::size_t>(cache_pos));
          response->write(web::StatusCode::ok, delta, headers);
        }
        else {
          headers.emplace("X-Log-Range", "full");
          response->write(web::StatusCode::ok, *snapshot->content, headers);
        }
      }
      else {
        // === Offset-only mode: read from disk, bounded by snapshot->file_size ===
        if (client_offset > 0 && client_offset < snapshot->file_size) {
          auto delta_size = snapshot->file_size - client_offset;
          if (delta_size <= MAX_RESPONSE_SIZE) {
            auto data = read_file_range(log_path, client_offset, delta_size);
            if (data) {
              headers.emplace("X-Log-Range", "incremental");
              response->write(web::StatusCode::ok, *data, headers);
              return;
            }
          }
        }
        // Delta too large, read failed, or first request: return tail up to snapshot->file_size
        auto tail_len = std::min(snapshot->file_size, MAX_RESPONSE_SIZE);
        auto tail_start = snapshot->file_size - tail_len;
        auto tail = read_file_range(log_path, tail_start, tail_len);
        if (!tail) {
          response->write(web::StatusCode::internal_server_error, "Failed to read log file");
          return;
        }
        headers.emplace("X-Log-Range", "full");
        response->write(web::StatusCode::ok, *tail, headers);
      }
    }

    void
    restart(resp_https_t response, req_https_t request) {
      if (!authenticate(response, request)) return;

      print_req(request);

      // We may not return from this call
      platf::restart();
    }

    void
    boom(resp_https_t response, req_https_t request) {
      if (!authenticate(response, request)) return;

      print_req(request);
#ifdef _WIN32
      if (GetConsoleWindow() == NULL) {
        lifetime::exit_sunshine(ERROR_SHUTDOWN_IN_PROGRESS, true);
        return;
      }
#endif
      lifetime::exit_sunshine(0, true);
    }

    void
    resetDisplayDevicePersistence(resp_https_t response, req_https_t request) {
      if (!authenticate(response, request)) return;

      print_req(request);

      pt::ptree outputTree;
      auto g = util::fail_guard([&]() {
        std::ostringstream data;
        pt::write_json(data, outputTree);
        response->write(data.str());
      });

      display_device::session_t::get().reset_persistence();
      outputTree.put("status", true);
    }

  }  // namespace

  void
  register_routes(https_server_t &server) {
    server.resource["^/api/logs$"]["GET"] = getLogs;
    server.resource["^/api/restart$"]["POST"] = restart;
    server.resource["^/api/restart$"]["GET"] = restart;
    server.resource["^/api/boom$"]["GET"] = boom;
    server.resource["^/api/reset-display-device-persistence$"]["POST"] = resetDisplayDevicePersistence;
#ifdef _WIN32
    server.resource["^/api/vdd/status$"]["GET"] = getVddStatus;
#endif
#ifdef _WIN32
    server.resource["^/api/vulkan-hdr-bridge$"]["GET"] = getVulkanHdrBridgeStatus;
#endif
#ifdef _WIN32
    server.resource["^/api/vulkan-hdr-bridge/validate$"]["POST"] = validateVulkanHdrBridge;
#endif
  }

}  // namespace confighttp::diagnostics
