#include "NativeTunnel.hpp"
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <iostream>
#include <cstring>

NativeTunnel::NativeTunnel() {}

NativeTunnel::~NativeTunnel() {
    disconnect();
}

bool NativeTunnel::connect_to_tunnel(const std::string& host, int port) {
    disconnect();

    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return false;

    struct sockaddr_in serv_addr;
    serv_addr.sin_family = AF_INET;
    serv_addr.sin_port = htons(port);

    if (inet_pton(AF_INET, host.c_str(), &serv_addr.sin_addr) <= 0) {
        close(fd);
        return false;
    }

    if (connect(fd, (struct sockaddr *)&serv_addr, sizeof(serv_addr)) < 0) {
        close(fd);
        return false;
    }

    _socket_fd = fd;
    _host = host;
    _port = port;
    _is_running = true;
    
    return true;
}

void NativeTunnel::disconnect() {
    _is_running = false;
    int fd = _socket_fd.exchange(-1);
    if (fd != -1) {
        shutdown(fd, SHUT_RDWR);
        close(fd);
    }
}

bool NativeTunnel::send_coordinate(double lat, double lon) {
    int fd = _socket_fd;
    if (fd == -1) return false;

    // 這裡實作 DVT Location Simulation 協議的簡化版本
    // 實際上 iOS 期望的是一個特定的 PLIST 或 Protobuf 封包
    // 為了相容現有的 pymobiledevice3 隧道，我們發送與原本 python 腳本預期一致的格式
    // 或者直接模擬 DVT 協議。
    
    // 考慮到目前的架構，我們讓 C++ 負責最高頻率的數據寫入
    // 格式： "SET_LOC:lat,lon\n"
    std::string msg = std::to_string(lat) + "," + std::to_string(lon) + "\n";
    ssize_t sent = send(fd, msg.c_str(), msg.length(), 0);
    
    return sent > 0;
}
