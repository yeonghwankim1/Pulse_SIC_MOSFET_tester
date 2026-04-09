#include "scpi_transport.h"

#include <stdexcept>

std::unique_ptr<IScpiTransport> CreateSerialScpiTransport(const std::string& target);
std::unique_ptr<IScpiTransport> CreateVisaScpiTransport(const std::string& target);
std::unique_ptr<IScpiTransport> CreateTcpScpiTransport(const std::string& target);

std::unique_ptr<IScpiTransport> CreateScpiTransport(
    const std::string& transport_type,
    const std::string& target) {
  if (transport_type == "serial") {
    return CreateSerialScpiTransport(target);
  }
  if (transport_type == "visa") {
    return CreateVisaScpiTransport(target);
  }
  if (transport_type == "tcp") {
    return CreateTcpScpiTransport(target);
  }
  throw std::runtime_error("Unsupported transport type: " + transport_type);
}
