#ifndef RUNNER_RASPBERRY_RECEIVER_H_
#define RUNNER_RASPBERRY_RECEIVER_H_

#include <string>
#include <vector>

struct RaspberryFrameSummary {
  std::string remote_address;
  int remote_port = 0;
  std::string debug_status;
  std::string time_str;
  std::string frame_id;
  int shape_rows = 0;
  int shape_cols = 0;
  int payload_bytes = 0;
  int value_count = 0;
  float min_value = 0.0f;
  float max_value = 0.0f;
  float mean_value = 0.0f;
  float center_value = 0.0f;
  std::vector<float> values;
};

bool ReceiveSingleRaspberryFrame(const std::string& host,
                                 int port,
                                 int timeout_ms,
                                 RaspberryFrameSummary& summary,
                                 std::string& error);

#endif  // RUNNER_RASPBERRY_RECEIVER_H_
