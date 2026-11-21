/* SPDX-License-Identifier: Apache-2.0 */
/* Based on https://github.com/osy/ThunderboltPatcher */
/* Derived from AsahiLinux/macvdmtool. DoDFU/DoVDM payloads are unchanged.
   The CLI requires --controller ID --port-number N --rid N. Matching count
   must be exactly 1; otherwise the process fail-closes and sends no VDM. */

#include "AppleHPMLib.h"
#include "ssops.h"
#include "triplet_select.h"
#include "../sender_protocol/mra_sender_protocol.h"
#include <csignal>
#include <cstdio>
#include <cstring>
#include <iostream>
#include <memory>
#include <string>
#include <unistd.h>
#include <vector>
#include <cstdlib>

#include <CoreFoundation/CFNumber.h>
#include <CoreFoundation/CFString.h>
#include <IOKit/IOKitLib.h>

struct failure : public std::runtime_error {
    failure(const char *x) : std::runtime_error(x)
    {
    }
};

struct IOObjectDeleter {
    io_object_t arg;

    IOObjectDeleter(io_object_t arg) : arg(arg)
    {
    }

    ~IOObjectDeleter()
    {
        IOObjectRelease(arg);
    }
};

struct HPMPluginInstance {
    IOCFPlugInInterface **plugin = nullptr;
    AppleHPMLib **device;

    // Raw local-command facts for diagnostics. These do not alter the
    // existing "any non-zero is failure" control flow.
    IOReturn lastCommandIOReturn = kIOReturnSuccess;
    IOReturn lastWriteIOReturn = kIOReturnSuccess;
    int lastRegister9 = -1;
    bool lastRegister9Valid = false;

    HPMPluginInstance(io_service_t service)
    {
        SInt32 score;
        IOReturn ret = IOCreatePlugInInterfaceForService(service, kAppleHPMLibType,
                                                         kIOCFPlugInInterfaceID, &plugin, &score);
        if (ret != kIOReturnSuccess)
            throw failure("IOCreatePlugInInterfaceForService failed");

        HRESULT res = (*plugin)->QueryInterface(plugin, CFUUIDGetUUIDBytes(kAppleHPMLibInterface),
                                                (LPVOID *)&device);
        if (res != S_OK)
            throw failure("QueryInterface failed");
    }

    ~HPMPluginInstance()
    {
        if (plugin) {
            printf("Exiting DBMa mode... ");
            if (this->command(0, 'DBMa', "\x00") == 0)
                printf("OK\n");
            else
                printf("Failed\n");
            IODestroyPlugInInterface(plugin);
        }
    }

    std::string readRegister(uint64_t chipAddr, uint8_t dataAddr, int flags = 0)
    {
        std::string ret;
        ret.resize(64);
        uint64_t rlen = 0;
        IOReturn x = (*device)->Read(device, chipAddr, dataAddr, &ret[0], 64, flags, &rlen);
        if (x != 0)
            throw failure("readRegister failed");
        return ret;
    }

    void writeRegister(uint64_t chipAddr, uint8_t dataAddr, std::string value)
    {
        IOReturn x = (*device)->Write(device, chipAddr, dataAddr, &value[0], value.length(), 0);
        if (x != 0)
            throw failure("writeRegister failed");
    }

    int command(uint64_t chipAddr, uint32_t cmd, std::string args = "")
    {
        lastCommandIOReturn = kIOReturnSuccess;
        lastWriteIOReturn = kIOReturnSuccess;
        lastRegister9 = -1;
        lastRegister9Valid = false;
        if (args.length())
            lastWriteIOReturn = (*device)->Write(device, chipAddr, 9, args.data(), args.length(), 0);
        lastCommandIOReturn = (*device)->Command(device, chipAddr, cmd, 0);
        if (lastCommandIOReturn)
            return -1;
        auto res = this->readRegister(chipAddr, 9);
        lastRegister9 = static_cast<unsigned char>(res[0]);
        lastRegister9Valid = true;
        return res[0] & 0xfu;
    }
};

