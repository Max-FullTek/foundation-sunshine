#include <gtest/gtest.h>
#include <nlohmann/json.hpp>
#include <utility>

#include "src/file_mapping/service.h"

TEST(FileMappingService, PersonalForkDoesNotStartOrIssueTokensEvenWithSavedMappings) {
  file_mapping::service_t service;
  file_mapping::service_t::config_t config;
  config.bind_address = "127.0.0.1";
  config.port = 0;
  config.mappings_json = R"([{"id":"old-share","path":"C:/old-share"}])";
  config.authorize_client = [](std::string_view) { return true; };
  service.start(std::move(config));

  const auto response = service.make_capability_response("paired-client", "127.0.0.1");
  const auto body = nlohmann::json::parse(response.body);
  EXPECT_FALSE(body.at("enabled").get<bool>());
  EXPECT_FALSE(body.at("listening").get<bool>());
  EXPECT_FALSE(body.at("ok").get<bool>());
  EXPECT_EQ(body.at("session_token"), "");
  EXPECT_EQ(body.at("diagnostics").at("bound_port"), "0");
  EXPECT_EQ(body.at("diagnostics").at("token"), "not_issued");
  service.stop();
}
