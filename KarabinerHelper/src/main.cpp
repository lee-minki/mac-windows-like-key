// WinMacKey KarabinerHelper
// Karabiner-DriverKit-VirtualHIDDevice 클라이언트
//
// 이 바이너리는 root 권한으로 실행되며, stdin에서 JSON 명령을 받아
// Karabiner 가상 HID 키보드에 HID report를 전송합니다.
//
// Unlicense: Karabiner headers are public domain.

#include <filesystem>
#include <pqrs/karabiner/driverkit/virtual_hid_device_driver.hpp>
#include <pqrs/karabiner/driverkit/virtual_hid_device_service.hpp>
#include <atomic>
#include <csignal>
#include <iostream>
#include <sstream>
#include <string>
#include <thread>

namespace {
std::atomic<bool> exit_flag(false);
std::atomic<bool> keyboard_ready(false);
std::atomic<bool> connected(false);
} // namespace

// JSON 파싱 (minimal — 외부 의존성 없이 직접 구현)
struct Command {
    std::string cmd;
    uint8_t modifiers = 0;
    std::vector<uint16_t> keys;
};

// 간단한 JSON 파서 (nlohmann/json 의존성 없이)
static bool parse_uint(const std::string& s, size_t& pos, uint64_t& out) {
    out = 0;
    size_t start = pos;
    while (pos < s.size() && std::isdigit(s[pos])) {
        out = out * 10 + (s[pos] - '0');
        pos++;
    }
    return pos > start;
}

static bool parse_string(const std::string& s, size_t& pos, std::string& out) {
    if (pos >= s.size() || s[pos] != '"') return false;
    pos++; // skip opening quote
    out.clear();
    while (pos < s.size() && s[pos] != '"') {
        out += s[pos++];
    }
    if (pos < s.size()) pos++; // skip closing quote
    return true;
}

static void skip_ws(const std::string& s, size_t& pos) {
    while (pos < s.size() && std::isspace(s[pos])) pos++;
}

static Command parse_command(const std::string& line) {
    Command cmd;
    size_t pos = 0;

    // Find "cmd":"value"
    auto find_key = [&](const std::string& key) -> bool {
        auto kpos = line.find("\"" + key + "\"");
        if (kpos == std::string::npos) return false;
        pos = kpos + key.size() + 2; // past closing quote
        skip_ws(line, pos);
        if (pos < line.size() && line[pos] == ':') pos++;
        skip_ws(line, pos);
        return true;
    };

    if (find_key("cmd")) {
        parse_string(line, pos, cmd.cmd);
    }

    if (find_key("modifiers")) {
        uint64_t v;
        if (parse_uint(line, pos, v)) {
            cmd.modifiers = static_cast<uint8_t>(v);
        }
    }

    if (find_key("keys")) {
        // Parse array of uint16
        skip_ws(line, pos);
        if (pos < line.size() && line[pos] == '[') {
            pos++;
            while (pos < line.size() && line[pos] != ']') {
                skip_ws(line, pos);
                uint64_t v;
                if (parse_uint(line, pos, v)) {
                    cmd.keys.push_back(static_cast<uint16_t>(v));
                }
                skip_ws(line, pos);
                if (pos < line.size() && line[pos] == ',') pos++;
            }
        }
    }

    return cmd;
}

static void send_response(const std::string& status, const std::string& message = "") {
    std::cout << "{\"status\":\"" << status << "\"";
    if (!message.empty()) {
        std::cout << ",\"message\":\"" << message << "\"";
    }
    std::cout << "}" << std::endl;
    std::cout.flush();
}