uint32_t GetUnlockKey()
{
    CFMutableDictionaryRef matching = IOServiceMatching("IOPlatformExpertDevice");
    if (!matching)
        throw failure("IOServiceMatching failed (IOPED)");

    io_iterator_t iter = 0;
    IOObjectDeleter iterDel(iter);
    io_service_t service = IOServiceGetMatchingService(kIOMasterPortDefault, matching);
    if (!service)
        throw failure("IOServiceGetMatchingService failed (IOPED)");

    IOObjectDeleter deviceDel(service);

    io_name_t deviceName;
    if (IORegistryEntryGetName(service, deviceName) != kIOReturnSuccess) {
        throw failure("IORegistryEntryGetName failed (IOPED)");
    }

    printf("Mac type: %s\n", deviceName);

    return (deviceName[0] << 24) | (deviceName[1] << 16) | (deviceName[2] << 8) | deviceName[3];
}

static bool property_is_yes(CFTypeRef value)
{
    if (!value)
        return false;
    CFTypeID kind = CFGetTypeID(value);
    if (kind == CFBooleanGetTypeID())
        return CFBooleanGetValue((CFBooleanRef)value);
    if (kind == CFStringGetTypeID())
        return CFStringCompare((CFStringRef)value, CFSTR("Yes"), 0) == kCFCompareEqualTo;
    if (kind == CFNumberGetTypeID()) {
        int number = 0;
        CFNumberGetValue((CFNumberRef)value, kCFNumberIntType, &number);
        return number != 0;
    }
    return false;
}

static bool entry_is_builtin_port(io_registry_entry_t entry)
{
    io_name_t name;
    if (IORegistryEntryGetName(entry, name) != kIOReturnSuccess)
        return false;
    if (std::strncmp(name, "Port-USB-C", 10) != 0)
        return false;
    CFTypeRef built = IORegistryEntryCreateCFProperty(entry, CFSTR("BuiltIn"), kCFAllocatorDefault, 0);
    bool yes = property_is_yes(built);
    if (built)
        CFRelease(built);
    return yes;
}

static bool subtree_has_builtin_port(io_registry_entry_t entry, int depth)
{
    if (entry_is_builtin_port(entry))
        return true;
    if (depth <= 0)
        return false;
    io_iterator_t iter = 0;
    if (IORegistryEntryGetChildIterator(entry, kIOServicePlane, &iter) != kIOReturnSuccess)
        return false;
    IOObjectDeleter iterDel(iter);
    io_object_t child;
    while ((child = IOIteratorNext(iter))) {
        IOObjectDeleter childDel(child);
        if (subtree_has_builtin_port(child, depth - 1))
            return true;
    }
    return false;
}

struct RidCandidate {
    io_service_t service;
    std::string path;
};

static void release_candidates(std::vector<RidCandidate> &matches)
{
    for (RidCandidate &item : matches) {
        if (item.service)
            IOObjectRelease(item.service);
        item.service = 0;
    }
}

static bool subtree_has_port(io_registry_entry_t entry, int depth)
{
    io_name_t name;
    if (IORegistryEntryGetName(entry, name) == kIOReturnSuccess &&
        std::strncmp(name, "Port-USB-C", 10) == 0)
        return true;
    if (depth <= 0)
        return false;
    io_iterator_t iter = 0;
    if (IORegistryEntryGetChildIterator(entry, kIOServicePlane, &iter) != kIOReturnSuccess)
        return false;
    IOObjectDeleter iterDel(iter);
    io_object_t child;
    while ((child = IOIteratorNext(iter))) {
        IOObjectDeleter childDel(child);
        if (subtree_has_port(child, depth - 1))
            return true;
    }
    return false;
}

struct RidSelection {
    size_t count = 0;
    std::string path;
    std::string reason;
    bool ready = false;
    io_service_t service = 0;
};

