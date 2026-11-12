/* SPDX-License-Identifier: Apache-2.0 */
/* Pure CLI / candidate matching for the controller + PortNumber + RID triplet.
   This header has no IOKit dependency so it can be unit-tested offline. */

#ifndef MRA_TRIPLET_SELECT_H
#define MRA_TRIPLET_SELECT_H

#include <cstdint>
#include <cstdlib>
#include <string>
#include <vector>

namespace mra_triplet {

struct CliRequest {
    std::string command;
    std::string controller;
    int32_t port_number = -1;
    int32_t rid = 0;
    bool have_controller = false;
    bool have_port = false;
    bool have_rid = false;
    bool ok = false;
    const char *reason = "TRIPLET_REQUIRED";
};

inline std::string normalize_controller_id(const std::string &value)
{
    std::string out = value;
    while (!out.empty() && (out.front() == ' ' || out.front() == '\t'))
        out.erase(out.begin());
    while (!out.empty() && (out.back() == ' ' || out.back() == '\t'))
        out.pop_back();
    if (out.size() >= 2 && out[0] == '0' && (out[1] == 'x' || out[1] == 'X'))
        out.erase(0, 2);
    for (char &ch : out) {
        if (ch >= 'A' && ch <= 'F')
            ch = static_cast<char>(ch - 'A' + 'a');
    }
    return out;
}

inline std::string usage_line(const char *argv0, const char *command)
{
    std::string name = argv0 ? argv0 : "direct_rid_dfu";
    std::string verb = command ? command : "probe";
    return name + " " + verb + " --controller ID --port-number N --rid N";
}

struct TripletCandidate {
    std::string controller;
    int32_t port_number = -1;
    int32_t rid = 0;
};

/* Exact controller + PortNumber + RID. No first-item or RID-only fallback. */
inline size_t count_triplet_matches(const std::vector<TripletCandidate> &candidates,
                                    const std::string &controller,
                                    int32_t port_number,
                                    int32_t rid)
{
    const std::string want = normalize_controller_id(controller);
    size_t count = 0;
    for (const TripletCandidate &item : candidates) {
        if (item.rid == rid && item.port_number == port_number &&
            normalize_controller_id(item.controller) == want)
            count++;
    }
    return count;
}

inline bool parse_int32_token(const std::string &value, int32_t *out)
{
    if (value.empty() || !out)
        return false;
    char *end = nullptr;
    long parsed = std::strtol(value.c_str(), &end, 10);
    if (!end || *end)
        return false;
    *out = (int32_t)parsed;
    return true;
}

inline bool parse_cli(int argc, char **argv, CliRequest *out)
{
    CliRequest request;
    if (!out)
        return false;
    for (int index = 1; index < argc; index++) {
        std::string arg = argv[index];
        if (arg == "--rid" || arg == "--controller" || arg == "--port-number") {
            if (index + 1 >= argc) {
                *out = request;
                return false;
            }
            std::string value = argv[++index];
            if (arg == "--rid") {
                if (!parse_int32_token(value, &request.rid)) {
                    *out = request;
                    return false;
                }
                request.have_rid = true;
            } else if (arg == "--controller") {
                if (normalize_controller_id(value).empty()) {
                    *out = request;
                    return false;
                }
                request.controller = value;
                request.have_controller = true;
            } else {
                if (!parse_int32_token(value, &request.port_number) || request.port_number < 0) {
                    *out = request;
                    return false;
                }
                request.have_port = true;
            }
        } else if (request.command.empty()) {
            request.command = arg;
        } else {
            *out = request;
            return false;
        }
    }
    if (!request.have_rid || !request.have_controller || !request.have_port ||
        request.command.empty()) {
        request.reason = "TRIPLET_REQUIRED";
        *out = request;
        return false;
    }
    if (request.command != "probe" && request.command != "dfu" && request.command != "reboot" && request.command != "recovery") {
        request.reason = "UNKNOWN_COMMAND";
        *out = request;
        return false;
    }
    request.ok = true;
    request.reason = "";
    *out = request;
    return true;
}

} /* namespace mra_triplet */

#endif
