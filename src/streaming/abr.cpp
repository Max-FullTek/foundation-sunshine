/**
 * @file src/streaming/abr.cpp
 * @brief Threshold-based adaptive bitrate control.
 */

#include "abr.h"
#include "src/logging.h"

#include <algorithm>



namespace abr {

  // NOTE: sessions are keyed by client_name (the device display name), which is the
  // identifier that bridges the stateless HTTPS REST endpoints (abrFeedback/
  // configureAbr resolve the client by source IP) and the streaming layer
  // (stream::session::change_dynamic_param_for_client also routes by client_name).
  // Limitation: two concurrently-running sessions that share the same device name
  // would collide on a single entry and cross-contaminate state. This is acceptable
  // because single-session deployments are immune and normally-paired devices have
  // distinct names; supporting multi-session-same-name would require a coordinated
  // rekey to a session-level id across resolve_client, this map, and
  // change_dynamic_param_for_client.
  static std::mutex sessions_mutex;
  static std::unordered_map<std::string, session_state_t> sessions;

  /**
   * @brief Sanitize client-provided network feedback values.
   */
  static network_feedback_t
  sanitize_feedback(const network_feedback_t &raw) {
    return {
      std::clamp(raw.packet_loss, 0.0, 100.0),
      std::max(raw.rtt_ms, 0.0),
      std::max(raw.decode_fps, 0.0),
      std::max(raw.dropped_frames, 0),
      std::max(raw.current_bitrate_kbps, 0),
    };
  }

  /// Convert mode enum to string
  static std::string
  mode_to_string(mode_e mode) {
    switch (mode) {
      case mode_e::QUALITY:
        return "quality";
      case mode_e::LOW_LATENCY:
        return "lowLatency";
      case mode_e::BALANCED:
      default:
        return "balanced";
    }
  }

  /**
   * @brief Threshold-based bitrate decision.
   */
  static action_t
  fallback_decision(session_state_t &state, const network_feedback_t &feedback) {
    action_t action;

    if (feedback.packet_loss > 5.0) {
      state.consecutive_high_loss++;
      state.stable_ticks = 0;
      int new_bitrate = static_cast<int>(state.current_bitrate_kbps * 0.70);
      new_bitrate = std::clamp(new_bitrate, state.config.min_bitrate_kbps, state.config.max_bitrate_kbps);
      action.new_bitrate_kbps = new_bitrate;
      action.reason = "fallback: emergency_drop";
    }
    else if (feedback.packet_loss > 2.0) {
      state.consecutive_high_loss = 0;
      state.stable_ticks = 0;
      int new_bitrate = static_cast<int>(state.current_bitrate_kbps * 0.90);
      new_bitrate = std::clamp(new_bitrate, state.config.min_bitrate_kbps, state.config.max_bitrate_kbps);
      action.new_bitrate_kbps = new_bitrate;
      action.reason = "fallback: moderate_drop";
    }
    else if (feedback.packet_loss < 0.5) {
      state.consecutive_high_loss = 0;
      state.stable_ticks++;
      if (state.stable_ticks >= 5) {
        int new_bitrate = static_cast<int>(state.current_bitrate_kbps * 1.05);
        new_bitrate = std::clamp(new_bitrate, state.config.min_bitrate_kbps, state.config.max_bitrate_kbps);
        if (new_bitrate != state.current_bitrate_kbps) {
          action.new_bitrate_kbps = new_bitrate;
          action.reason = "fallback: probe_up";
        }
      }
    }

    return action;
  }

  void
  enable(const std::string &client_name, const config_t &cfg, int initial_bitrate_kbps, const std::string &app_name) {
    std::lock_guard lock(sessions_mutex);

    auto &state = sessions[client_name];
    state.config = cfg;
    state.config.enabled = true;
    state.initial_bitrate_kbps = initial_bitrate_kbps;
    state.current_bitrate_kbps = initial_bitrate_kbps;
    state.app_name = app_name;
    state.consecutive_high_loss = 0;
    state.stable_ticks = 0;
    // Apply mode presets only for bounds that were not explicitly configured.
    // This preserves a client/host maxBitrate cap when minBitrate is omitted.
    if (state.config.min_bitrate_kbps <= 0 || state.config.max_bitrate_kbps <= 0) {
      int preset_min_bitrate_kbps = 0;
      int preset_max_bitrate_kbps = 0;
      switch (cfg.mode) {
        case mode_e::QUALITY:
          preset_min_bitrate_kbps = std::max(5000, initial_bitrate_kbps / 2);
          preset_max_bitrate_kbps = std::min(150000, initial_bitrate_kbps * 3 / 2);
          break;
        case mode_e::LOW_LATENCY:
          preset_min_bitrate_kbps = 2000;
          preset_max_bitrate_kbps = initial_bitrate_kbps * 6 / 5;
          break;
        case mode_e::BALANCED:
        default:
          preset_min_bitrate_kbps = std::max(3000, initial_bitrate_kbps * 3 / 10);
          preset_max_bitrate_kbps = std::min(150000, initial_bitrate_kbps * 2);
          break;
      }
      if (state.config.min_bitrate_kbps <= 0) {
        state.config.min_bitrate_kbps = preset_min_bitrate_kbps;
      }
      if (state.config.max_bitrate_kbps <= 0) {
        state.config.max_bitrate_kbps = preset_max_bitrate_kbps;
      }
      // Guard against inverted range when initial_bitrate is very low
      if (state.config.min_bitrate_kbps > state.config.max_bitrate_kbps) {
        state.config.min_bitrate_kbps = state.config.max_bitrate_kbps;
      }
    }

    // Clamp current bitrate to the computed range
    state.current_bitrate_kbps = std::clamp(
      state.current_bitrate_kbps,
      state.config.min_bitrate_kbps,
      state.config.max_bitrate_kbps);

    BOOST_LOG(info) << "ABR enabled for client '" << client_name
                    << "': app=" << app_name
                    << " mode=" << mode_to_string(cfg.mode)
                    << " bitrate=" << initial_bitrate_kbps
                    << " range=[" << state.config.min_bitrate_kbps
                    << "," << state.config.max_bitrate_kbps << "] Kbps";
  }