static void print_result_json(int32_t requested, size_t count, int selected_rid, bool built_in,
                              bool port_usb_c, bool send_performed, const char *status,
                              const char *reason)
{
    printf("{\"rid_selective\":true,\"requested_rid\":%d,\"candidate_service_count\":%zu,",
           requested, count);
    if (selected_rid < 0)
        printf("\"selected_rid\":null,");
    else
        printf("\"selected_rid\":%d,", selected_rid);
    printf("\"built_in\":%s,\"port_usb_c\":%s,\"send_performed\":%s,\"status\":\"%s\","
           "\"reason\":\"%s\",\"dfu_success\":false}\n",
           built_in ? "true" : "false", port_usb_c ? "true" : "false",
           send_performed ? "true" : "false", status, reason ? reason : "");
    fflush(stdout);
}


static bool read_int32_property(io_registry_entry_t entry, CFStringRef key, int32_t *out)
{
    CFTypeRef data = IORegistryEntryCreateCFProperty(entry, key, kCFAllocatorDefault, 0);
    if (!data)
        return false;
    bool ok = false;
    if (CFGetTypeID(data) == CFNumberGetTypeID())
        ok = CFNumberGetValue((CFNumberRef)data, kCFNumberSInt32Type, out);
    CFRelease(data);
    return ok;
}

/* Hex form matches HostPorts.swift: the digits after ioreg "id 0x". */
static std::string registry_id_hex(io_registry_entry_t entry)
{
    uint64_t entry_id = 0;
    if (IORegistryEntryGetRegistryEntryID(entry, &entry_id) != kIOReturnSuccess)
        return "";
    char buf[32];
    std::snprintf(buf, sizeof(buf), "%llx", (unsigned long long)entry_id);
    return buf;
}

static void collect_port_numbers(io_registry_entry_t entry, int depth, std::vector<int32_t> *out)
{
    int32_t value = 0;
    if (read_int32_property(entry, CFSTR("PortNumber"), &value))
        out->push_back(value);
    if (depth <= 0)
        return;
    io_iterator_t iter = 0;
    if (IORegistryEntryGetChildIterator(entry, kIOServicePlane, &iter) != kIOReturnSuccess)
        return;
    IOObjectDeleter iterDel(iter);
    io_object_t child;
    while ((child = IOIteratorNext(iter))) {
        IOObjectDeleter childDel(child);
        collect_port_numbers(child, depth - 1, out);
    }
}

static bool service_has_port_number(io_service_t device, int32_t wanted)
{
    std::vector<int32_t> numbers;
    collect_port_numbers(device, 4, &numbers);
    for (int32_t n : numbers) {
        if (n == wanted)
            return true;
    }
    return false;
}

/* Count is after controller + PortNumber + RID + BuiltIn + Port-USB-C.
   Probe does not open a plugin and does not send VDM. */
