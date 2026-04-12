#include "raspberry_receiver.h"

#include <winsock2.h>
#include <ws2tcpip.h>

#include <algorithm>
#include <cstring>
#include <limits>
#include <regex>
#include <string>
#include <vector>

#pragma comment(lib, "Ws2_32.lib")

namespace {

class WsaSession {
 public:
  bool Start(std::string& error) {
    if (started_) return true;
    WSADATA data;
    const int rc = WSAStartup(MAKEWORD(2, 2), &data);
    if (rc != 0) {
      error = "WSAStartup failed: " + std::to_string(rc);
      return false;
    }
    started_ = true;
    return true;
  }

  ~WsaSession() {
    if (started_) {
      WSACleanup();
    }
  }

 private:
  bool started_ = false;
};

class SocketHandle {
 public:
  SocketHandle() = default;
  explicit SocketHandle(SOCKET socket) : socket_(socket) {}
  ~SocketHandle() { Close(); }

  SocketHandle(const SocketHandle&) = delete;
  SocketHandle& operator=(const SocketHandle&) = delete;

  SocketHandle(SocketHandle&& other) noexcept : socket_(other.socket_) {
    other.socket_ = INVALID_SOCKET;
  }

  SocketHandle& operator=(SocketHandle&& other) noexcept {
    if (this != &other) {
      Close();
      socket_ = other.socket_;
      other.socket_ = INVALID_SOCKET;
    }
    return *this;
  }

  SOCKET get() const { return socket_; }
  bool valid() const { return socket_ != INVALID_SOCKET; }

  void reset(SOCKET socket = INVALID_SOCKET) {
    Close();
    socket_ = socket;
  }

 private:
  void Close() {
    if (socket_ != INVALID_SOCKET) {
      closesocket(socket_);
      socket_ = INVALID_SOCKET;
    }
  }

