#include "scpi_transport.h"

#include <windows.h>

#include <chrono>
#include <stdexcept>
#include <string>
#include <thread>

namespace {

std::wstring ToWide(const std::string& text) {
  return std::wstring(text.begin(), text.end());
}

std::string Trim(const std::string& text) {
  const auto first = text.find_first_not_of(" \r\n\t");
  if (first == std::string::npos) {
    return "";
  }
  const auto last = text.find_last_not_of(" \r\n\t");
  return text.substr(first, last - first + 1);
}

class SerialScpiTransport : public IScpiTransport {
 public:
  explicit SerialScpiTransport(const std::string& port_name) : port_name_(port_name) {
    std::wstring device_name = L"\\\\.\\" + ToWide(port_name);
    handle_ = CreateFileW(device_name.c_str(), GENERIC_READ | GENERIC_WRITE, 0,
                          nullptr, OPEN_EXISTING, 0, nullptr);
    if (handle_ == INVALID_HANDLE_VALUE) {
      throw std::runtime_error("Failed to open serial port " + port_name + ".");
    }

    DCB dcb = {};
    dcb.DCBlength = sizeof(DCB);
    if (!GetCommState(handle_, &dcb)) {
      throw std::runtime_error("Failed to get serial state.");
    }
    dcb.BaudRate = CBR_9600;
    dcb.ByteSize = 8;
    dcb.Parity = NOPARITY;
    dcb.StopBits = ONESTOPBIT;
    dcb.fBinary = TRUE;
    dcb.fDtrControl = DTR_CONTROL_ENABLE;
    dcb.fRtsControl = RTS_CONTROL_ENABLE;
    if (!SetCommState(handle_, &dcb)) {
      throw std::runtime_error("Failed to configure serial port.");
    }

    COMMTIMEOUTS timeouts = {};
    timeouts.ReadIntervalTimeout = 50;
    timeouts.ReadTotalTimeoutConstant = 100;
    timeouts.ReadTotalTimeoutMultiplier = 0;
    timeouts.WriteTotalTimeoutConstant = 2000;
    timeouts.WriteTotalTimeoutMultiplier = 0;
    if (!SetCommTimeouts(handle_, &timeouts)) {
      throw std::runtime_error("Failed to configure serial timeouts.");
    }

    PurgeComm(handle_, PURGE_RXCLEAR | PURGE_TXCLEAR);
  }

  ~SerialScpiTransport() override {
    if (handle_ != INVALID_HANDLE_VALUE) {
      CloseHandle(handle_);
      handle_ = INVALID_HANDLE_VALUE;
    }
  }

  std::string Identify() override {
    PurgeComm(handle_, PURGE_RXCLEAR);
    WriteLine("*IDN?");
    return ReadLine();
  }

  void WriteLine(const std::string& command) override {
    const std::string payload = command + "\n";
    DWORD written = 0;
    if (!WriteFile(handle_, payload.data(), static_cast<DWORD>(payload.size()),
                   &written, nullptr) ||
        written != payload.size()) {
      throw std::runtime_error("Failed to write command: " + command);
    }
    FlushFileBuffers(handle_);
    std::this_thread::sleep_for(std::chrono::milliseconds(50));
  }

  std::string ReadLine(int timeout_ms = 2000) override {
    std::string response;
    auto deadline = std::chrono::steady_clock::now() +
                    std::chrono::milliseconds(timeout_ms);
    char ch = 0;
    while (std::chrono::steady_clock::now() < deadline) {
      DWORD bytes_read = 0;
      if (!ReadFile(handle_, &ch, 1, &bytes_read, nullptr)) {
        throw std::runtime_error("Failed to read serial response.");
      }
      if (bytes_read == 0) {
        continue;
      }
      if (ch == '\n') {
        break;
      }
      response.push_back(ch);
    }
    return Trim(response);
  }

  std::string DisplayTarget() const override { return port_name_; }

 private:
  std::string port_name_;
  HANDLE handle_ = INVALID_HANDLE_VALUE;
};

}  // namespace

std::unique_ptr<IScpiTransport> CreateSerialScpiTransport(const std::string& target) {
  return std::make_unique<SerialScpiTransport>(target);
}