static RidSelection select_triplet(const std::string &controller, int32_t port_number,
                                   int32_t requested_rid, bool retain_unique)
{
    RidSelection result;
    printf("Looking for HPM devices...\n");

    CFMutableDictionaryRef matching = IOServiceMatching("AppleHPM");
    if (!matching)
        throw failure("IOServiceMatching failed");

    io_iterator_t iter = 0;
    IOObjectDeleter iterDel(iter);
    if (IOServiceGetMatchingServices(kIOMasterPortDefault, matching, &iter) != kIOReturnSuccess)
        throw failure("IOServiceGetMatchingServices failed");

    std::vector<RidCandidate> matches;
    int raw_rid_hits = 0;
    int port_without_builtin = 0;
    io_service_t device;
    while ((device = IOIteratorNext(iter))) {
        IOObjectDeleter deviceDel(device);
        io_string_t pathName;

        if (IORegistryEntryGetPath(device, kIOServicePlane, pathName) != kIOReturnSuccess) {
            fprintf(stderr, "Failed to get device path for object %d.\n", device);
            continue;
        }

        CFNumberRef data = (CFNumberRef)IORegistryEntryCreateCFProperty(device, CFSTR("RID"),
                                                                        kCFAllocatorDefault, 0);
        if (!data)
            continue;

        int32_t rid = 0;
        CFNumberGetValue(data, kCFNumberSInt32Type, &rid);
        CFRelease(data);

        if (rid != requested_rid)
            continue;
        raw_rid_hits++;
        bool has_port = subtree_has_port(device, 4);
        bool builtin_port = subtree_has_builtin_port(device, 4);
        if (!has_port || !builtin_port) {
            if (has_port && !builtin_port)
                port_without_builtin++;
            continue;
        }

        std::string got_controller = mra_triplet::normalize_controller_id(registry_id_hex(device));
        if (got_controller != mra_triplet::normalize_controller_id(controller) ||
            !service_has_port_number(device, port_number)) {
            continue;
        }

        if (retain_unique)
            IOObjectRetain(device);
        matches.push_back(RidCandidate{retain_unique ? device : 0, pathName});
    }

    result.count = matches.size();
    if (matches.size() == 1) {
        result.ready = true;
        result.path = matches[0].path;
        result.reason = "";
        result.service = matches[0].service;
        matches.clear();
        return result;
    }
    release_candidates(matches);
    if (matches.size() > 1)
        result.reason = "RID_SERVICE_AMBIGUOUS";
    else if (raw_rid_hits > 0 && port_without_builtin == raw_rid_hits)
        result.reason = "NOT_BUILTIN";
    else if (raw_rid_hits > 0)
        result.reason = "TRIPLET_NOT_PRESENT";
    else
        result.reason = "RID_NOT_PRESENT";
    result.ready = false;
    return result;
};

void UnlockAce(HPMPluginInstance &inst, int no, uint32_t key)
{
    printf("Unlocking... ");
    std::stringstream args;
    put(args, key);
    if (inst.command(no, 'LOCK', args.str())) {
        printf(" Failed.\n");
        printf("Trying to reset... ");
        if (inst.command(no, 'Gaid')) {
            printf("Failed.\n");
            throw failure("Failed to unlock device");
        }
        printf("OK.\nUnlocking... ");
        if (inst.command(no, 'LOCK', args.str())) {
            printf(" Failed.\n");
            throw failure("Failed to unlock device");
        }
    }

    printf("OK\n");
}

void DoVDM(HPMPluginInstance &inst, int no, std::vector<uint32_t> vdm)
{

    auto rs = inst.readRegister(no, 0x4d);
    uint8_t rxst = rs[0];

    std::stringstream args;
    put(args, (uint8_t)(((3 << 4) | vdm.size())));
    for (uint32_t i : vdm)
        put(args, i);

    auto v = args.str();

    if (inst.command(no, 'VDMs', args.str()))
        throw failure("Failed to send VDM\n");

    int i;
    for (i = 0; i < 16; i++) {
        rs = inst.readRegister(no, 0x4d);
        if ((uint8_t)rs[0] != rxst)
            break;
    }
    if (i >= 16)
        throw failure("Did not get a reply to VDM\n");

    uint32_t vdmhdr;
    std::stringstream reply;
    reply.str(rs);
    get(reply, rxst);
    get(reply, vdmhdr);

    if (vdmhdr != (vdm[0] | 0x40)) {
        printf("VDM failed (reply: 0x%08x)\n", vdmhdr);
        throw failure("VDM failed");
    }
}

