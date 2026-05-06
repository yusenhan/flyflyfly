#ifndef NativeTunnel_hpp
#define NativeTunnel_hpp

#ifdef __cplusplus
#include <string>
#include <vector>
#include <mutex>
#include <atomic>
#include <thread>

class NativeTunnel {
    std::atomic<int> _socket_fd{-1};
    std::atomic<bool> _is_running{false};
    std::string _host;
    int _port;
    
public:
    NativeTunnel();
    ~NativeTunnel();

    bool connect_to_tunnel(const std::string& host, int port);
    void disconnect();
    
    // 直接發送二進制封包，避免字串解析
    bool send_coordinate(double lat, double lon);
    
    bool is_connected() const { return _socket_fd != -1; }
};
#endif

#endif /* NativeTunnel_hpp */