  void
  disable(const std::string &client_name) {
    std::lock_guard lock(sessions_mutex);
    sessions.erase(client_name);
    BOOST_LOG(info) << "ABR disabled for client '" << client_name << "'";
  }

  bool
  is_enabled(const std::string &client_name) {
    std::lock_guard lock(sessions_mutex);
    auto it = sessions.find(client_name);
    return it != sessions.end() && it->second.config.enabled;
  }

  action_t
  process_feedback(const std::string &client_name, const network_feedback_t &raw_feedback) {
    auto feedback = sanitize_feedback(raw_feedback);

    std::lock_guard lock(sessions_mutex);

    auto it = sessions.find(client_name);
    if (it == sessions.end() || !it->second.config.enabled) {
      return { .reason = "ABR not enabled" };
    }

    auto &state = it->second;
    auto now = std::chrono::steady_clock::now();

    // Update current bitrate from client report, clamped to session range
    if (feedback.current_bitrate_kbps > 0) {
      state.current_bitrate_kbps = std::clamp(
        feedback.current_bitrate_kbps,
        state.config.min_bitrate_kbps,
        state.config.max_bitrate_kbps);
    }

    action_t result_action;
    auto since_last_fallback = std::chrono::duration_cast<std::chrono::seconds>(now - state.last_fallback_time).count();
    bool can_fallback = since_last_fallback >= session_state_t::FALLBACK_INTERVAL_SECONDS;

    // Emergency: high packet loss — immediate, no rate limit
    if (feedback.packet_loss > 5.0) {
      auto action = fallback_decision(state, feedback);
      if (action.new_bitrate_kbps > 0) {
        state.current_bitrate_kbps = action.new_bitrate_kbps;
        state.last_fallback_time = now;
        result_action = action;
      }
      return result_action;
    }

    // Regular fallback: moderate loss, probe-up, etc.
    if (can_fallback) {
      state.last_fallback_time = now;
      auto action = fallback_decision(state, feedback);
      if (action.new_bitrate_kbps > 0) {
        if (action.new_bitrate_kbps > 0) {
          state.current_bitrate_kbps = action.new_bitrate_kbps;
          BOOST_LOG(info) << "ABR fallback for '" << client_name
                          << "': " << action.new_bitrate_kbps << " Kbps"
                          << " (" << action.reason << ")";
          result_action = action;
        }
      }
    }

    return result_action;
  }

  capabilities_t
  get_capabilities() {
    return { true, 1 };
  }

  void
  cleanup(const std::string &client_name) {
    disable(client_name);
  }

}  // namespace abr

#ifdef SUNSHINE_TESTS
  #include <gtest/gtest.h>

namespace {

  abr::session_state_t
  make_test_session_state(int current_bitrate_kbps = 20000, int min_bitrate_kbps = 10000, int max_bitrate_kbps = 50000) {
    abr::session_state_t state;
    state.current_bitrate_kbps = current_bitrate_kbps;
    state.config.min_bitrate_kbps = min_bitrate_kbps;
    state.config.max_bitrate_kbps = max_bitrate_kbps;
    return state;
  }

}  // namespace

TEST(AbrConfigTests, PreservesExplicitMaxBitrateWhenMinIsOmitted) {
  abr::config_t cfg;
  cfg.enabled = true;
  cfg.min_bitrate_kbps = 0;
  cfg.max_bitrate_kbps = 15000;
  cfg.mode = abr::mode_e::BALANCED;

  const std::string client_name = "abr-max-cap-test";
  abr::enable(client_name, cfg, 50000, "Test Game");

  auto action = abr::process_feedback(client_name, {
    .packet_loss = 6.0,
    .rtt_ms = 10.0,
    .decode_fps = 60.0,
    .dropped_frames = 0,
    .current_bitrate_kbps = 50000,
  });

  EXPECT_GT(action.new_bitrate_kbps, 0);
  EXPECT_LE(action.new_bitrate_kbps, cfg.max_bitrate_kbps);

  abr::cleanup(client_name);
}

#endif