int DoSerial(HPMPluginInstance &inst, int no)
{
    printf("Putting target into serial mode... ");

    std::vector<uint32_t> serial{0x5ac8012, 0x1840306};
    DoVDM(inst, no, serial);

    printf("OK\n");

    printf("Putting local end into serial mode... ");

    std::stringstream args;
    put(args, (uint32_t)0x1840306);

    int dvEnReturn = inst.command(no, 'DVEn', args.str());
    if (dvEnReturn) {
        // Preserve both possible failure classes without changing the
        // existing failure decision: -1 means IOKit Command/Write failure;
        // 1..15 is the register-9 low nibble status.
        printf("Failed (DVEn return=%d, IOKit=0x%08x, write=0x%08x, reg9=%d%s).\n",
               dvEnReturn,
               static_cast<unsigned int>(inst.lastCommandIOReturn),
               static_cast<unsigned int>(inst.lastWriteIOReturn),
               inst.lastRegister9,
               inst.lastRegister9Valid ? "" : " invalid");
        return 1;
    }
    printf("OK\n");

    return 0;
}

int DoDebugUSB(HPMPluginInstance &inst, int no)
{
    printf("Switching target into debug USB mode... ");

    std::vector<uint32_t> dfu{0x5ac8012, 0x1824606};
    DoVDM(inst, no, dfu);

    printf("OK\n");
    return 0;
}

int DoReboot(HPMPluginInstance &inst, int no)
{
    printf("Rebooting target into normal mode... ");

    std::vector<uint32_t> reboot{0x5ac8012, 0x105, 0x80000000};
    DoVDM(inst, no, reboot);

    printf("OK\n");
    return 0;
}

int WaitConnected(HPMPluginInstance &inst, int no)
{
    printf("Waiting for connection...");
    fflush(stdout);

    sleep(1);
    int i;
    for (i = 0; i < 30; i++) {
        printf(".");
        fflush(stdout);
        auto t = inst.readRegister(no, 0x3f);
        if (t[0] & 1)
            break;
        usleep(100000);
    }
    if (i >= 30) {
        printf(" Timed out\n");
        return 1;
    }
    printf(" Connected\n");
    sleep(1);

    return 0;
}

int DoRebootSerial(HPMPluginInstance &inst, int no)
{
    /* Owner's old `dfu_tool reboot serial`: DoReboot, then WaitConnected
       (30 x 100 ms after a 1 s settle), then DoSerial. Disassembly of the
       old dfu_tool confirms this order. This is serial mode, not macOS
       Recovery. */
    int reboot = DoReboot(inst, no);
    if (reboot != 0)
        return reboot;
    int connected = WaitConnected(inst, no);
    if (connected != 0)
        return connected;
    return DoSerial(inst, no);
}

int DoDFU(HPMPluginInstance &inst, int no)
{
    printf("Rebooting target into DFU mode... ");

    std::vector<uint32_t> dfu{0x5ac8012, 0x106, 0x80010000};
    DoVDM(inst, no, dfu);

    printf("OK\n");
    return 0;
}

static int refuse_triplet(const char *argv0)
{
    print_result_json(0, 0, -1, false, false, false, "BLOCKED", "TRIPLET_REQUIRED");
    printf("Usage: %s\n", mra_triplet::usage_line(argv0, "probe").c_str());
    printf("       %s\n", mra_triplet::usage_line(argv0, "dfu").c_str());
    printf("       %s\n", mra_triplet::usage_line(argv0, "reboot").c_str());
    printf("       %s\n", mra_triplet::usage_line(argv0, "recovery").c_str());
    return 2;
}

/* Select exactly one RID-selective target and reach the DBMa handshake.
   Everything that sends a VDM goes through here, so reboot and dfu share the
   same target discipline. */
