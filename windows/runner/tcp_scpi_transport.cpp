#include "scpi_transport.h"

#include <winsock2.h>
#include <ws2tcpip.h>

#include <chrono>
#include <stdexcept>
#include <string>
#include <thread>

#pragma comment(lib, "Ws2_32.lib")

namespace {

std::string Trim(const std::string& text) {
  const auto first = text.find_first_not_of(" \r\n\t");
  if (first == std::string::npos) {
    return "";
  }
  const auto last = text.find_last_not_of(" \r\n\t");
  return text.substr(first, last - first + 1);
}

class TcpWsaSession {
 public:
  TcpWsaSession() {
    WSADATA data;
    const int rc = WSAStartup(MAKEWORD(2, 2), &data);
    if (rc != 0) {
      throw std::runtime_error("WSAStartup failed: " + std::to_string(rc));
    }
  }

  ~TcpWsaSession() { WSACleanup(); }
};

class TcpScpiTransport : public IScpiTransport {
 public:
  explicit TcpScpiTransport(const std::string& endpoint) : endpoint_(endpoint) {
    const auto separator = endpoint.find(':');
    if (separator == std::string::npos) {
      throw std::runtime_error("TCP target must be host:port.");
    }
    const std::string host = endpoint.substr(0, separator);
    const std::string port = endpoint.substr(separator + 1);

    addrinfo hints = {};
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_STREAM;
    hints.ai_protocol = IPPROTO_TCP;

    addrinfo* result = nullptr;
    if (getaddrinfo(host.c_str(), port.c_str(), &hints, &result) != 0) {
      throw std::runtime_error("getaddrinfo failed for " + endpoint);
    }

    for (auto* addr = result; addr != nullptr; addr = addr->ai_next) {
      socket_ = socket(addr->ai_family, addr->ai_socktype, addr->ai_protocol);
      if (socket_ == INVALID_SOCKET) {
        continue;
      }
      if (connect(socket_, addr->ai_addr, static_cast<int>(addr->ai_addrlen)) == 0) {
        break;
      }
      closesocket(socket_);
      socket_ = INVALID_SOCKET;
    }
    freeaddrinfo(result);

    if (socket_ == INVALID_SOCKET) {
      throw std::runtime_error("Failed to connect TCP socket " + endpoint);
    }
  }

  ~TcpScpiTransport() override {
    if (socket_ != INVALID_SOCKET) {
      closesocket(socket_);
      socket_ = INVALID_SOCKET;
    }
  }

  std::string Identify() override {
    WriteLine("*IDN?");
    return ReadLine();
  }

  void WriteLine(const std::string& command) override {
    const std::string payload = command + "\n";
    if (send(socket_, payload.c_str(), static_cast<int>(payload.size()), 0) ==
        SOCKET_ERROR) {
      throw std::runtime_error("Failed to send TCP command.");
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(50));
  }

  std::string ReadLine(int timeout_ms = 2000) override {
    std::string response;
    auto deadline = std::chrono::steady_clock::now() +
                    std::chrono::milliseconds(timeout_ms);
    char ch = 0;
    while (std::chrono::steady_clock::now() < deadline) {
      const int rc = recv(socket_, &ch, 1, 0);
      if (rc == SOCKET_ERROR) {
        throw std::runtime_error("Failed to read TCP response.");
      }
      if (rc == 0) {
        break;
      }
      if (ch == '\n') {
        break;
      }
      response.push_back(ch);
    }
    return Trim(response);
  }

  std::string DisplayTarget() const override { return endpoint_; }

 private:
  TcpWsaSession wsa_;
  std::string endpoint_;
  SOCKET socket_ = INVALID_SOCKET;
};

}  // namespace

std::unique_ptr<IScpiTransport> CreateTcpScpiTransport(const std::string& target) {
  return std::make_unique<TcpScpiTransport>(target);
}
