#include "instrument_controller.h"

#include <algorithm>
#include <chrono>
#include <sstream>
#include <stdexcept>

namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;

std::string FormatDouble(double value, int precision = 2) {
  std::ostringstream stream;
  stream.setf(std::ios::fixed);
  stream.precision(precision);
  stream << value;
  return stream.str();
}

std::vector<double> BuildVoltagePoints(double start, double end, double step) {
  if (step <= 0) {
    throw std::runtime_error("Voltage step must be greater than 0.");
  }
  if (end < start) {
    throw std::runtime_error("Voltage end must be greater than or equal to voltage start.");
  }

  std::vector<double> points;
  const double epsilon = step / 1000.0;
  for (double current = start; current <= end + epsilon; current += step) {
    points.push_back(std::min(current, end));
  }
  return points;
}

double PeriodUsToFrequency(double period_us) {
  if (period_us <= 0) {
    throw std::runtime_error("Period must be greater than 0.");
  }
  return 1000000.0 / period_us;
}
void SetOutput(IScpiTransport& transport, bool enabled) {
  transport.WriteLine(enabled ? "OUTP1 ON" : "OUTP1 OFF");
}

void SetSquareWave(IScpiTransport& transport, double frequency, double vpp,
                   double offset, double duty) {
  transport.WriteLine("*CLS");
  transport.WriteLine("SYST:REM");
  transport.WriteLine("OUTP1:LOAD INF");
  transport.WriteLine("SOUR1:APPL:SQU " + FormatDouble(frequency, 6) + "," +
                      FormatDouble(vpp, 6) + "," + FormatDouble(offset, 6));
  transport.WriteLine("SOUR1:SQU:DCYC " + FormatDouble(duty, 3));
}

}  // namespace

InstrumentController::InstrumentController()
    : running_(false), stop_requested_(false) {}

InstrumentController::~InstrumentController() {
  Shutdown();
}

flutter::EncodableValue InstrumentController::Identify(
    const flutter::EncodableMap& arguments) {
  EncodableList logs;
  try {
    const std::string transport_type = GetString(arguments, "transportType");
    const std::string target = GetString(arguments, "target");
    auto transport = CreateScpiTransport(transport_type, target);
    const std::string idn = transport->Identify();
    EncodableMap log1;
    log1[EncodableValue("level")] = EncodableValue("info");
    log1[EncodableValue("message")] =
        EncodableValue("Connected target: " + transport->DisplayTarget());
    logs.push_back(EncodableValue(log1));
    EncodableMap log2;
    log2[EncodableValue("level")] = EncodableValue("info");
    log2[EncodableValue("message")] = EncodableValue("IDN: " + idn);
    logs.push_back(EncodableValue(log2));

    EncodableMap result = BuildResult(true, "Handshake completed.");
    result[EncodableValue("logs")] = EncodableValue(logs);
    return EncodableValue(result);
  } catch (const std::exception& error) {
    EncodableMap log;
    log[EncodableValue("level")] = EncodableValue("error");
    log[EncodableValue("message")] =
        EncodableValue(std::string("Transport Error: ") + error.what());
    logs.push_back(EncodableValue(log));

    EncodableMap result = BuildResult(false, error.what());
    result[EncodableValue("logs")] = EncodableValue(logs);
    return EncodableValue(result);
  }
}

flutter::EncodableValue InstrumentController::StartSweep(
    const flutter::EncodableMap& arguments) {
  if (running_) {
    return EncodableValue(BuildResult(false, "Sweep already running."));
  }

  SweepConfig config = {
      GetString(arguments, "transportType"),  GetString(arguments, "target"),
      GetDouble(arguments, "periodUs"),       GetDouble(arguments, "voltageStart"),
      GetDouble(arguments, "voltageEnd"),     GetDouble(arguments, "voltageStep"),
      GetDouble(arguments, "onTimeSeconds"),  GetDouble(arguments, "offTimeSeconds"),
      GetDouble(arguments, "dutyRatio"),
  };

  {
    std::lock_guard<std::mutex> lock(logs_mutex_);
    pending_logs_.clear();
  }

  stop_requested_ = false;
  running_ = true;
  if (worker_.joinable()) {
    worker_.join();
  }
  worker_ = std::thread(&InstrumentController::RunSweep, this, config);
  return EncodableValue(BuildResult(true, "Sweep started."));
}

flutter::EncodableValue InstrumentController::StopSweep() {
  stop_requested_ = true;
  AddLog("warning", "Stop requested. Waiting for output off.");
  return EncodableValue(BuildResult(true, "Stop requested."));
}