static int prepare_target(const std::string &controller, int32_t port_number, int32_t requested_rid,
                           std::unique_ptr<HPMPluginInstance> &inst, int &no)
{
    uint32_t key = GetUnlockKey();
    RidSelection selected = select_triplet(controller, port_number, requested_rid, true);
    if (!selected.ready || selected.count != 1 || !selected.service) {
        if (selected.service)
            IOObjectRelease(selected.service);
        print_result_json(requested_rid, selected.count, -1, false, false, false, "BLOCKED",
                          selected.reason.c_str());
        return 2;
    }

    try {
        inst = std::make_unique<HPMPluginInstance>(selected.service);
    } catch (failure &error) {
        IOObjectRelease(selected.service);
        print_result_json(requested_rid, selected.count, -1, false, false, false, "BLOCKED",
                          "OPEN_FAILED");
        printf("%s\n", error.what());
        return 2;
    }
    IOObjectRelease(selected.service);
    selected.service = 0;

    no = 0;
    auto t = inst->readRegister(no, 0x3f);
    std::string type = (t[0] & 1) ? ((t[0] & 2) == 0 ? "Source" : "Sink") : "None";
    printf("Connection: %s\n", type.c_str());
    if (!(t[0] & 1)) {
        /* The operator explicitly selected this RID. A missing partner report
           no longer aborts the attempt; it is recorded and the one send goes
           ahead, with the real outcome reported afterwards. */
        printf("Connection report: no partner (explicit RID continues)\n");
        fflush(stdout);
    }

    auto res = inst->readRegister(no, 0x03);
    res.erase(res.find('\0'));
    printf("Status: %s\n", res.c_str());
    fflush(stdout);
    if (res != "DBMa") {
        try {
            UnlockAce(*inst, no, key);
            printf("Entering DBMa mode... ");
            if (inst->command(no, 'DBMa', "\x01")) {
                printf("FAILED\n");
                printf("DBMa result: command failed (explicit RID continues)\n");
            } else {
                res = inst->readRegister(no, 0x03);
                res.erase(res.find('\0'));
                printf("Status: %s\n", res.c_str());
                if (res != "DBMa") {
                    printf("DBMa result: not confirmed (explicit RID continues)\n");
                } else {
                    printf("DBMa result: ready\n");
                }
            }
        } catch (failure &error) {
            printf("DBMa result: %s (explicit RID continues)\n", error.what());
        }
        fflush(stdout);
    } else {
        printf("DBMa result: already ready\n");
        fflush(stdout);
    }
    return 0;
}


static int run_dfu(const std::string &controller, int32_t port_number, int32_t requested_rid)
{
    /* The binding is the only thing that makes child stdout authoritative to
       ServiceMain. Without a complete binding this is a manual CLI run and no
       frame is emitted. */
    mra_sender::Binding binding = mra_sender::load_binding();
    std::unique_ptr<HPMPluginInstance> inst;
    int no = 0;
    int prepared = prepare_target(controller, port_number, requested_rid, inst, no);
    if (prepared != 0) {
        /* prepare_target only opens/validates the target; no VDM is sent. */
        mra_sender::emit_receipt(binding, "NOT_DISPATCHED",
                                 "PRE_BOUNDARY_FAILURE", requested_rid,
                                 "direct_rid_dfu");
        return prepared;
    }

    if (binding.complete) {
        /* Checked delivery: if ARMED cannot be flushed to the parent, the
           child must not enter the VDM boundary. The parent treats any
           post-launch absence of a terminal frame as DISPATCH_UNKNOWN. */
        if (!mra_sender::emit_ready(binding, "direct_rid_dfu"))
            return 3;
        if (!mra_sender::emit_armed(binding, "direct_rid_dfu"))
            return 3;
    }

    int dfu = 1;
    try {
        dfu = DoDFU(*inst, no);
    } catch (failure &error) {
        /* ARMED has been emitted: the VDM may already have crossed the wire. */
        mra_sender::emit_receipt(binding, "DISPATCH_UNKNOWN",
                                 "BOUNDARY_ARMED_FAILURE", requested_rid,
                                 "direct_rid_dfu");
        print_result_json(requested_rid, 1, requested_rid, true, true, true,
                          "BLOCKED", "DFU_COMMAND_FAILED");
        throw;
    }
    if (dfu == 0) {
        mra_sender::emit_receipt(binding, "REQUEST_SENT",
                                 "DFU_VDM_SUBMITTED", requested_rid,
                                 "direct_rid_dfu");
    } else {
        mra_sender::emit_receipt(binding, "DISPATCH_UNKNOWN",
                                 "DFU_COMMAND_FAILED", requested_rid,
                                 "direct_rid_dfu");
    }
    /* Destructor releases the HPM plugin. REQUEST_SUBMITTED is not DFU success. */
    print_result_json(requested_rid, 1, requested_rid, true, true, dfu == 0,
                      dfu == 0 ? "REQUEST_SUBMITTED" : "BLOCKED",
                      dfu == 0 ? "" : "DFU_COMMAND_FAILED");
    return dfu == 0 ? 0 : 1;
}

