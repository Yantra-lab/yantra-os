/* The system, for the desktop's control centre (y_sys, Windows): battery, volume, network.
   Every function returns -1 when the machine does not have or does not tell the value, so the
   desktop hides it instead of showing something made up. */
#define COBJMACROS
#include <windows.h>
#include <initguid.h>
#include <mmdeviceapi.h>
#include <endpointvolume.h>
#include <winsock2.h>
#include <iphlpapi.h>
#include <wlanapi.h>
#include <string.h>
#include <stdlib.h>

/* Battery: percent 0-100, or -1 without a battery. */
int ysys_battery(void) {
  SYSTEM_POWER_STATUS s;
  if (!GetSystemPowerStatus(&s)) return -1;
  if (s.BatteryFlag == 128 || s.BatteryFlag == 255 || s.BatteryLifePercent == 255) return -1;
  return s.BatteryLifePercent;
}

/* 1 on mains power, 0 on battery, -1 unknown. */
int ysys_charging(void) {
  SYSTEM_POWER_STATUS s;
  if (!GetSystemPowerStatus(&s) || s.ACLineStatus == 255) return -1;
  return s.ACLineStatus == 1 ? 1 : 0;
}

static IAudioEndpointVolume* endpoint(void) {
  IMMDeviceEnumerator* en = NULL;
  IMMDevice* dev = NULL;
  IAudioEndpointVolume* vol = NULL;
  CoInitializeEx(NULL, COINIT_MULTITHREADED);
  if (FAILED(CoCreateInstance(&CLSID_MMDeviceEnumerator, NULL, CLSCTX_ALL, &IID_IMMDeviceEnumerator,
                              (void**)&en))) return NULL;
  if (SUCCEEDED(IMMDeviceEnumerator_GetDefaultAudioEndpoint(en, eRender, eConsole, &dev))) {
    IMMDevice_Activate(dev, &IID_IAudioEndpointVolume, CLSCTX_ALL, NULL, (void**)&vol);
    IMMDevice_Release(dev);
  }
  IMMDeviceEnumerator_Release(en);
  return vol;
}

/* The default output's volume, 0-100, or -1 without one. */
int ysys_volume(void) {
  IAudioEndpointVolume* v = endpoint();
  float f = -1;
  if (!v) return -1;
  if (FAILED(IAudioEndpointVolume_GetMasterVolumeLevelScalar(v, &f))) f = -1;
  IAudioEndpointVolume_Release(v);
  return f < 0 ? -1 : (int)(f * 100.0f + 0.5f);
}

int ysys_set_volume(int pct) {
  IAudioEndpointVolume* v = endpoint();
  int ok;
  if (!v) return 0;
  if (pct < 0) pct = 0;
  if (pct > 100) pct = 100;
  ok = SUCCEEDED(IAudioEndpointVolume_SetMasterVolumeLevelScalar(v, pct / 100.0f, NULL));
  IAudioEndpointVolume_Release(v);
  return ok;
}

/* 1 muted, 0 not, -1 no output. */
int ysys_muted(void) {
  IAudioEndpointVolume* v = endpoint();
  BOOL m = FALSE;
  int r;
  if (!v) return -1;
  r = SUCCEEDED(IAudioEndpointVolume_GetMute(v, &m)) ? (m ? 1 : 0) : -1;
  IAudioEndpointVolume_Release(v);
  return r;
}

int ysys_set_muted(int on) {
  IAudioEndpointVolume* v = endpoint();
  int ok;
  if (!v) return 0;
  ok = SUCCEEDED(IAudioEndpointVolume_SetMute(v, on ? TRUE : FALSE, NULL));
  IAudioEndpointVolume_Release(v);
  return ok;
}

/* 0 offline, 1 wired, 2 Wi-Fi: the first connected adapter that has a gateway. */
int ysys_network(void) {
  ULONG size = 16 * 1024;
  IP_ADAPTER_ADDRESSES* list = (IP_ADAPTER_ADDRESSES*)malloc(size);
  int kind = 0;
  if (!list) return -1;
  if (GetAdaptersAddresses(AF_UNSPEC, GAA_FLAG_INCLUDE_GATEWAYS, NULL, list, &size) == ERROR_BUFFER_OVERFLOW) {
    free(list);
    list = (IP_ADAPTER_ADDRESSES*)malloc(size);
    if (!list) return -1;
  }
  if (GetAdaptersAddresses(AF_UNSPEC, GAA_FLAG_INCLUDE_GATEWAYS, NULL, list, &size) == NO_ERROR) {
    for (IP_ADAPTER_ADDRESSES* a = list; a; a = a->Next) {
      if (a->OperStatus != IfOperStatusUp || !a->FirstGatewayAddress) continue;
      if (a->IfType == IF_TYPE_IEEE80211) { kind = 2; break; }
      if (a->IfType == IF_TYPE_ETHERNET_CSMACD) kind = 1;
    }
  }
  free(list);
  return kind;
}

