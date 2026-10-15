#include <boost/log/sources/severity_logger.hpp>

#include "src/config.h"

boost::log::sources::severity_logger<int> verbose;
boost::log::sources::severity_logger<int> debug;
boost::log::sources::severity_logger<int> info;
boost::log::sources::severity_logger<int> warning;
boost::log::sources::severity_logger<int> error;
boost::log::sources::severity_logger<int> fatal;
#ifdef SUNSHINE_TESTS
boost::log::sources::severity_logger<int> tests;
#endif

namespace config {
  video_t video;
  audio_t audio;
  stream_t stream;
  nvhttp_t nvhttp;
  input_t input;
  sunshine_t sunshine;
}  // namespace config