int main(void) {
    // Signal handler
    std::signal(SIGINT, [](int) { exit_flag = true; });
    std::signal(SIGTERM, [](int) { exit_flag = true; });

    // Check root privileges
    if (getuid() != 0) {
        send_response("error", "root_required: This program must be run with sudo");
        return 1;
    }

    try {
        // Initialize dispatcher (required by Karabiner client)
        pqrs::dispatcher::extra::initialize_shared_dispatcher();

        auto client = std::make_unique<pqrs::karabiner::driverkit::virtual_hid_device_service::client>();

        // Connection callbacks
        client->connected.connect([&client] {
            pqrs::karabiner::driverkit::virtual_hid_device_service::virtual_hid_keyboard_parameters parameters;
            parameters.set_country_code(pqrs::hid::country_code::us);
            client->async_virtual_hid_keyboard_initialize(parameters);

            connected = true;
            send_response("connected");
        });

        client->connect_failed.connect([](auto&& error_code) {
            send_response("error", "connect_failed: " + error_code.message());
        });

        client->closed.connect([] {
            connected = false;
            keyboard_ready = false;
            send_response("closed");
        });

        client->error_occurred.connect([](auto&& error_code) {
            send_response("error", "error: " + error_code.message());
        });

        client->driver_activated.connect([](auto&& activated) {
            if (!activated) {
                send_response("warning", "driver_not_activated");
            }
        });

        client->driver_version_mismatched.connect([](auto&& mismatched) {
            if (mismatched) {
                send_response("warning", "driver_version_mismatched");
            }
        });

        client->virtual_hid_keyboard_ready.connect([](auto&& ready) {
            keyboard_ready = ready;
            if (ready) {
                send_response("ready");
            } else {
                send_response("not_ready");
            }
        });

        // Start client
        client->async_start();

        // Wait for keyboard to become ready (up to 5 seconds)
        send_response("connecting");
        for (int i = 0; i < 50 && !exit_flag && !keyboard_ready; ++i) {
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
        }

        if (!keyboard_ready) {
            send_response("warning", "keyboard_not_ready_after_timeout");
        }

        // stdin reader thread — reads JSON commands line by line
        std::thread stdin_thread([&client] {
            std::string line;
            while (!exit_flag && std::getline(std::cin, line)) {
                if (line.empty()) continue;

                auto cmd = parse_command(line);

                if (cmd.cmd == "post_key") {
                    if (!keyboard_ready) {
                        send_response("error", "keyboard_not_ready");
                        continue;
                    }

                    pqrs::karabiner::driverkit::virtual_hid_device_driver::hid_report::keyboard_input report;

                    // Set modifiers
                    if (cmd.modifiers & 0x01) report.modifiers.insert(pqrs::karabiner::driverkit::virtual_hid_device_driver::hid_report::modifier::left_control);
                    if (cmd.modifiers & 0x02) report.modifiers.insert(pqrs::karabiner::driverkit::virtual_hid_device_driver::hid_report::modifier::left_shift);
                    if (cmd.modifiers & 0x04) report.modifiers.insert(pqrs::karabiner::driverkit::virtual_hid_device_driver::hid_report::modifier::left_option);
                    if (cmd.modifiers & 0x08) report.modifiers.insert(pqrs::karabiner::driverkit::virtual_hid_device_driver::hid_report::modifier::left_command);
                    if (cmd.modifiers & 0x10) report.modifiers.insert(pqrs::karabiner::driverkit::virtual_hid_device_driver::hid_report::modifier::right_control);
                    if (cmd.modifiers & 0x20) report.modifiers.insert(pqrs::karabiner::driverkit::virtual_hid_device_driver::hid_report::modifier::right_shift);
                    if (cmd.modifiers & 0x40) report.modifiers.insert(pqrs::karabiner::driverkit::virtual_hid_device_driver::hid_report::modifier::right_option);
                    if (cmd.modifiers & 0x80) report.modifiers.insert(pqrs::karabiner::driverkit::virtual_hid_device_driver::hid_report::modifier::right_command);

                    // Set keys
                    for (auto key : cmd.keys) {
                        report.keys.insert(key);
                    }

                    client->async_post_report(report);
                    send_response("ok");

                } else if (cmd.cmd == "release") {
                    // Send empty report (all keys released)
                    if (!keyboard_ready) {
                        send_response("error", "keyboard_not_ready");
                        continue;
                    }

                    pqrs::karabiner::driverkit::virtual_hid_device_driver::hid_report::keyboard_input report;
                    client->async_post_report(report);
                    send_response("ok");

                } else if (cmd.cmd == "ping") {
                    send_response(keyboard_ready ? "ready" : "not_ready");

                } else if (cmd.cmd == "quit") {
                    exit_flag = true;
                    send_response("bye");
                    break;

                } else {
                    send_response("error", "unknown_command: " + cmd.cmd);
                }
            }

            exit_flag = true;
        });

        // Main loop — wait for exit
        while (!exit_flag) {
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
        }

        // Cleanup
        client = nullptr;

        if (stdin_thread.joinable()) {
            stdin_thread.join();
        }

        pqrs::dispatcher::extra::terminate_shared_dispatcher();

    } catch (const std::filesystem::filesystem_error& e) {
        send_response("error", "filesystem_error: " + std::string(e.what()));
        return 1;
    } catch (const std::exception& e) {
        send_response("error", "exception: " + std::string(e.what()));
        return 1;
    }

    return 0;
}