/* The connected Wi-Fi network's name into buf (up to cap bytes); its length, or -1. */
int ysys_wifi_name(char* buf, int cap) {
  HANDLE h = NULL;
  DWORD ver = 0;
  PWLAN_INTERFACE_INFO_LIST ifs = NULL;
  int n = -1;
  if (WlanOpenHandle(2, NULL, &ver, &h) != ERROR_SUCCESS) return -1;
  if (WlanEnumInterfaces(h, NULL, &ifs) == ERROR_SUCCESS) {
    for (DWORD i = 0; i < ifs->dwNumberOfItems && n < 0; i++) {
      PWLAN_CONNECTION_ATTRIBUTES at = NULL;
      DWORD sz = 0;
      if (ifs->InterfaceInfo[i].isState != wlan_interface_state_connected) continue;
      if (WlanQueryInterface(h, &ifs->InterfaceInfo[i].InterfaceGuid, wlan_intf_opcode_current_connection,
                             NULL, &sz, (PVOID*)&at, NULL) == ERROR_SUCCESS) {
        DOT11_SSID* s = &at->wlanAssociationAttributes.dot11Ssid;
        n = (int)s->uSSIDLength;
        if (n > cap) n = cap;
        memcpy(buf, s->ucSSID, n);
        WlanFreeMemory(at);
      }
    }
    WlanFreeMemory(ifs);
  }
  WlanCloseHandle(h, NULL);
  return n;
}

/* ---- for the dashboard: uptime, resources, who and where ---------------------------------- */

/* Seconds since the machine started. */
int ysys_uptime(void) { return (int)(GetTickCount64() / 1000); }

static ULONGLONG ft(FILETIME t) { return ((ULONGLONG)t.dwHighDateTime << 32) | t.dwLowDateTime; }

/* CPU use 0-100 since the last call (the first call measures from boot), or -1. */
int ysys_cpu(void) {
  static ULONGLONG lastIdle = 0, lastTotal = 0;
  FILETIME idle, kern, user;
  ULONGLONG i, t, di, dt;
  if (!GetSystemTimes(&idle, &kern, &user)) return -1;
  i = ft(idle); t = ft(kern) + ft(user);          /* kernel time includes idle time */
  di = i - lastIdle; dt = t - lastTotal;
  lastIdle = i; lastTotal = t;
  if (dt == 0) return 0;
  return (int)(100 - (di * 100) / dt);
}

/* Memory in use 0-100, or -1. */
int ysys_memory(void) {
  MEMORYSTATUSEX m;
  m.dwLength = sizeof m;
  return GlobalMemoryStatusEx(&m) ? (int)m.dwMemoryLoad : -1;
}

/* The system disk's use 0-100, or -1. */
int ysys_disk(void) {
  ULARGE_INTEGER freeToMe, total, freeAll;
  char dir[MAX_PATH];
  UINT n = GetWindowsDirectoryA(dir, MAX_PATH);
  if (n < 3) strcpy(dir, "C:\\");
  dir[3] = 0;                                     /* "C:\" */
  if (!GetDiskFreeSpaceExA(dir, &freeToMe, &total, &freeAll) || total.QuadPart == 0) return -1;
  return (int)(100 - (freeAll.QuadPart * 100) / total.QuadPart);
}

/* The user's name, the computer's name, the system's name: into buf, their length, or -1. */
int ysys_user(char* buf, int cap) {
  DWORD n = (DWORD)cap;
  return GetUserNameA(buf, &n) ? (int)n - 1 : -1;
}

int ysys_host(char* buf, int cap) {
  DWORD n = (DWORD)cap;
  return GetComputerNameA(buf, &n) ? (int)n : -1;
}

int ysys_os(char* buf, int cap) {
  const char* name = "Windows";
  int n = (int)strlen(name);
  if (n > cap) n = cap;
  memcpy(buf, name, n);
  return n;
}
