#include "instrument_controller.h"

#include <algorithm>
#include <chrono>
#include <sstream>
#include <stdexcept>
#include <windows.h>

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

using ViStatus = long;
using ViSession = unsigned long;
using ViFindList = unsigned long;
using ViUInt32 = unsigned long;
using ViChar = char;

constexpr ViStatus kViSuccess = 0;
constexpr ViUInt32 kViAttrTmoValue = 0x3FFF001A;

using ViOpenDefaultRMFn = ViStatus(__stdcall*)(ViSession*);
using ViCloseFn = ViStatus(__stdcall*)(ViSession);
using ViFindRsrcFn =
    ViStatus(__stdcall*)(ViSession, const ViChar*, ViFindList*, ViUInt32*, ViChar[]);
using ViFindNextFn = ViStatus(__stdcall*)(ViFindList, ViChar[]);
using ViOpenFn =
    ViStatus(__stdcall*)(ViSession, const ViChar*, ViUInt32, ViUInt32, ViSession*);
using ViSetAttributeFn = ViStatus(__stdcall*)(ViSession, ViUInt32, ViUInt32);
using ViWriteFn =
    ViStatus(__stdcall*)(ViSession, const unsigned char*, ViUInt32, ViUInt32*);
using ViReadFn =
    ViStatus(__stdcall*)(ViSession, unsigned char*, ViUInt32, ViUInt32*);

struct VisaApi {
  HMODULE dll = nullptr;
  ViOpenDefaultRMFn open_default_rm = nullptr;
  ViCloseFn close = nullptr;
  ViFindRsrcFn find_rsrc = nullptr;
  ViFindNextFn find_next = nullptr;
  ViOpenFn open = nullptr;
  ViSetAttributeFn set_attribute = nullptr;
  ViWriteFn write = nullptr;
  ViReadFn read = nullptr;
};

VisaApi& GetVisaApi() {
  static VisaApi api;
  static bool loaded = false;
  if (!loaded) {
    api.dll = ::LoadLibraryW(L"visa64.dll");
    if (!api.dll) {
      api.dll = ::LoadLibraryW(L"visa32.dll");
    }
    if (!api.dll) {
      throw std::runtime_error("NI-VISA DLL (visa64.dll/visa32.dll) not found.");
    }
    api.open_default_rm = reinterpret_cast<ViOpenDefaultRMFn>(
        ::GetProcAddress(api.dll, "viOpenDefaultRM"));
    api.close = reinterpret_cast<ViCloseFn>(::GetProcAddress(api.dll, "viClose"));
    api.find_rsrc =
        reinterpret_cast<ViFindRsrcFn>(::GetProcAddress(api.dll, "viFindRsrc"));
    api.find_next =
        reinterpret_cast<ViFindNextFn>(::GetProcAddress(api.dll, "viFindNext"));
    api.open = reinterpret_cast<ViOpenFn>(::GetProcAddress(api.dll, "viOpen"));
    api.set_attribute = reinterpret_cast<ViSetAttributeFn>(
        ::GetProcAddress(api.dll, "viSetAttribute"));
    api.write = reinterpret_cast<ViWriteFn>(::GetProcAddress(api.dll, "viWrite"));
    api.read = reinterpret_cast<ViReadFn>(::GetProcAddress(api.dll, "viRead"));
    if (!api.open_default_rm || !api.close || !api.find_rsrc || !api.find_next ||
        !api.open || !api.set_attribute || !api.write || !api.read) {
      throw std::runtime_error("Failed to load NI-VISA symbols.");
    }
    loaded = true;
  }
  return api;
}

