#ifndef RUNNER_INSTRUMENT_CONTROLLER_H_
#define RUNNER_INSTRUMENT_CONTROLLER_H_

#include <flutter/encodable_value.h>

#include <atomic>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include "scpi_transport.h"

class InstrumentController {
 public:
  InstrumentController();
  ~InstrumentController();

  flutter::EncodableValue Identify(const flutter::EncodableMap& arguments);
  flutter::EncodableValue StartSweep(const flutter::EncodableMap& arguments);
  flutter::EncodableValue StopSweep();
  flutter::EncodableValue FetchLogs();
  void Shutdown();

 private:
  struct SweepConfig {
    std::string transport_type;
    std::string target;
    double period_us;
    double voltage_start;
    double voltage_end;
    double voltage_step;
    double on_time;
    double off_time;
    double duty_ratio;
  };

  std::atomic<bool> running_;
  std::atomic<bool> stop_requested_;
  std::mutex logs_mutex_;
  std::vector<flutter::EncodableValue> pending_logs_;
  std::thread worker_;

  void AddLog(const std::string& level, const std::string& message);
  void RunSweep(SweepConfig config);
  bool SleepWithStopCheck(double seconds);
  flutter::EncodableMap BuildResult(bool success, const std::string& summary);
  static std::string GetString(const flutter::EncodableMap& arguments, const char* key);
  static double GetDouble(const flutter::EncodableMap& arguments, const char* key);
};

#endif
