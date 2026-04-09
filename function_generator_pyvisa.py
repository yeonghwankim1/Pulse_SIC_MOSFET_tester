import argparse
import os
import sys
import time

import serial

DEFAULT_PORT = "COM5"
DEFAULT_PERIOD_US = 10.0
DEFAULT_DUTY_RATIO = 0.5
DEFAULT_VOLTAGE_START = 1.0
DEFAULT_VOLTAGE_END = 5.0
DEFAULT_VOLTAGE_STEP = 0.1
DEFAULT_ON_TIME = 2.0
DEFAULT_OFF_TIME = 0.01
DEFAULT_STOP_FILE = ".pulse_stop"


def log(message):
    print(message, flush=True)


def open_port(port_name):
    return serial.Serial(
        port=port_name,
        baudrate=9600,
        bytesize=serial.EIGHTBITS,
        parity=serial.PARITY_NONE,
        stopbits=serial.STOPBITS_ONE,
        timeout=2,
        write_timeout=2,
    )


def write_line(port, command):
    port.write(f"{command}\n".encode())
    port.flush()
    time.sleep(0.05)


def read_line(port):
    return port.readline().decode(errors="replace").strip()


def identify(port):
    port.reset_input_buffer()
    write_line(port, "*IDN?")
    return read_line(port)


def set_square_wave(port, frequency, vpp, offset, duty):
    commands = [
        "*CLS",
        "SYST:REM",
        "OUTP1:LOAD INF",
        f"SOUR1:APPL:SQU {frequency},{vpp},{offset}",
        f"SOUR1:SQU:DCYC {duty}",
    ]
    for command in commands:
        write_line(port, command)


def set_output(port, enabled):
    write_line(port, "OUTP1 ON" if enabled else "OUTP1 OFF")


def period_us_to_frequency(period_us):
    return 1_000_000.0 / period_us


def build_voltage_points(start, end, step):
    if step <= 0:
        raise ValueError("Voltage step must be greater than 0.")
    if end < start:
        raise ValueError("Voltage end must be greater than or equal to voltage start.")

    points = []
    current = start
    epsilon = step / 1000.0
    while current <= end + epsilon:
        points.append(min(current, end))
        current += step
    return points


def should_stop(stop_file):
    return bool(stop_file) and os.path.exists(stop_file)


def remove_stop_file(stop_file):
    if stop_file and os.path.exists(stop_file):
        os.remove(stop_file)


def sleep_with_stop_check(seconds, stop_file):
    end_time = time.time() + max(seconds, 0)
    while time.time() < end_time:
        if should_stop(stop_file):
            return True
        time.sleep(min(0.05, end_time - time.time()))
    return should_stop(stop_file)


def run_identify(args):
    port = None
    try:
        port = open_port(args.port)
        idn = identify(port)
        log(f"Connected port: {args.port}")
        log(f"IDN: {idn}")
        return 0
    except Exception as exc:
        log(f"Serial Error: {exc}")
        return 1
    finally:
        if port is not None and port.is_open:
            port.close()


def run_sweep(args):
    port = None
    try:
        remove_stop_file(args.stop_file)
        port = open_port(args.port)
        idn = identify(port)
        frequency = period_us_to_frequency(args.period_us)
        duty_percent = args.duty * 100.0
        voltage_points = build_voltage_points(
            args.voltage_start,
            args.voltage_end,
            args.voltage_step,
        )

        log(f"Connected port: {args.port}")
        log(f"IDN: {idn}")
        log(f"Period: {args.period_us} us")
        log(f"Frequency: {frequency} Hz")
        log(f"Duty: {duty_percent} %")
        log(f"Voltage sweep: {args.voltage_start} V -> {args.voltage_end} V")
        log(f"Voltage step: {args.voltage_step} V")
        log(f"Output on-time: {args.on_time} seconds")
        log(f"Output off-time: {args.off_time} seconds")

        for index, vpp in enumerate(voltage_points):
            if should_stop(args.stop_file):
                log("Stop requested before next step.")
                break
            set_output(port, False)
            if sleep_with_stop_check(args.off_time, args.stop_file):
                log("Stop requested during off-time.")
                break
            offset = vpp / 2.0
            set_square_wave(port, frequency, vpp, offset, duty_percent)
            set_output(port, True)
            log(f"Step {index + 1}: Vpp={vpp} V, Offset={offset} V")
            if sleep_with_stop_check(args.on_time, args.stop_file):
                log("Stop requested during on-time.")
                break

        set_output(port, False)
        log("Output stopped.")
        return 0
    except Exception as exc:
        log(f"Serial Error: {exc}")
        return 1
    finally:
        if port is not None and port.is_open:
            try:
                set_output(port, False)
            except Exception:
                pass
            port.close()
        remove_stop_file(args.stop_file)


def build_parser():
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    identify_parser = subparsers.add_parser("identify")
    identify_parser.add_argument("--port", default=DEFAULT_PORT, help="Serial port name")

    sweep_parser = subparsers.add_parser("sweep")
    sweep_parser.add_argument("--port", default=DEFAULT_PORT, help="Serial port name")
    sweep_parser.add_argument("--period-us", type=float, default=DEFAULT_PERIOD_US)
    sweep_parser.add_argument("--voltage-start", type=float, default=DEFAULT_VOLTAGE_START)
    sweep_parser.add_argument("--voltage-end", type=float, default=DEFAULT_VOLTAGE_END)
    sweep_parser.add_argument("--voltage-step", type=float, default=DEFAULT_VOLTAGE_STEP)
    sweep_parser.add_argument("--on-time", type=float, default=DEFAULT_ON_TIME)
    sweep_parser.add_argument("--off-time", type=float, default=DEFAULT_OFF_TIME)
    sweep_parser.add_argument("--duty", type=float, default=DEFAULT_DUTY_RATIO)
    sweep_parser.add_argument("--stop-file", default=DEFAULT_STOP_FILE)

    return parser


def main():
    parser = build_parser()
    args = parser.parse_args()

    if args.command == "identify":
        return run_identify(args)
    if args.command == "sweep":
        return run_sweep(args)

    parser.error("Unsupported command")
    return 2


if __name__ == "__main__":
    sys.exit(main())