std::vector<std::string> ListVisaResources() {
  auto& api = GetVisaApi();
  std::vector<std::string> out;
  ViSession rm = 0;
  ViFindList find_list = 0;
  ViUInt32 count = 0;
  ViChar desc[256] = {};

  auto rm_status = api.open_default_rm(&rm);
  if (rm_status < kViSuccess) {
    throw std::runtime_error("viOpenDefaultRM failed: " + std::to_string(rm_status));
  }
  auto find_status = api.find_rsrc(rm, const_cast<ViChar*>("?*INSTR"), &find_list,
                                   &count, desc);
  if (find_status < kViSuccess) {
    api.close(rm);
    throw std::runtime_error("viFindRsrc failed: " + std::to_string(find_status));
  }
  out.emplace_back(desc);
  for (ViUInt32 i = 1; i < count; ++i) {
    auto next_status = api.find_next(find_list, desc);
    if (next_status < kViSuccess) {
      break;
    }
    out.emplace_back(desc);
  }
  api.close(find_list);
  api.close(rm);
  return out;
}

std::string QueryVisaIdn(const std::string& resource, int timeout_ms = 3000) {
  auto& api = GetVisaApi();
  ViSession rm = 0;
  ViSession inst = 0;
  auto rm_status = api.open_default_rm(&rm);
  if (rm_status < kViSuccess) {
    throw std::runtime_error("viOpenDefaultRM failed: " + std::to_string(rm_status));
  }
  auto open_status =
      api.open(rm, const_cast<ViChar*>(resource.c_str()), 0, timeout_ms, &inst);
  if (open_status < kViSuccess) {
    api.close(rm);
    throw std::runtime_error("viOpen failed: " + std::to_string(open_status));
  }
  api.set_attribute(inst, kViAttrTmoValue, static_cast<ViUInt32>(timeout_ms));
  const std::string command = "*IDN?\n";
  ViUInt32 written = 0;
  auto write_status = api.write(
      inst, reinterpret_cast<const unsigned char*>(command.c_str()),
      static_cast<ViUInt32>(command.size()), &written);
  if (write_status < kViSuccess) {
    api.close(inst);
    api.close(rm);
    throw std::runtime_error("viWrite failed: " + std::to_string(write_status));
  }
  unsigned char buffer[2048] = {};
  ViUInt32 read = 0;
  auto read_status = api.read(inst, buffer, sizeof(buffer) - 1, &read);
  api.close(inst);
  api.close(rm);
  if (read_status < kViSuccess) {
    throw std::runtime_error("viRead failed: " + std::to_string(read_status));
  }
  return std::string(reinterpret_cast<char*>(buffer), read);
}
void SetGeneratorOutput(IScpiTransport& transport, bool enabled) {
  transport.WriteLine(enabled ? "OUTP1 ON" : "OUTP1 OFF");
}

void SetSourceMeterOutput(IScpiTransport& transport, bool enabled) {
  transport.WriteLine(enabled ? "OUTP ON" : "OUTP OFF");
}

void SetDcVoltage(IScpiTransport& transport, double voltage) {
  transport.WriteLine("*CLS");
  transport.WriteLine("SYST:REM");
  transport.WriteLine("SOUR:FUNC VOLT");
  transport.WriteLine("SOUR:VOLT " + FormatDouble(voltage, 6));
}

void ConfigureSourceMeter(IScpiTransport& transport, double current_limit_amps) {
  transport.WriteLine("*CLS");
  transport.WriteLine("SYST:REM");
  transport.WriteLine("SOUR:FUNC VOLT");
  transport.WriteLine("SENS:CURR:RANG:AUTO ON");
  transport.WriteLine("SOUR:VOLT:ILIM " + FormatDouble(current_limit_amps, 6));
  transport.WriteLine("SOUR:VOLT 0");
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

double ParseReading(const std::string& response, const char* label) {
  size_t processed = 0;
  const double value = std::stod(response, &processed);
  if (processed == 0) {
    throw std::runtime_error(std::string("Failed to parse ") + label + " response.");
  }
  return value;
}

}  // namespace

InstrumentController::InstrumentController()
    : running_(false), stop_requested_(false), scan_running_(false) {}

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

flutter::EncodableValue InstrumentController::ListResources() {
  EncodableList resources;
  for (const auto& item : ListVisaResources()) {
    resources.push_back(EncodableValue(item));
  }
  return EncodableValue(resources);
}

