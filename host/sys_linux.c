/* The system, for the desktop's control centre (y_sys, Linux): battery and network from /sys.
   Volume goes through PipeWire next (docs/shell/DUSKY-SPEC.md §11); until then -1, which the
   desktop hides. Every function returns -1 when the value is not known. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>
#include <sys/stat.h>

static int readLine(const char* path, char* buf, int cap) {
  FILE* f = fopen(path, "r");
  int n;
  if (!f) return -1;
  if (!fgets(buf, cap, f)) { fclose(f); return -1; }
  fclose(f);
  n = (int)strlen(buf);
  while (n > 0 && (buf[n - 1] == '\n' || buf[n - 1] == '\r')) buf[--n] = 0;
  return n;
}

static int firstBattery(char* dir, int cap) {
  DIR* d = opendir("/sys/class/power_supply");
  struct dirent* e;
  int found = 0;
  if (!d) return 0;
  while ((e = readdir(d)) && !found) {
    char t[64], p[512];
    snprintf(p, sizeof p, "/sys/class/power_supply/%s/type", e->d_name);
    if (readLine(p, t, sizeof t) > 0 && strcmp(t, "Battery") == 0) {
      snprintf(dir, cap, "/sys/class/power_supply/%s", e->d_name);
      found = 1;
    }
  }
  closedir(d);
  return found;
}

int ysys_battery(void) {
  char dir[512], p[600], v[32];
  if (!firstBattery(dir, sizeof dir)) return -1;
  snprintf(p, sizeof p, "%s/capacity", dir);
  if (readLine(p, v, sizeof v) <= 0) return -1;
  return atoi(v);
}

int ysys_charging(void) {
  char dir[512], p[600], v[32];
  if (!firstBattery(dir, sizeof dir)) return -1;
  snprintf(p, sizeof p, "%s/status", dir);
  if (readLine(p, v, sizeof v) <= 0) return -1;
  return strcmp(v, "Discharging") == 0 ? 0 : 1;
}

int ysys_volume(void) { return -1; }
int ysys_set_volume(int pct) { (void)pct; return 0; }
int ysys_muted(void) { return -1; }
int ysys_set_muted(int on) { (void)on; return 0; }

/* 0 offline, 1 wired, 2 Wi-Fi: an interface other than lo that is up. */
int ysys_network(void) {
  DIR* d = opendir("/sys/class/net");
  struct dirent* e;
  int kind = 0;
  if (!d) return -1;
  while ((e = readdir(d))) {
    char p[512], st[32];
    struct stat sb;
    if (e->d_name[0] == '.' || strcmp(e->d_name, "lo") == 0) continue;
    snprintf(p, sizeof p, "/sys/class/net/%s/operstate", e->d_name);
    if (readLine(p, st, sizeof st) <= 0 || strcmp(st, "up") != 0) continue;
    snprintf(p, sizeof p, "/sys/class/net/%s/wireless", e->d_name);
    if (stat(p, &sb) == 0) { kind = 2; break; }
    kind = 1;
  }
  closedir(d);
  return kind;
}

int ysys_wifi_name(char* buf, int cap) { (void)buf; (void)cap; return -1; }

/* ---- for the dashboard: uptime, resources, who and where ---------------------------------- */
#include <unistd.h>
#include <sys/statvfs.h>

int ysys_uptime(void) {
  char v[64];
  if (readLine("/proc/uptime", v, sizeof v) <= 0) return -1;
  return atoi(v);
}

int ysys_cpu(void) {
  static long long lastIdle = 0, lastTotal = 0;
  char line[256];
  long long u, n, s, i, io, irq, sirq, st, t, di, dt;
  if (readLine("/proc/stat", line, sizeof line) <= 0) return -1;
  if (sscanf(line, "cpu %lld %lld %lld %lld %lld %lld %lld %lld", &u, &n, &s, &i, &io, &irq, &sirq, &st) < 4) return -1;
  t = u + n + s + i + io + irq + sirq + st;
  di = (i + io) - lastIdle; dt = t - lastTotal;
  lastIdle = i + io; lastTotal = t;
  if (dt <= 0) return 0;
  return (int)(100 - (di * 100) / dt);
}

int ysys_memory(void) {
  FILE* f = fopen("/proc/meminfo", "r");
  char k[64];
  long long v, total = -1, avail = -1;
  if (!f) return -1;
  while (fscanf(f, "%63s %lld kB\n", k, &v) == 2) {
    if (strcmp(k, "MemTotal:") == 0) total = v;
    else if (strcmp(k, "MemAvailable:") == 0) avail = v;
  }
  fclose(f);
  if (total <= 0 || avail < 0) return -1;
  return (int)(100 - (avail * 100) / total);
}

int ysys_disk(void) {
  struct statvfs s;
  if (statvfs("/", &s) != 0 || s.f_blocks == 0) return -1;
  return (int)(100 - ((long long)s.f_bavail * 100) / (long long)s.f_blocks);
}

static int copyOut(const char* v, char* buf, int cap) {
  int n;
  if (!v) return -1;
  n = (int)strlen(v);
  if (n > cap) n = cap;
  memcpy(buf, v, n);
  return n;
}

int ysys_user(char* buf, int cap) { return copyOut(getenv("USER"), buf, cap); }

int ysys_host(char* buf, int cap) {
  char h[256];
  if (gethostname(h, sizeof h) != 0) return -1;
  h[255] = 0;
  return copyOut(h, buf, cap);
}

int ysys_os(char* buf, int cap) {
  FILE* f = fopen("/etc/os-release", "r");
  char line[256];
  if (!f) return copyOut("Linux", buf, cap);
  while (fgets(line, sizeof line, f)) {
    if (strncmp(line, "PRETTY_NAME=", 12) == 0) {
      char* v = line + 12;
      int n;
      if (*v == '"') v++;
      n = (int)strlen(v);
      while (n > 0 && (v[n - 1] == '\n' || v[n - 1] == '"')) v[--n] = 0;
      fclose(f);
      return copyOut(v, buf, cap);
    }
  }
  fclose(f);
  return copyOut("Linux", buf, cap);
}