flutter::EncodableValue InstrumentController::FetchLogs() {
  EncodableList logs;
  {
    std::lock_guard<std::mutex> lock(logs_mutex_);
    logs.swap(pending_logs_);
  }

  EncodableMap result;
  result[EncodableValue("logs")] = EncodableValue(logs);
  result[EncodableValue("running")] = EncodableValue(running_.load());
  return EncodableValue(result);
}

void InstrumentController::Shutdown() {
  stop_requested_ = true;
  if (worker_.joinable()) {
    worker_.join();
  }
}

void InstrumentController::AddLog(const std::string& level,
                                  const std::string& message) {
  EncodableMap log;
  log[EncodableValue("level")] = EncodableValue(level);
  log[EncodableValue("message")] = EncodableValue(message);

  std::lock_guard<std::mutex> lock(logs_mutex_);
  pending_logs_.push_back(EncodableValue(log));
}

void InstrumentController::RunSweep(SweepConfig config) {
  try {
    auto transport = CreateScpiTransport(config.transport_type, config.target);
    const std::string idn = transport->Identify();
    const double frequency = PeriodUsToFrequency(config.period_us);
    const double duty_percent = config.duty_ratio * 100.0;
    const auto points = BuildVoltagePoints(config.voltage_start, config.voltage_end,
                                           config.voltage_step);

    AddLog("info", "Connected target: " + transport->DisplayTarget());
    AddLog("info", "IDN: " + idn);
    AddLog("info", "Period: " + FormatDouble(config.period_us, 3) + " us");
    AddLog("info", "Frequency: " + FormatDouble(frequency, 3) + " Hz");
    AddLog("info", "Duty: " + FormatDouble(duty_percent, 2) + " %");

    for (size_t index = 0; index < points.size(); ++index) {
      if (stop_requested_) {
        AddLog("warning", "Stop requested before next step.");
        break;
      }

      SetOutput(*transport, false);
      if (SleepWithStopCheck(config.off_time)) {
        AddLog("warning", "Stop requested during off-time.");
        break;
      }

      const double vpp = points[index];
      const double offset = vpp / 2.0;
      SetSquareWave(*transport, frequency, vpp, offset, duty_percent);
      SetOutput(*transport, true);
      AddLog("info", "Step " + std::to_string(index + 1) + ": Vpp=" +
                         FormatDouble(vpp, 2) + " V, Offset=" +
                         FormatDouble(offset, 2) + " V");

      if (SleepWithStopCheck(config.on_time)) {
        AddLog("warning", "Stop requested during on-time.");
        break;
      }
    }

    SetOutput(*transport, false);
    AddLog("info", "Output stopped.");
  } catch (const std::exception& error) {
    AddLog("error", std::string("Transport Error: ") + error.what());
  }

  running_ = false;
  stop_requested_ = false;
}

bool InstrumentController::SleepWithStopCheck(double seconds) {
  auto end = std::chrono::steady_clock::now() +
             std::chrono::milliseconds(static_cast<int>(std::max(seconds, 0.0) * 1000));
  while (std::chrono::steady_clock::now() < end) {
    if (stop_requested_) {
      return true;
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(50));
  }
  return stop_requested_;
}

flutter::EncodableMap InstrumentController::BuildResult(bool success,
                                                        const std::string& summary) {
  EncodableMap result;
  result[EncodableValue("success")] = EncodableValue(success);
  result[EncodableValue("summary")] = EncodableValue(summary);
  return result;
}

std::string InstrumentController::GetString(const flutter::EncodableMap& arguments,
                                            const char* key) {
  const auto it = arguments.find(EncodableValue(key));
  if (it == arguments.end()) {
    throw std::runtime_error(std::string("Missing argument: ") + key);
  }
  return std::get<std::string>(it->second);
}

double InstrumentController::GetDouble(const flutter::EncodableMap& arguments,
                                       const char* key) {
  const auto it = arguments.find(EncodableValue(key));
  if (it == arguments.end()) {
    throw std::runtime_error(std::string("Missing argument: ") + key);
  }
  if (const auto* int_value = std::get_if<int32_t>(&(it->second))) {
    return static_cast<double>(*int_value);
  }
  if (const auto* long_value = std::get_if<int64_t>(&(it->second))) {
    return static_cast<double>(*long_value);
  }
  if (const auto* double_value = std::get_if<double>(&(it->second))) {
    return *double_value;
  }
  throw std::runtime_error(std::string("Invalid numeric argument: ") + key);
}