flutter::EncodableValue InstrumentController::QueryIdn(
    const flutter::EncodableMap& arguments) {
  EncodableMap result;
  const std::string resource = GetString(arguments, "resource");
  result[EncodableValue("resource")] = EncodableValue(resource);
  result[EncodableValue("idn")] = EncodableValue(QueryVisaIdn(resource));
  return EncodableValue(result);
}

flutter::EncodableValue InstrumentController::StartResourceScan() {
  if (scan_running_) {
    EncodableMap result;
    result[EncodableValue("started")] = EncodableValue(false);
    result[EncodableValue("running")] = EncodableValue(true);
    return EncodableValue(result);
  }

  if (scan_worker_.joinable()) {
    scan_worker_.join();
  }

  {
    std::lock_guard<std::mutex> lock(scan_mutex_);
    scan_resources_.clear();
    scan_name_entries_.clear();
    scan_error_.clear();
  }

  scan_running_ = true;
  scan_worker_ = std::thread(&InstrumentController::RunResourceScan, this);

  EncodableMap result;
  result[EncodableValue("started")] = EncodableValue(true);
  result[EncodableValue("running")] = EncodableValue(true);
  return EncodableValue(result);
}

flutter::EncodableValue InstrumentController::FetchResourceScan() {
  EncodableMap result;
  result[EncodableValue("running")] = EncodableValue(scan_running_.load());

  {
    std::lock_guard<std::mutex> lock(scan_mutex_);
    EncodableList resources;
    for (const auto& resource : scan_resources_) {
      resources.push_back(EncodableValue(resource));
    }
    result[EncodableValue("resources")] = EncodableValue(resources);
    result[EncodableValue("names")] = EncodableValue(scan_name_entries_);
    if (!scan_error_.empty()) {
      result[EncodableValue("error")] = EncodableValue(scan_error_);
    }
  }

  return EncodableValue(result);
}

