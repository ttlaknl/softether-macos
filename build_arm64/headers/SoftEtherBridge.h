// SoftEtherBridge.h
// SoftEther VPN Client Core C/Swift Bridge Header
// Designed for Apple Silicon (arm64) macOS & iOS

#ifndef SoftEtherBridge_h
#define SoftEtherBridge_h

#include <stdio.h>
#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// VPN Connection Status Enum
typedef enum {
    SE_STATUS_DISCONNECTED = 0,
    SE_STATUS_CONNECTING   = 1,
    SE_STATUS_CONNECTED    = 2,
    SE_STATUS_DISCONNECTING = 3,
    SE_STATUS_ERROR        = 4
} SEVPNStatus;

// Connection Account Profile Structure
typedef struct {
    char account_name[64];
    char server_hostname[256];
    uint32_t server_port;
    char hub_name[64];
    char username[64];
    char password[64];
    bool use_certificate;
    char cert_path[512];
    char pkey_path[512];
} SEAccountProfile;

// Traffic Realtime Metrics
typedef struct {
    uint64_t bytes_sent;
    uint64_t bytes_recv;
    uint32_t speed_bps_up;
    uint32_t speed_bps_down;
} SETrafficMetrics;

// Callback Types for Swift
typedef void (*SELogCallback)(const char* log_message, int level);
typedef void (*SEStatusCallback)(SEVPNStatus new_status, const char* message);
typedef void (*SETrafficCallback)(SETrafficMetrics metrics);

// Core Control API Functions
bool SE_InitCoreEngine(void);
void SE_FreeCoreEngine(void);

bool SE_StartClientService(void);
bool SE_StopClientService(void);

bool SE_ConnectAccount(const SEAccountProfile* profile);
bool SE_DisconnectAccount(const char* account_name);

SEVPNStatus SE_GetAccountStatus(const char* account_name);
SETrafficMetrics SE_GetTrafficMetrics(void);

void SE_RegisterLogCallback(SELogCallback callback);
void SE_RegisterStatusCallback(SEStatusCallback callback);
void SE_RegisterTrafficCallback(SETrafficCallback callback);

int SE_ExecuteVpnCmd(const char* cmdline, char* output_buf, size_t buf_size);

#ifdef __cplusplus
}
#endif

#endif /* SoftEtherBridge_h */
