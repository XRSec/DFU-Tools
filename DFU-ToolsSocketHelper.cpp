/* SPDX-License-Identifier: Apache-2.0 */

#include <arpa/inet.h>
#include <cerrno>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <sstream>
#include <string>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <vector>

#define DFUTOOLS_LIBRARY
#include "DFUToolsHelper/DFUToolsHelper.cpp"

namespace {

constexpr const char *kCommunicationPassword = "com.xrsec.dfu_tools.socket_xor.2026";

void applyRollingXOR(std::vector<uint8_t> &buf, const std::vector<uint8_t> &key)
{
    uint8_t acc = 0xA5;
    for (size_t i = 0; i < buf.size(); ++i) {
        acc = static_cast<uint8_t>((acc + key[i % key.size()]) ^ static_cast<uint8_t>(i & 0xff));
        buf[i] ^= acc;
    }
}

std::vector<uint8_t> receiveData(int fd)
{
    uint32_t length = 0;
    auto lengthBuffer = reinterpret_cast<uint8_t *>(&length);
    size_t lengthRead = 0;
    while (lengthRead < sizeof(length)) {
        ssize_t received = recv(fd, lengthBuffer + lengthRead, sizeof(length) - lengthRead, 0);
        if (received <= 0) {
            throw failure("Failed to receive message length");
        }
        lengthRead += static_cast<size_t>(received);
    }

    length = ntohl(length);
    std::vector<uint8_t> buffer(length);
    size_t totalRead = 0;
    while (totalRead < buffer.size()) {
        ssize_t received = recv(fd, buffer.data() + totalRead, buffer.size() - totalRead, 0);
        if (received <= 0) {
            throw failure("Failed to receive message body");
        }
        totalRead += static_cast<size_t>(received);
    }

    return buffer;
}

std::vector<std::string> splitLines(const std::string &payload)
{
    std::vector<std::string> parts;
    std::stringstream stream(payload);
    std::string line;
    while (std::getline(stream, line)) {
        parts.push_back(line);
    }
    return parts;
}

int executeCommand(const std::string &command, const std::string &arg)
{
    std::vector<std::string> args;

    if (command == "serial") {
        args.push_back("serial");
    } else if (command == "debugusb") {
        args.push_back("debugusb");
    } else if (command == "reboot") {
        args.push_back("reboot");
    } else if (command == "rebootSerial") {
        args.push_back("reboot");
        args.push_back("serial");
    } else if (command == "rebootDebugUSB") {
        args.push_back("reboot");
        args.push_back("debugusb");
    } else if (command == "dfu") {
        args.push_back("dfu");
    } else if (command == "nop") {
        args.push_back("nop");
    } else if (command == "actions") {
        args.push_back("actions");
    } else if (command == "actionInfo") {
        args.push_back("action");
        args.push_back(arg.empty() ? "0x0" : arg);
    } else {
        printf("Unknown command\n");
        return 1;
    }

    std::vector<char *> argv;
    argv.push_back(const_cast<char *>("DFUToolsHelper"));
    for (auto &item : args) {
        argv.push_back(const_cast<char *>(item.c_str()));
    }
    argv.push_back(nullptr);

    return main2(static_cast<int>(args.size() + 1), argv.data());
}

} // namespace

int main(int argc, char **argv)
{
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <socket_path>\n", argv[0]);
        return 1;
    }

    const char *socketPath = argv[1];
    int socketFd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (socketFd < 0) {
        perror("socket");
        return 1;
    }

    sockaddr_un addr {};
    addr.sun_len = sizeof(addr);
    addr.sun_family = AF_UNIX;
    if (std::strlen(socketPath) >= sizeof(addr.sun_path)) {
        fprintf(stderr, "Socket path too long\n");
        close(socketFd);
        return 1;
    }
    std::strncpy(addr.sun_path, socketPath, sizeof(addr.sun_path) - 1);

    if (connect(socketFd, reinterpret_cast<sockaddr *>(&addr), sizeof(addr)) != 0) {
        perror("connect");
        close(socketFd);
        return 1;
    }

    try {
        auto sessionKey = receiveData(socketFd);
        auto encryptedRequest = receiveData(socketFd);
        close(socketFd);

        applyRollingXOR(encryptedRequest, sessionKey);
        std::string payload(encryptedRequest.begin(), encryptedRequest.end());
        auto parts = splitLines(payload);

        if (parts.size() < 2) {
            throw failure("Invalid request payload");
        }
        if (parts[0] != kCommunicationPassword) {
            throw failure("Invalid communication password");
        }

        const std::string command = parts[1];
        const std::string arg = parts.size() >= 3 ? parts[2] : "";
        return executeCommand(command, arg);
    } catch (const failure &error) {
        printf("%s\n", error.what());
        close(socketFd);
        return -1;
    } catch (const std::exception &error) {
        fprintf(stderr, "%s\n", error.what());
        close(socketFd);
        return -1;
    }
}
