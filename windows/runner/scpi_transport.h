#ifndef RUNNER_SCPI_TRANSPORT_H_
#define RUNNER_SCPI_TRANSPORT_H_

#include <memory>
#include <string>

class IScpiTransport {
 public:
  virtual ~IScpiTransport() = default;

  virtual std::string Identify() = 0;
  virtual void WriteLine(const std::string& command) = 0;
  virtual std::string ReadLine(int timeout_ms = 2000) = 0;
  virtual std::string DisplayTarget() const = 0;
};

std::unique_ptr<IScpiTransport> CreateScpiTransport(
    const std::string& transport_type,
    const std::string& target);

#endif