static int run_reboot(const std::string &controller, int32_t port_number, int32_t requested_rid)
{
    /* Same checked-delivery contract as run_dfu: load the binding before the
       target work, and emit no frame for a manual CLI run. */
    mra_sender::Binding binding = mra_sender::load_binding();
    std::unique_ptr<HPMPluginInstance> inst;
    int no = 0;
    int prepared = 0;
    try {
        prepared = prepare_target(controller, port_number, requested_rid, inst, no);
    } catch (failure &error) {
        /* prepare_target sends no VDM; a throw is still pre-boundary. */
        mra_sender::emit_receipt(binding, "NOT_DISPATCHED",
                                 "PRE_BOUNDARY_FAILURE", requested_rid,
                                 "direct_rid_dfu");
        print_result_json(requested_rid, 0, -1, false, false, false, "BLOCKED",
                          "PRE_BOUNDARY_FAILURE");
        printf("%s\n", error.what());
        return 2;
    }
    if (prepared != 0) {
        /* prepare_target only opens/validates the target; no VDM is sent. */
        mra_sender::emit_receipt(binding, "NOT_DISPATCHED",
                                 "PRE_BOUNDARY_FAILURE", requested_rid,
                                 "direct_rid_dfu");
        return prepared;
    }

    if (binding.complete) {
        /* READY and ARMED are checked writes. If either cannot be flushed to
           the parent, do not enter the DoReboot VDM boundary. */
        if (!mra_sender::emit_ready(binding, "direct_rid_dfu"))
            return 3;
        if (!mra_sender::emit_armed(binding, "direct_rid_dfu"))
            return 3;
    }

    int reboot = 1;
    try {
        reboot = DoReboot(*inst, no);
    } catch (failure &error) {
        /* ARMED was flushed: the reboot VDM may already have crossed the wire.
           This is DISPATCH_UNKNOWN, never NOT_DISPATCHED. */
        mra_sender::emit_receipt(binding, "DISPATCH_UNKNOWN",
                                 "BOUNDARY_ARMED_FAILURE", requested_rid,
                                 "direct_rid_dfu");
        print_result_json(requested_rid, 1, requested_rid, true, true, true,
                          "BLOCKED", "REBOOT_COMMAND_FAILED");
        printf("%s\n", error.what());
        return 1;
    }
    if (reboot == 0) {
        mra_sender::emit_receipt(binding, "REQUEST_SENT", "REBOOT_REQUESTED",
                                 requested_rid, "direct_rid_dfu");
    } else {
        mra_sender::emit_receipt(binding, "DISPATCH_UNKNOWN",
                                 "REBOOT_COMMAND_FAILED", requested_rid,
                                 "direct_rid_dfu");
    }
    /* REBOOT_REQUESTED is a receipt, not proof the target rebooted. The JSON
       below is diagnostic only; the framed receipt is the helper authority. */
    print_result_json(requested_rid, 1, requested_rid, true, true, reboot == 0,
                      reboot == 0 ? "REBOOT_REQUESTED" : "BLOCKED",
                      reboot == 0 ? "" : "REBOOT_COMMAND_FAILED");
    return reboot == 0 ? 0 : 1;
}