  SOCKET socket_ = INVALID_SOCKET;
};

struct RaspberryConnectionState {
  std::string host;
  int port = 0;
  SocketHandle server;
  SocketHandle client;
  bool listening = false;
  std::string remote_address;
  int remote_port = 0;
};

WsaSession g_wsa;
RaspberryConnectionState g_connection;

bool IsListenHost(const std::string& host) {
  return host.empty() || host == "0.0.0.0" || host == "::";
}

bool WaitForReadable(SOCKET socket, int timeout_ms, const std::string& timeout_message, std::string& error) {
  fd_set read_set;
  FD_ZERO(&read_set);
  FD_SET(socket, &read_set);
  timeval tv = {};
  tv.tv_sec = timeout_ms / 1000;
  tv.tv_usec = (timeout_ms % 1000) * 1000;
  const int rc = select(0, &read_set, nullptr, nullptr, timeout_ms >= 0 ? &tv : nullptr);
  if (rc == 0) {
    error = timeout_message;
    return false;
  }
  if (rc == SOCKET_ERROR) {
    error = "select failed: " + std::to_string(WSAGetLastError());
    return false;
  }
  return true;
}

bool WaitForWritable(SOCKET socket, int timeout_ms, const std::string& timeout_message, std::string& error) {
  fd_set write_set;
  FD_ZERO(&write_set);
  FD_SET(socket, &write_set);
  timeval tv = {};
  tv.tv_sec = timeout_ms / 1000;
  tv.tv_usec = (timeout_ms % 1000) * 1000;
  const int rc = select(0, nullptr, &write_set, nullptr, timeout_ms >= 0 ? &tv : nullptr);
  if (rc == 0) {
    error = timeout_message;
    return false;
  }
  if (rc == SOCKET_ERROR) {
    error = "select failed: " + std::to_string(WSAGetLastError());
    return false;
  }
  return true;
}

bool ReceiveExact(SOCKET socket, char* buffer, int size, std::string& error) {
  int received = 0;
  while (received < size) {
    const int rc = recv(socket, buffer + received, size - received, 0);
    if (rc == 0) {
      error = "Socket closed while receiving data.";
      return false;
    }
    if (rc == SOCKET_ERROR) {
      error = "recv failed: " + std::to_string(WSAGetLastError());
      return false;
    }
    received += rc;
  }
  return true;
}

bool ExtractIntField(const std::string& json, const std::string& key, int& out) {
  const std::regex pattern("\"" + key + "\"\\s*:\\s*(-?\\d+)");
  std::smatch match;
  if (!std::regex_search(json, match, pattern) || match.size() < 2) {
    return false;
  }
  out = std::stoi(match[1].str());
  return true;
}

bool ExtractStringField(const std::string& json, const std::string& key, std::string& out) {
  const std::regex pattern("\"" + key + "\"\\s*:\\s*\"([^\"]*)\"");
  std::smatch match;
  if (!std::regex_search(json, match, pattern) || match.size() < 2) {
    return false;
  }
  out = match[1].str();
  return true;
}

bool ExtractFlexibleStringField(const std::string& json, const std::string& key, std::string& out) {
  if (ExtractStringField(json, key, out)) return true;
  int numeric_value = 0;
  if (!ExtractIntField(json, key, numeric_value)) return false;
  out = std::to_string(numeric_value);
  return true;
}

bool ExtractShape(const std::string& json, int& rows, int& cols) {
  const std::regex pattern("\"shape\"\\s*:\\s*\\[\\s*(\\d+)\\s*,\\s*(\\d+)\\s*\\]");
  std::smatch match;
  if (!std::regex_search(json, match, pattern) || match.size() < 3) {
    return false;
  }
  rows = std::stoi(match[1].str());
  cols = std::stoi(match[2].str());
  return true;
}

uint32_t ReadBigEndianU32(const unsigned char* bytes) {
  return (static_cast<uint32_t>(bytes[0]) << 24) |
         (static_cast<uint32_t>(bytes[1]) << 16) |
         (static_cast<uint32_t>(bytes[2]) << 8) |
         static_cast<uint32_t>(bytes[3]);
}

void PopulateStats(const std::vector<float>& values, int rows, int cols, RaspberryFrameSummary& summary) {
  if (values.empty()) return;
  summary.values = values;

  float min_value = std::numeric_limits<float>::max();
  float max_value = std::numeric_limits<float>::lowest();
  double sum = 0.0;
  for (float value : values) {
    min_value = std::min(min_value, value);
    max_value = std::max(max_value, value);
    sum += value;
  }

  summary.value_count = static_cast<int>(values.size());
  summary.min_value = min_value;
  summary.max_value = max_value;
  summary.mean_value = static_cast<float>(sum / values.size());

  if (rows > 0 && cols > 0 && static_cast<size_t>(rows * cols) <= values.size()) {
    const int center_index = (rows / 2) * cols + (cols / 2);
    summary.center_value = values[center_index];
  }
}

void ResetClient() {
  g_connection.client.reset();
  g_connection.remote_address.clear();
  g_connection.remote_port = 0;
}

void ResetAllConnections() {
  ResetClient();
  g_connection.server.reset();
  g_connection.listening = false;
  g_connection.host.clear();
  g_connection.port = 0;
}

bool EnsureListeningSocket(const std::string& host, int port, std::string& error) {
  if (g_connection.listening && g_connection.host == host && g_connection.port == port && g_connection.server.valid()) {
    return true;
  }

  ResetAllConnections();

  addrinfo hints = {};
  hints.ai_family = AF_INET;
  hints.ai_socktype = SOCK_STREAM;
  hints.ai_protocol = IPPROTO_TCP;
  hints.ai_flags = AI_PASSIVE;

  addrinfo* addr_result = nullptr;
  const std::string bind_host = host.empty() ? "0.0.0.0" : host;
  const std::string port_text = std::to_string(port);
  const int gai_rc = getaddrinfo(bind_host.c_str(), port_text.c_str(), &hints, &addr_result);
  if (gai_rc != 0) {
    error = "listen getaddrinfo failed for " + bind_host + ":" + port_text + " (" + std::to_string(gai_rc) + ")";
    return false;
  }

  SocketHandle server(socket(addr_result->ai_family, addr_result->ai_socktype, addr_result->ai_protocol));
  if (!server.valid()) {
    freeaddrinfo(addr_result);
    error = "listen socket failed for " + bind_host + ":" + port_text + " (" + std::to_string(WSAGetLastError()) + ")";
    return false;
  }

  BOOL reuse = 1;
  setsockopt(server.get(), SOL_SOCKET, SO_REUSEADDR, reinterpret_cast<const char*>(&reuse), sizeof(reuse));

  if (bind(server.get(), addr_result->ai_addr, static_cast<int>(addr_result->ai_addrlen)) == SOCKET_ERROR) {
    freeaddrinfo(addr_result);
    error = "bind failed for " + bind_host + ":" + port_text + " (" + std::to_string(WSAGetLastError()) + ")";
    return false;
  }
  freeaddrinfo(addr_result);

  if (listen(server.get(), 1) == SOCKET_ERROR) {
    error = "listen failed for " + bind_host + ":" + port_text + " (" + std::to_string(WSAGetLastError()) + ")";
    return false;
  }

  g_connection.server = std::move(server);
  g_connection.host = host;
  g_connection.port = port;
  g_connection.listening = true;
  return true;
}

bool EnsureAcceptedClientConnected(int timeout_ms, std::string& error) {
  if (g_connection.client.valid()) {
    return true;
  }
  if (!g_connection.server.valid()) {
    error = "Server socket is not initialized.";
    return false;
  }

  if (timeout_ms > 0 &&
      !WaitForReadable(
          g_connection.server.get(),
          timeout_ms,
          "Timed out waiting for Raspberry connection.",
          error)) {
    return false;
  }

  sockaddr_in client_addr = {};
  int client_len = sizeof(client_addr);
  SocketHandle client(accept(g_connection.server.get(), reinterpret_cast<sockaddr*>(&client_addr), &client_len));
  if (!client.valid()) {
    error = "accept failed: " + std::to_string(WSAGetLastError());
    return false;
  }

  if (timeout_ms > 0) {
    DWORD recv_timeout = static_cast<DWORD>(timeout_ms);
    setsockopt(client.get(), SOL_SOCKET, SO_RCVTIMEO, reinterpret_cast<const char*>(&recv_timeout), sizeof(recv_timeout));
  }

  char remote_ip[INET_ADDRSTRLEN] = {};
  inet_ntop(AF_INET, &client_addr.sin_addr, remote_ip, sizeof(remote_ip));
  g_connection.remote_address = remote_ip;
  g_connection.remote_port = ntohs(client_addr.sin_port);
  g_connection.client = std::move(client);
  return true;
}

bool EnsureOutgoingClientConnected(const std::string& host, int port, int timeout_ms, std::string& error) {
  if (!g_connection.listening &&
      g_connection.host == host &&
      g_connection.port == port &&
      g_connection.client.valid()) {
    return true;
  }

  ResetAllConnections();

  addrinfo hints = {};
  hints.ai_family = AF_INET;
  hints.ai_socktype = SOCK_STREAM;
  hints.ai_protocol = IPPROTO_TCP;

  addrinfo* addr_result = nullptr;
  const std::string port_text = std::to_string(port);
  const int gai_rc = getaddrinfo(host.c_str(), port_text.c_str(), &hints, &addr_result);
  if (gai_rc != 0) {
    error = "connect getaddrinfo failed for " + host + ":" + port_text + " (" + std::to_string(gai_rc) + ")";
    return false;
  }

  bool connected = false;
  int last_error = 0;
  for (auto* addr = addr_result; addr != nullptr; addr = addr->ai_next) {
    SocketHandle client(socket(addr->ai_family, addr->ai_socktype, addr->ai_protocol));
    if (!client.valid()) {
      last_error = WSAGetLastError();
      continue;
    }

    u_long non_blocking = 1;
    if (ioctlsocket(client.get(), FIONBIO, &non_blocking) == SOCKET_ERROR) {
      last_error = WSAGetLastError();
      continue;
    }

    const int connect_rc = connect(client.get(), addr->ai_addr, static_cast<int>(addr->ai_addrlen));
    if (connect_rc == SOCKET_ERROR) {
      const int connect_error = WSAGetLastError();
      if (connect_error != WSAEWOULDBLOCK &&
          connect_error != WSAEINPROGRESS &&
          connect_error != WSAEALREADY) {
        last_error = connect_error;
        continue;
      }

      if (timeout_ms > 0 &&
          !WaitForWritable(
              client.get(),
              timeout_ms,
              "Timed out connecting to Raspberry at " + host + ":" + port_text + ".",
              error)) {
        freeaddrinfo(addr_result);
        return false;
      }

      int socket_error = 0;
      int socket_error_len = sizeof(socket_error);
      if (getsockopt(client.get(),
                     SOL_SOCKET,
                     SO_ERROR,
                     reinterpret_cast<char*>(&socket_error),
                     &socket_error_len) == SOCKET_ERROR) {
        last_error = WSAGetLastError();
        continue;
      }
      if (socket_error != 0) {
        last_error = socket_error;
        continue;
      }
    }

    non_blocking = 0;
    ioctlsocket(client.get(), FIONBIO, &non_blocking);
    if (timeout_ms > 0) {
      DWORD recv_timeout = static_cast<DWORD>(timeout_ms);
      setsockopt(client.get(), SOL_SOCKET, SO_RCVTIMEO, reinterpret_cast<const char*>(&recv_timeout), sizeof(recv_timeout));
    }

    sockaddr_in remote_addr = {};
    if (addr->ai_addrlen >= static_cast<int>(sizeof(remote_addr))) {
      std::memcpy(&remote_addr, addr->ai_addr, sizeof(remote_addr));
      char remote_ip[INET_ADDRSTRLEN] = {};
      inet_ntop(AF_INET, &remote_addr.sin_addr, remote_ip, sizeof(remote_ip));
      g_connection.remote_address = remote_ip;
      g_connection.remote_port = ntohs(remote_addr.sin_port);
    } else {
      g_connection.remote_address = host;
      g_connection.remote_port = port;
    }

    g_connection.client = std::move(client);
    g_connection.host = host;
    g_connection.port = port;
    g_connection.listening = false;
    connected = true;
    break;
  }

  freeaddrinfo(addr_result);
  if (!connected) {
    error = "connect failed for " + host + ":" + port_text + " (" + std::to_string(last_error) + ")";
  }
  return connected;
}

bool ReceiveFrameFromCurrentClient(int timeout_ms, RaspberryFrameSummary& summary, std::string& error) {
  if (!g_connection.client.valid()) {
    error = "Client socket is not connected.";
    return false;
  }

  if (timeout_ms > 0 &&
      !WaitForReadable(
          g_connection.client.get(),
          timeout_ms,
          "Timed out waiting for Raspberry frame data.",
          error)) {
    ResetClient();
    return false;
  }

  summary = RaspberryFrameSummary();
  summary.remote_address = g_connection.remote_address;
  summary.remote_port = g_connection.remote_port;
  summary.debug_status = "client_connected";

  unsigned char meta_len_bytes[4] = {};
  if (!ReceiveExact(g_connection.client.get(), reinterpret_cast<char*>(meta_len_bytes), 4, error)) {
    ResetClient();
    return false;
  }
  summary.debug_status = "header_length_received";

  const uint32_t meta_len = ReadBigEndianU32(meta_len_bytes);
  if (meta_len == 0 || meta_len > 1024 * 1024) {
    ResetClient();
    error = "Invalid metadata length.";
    return false;
  }

  std::string metadata(meta_len, '\0');
  if (!ReceiveExact(g_connection.client.get(), metadata.data(), static_cast<int>(meta_len), error)) {
    ResetClient();
    return false;
  }
  summary.debug_status = "metadata_received";

  if (!ExtractIntField(metadata, "payload_bytes", summary.payload_bytes) || summary.payload_bytes <= 0) {
    ResetClient();
    error = "payload_bytes not found in metadata.";
    return false;
  }
  if (!ExtractShape(metadata, summary.shape_rows, summary.shape_cols)) {
    ResetClient();
    error = "shape not found in metadata.";
    return false;
  }

  ExtractFlexibleStringField(metadata, "time_str", summary.time_str);
  ExtractFlexibleStringField(metadata, "frame_id", summary.frame_id);

  std::vector<char> payload(static_cast<size_t>(summary.payload_bytes));
  if (!ReceiveExact(g_connection.client.get(), payload.data(), summary.payload_bytes, error)) {
    ResetClient();
    return false;
  }
  summary.debug_status = "payload_received";

  if (summary.payload_bytes % static_cast<int>(sizeof(float)) != 0) {
    ResetClient();
    error = "Payload size is not a multiple of float32.";
    return false;
  }

  std::vector<float> values(static_cast<size_t>(summary.payload_bytes / sizeof(float)));
  std::memcpy(values.data(), payload.data(), static_cast<size_t>(summary.payload_bytes));
  PopulateStats(values, summary.shape_rows, summary.shape_cols, summary);
  summary.debug_status = "frame_complete";
  return true;
}

}  // namespace

bool ReceiveSingleRaspberryFrame(const std::string& host,
                                 int port,
                                 int timeout_ms,
                                 RaspberryFrameSummary& summary,
                                 std::string& error) {
  summary = RaspberryFrameSummary();
  summary.debug_status = "start";
  if (!g_wsa.Start(error)) {
    summary.debug_status = "wsa_start_failed";
    return false;
  }
  summary.debug_status = "wsa_ready";

  if (IsListenHost(host)) {
    if (!EnsureListeningSocket(host, port, error)) {
      summary.debug_status = "listen_failed";
      return false;
    }
    summary.debug_status = g_connection.client.valid() ? "listening_reuse_client" : "listening_wait_client";

    if (!EnsureAcceptedClientConnected(timeout_ms, error)) {
      summary.debug_status = "accept_failed";
      return false;
    }
    summary.debug_status = "client_accepted";
  } else {
    if (!EnsureOutgoingClientConnected(host, port, timeout_ms, error)) {
      summary.debug_status = "connect_failed";
      return false;
    }
    summary.debug_status = "client_connected_outgoing";
  }

  return ReceiveFrameFromCurrentClient(timeout_ms, summary, error);
}
