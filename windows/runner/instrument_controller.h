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
  flutter::EncodableValue ListResources();
  flutter::EncodableValue QueryIdn(const flutter::EncodableMap& arguments);
  flutter::EncodableValue StartResourceScan();
  flutter::EncodableValue FetchResourceScan();
  flutter::EncodableValue StartSweep(const flutter::EncodableMap& arguments);
  flutter::EncodableValue StopSweep();
  flutter::EncodableValue FetchLogs();
  void Shutdown();

 private:
  struct SweepConfig {
    std::string transport_type;
    std::string target;
    std::string drain_transport_type;
    std::string drain_target;
    std::string current_transport_type;
    std::string current_target;
    double period_us;
    double voltage_start;
    double voltage_end;
    double voltage_step;
    double drain_voltage;
    double on_time;
    double off_time;
    double duty_ratio;
    double current_measure_delay_seconds = 0.05;
    bool sync_drain_with_gate_timing = false;
    bool measure_drain_current_on_time = false;
  };

  std::atomic<bool> running_;
  std::atomic<bool> stop_requested_;
  std::atomic<bool> scan_running_;
  std::mutex logs_mutex_;
  std::mutex scan_mutex_;
  std::vector<flutter::EncodableValue> pending_logs_;
  std::vector<std::string> scan_resources_;
  std::vector<flutter::EncodableValue> scan_name_entries_;
  std::string scan_error_;
  std::thread worker_;
  std::thread scan_worker_;

  void AddLog(const std::string& level, const std::string& message);
  void RunResourceScan();
  void RunSweep(SweepConfig config);
  bool SleepWithStopCheck(double seconds);
  std::string QueryCurrentOnTime(IScpiTransport& transport);
  flutter::EncodableMap BuildResult(bool success, const std::string& summary);
  static std::string GetString(const flutter::EncodableMap& arguments, const char* key);
  static double GetDouble(const flutter::EncodableMap& arguments, const char* key);
  static bool GetBool(const flutter::EncodableMap& arguments, const char* key);
  static bool HasString(const flutter::EncodableMap& arguments, const char* key);
  static bool HasBool(const flutter::EncodableMap& arguments, const char* key);
  static bool HasDouble(const flutter::EncodableMap& arguments, const char* key);
};

#endif