flutter::EncodableValue InstrumentController::StartSweep(
    const flutter::EncodableMap& arguments) {
  if (running_) {
    return EncodableValue(BuildResult(false, "Sweep already running."));
  }

  SweepConfig config = {
      GetString(arguments, "transportType"),
      GetString(arguments, "target"),
      HasString(arguments, "drainTransportType")
          ? GetString(arguments, "drainTransportType")
          : "",
      HasString(arguments, "drainTarget") ? GetString(arguments, "drainTarget") : "",
      HasString(arguments, "currentTransportType")
          ? GetString(arguments, "currentTransportType")
          : "",
      HasString(arguments, "currentTarget") ? GetString(arguments, "currentTarget") : "",
      GetDouble(arguments, "periodUs"),
      GetDouble(arguments, "voltageStart"),
      GetDouble(arguments, "voltageEnd"),
      GetDouble(arguments, "voltageStep"),
      HasDouble(arguments, "drainVoltage") ? GetDouble(arguments, "drainVoltage") : 0.0,
      HasDouble(arguments, "drainCurrentLimitAmps")
          ? GetDouble(arguments, "drainCurrentLimitAmps")
          : 1.0,
      GetDouble(arguments, "onTimeSeconds"),
      GetDouble(arguments, "offTimeSeconds"),
      GetDouble(arguments, "dutyRatio"),
      HasDouble(arguments, "currentMeasureDelaySeconds")
          ? GetDouble(arguments, "currentMeasureDelaySeconds")
          : 0.05,
      HasBool(arguments, "syncDrainWithGateTiming")
          ? GetBool(arguments, "syncDrainWithGateTiming")
          : false,
      HasBool(arguments, "measureDrainCurrentOnTime")
          ? GetBool(arguments, "measureDrainCurrentOnTime")
          : false,
      HasBool(arguments, "voltageDropProtect")
          ? GetBool(arguments, "voltageDropProtect")
          : false,
      HasDouble(arguments, "voltageDropThresholdVolts")
          ? GetDouble(arguments, "voltageDropThresholdVolts")
          : 1.0,
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
  if (scan_worker_.joinable()) {
    scan_worker_.join();
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

void InstrumentController::RunResourceScan() {
  try {
    const auto resources = ListVisaResources();
    {
      std::lock_guard<std::mutex> lock(scan_mutex_);
      scan_resources_ = resources;
      scan_name_entries_.clear();
      scan_error_.clear();
      for (const auto& resource : resources) {
        EncodableMap entry;
        entry[EncodableValue("resource")] = EncodableValue(resource);
        entry[EncodableValue("name")] = EncodableValue(resource);
        scan_name_entries_.push_back(EncodableValue(entry));
      }
    }

    for (size_t i = 0; i < resources.size(); ++i) {
      try {
        const auto idn = QueryVisaIdn(resources[i]);
        std::lock_guard<std::mutex> lock(scan_mutex_);
        EncodableMap entry;
        entry[EncodableValue("resource")] = EncodableValue(resources[i]);
        entry[EncodableValue("name")] = EncodableValue(idn);
        scan_name_entries_[i] = EncodableValue(entry);
      } catch (...) {
      }
    }
  } catch (const std::exception& error) {
    std::lock_guard<std::mutex> lock(scan_mutex_);
    scan_error_ = error.what();
  }
  scan_running_ = false;
}

void InstrumentController::RunSweep(SweepConfig config) {
  if (config.sync_drain_with_gate_timing && config.measure_drain_current_on_time &&
      !config.drain_target.empty()) {
    RunIdVgsPulseSweep(config);
    return;
  }

  try {
    auto transport = CreateScpiTransport(config.transport_type, config.target);
    std::unique_ptr<IScpiTransport> drain_transport;
    if (config.sync_drain_with_gate_timing && !config.drain_target.empty() &&
        !config.drain_transport_type.empty()) {
      drain_transport =
          CreateScpiTransport(config.drain_transport_type, config.drain_target);
    }
    std::unique_ptr<IScpiTransport> current_transport;
    if (config.measure_drain_current_on_time && !config.current_target.empty() &&
        !config.current_transport_type.empty()) {
      current_transport =
          CreateScpiTransport(config.current_transport_type, config.current_target);
    }
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
    if (drain_transport != nullptr) {
      SetDcVoltage(*drain_transport, config.drain_voltage);
      SetSourceMeterOutput(*drain_transport, false);
      AddLog("info", "Drain timing follows Gate Setting On/Off using " +
                         drain_transport->DisplayTarget());
    }

    for (size_t index = 0; index < points.size(); ++index) {
      if (stop_requested_) {
        AddLog("warning", "Stop requested before next step.");
        break;
      }

      SetGeneratorOutput(*transport, false);
      if (drain_transport != nullptr) {
        SetSourceMeterOutput(*drain_transport, false);
      }
      if (SleepWithStopCheck(config.off_time)) {
        AddLog("warning", "Stop requested during off-time.");
        break;
      }

      const double vpp = points[index];
      const double offset = vpp / 2.0;
      SetSquareWave(*transport, frequency, vpp, offset, duty_percent);
      SetGeneratorOutput(*transport, true);
      if (drain_transport != nullptr) {
        SetDcVoltage(*drain_transport, config.drain_voltage);
        SetSourceMeterOutput(*drain_transport, true);
      }
      AddLog("info", "Step " + std::to_string(index + 1) + ": Vpp=" +
                         FormatDouble(vpp, 2) + " V, Offset=" +
                         FormatDouble(offset, 2) + " V");

      if (current_transport != nullptr) {
        const double settle_seconds =
            std::min(std::max(config.current_measure_delay_seconds, 0.0), config.on_time);
        if (SleepWithStopCheck(settle_seconds)) {
          AddLog("warning", "Stop requested before on-time current measurement.");
          break;
        }
        try {
          const std::string current_reading = QueryCurrentOnTime(*current_transport);
          AddLog("info", "Drain current during on-time: " + current_reading);
        } catch (const std::exception& error) {
          AddLog("warning", std::string("Drain current read failed during on-time: ") +
                                error.what());
        }
        const double remaining_on_time = std::max(config.on_time - settle_seconds, 0.0);
        if (SleepWithStopCheck(remaining_on_time)) {
          AddLog("warning", "Stop requested during on-time.");
          break;
        }
        SetGeneratorOutput(*transport, false);
        if (drain_transport != nullptr) {
          SetSourceMeterOutput(*drain_transport, false);
        }
        continue;
      }

      if (SleepWithStopCheck(config.on_time)) {
        AddLog("warning", "Stop requested during on-time.");
        break;
      }
      SetGeneratorOutput(*transport, false);
      if (drain_transport != nullptr) {
        SetSourceMeterOutput(*drain_transport, false);
      }
    }

    SetGeneratorOutput(*transport, false);
    if (drain_transport != nullptr) {
      SetSourceMeterOutput(*drain_transport, false);
    }
    AddLog("info", "Output stopped.");
  } catch (const std::exception& error) {
    AddLog("error", std::string("Transport Error: ") + error.what());
  }

  running_ = false;
  stop_requested_ = false;
}

void InstrumentController::RunIdVgsPulseSweep(SweepConfig config) {
  IScpiTransport* gate_output = nullptr;
  IScpiTransport* drain_output = nullptr;
  try {
    auto gate_transport = CreateScpiTransport(config.transport_type, config.target);
    auto drain_transport =
        CreateScpiTransport(config.drain_transport_type, config.drain_target);
    gate_output = gate_transport.get();
    drain_output = drain_transport.get();

    IScpiTransport* current_transport = drain_transport.get();
    std::unique_ptr<IScpiTransport> dedicated_current_transport;
    if (!config.current_target.empty() && !config.current_transport_type.empty() &&
        !(config.current_target == config.drain_target &&
          config.current_transport_type == config.drain_transport_type)) {
      dedicated_current_transport =
          CreateScpiTransport(config.current_transport_type, config.current_target);
      current_transport = dedicated_current_transport.get();
    }

    const std::string gate_idn = gate_transport->Identify();
    const std::string drain_idn = drain_transport->Identify();
    const double frequency = PeriodUsToFrequency(config.period_us);
    const double duty_percent = config.duty_ratio * 100.0;
    const auto points =
        BuildVoltagePoints(config.voltage_start, config.voltage_end, config.voltage_step);

    AddLog("info", "Id-Vgs pulse sweep uses dedicated Gate/Drain timing control.");
    AddLog("info", "Gate target: " + gate_transport->DisplayTarget());
    AddLog("info", "Gate IDN: " + gate_idn);
    AddLog("info", "Drain source meter: " + drain_transport->DisplayTarget());
    AddLog("info", "Drain IDN: " + drain_idn);
    if (current_transport == drain_transport.get()) {
      AddLog("info", "Drain current is measured from the drain source meter.");
    } else {
      AddLog("info", "Current measurement target: " + current_transport->DisplayTarget());
    }

    ConfigureSourceMeter(*drain_transport, config.drain_current_limit_amps);
    SetSourceMeterOutput(*drain_transport, false);
    SetDcVoltage(*drain_transport, config.drain_voltage);
    SetGeneratorOutput(*gate_transport, false);

    for (size_t index = 0; index < points.size(); ++index) {
      if (stop_requested_) {
        AddLog("warning", "Stop requested before next Id-Vgs point.");
        break;
      }

      SetGeneratorOutput(*gate_transport, false);
      SetSourceMeterOutput(*drain_transport, false);
      if (SleepWithStopCheck(config.off_time)) {
        AddLog("warning", "Stop requested during gate/drain off-time.");
        break;
      }

      const double gate_high = points[index];
      const double offset = gate_high / 2.0;
      SetSquareWave(*gate_transport, frequency, gate_high, offset, duty_percent);
      SetDcVoltage(*drain_transport, config.drain_voltage);
      SetSourceMeterOutput(*drain_transport, true);
      SetGeneratorOutput(*gate_transport, true);
      AddLog("info", "Step " + std::to_string(index + 1) + ": Gate high=" +
                         FormatDouble(gate_high, 3) + " V, Drain=" +
                         FormatDouble(config.drain_voltage, 3) + " V");

      const double settle_seconds =
          std::min(std::max(config.current_measure_delay_seconds, 0.0), config.on_time);
      if (SleepWithStopCheck(settle_seconds)) {
        AddLog("warning", "Stop requested before on-time current measurement.");
        break;
      }

      const std::string current_response = QueryCurrentOnTime(*current_transport);
      const double drain_current = ParseReading(current_response, "current");
      AddLog("info", "Drain current during on-time: " +
                         FormatDouble(drain_current, 6) + " A");

      if (config.voltage_drop_protect) {
        const std::string drain_voltage_response = QueryVoltage(*drain_transport);
        const double measured_drain_voltage =
            ParseReading(drain_voltage_response, "drain voltage");
        const double voltage_drop = config.drain_voltage - measured_drain_voltage;
        AddLog("info", "Measured drain voltage: " +
                           FormatDouble(measured_drain_voltage, 6) + " V");
        if (voltage_drop > config.voltage_drop_threshold_volts) {
          AddLog("warning", "Voltage protection triggered. Drain drop=" +
                                FormatDouble(voltage_drop, 6) + " V");
          break;
        }
      }

      const double remaining_on_time = std::max(config.on_time - settle_seconds, 0.0);
      if (SleepWithStopCheck(remaining_on_time)) {
        AddLog("warning", "Stop requested during gate/drain on-time.");
        break;
      }

      SetGeneratorOutput(*gate_transport, false);
      SetSourceMeterOutput(*drain_transport, false);
    }

    SetGeneratorOutput(*gate_transport, false);
    SetSourceMeterOutput(*drain_transport, false);
    AddLog("info", "Id-Vgs pulse sweep finished with outputs off.");
  } catch (const std::exception& error) {
    try {
      if (gate_output != nullptr) {
        SetGeneratorOutput(*gate_output, false);
      }
    } catch (...) {
    }
    try {
      if (drain_output != nullptr) {
        SetSourceMeterOutput(*drain_output, false);
      }
    } catch (...) {
    }
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

std::string InstrumentController::QueryCurrentOnTime(IScpiTransport& transport) {
  transport.WriteLine("MEAS:CURR?");
  auto response = transport.ReadLine();
  if (!response.empty()) {
    return response;
  }
  transport.WriteLine("READ?");
  response = transport.ReadLine();
  if (response.empty()) {
    throw std::runtime_error("Empty current response.");
  }
  return response;
}

std::string InstrumentController::QueryVoltage(IScpiTransport& transport) {
  transport.WriteLine("MEAS:VOLT?");
  auto response = transport.ReadLine();
  if (response.empty()) {
    transport.WriteLine("READ?");
    response = transport.ReadLine();
  }
  if (response.empty()) {
    throw std::runtime_error("Empty voltage response.");
  }
  return response;
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

bool InstrumentController::GetBool(const flutter::EncodableMap& arguments,
                                   const char* key) {
  const auto it = arguments.find(EncodableValue(key));
  if (it == arguments.end()) {
    throw std::runtime_error(std::string("Missing argument: ") + key);
  }
  if (const auto* bool_value = std::get_if<bool>(&(it->second))) {
    return *bool_value;
  }
  throw std::runtime_error(std::string("Invalid boolean argument: ") + key);
}

bool InstrumentController::HasString(const flutter::EncodableMap& arguments,
                                     const char* key) {
  const auto it = arguments.find(EncodableValue(key));
  return it != arguments.end() && std::holds_alternative<std::string>(it->second);
}

bool InstrumentController::HasBool(const flutter::EncodableMap& arguments,
                                   const char* key) {
  const auto it = arguments.find(EncodableValue(key));
  return it != arguments.end() && std::holds_alternative<bool>(it->second);
}

bool InstrumentController::HasDouble(const flutter::EncodableMap& arguments,
                                     const char* key) {
  const auto it = arguments.find(EncodableValue(key));
  return it != arguments.end() &&
         (std::holds_alternative<int32_t>(it->second) ||
          std::holds_alternative<int64_t>(it->second) ||
          std::holds_alternative<double>(it->second));
}