static int run_recovery(const std::string &controller, int32_t port_number, int32_t requested_rid)
{
    /* Same checked-delivery and single-target contract as run_reboot; only
       the VDM action differs (the Owner's old `reboot serial` serial mode). */
    mra_sender::Binding binding = mra_sender::load_binding();
    std::unique_ptr<HPMPluginInstance> inst;
    int no = 0;
    int prepared = 0;
    try {
        prepared = prepare_target(controller, port_number, requested_rid, inst, no);
    } catch (failure &error) {
        mra_sender::emit_receipt(binding, "NOT_DISPATCHED",
                                 "PRE_BOUNDARY_FAILURE", requested_rid,
                                 "direct_rid_dfu");
        print_result_json(requested_rid, 0, -1, false, false, false, "BLOCKED",
                          "PRE_BOUNDARY_FAILURE");
        printf("%s\n", error.what());
        return 2;
    }
    if (prepared != 0) {
        mra_sender::emit_receipt(binding, "NOT_DISPATCHED",
                                 "PRE_BOUNDARY_FAILURE", requested_rid,
                                 "direct_rid_dfu");
        return prepared;
    }

    if (binding.complete) {
        if (!mra_sender::emit_ready(binding, "direct_rid_dfu"))
            return 3;
        if (!mra_sender::emit_armed(binding, "direct_rid_dfu"))
            return 3;
    }

    int recovery = 1;
    try {
        recovery = DoRebootSerial(*inst, no);
    } catch (failure &error) {
        mra_sender::emit_receipt(binding, "DISPATCH_UNKNOWN",
                                 "BOUNDARY_ARMED_FAILURE", requested_rid,
                                 "direct_rid_dfu");
        print_result_json(requested_rid, 1, requested_rid, true, true, true,
                          "BLOCKED", "RECOVERY_COMMAND_FAILED");
        printf("%s\n", error.what());
        return 1;
    }
    if (recovery == 0) {
        mra_sender::emit_receipt(binding, "REQUEST_SENT", "RECOVERY_REQUESTED",
                                 requested_rid, "direct_rid_dfu");
    } else {
        mra_sender::emit_receipt(binding, "DISPATCH_UNKNOWN",
                                 "RECOVERY_COMMAND_FAILED", requested_rid,
                                 "direct_rid_dfu");
    }
    print_result_json(requested_rid, 1, requested_rid, true, true, recovery == 0,
                      recovery == 0 ? "RECOVERY_REQUESTED" : "BLOCKED",
                      recovery == 0 ? "" : "RECOVERY_COMMAND_FAILED");
    return recovery == 0 ? 0 : 1;
}

int main2(int argc, char **argv)
{
    setvbuf(stdout, nullptr, _IOLBF, 0);
    mra_triplet::CliRequest request;
    if (!mra_triplet::parse_cli(argc, argv, &request)) {
        if (request.reason && std::strcmp(request.reason, "UNKNOWN_COMMAND") == 0) {
            print_result_json(request.rid, 0, -1, false, false, false, "BLOCKED", "UNKNOWN_COMMAND");
            return 2;
        }
        return refuse_triplet(argv[0]);
    }

    if (request.command == "probe") {
        RidSelection selected = select_triplet(request.controller, request.port_number, request.rid, false);
        bool ready = selected.ready && selected.count == 1;
        print_result_json(request.rid, selected.count, ready ? request.rid : -1, ready, ready,
                          false, ready ? "READY" : "BLOCKED", selected.reason.c_str());
        return ready ? 0 : 2;
    }
    if (request.command == "reboot")
        return run_reboot(request.controller, request.port_number, request.rid);
    if (request.command == "recovery")
        return run_recovery(request.controller, request.port_number, request.rid);
    return run_dfu(request.controller, request.port_number, request.rid);
}

int main(int argc, char **argv)
{
    /* A closed stdout must make the checked frame write fail, not kill the
       process before the ARMED gate can abort the VDM. */
    std::signal(SIGPIPE, SIG_IGN);
    // This makes sure we call the HPMPluginInstance destructor.
    try {
        return main2(argc, argv);
    } catch (failure e) {
        printf("%s\n", e.what());
        return 1;
    }
}
