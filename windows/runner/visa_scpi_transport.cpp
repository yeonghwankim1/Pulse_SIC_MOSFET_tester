#include "scpi_transport.h"

#include <windows.h>

#include <stdexcept>
#include <string>

namespace {

using ViStatus = long;
using ViSession = unsigned long;
using ViUInt32 = unsigned long;
using ViChar = char;

constexpr ViStatus kViSuccess = 0;
constexpr ViUInt32 kViAttrTmoValue = 0x3FFF001A;

using ViOpenDefaultRMFn = ViStatus(__stdcall*)(ViSession*);
using ViCloseFn = ViStatus(__stdcall*)(ViSession);
using ViOpenFn = ViStatus(__stdcall*)(ViSession, const ViChar*, ViUInt32, ViUInt32, ViSession*);
using ViSetAttributeFn = ViStatus(__stdcall*)(ViSession, ViUInt32, ViUInt32);
using ViWriteFn = ViStatus(__stdcall*)(ViSession, const unsigned char*, ViUInt32, ViUInt32*);
using ViReadFn = ViStatus(__stdcall*)(ViSession, unsigned char*, ViUInt32, ViUInt32*);

struct VisaApi {
  HMODULE dll = nullptr;
  ViOpenDefaultRMFn open_default_rm = nullptr;
  ViCloseFn close = nullptr;
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
    api.open_default_rm =
        reinterpret_cast<ViOpenDefaultRMFn>(::GetProcAddress(api.dll, "viOpenDefaultRM"));
    api.close = reinterpret_cast<ViCloseFn>(::GetProcAddress(api.dll, "viClose"));
    api.open = reinterpret_cast<ViOpenFn>(::GetProcAddress(api.dll, "viOpen"));
    api.set_attribute =
        reinterpret_cast<ViSetAttributeFn>(::GetProcAddress(api.dll, "viSetAttribute"));
    api.write = reinterpret_cast<ViWriteFn>(::GetProcAddress(api.dll, "viWrite"));
    api.read = reinterpret_cast<ViReadFn>(::GetProcAddress(api.dll, "viRead"));
    if (!api.open_default_rm || !api.close || !api.open || !api.set_attribute ||
        !api.write || !api.read) {
      throw std::runtime_error("Failed to load NI-VISA symbols.");
    }
    loaded = true;
  }
  return api;
}

std::string Trim(const std::string& text) {
  const auto first = text.find_first_not_of(" \r\n\t");
  if (first == std::string::npos) {
    return "";
  }
  const auto last = text.find_last_not_of(" \r\n\t");
  return text.substr(first, last - first + 1);
}

class VisaScpiTransport : public IScpiTransport {
 public:
  explicit VisaScpiTransport(const std::string& resource_name)
      : resource_name_(resource_name) {
    auto& api = GetVisaApi();
    const auto rm_status = api.open_default_rm(&rm_);
    if (rm_status < kViSuccess) {
      throw std::runtime_error("viOpenDefaultRM failed: " + std::to_string(rm_status));
    }
    const auto open_status =
        api.open(rm_, const_cast<ViChar*>(resource_name.c_str()), 0, 5000, &inst_);
    if (open_status < kViSuccess) {
      api.close(rm_);
      rm_ = 0;
      throw std::runtime_error("viOpen failed: " + std::to_string(open_status));
    }
    api.set_attribute(inst_, kViAttrTmoValue, static_cast<ViUInt32>(5000));
  }

  ~VisaScpiTransport() override {
    auto& api = GetVisaApi();
    if (inst_ != 0) {
      api.close(inst_);
      inst_ = 0;
    }
    if (rm_ != 0) {
      api.close(rm_);
      rm_ = 0;
    }
  }

  std::string Identify() override {
    WriteLine("*IDN?");
    return ReadLine();
  }

  void WriteLine(const std::string& command) override {
    auto& api = GetVisaApi();
    std::string payload = command;
    if (payload.empty() || payload.back() != '\n') {
      payload.push_back('\n');
    }
    ViUInt32 written = 0;
    const auto status = api.write(inst_, reinterpret_cast<const unsigned char*>(payload.c_str()),
                                  static_cast<ViUInt32>(payload.size()), &written);
    if (status < kViSuccess) {
      throw std::runtime_error("viWrite failed: " + std::to_string(status));
    }
  }

  std::string ReadLine(int timeout_ms = 2000) override {
    auto& api = GetVisaApi();
    api.set_attribute(inst_, kViAttrTmoValue, static_cast<ViUInt32>(timeout_ms));
    unsigned char buffer[2048] = {};
    ViUInt32 read = 0;
    const auto status = api.read(inst_, buffer, sizeof(buffer) - 1, &read);
    if (status < kViSuccess) {
      throw std::runtime_error("viRead failed: " + std::to_string(status));
    }
    return Trim(std::string(reinterpret_cast<char*>(buffer), read));
  }

  std::string DisplayTarget() const override { return resource_name_; }

 private:
  std::string resource_name_;
  ViSession rm_ = 0;
  ViSession inst_ = 0;
};

}  // namespace

std::unique_ptr<IScpiTransport> CreateVisaScpiTransport(const std::string& target) {
  return std::make_unique<VisaScpiTransport>(target);
}
