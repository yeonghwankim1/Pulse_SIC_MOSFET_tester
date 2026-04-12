#include "flutter_window.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <atomic>
#include <optional>
#include <sstream>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>
#include <windows.h>
#include <shlobj.h>

#include "flutter/generated_plugin_registrant.h"

#include "raspberry_receiver.h"

namespace {

std::string TrimAscii(const std::string& value) {
  size_t start = 0;
  while (start < value.size() &&
         (value[start] == '\r' || value[start] == '\n' || value[start] == ' ' || value[start] == '\t')) {
    ++start;
  }
  size_t end = value.size();
  while (end > start &&
         (value[end - 1] == '\r' || value[end - 1] == '\n' || value[end - 1] == ' ' || value[end - 1] == '\t')) {
    --end;
  }
  return value.substr(start, end - start);
}

std::wstring Utf8ToWide(const std::string& text) {
  if (text.empty()) {
    return std::wstring();
  }
  const int len = MultiByteToWideChar(CP_UTF8, 0, text.c_str(), -1, nullptr, 0);
  if (len <= 0) {
    return std::wstring();
  }
  std::wstring out(static_cast<size_t>(len - 1), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, text.c_str(), -1, out.data(), len);
  return out;
}

std::string WideToUtf8(const std::wstring& text) {
  if (text.empty()) {
    return std::string();
  }
  const int len = WideCharToMultiByte(CP_UTF8, 0, text.c_str(), -1, nullptr, 0, nullptr, nullptr);
  if (len <= 0) {
    return std::string();
  }
  std::string out(static_cast<size_t>(len - 1), '\0');
  WideCharToMultiByte(CP_UTF8, 0, text.c_str(), -1, out.data(), len, nullptr, nullptr);
  return out;
}

std::optional<std::string> PickDirectory(const std::string& initial_dir) {
  (void)initial_dir;
  BROWSEINFOW bi = {};
  bi.lpszTitle = L"Select Folder";
  bi.ulFlags = BIF_RETURNONLYFSDIRS | BIF_NEWDIALOGSTYLE | BIF_USENEWUI;

  const auto pidl = SHBrowseForFolderW(&bi);
  if (pidl == nullptr) {
    return std::nullopt;
  }

  wchar_t path[MAX_PATH] = {};
  const bool ok = SHGetPathFromIDListW(pidl, path) == TRUE;
  CoTaskMemFree(pidl);
  if (!ok) {
    return std::nullopt;
  }
  return WideToUtf8(path);
}

std::string QuoteForCmd(const std::string& text) {
  std::string out = "\"";
  for (char ch : text) {
    if (ch == '"') {
      out += "\\\"";
    } else {
      out.push_back(ch);
    }
  }
  out.push_back('"');
  return out;
}

bool RunHiddenCommand(const std::wstring& command, DWORD& exit_code, std::string& error) {
  STARTUPINFOW startup_info = {};
  startup_info.cb = sizeof(startup_info);
  startup_info.dwFlags = STARTF_USESHOWWINDOW;
  startup_info.wShowWindow = SW_HIDE;
  PROCESS_INFORMATION process_info = {};
  std::wstring mutable_command = command;

  if (!CreateProcessW(nullptr, mutable_command.data(), nullptr, nullptr, FALSE,
                      CREATE_NO_WINDOW, nullptr, nullptr, &startup_info,
                      &process_info)) {
    error = "CreateProcess failed: " + std::to_string(GetLastError());
    return false;
  }

  WaitForSingleObject(process_info.hProcess, INFINITE);
  if (!GetExitCodeProcess(process_info.hProcess, &exit_code)) {
    error = "GetExitCodeProcess failed: " + std::to_string(GetLastError());
    CloseHandle(process_info.hThread);
    CloseHandle(process_info.hProcess);
    return false;
  }

  CloseHandle(process_info.hThread);
  CloseHandle(process_info.hProcess);
  return true;
}

bool RunCommandCapture(const std::wstring& command,
                       std::string& output,
                       DWORD& exit_code,
                       std::string& error) {
  SECURITY_ATTRIBUTES security_attributes = {};
  security_attributes.nLength = sizeof(security_attributes);
  security_attributes.bInheritHandle = TRUE;

  HANDLE read_pipe = nullptr;
  HANDLE write_pipe = nullptr;
  if (!CreatePipe(&read_pipe, &write_pipe, &security_attributes, 0)) {
    error = "CreatePipe failed: " + std::to_string(GetLastError());
    return false;
  }
  SetHandleInformation(read_pipe, HANDLE_FLAG_INHERIT, 0);

  STARTUPINFOW startup_info = {};
  startup_info.cb = sizeof(startup_info);
  startup_info.dwFlags = STARTF_USESHOWWINDOW | STARTF_USESTDHANDLES;
  startup_info.wShowWindow = SW_HIDE;
  startup_info.hStdOutput = write_pipe;
  startup_info.hStdError = write_pipe;
  PROCESS_INFORMATION process_info = {};
  std::wstring mutable_command = command;

  if (!CreateProcessW(nullptr, mutable_command.data(), nullptr, nullptr, TRUE,
                      CREATE_NO_WINDOW, nullptr, nullptr, &startup_info,
                      &process_info)) {
    error = "CreateProcess failed: " + std::to_string(GetLastError());
    CloseHandle(read_pipe);
    CloseHandle(write_pipe);
    return false;
  }

  CloseHandle(write_pipe);
  write_pipe = nullptr;

  std::string captured;
  char buffer[4096];
  DWORD bytes_read = 0;
  while (ReadFile(read_pipe, buffer, sizeof(buffer), &bytes_read, nullptr) &&
         bytes_read > 0) {
    captured.append(buffer, buffer + bytes_read);
  }

  WaitForSingleObject(process_info.hProcess, INFINITE);
  if (!GetExitCodeProcess(process_info.hProcess, &exit_code)) {
    error = "GetExitCodeProcess failed: " + std::to_string(GetLastError());
    CloseHandle(read_pipe);
    CloseHandle(process_info.hThread);
    CloseHandle(process_info.hProcess);
    return false;
  }

  CloseHandle(read_pipe);
  CloseHandle(process_info.hThread);
  CloseHandle(process_info.hProcess);
  output = captured;
  return true;
}

std::vector<std::string> ListEthernetAdapters(std::string& error) {
  std::vector<std::string> adapters;
  std::string output;
  DWORD exit_code = 0;
  if (!RunCommandCapture(
          L"cmd.exe /C chcp 65001>nul && netsh interface show interface",
          output,
          exit_code,
          error)) {
    return adapters;
  }
  if (exit_code != 0) {
    error = "netsh interface show interface failed with exit code " +
            std::to_string(exit_code);
    return adapters;
  }

  std::istringstream stream(output);
  std::string line;
  while (std::getline(stream, line)) {
    if (line.find("Dedicated") == std::string::npos) {
      continue;
    }
    if (line.find("Connected") == std::string::npos) {
      continue;
    }
    const auto pos = line.find("Dedicated");
    if (pos == std::string::npos) {
      continue;
    }
    const std::string adapter_name =
        TrimAscii(line.substr(pos + std::string("Dedicated").size()));
    if (!adapter_name.empty()) {
      adapters.push_back(adapter_name);
    }
  }
  return adapters;
}

bool ConfigureAdapterStaticIpv4(const std::string& adapter_name,
                                const std::string& ip_address,
                                int prefix_length,
                                std::string& error) {
  const std::string mask = prefix_length == 24 ? "255.255.255.0" : "255.255.255.0";
  const std::string command =
      "cmd.exe /C netsh interface ipv4 set address name=" +
      QuoteForCmd(adapter_name) + " static " + ip_address + " " + mask;
  DWORD exit_code = 0;
  if (!RunHiddenCommand(Utf8ToWide(command), exit_code, error)) {
    return false;
  }
  if (exit_code != 0) {
    error = "netsh static IP failed with exit code " + std::to_string(exit_code) +
            ". Try running the app as administrator.";
    return false;
  }
  return true;
}

bool ConfigureAdapterDhcp(const std::string& adapter_name, std::string& error) {
  const std::string command =
      "cmd.exe /C netsh interface ipv4 set address name=" +
      QuoteForCmd(adapter_name) + " source=dhcp";
  DWORD exit_code = 0;
  if (!RunHiddenCommand(Utf8ToWide(command), exit_code, error)) {
    return false;
  }
  if (exit_code != 0) {
    error = "netsh DHCP restore failed with exit code " + std::to_string(exit_code) +
            ". Try running the app as administrator.";
    return false;
  }
  return true;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  instrument_controller_ = std::make_unique<InstrumentController>();
  SetUpMethodChannel();
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (channel_) {
    channel_ = nullptr;
  }
  if (instrument_controller_) {
    instrument_controller_->Shutdown();
    instrument_controller_ = nullptr;
  }
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

void FlutterWindow::SetUpMethodChannel() {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(),
      "sic_mosfet/native_control",
      &flutter::StandardMethodCodec::GetInstance());

  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        try {
          const auto* arguments =
              std::get_if<flutter::EncodableMap>(call.arguments());
          if (call.method_name() == "identify") {
            if (arguments == nullptr) {
              result->Error("bad_args", "Arguments are required.");
              return;
            }
            result->Success(instrument_controller_->Identify(*arguments));
            return;
          }
          if (call.method_name() == "listResources") {
            result->Success(instrument_controller_->ListResources());
            return;
          }
          if (call.method_name() == "queryIdn") {
            if (arguments == nullptr) {
              result->Error("bad_args", "Arguments are required.");
              return;
            }
            result->Success(instrument_controller_->QueryIdn(*arguments));
            return;
          }
          if (call.method_name() == "receiveRaspberryFrame") {
            if (arguments == nullptr) {
              result->Error("bad_args", "Arguments are required.");
              return;
            }

            std::string host = "0.0.0.0";
            int port = 5001;
            int timeout_ms = 10000;

            const auto host_it = arguments->find(flutter::EncodableValue("host"));
            if (host_it != arguments->end()) {
              host = std::get<std::string>(host_it->second);
            }
            const auto port_it = arguments->find(flutter::EncodableValue("port"));
            if (port_it != arguments->end()) {
              port = std::get<int>(port_it->second);
            }
            const auto timeout_it = arguments->find(flutter::EncodableValue("timeoutMs"));
            if (timeout_it != arguments->end()) {
              port = port;
              timeout_ms = std::get<int>(timeout_it->second);
            }

            auto async_result = std::move(result);
            std::thread([host, port, timeout_ms, async_result = std::move(async_result)]() mutable {
              RaspberryFrameSummary summary;
              std::string error;
              if (!ReceiveSingleRaspberryFrame(host, port, timeout_ms, summary, error)) {
                async_result->Error("raspberry_receive_failed", error);
                return;
              }

              flutter::EncodableMap out;
              out[flutter::EncodableValue("host")] = flutter::EncodableValue(host);
              out[flutter::EncodableValue("port")] = flutter::EncodableValue(port);
              out[flutter::EncodableValue("remoteAddress")] =
                  flutter::EncodableValue(summary.remote_address);
              out[flutter::EncodableValue("remotePort")] =
                  flutter::EncodableValue(summary.remote_port);
              out[flutter::EncodableValue("debugStatus")] =
                  flutter::EncodableValue(summary.debug_status);
              out[flutter::EncodableValue("timeStr")] =
                  flutter::EncodableValue(summary.time_str);
              out[flutter::EncodableValue("frameId")] =
                  flutter::EncodableValue(summary.frame_id);
              out[flutter::EncodableValue("rows")] =
                  flutter::EncodableValue(summary.shape_rows);
              out[flutter::EncodableValue("cols")] =
                  flutter::EncodableValue(summary.shape_cols);
              out[flutter::EncodableValue("payloadBytes")] =
                  flutter::EncodableValue(summary.payload_bytes);
              out[flutter::EncodableValue("valueCount")] =
                  flutter::EncodableValue(summary.value_count);
              out[flutter::EncodableValue("min")] =
                  flutter::EncodableValue(static_cast<double>(summary.min_value));
              out[flutter::EncodableValue("max")] =
                  flutter::EncodableValue(static_cast<double>(summary.max_value));
              out[flutter::EncodableValue("mean")] =
                  flutter::EncodableValue(static_cast<double>(summary.mean_value));
              out[flutter::EncodableValue("center")] =
                  flutter::EncodableValue(static_cast<double>(summary.center_value));
              flutter::EncodableList values;
              for (float value : summary.values) {
                values.emplace_back(static_cast<double>(value));
              }
              out[flutter::EncodableValue("values")] = flutter::EncodableValue(values);
              async_result->Success(flutter::EncodableValue(out));
            }).detach();
            return;
          }
          if (call.method_name() == "listEthernetAdapters") {
            std::string error;
            const auto adapters = ListEthernetAdapters(error);
            if (!error.empty() && adapters.empty()) {
              result->Error("network_list_failed", error);
              return;
            }
            flutter::EncodableList out;
            for (const auto& adapter : adapters) {
              out.emplace_back(adapter);
            }
            result->Success(flutter::EncodableValue(out));
            return;
          }
          if (call.method_name() == "configureDirectLinkMode") {
            if (arguments == nullptr) {
              result->Error("bad_args", "Arguments are required.");
              return;
            }
            std::string adapter_name;
            std::string ip_address = "192.168.50.1";
            int prefix_length = 24;

            const auto adapter_it = arguments->find(flutter::EncodableValue("adapterName"));
            if (adapter_it == arguments->end() ||
                !std::holds_alternative<std::string>(adapter_it->second)) {
              result->Error("bad_args", "adapterName is required.");
              return;
            }
            adapter_name = std::get<std::string>(adapter_it->second);

            const auto ip_it = arguments->find(flutter::EncodableValue("ipAddress"));
            if (ip_it != arguments->end() &&
                std::holds_alternative<std::string>(ip_it->second)) {
              ip_address = std::get<std::string>(ip_it->second);
            }
            const auto prefix_it = arguments->find(flutter::EncodableValue("prefixLength"));
            if (prefix_it != arguments->end() &&
                std::holds_alternative<int>(prefix_it->second)) {
              prefix_length = std::get<int>(prefix_it->second);
            }

            std::string error;
            if (!ConfigureAdapterStaticIpv4(adapter_name, ip_address, prefix_length, error)) {
              result->Error("network_config_failed", error);
              return;
            }
            result->Success(flutter::EncodableValue(true));
            return;
          }
          if (call.method_name() == "restoreDirectLinkMode") {
            if (arguments == nullptr) {
              result->Error("bad_args", "Arguments are required.");
              return;
            }
            const auto adapter_it = arguments->find(flutter::EncodableValue("adapterName"));
            if (adapter_it == arguments->end() ||
                !std::holds_alternative<std::string>(adapter_it->second)) {
              result->Error("bad_args", "adapterName is required.");
              return;
            }
            const std::string adapter_name = std::get<std::string>(adapter_it->second);

            std::string error;
            if (!ConfigureAdapterDhcp(adapter_name, error)) {
              result->Error("network_restore_failed", error);
              return;
            }
            result->Success(flutter::EncodableValue(true));
            return;
          }
          if (call.method_name() == "startResourceScan") {
            result->Success(instrument_controller_->StartResourceScan());
            return;
          }
          if (call.method_name() == "fetchResourceScan") {
            result->Success(instrument_controller_->FetchResourceScan());
            return;
          }
          if (call.method_name() == "startSweep") {
            if (arguments == nullptr) {
              result->Error("bad_args", "Arguments are required.");
              return;
            }
            result->Success(instrument_controller_->StartSweep(*arguments));
            return;
          }
          if (call.method_name() == "stopSweep") {
            result->Success(instrument_controller_->StopSweep());
            return;
          }
          if (call.method_name() == "fetchLogs") {
            result->Success(instrument_controller_->FetchLogs());
            return;
          }
          if (call.method_name() == "fetchSweepData") {
            result->Success(instrument_controller_->FetchSweepData());
            return;
          }
          if (call.method_name() == "pickDirectory") {
            std::string initial_dir;
            if (arguments != nullptr) {
              const auto initial_dir_it = arguments->find(flutter::EncodableValue("initialDir"));
              if (initial_dir_it != arguments->end() &&
                  std::holds_alternative<std::string>(initial_dir_it->second)) {
                initial_dir = std::get<std::string>(initial_dir_it->second);
              }
            }
            const auto selected = PickDirectory(initial_dir);
            if (!selected.has_value()) {
              result->Success();
              return;
            }
            result->Success(flutter::EncodableValue(*selected));
            return;
          }
          result->NotImplemented();
        } catch (const std::exception& error) {
          result->Error("native_error", error.what());
        } catch (...) {
          result->Error("native_error", "Unknown native exception");
        }
      });
}
