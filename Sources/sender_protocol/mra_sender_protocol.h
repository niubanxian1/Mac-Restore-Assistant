/* SPDX-License-Identifier: Apache-2.0 */
/* Stage 1 Phase B — shared child event framing with checked delivery.
 *
 * A frame is one line:
 *
 *   MRA_CHILD_EVENT_V1 {json}\n
 *
 * Every emit returns false if the line could not be fully written and flushed.
 * direct_rid_dfu treats a failed READY/ARMED write as a hard abort before the
 * VDM; the parent never infers NOT_DISPATCHED from absent output.
 *
 * The binding operation is exactly ENTER_DFU or REBOOT. The frame carries the
 * binding's operation, and MRA_SCOPE_KIND, when present, must match it. */
#ifndef MRA_SENDER_PROTOCOL_H
#define MRA_SENDER_PROTOCOL_H

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>

namespace mra_sender {

static const char *kFrameMagic = "MRA_CHILD_EVENT_V1";
static const int kProtocolVersion = 1;
static const char *kOperationEnterDfu = "ENTER_DFU";
static const char *kOperationReboot = "REBOOT";

struct Binding {
    bool complete = false;
    std::string action_id;
    std::string token_id;
    std::string scope_hash;
    std::string sender_session_id;
    std::string operation;
    long generation = 0;
};

inline bool parse_generation(const char *text, long *out)
{
    if (!text || !*text)
        return false;
    char *end = nullptr;
    long value = std::strtol(text, &end, 10);
    if (!end || *end || value < 0)
        return false;
    *out = value;
    return true;
}

inline const char *env_text(const char *name)
{
    const char *value = std::getenv(name);
    return (value && *value) ? value : "";
}

inline bool supported_operation(const char *operation)
{
    return std::strcmp(operation, kOperationEnterDfu) == 0 ||
           std::strcmp(operation, kOperationReboot) == 0;
}

inline Binding load_binding()
{
    Binding binding;
    const char *action = env_text("MRA_ACTION_ID");
    const char *token = env_text("MRA_TOKEN_ID");
    const char *scope_hash = env_text("MRA_SCOPE_HASH");
    const char *session = env_text("MRA_SENDER_SESSION_ID");
    const char *operation = env_text("MRA_OPERATION");
    const char *generation = env_text("MRA_GENERATION");
    const char *scope_kind = env_text("MRA_SCOPE_KIND");
    if (!*action || !*token || !*scope_hash || !*session || !*operation || !*generation)
        return binding;
    if (!supported_operation(operation))
        return binding;
    if (*scope_kind && std::strcmp(scope_kind, operation) != 0)
        return binding;
    if (!parse_generation(generation, &binding.generation))
        return binding;
    binding.action_id = action;
    binding.token_id = token;
    binding.scope_hash = scope_hash;
    binding.sender_session_id = session;
    binding.operation = operation;
    binding.complete = true;
    return binding;
}

inline void json_escape(const std::string &value, std::string *out)
{
    static const char *hex = "0123456789abcdef";
    out->push_back('"');
    for (unsigned char ch : value) {
        switch (ch) {
        case '"': out->append("\\\""); break;
        case '\\': out->append("\\\\"); break;
        case '\n': out->append("\\n"); break;
        case '\r': out->append("\\r"); break;
        case '\t': out->append("\\t"); break;
        case '\b': out->append("\\b"); break;
        case '\f': out->append("\\f"); break;
        default:
            if (ch < 0x20) {
                out->append("\\u00");
                out->push_back(hex[(ch >> 4) & 0xf]);
                out->push_back(hex[ch & 0xf]);
            } else {
                out->push_back(static_cast<char>(ch));
            }
        }
    }
    out->push_back('"');
}

inline bool emit(const Binding &binding, const char *event_type,
                 const char *dispatch_state, int rid, const char *reason,
                 const char *sender_identity)
{
    if (!binding.complete)
        return true;
    std::string json;
    json.reserve(512);
    json.append("{\"protocol_version\":");
    json.append(std::to_string(kProtocolVersion));
    json.append(",\"event_type\":");
    json_escape(event_type, &json);
    json.append(",\"action_id\":");
    json_escape(binding.action_id, &json);
    json.append(",\"operation\":");
    json_escape(binding.operation, &json);
    json.append(",\"token_id\":");
    json_escape(binding.token_id, &json);
    json.append(",\"generation\":");
    json.append(std::to_string(binding.generation));
    json.append(",\"scope_hash\":");
    json_escape(binding.scope_hash, &json);
    json.append(",\"sender_session_id\":");
    json_escape(binding.sender_session_id, &json);
    json.append(",\"sender_identity\":");
    json_escape(sender_identity, &json);
    if (dispatch_state != nullptr) {
        json.append(",\"dispatch_state\":");
        json_escape(dispatch_state, &json);
        json.append(",\"rid\":");
        json.append(std::to_string(rid));
        json.append(",\"reason\":");
        json_escape(reason != nullptr ? reason : "", &json);
    }
    json.append("}\n");

    std::string line;
    line.reserve(json.size() + 32);
    line.append(kFrameMagic);
    line.push_back(' ');
    line.append(json);
    if (std::fwrite(line.data(), 1, line.size(), stdout) != line.size())
        return false;
    if (std::fflush(stdout) != 0)
        return false;
    return std::ferror(stdout) == 0;
}

inline bool emit_ready(const Binding &binding, const char *sender_identity)
{
    return emit(binding, "SENDER_READY", nullptr, 0, nullptr, sender_identity);
}

inline bool emit_armed(const Binding &binding, const char *sender_identity)
{
    return emit(binding, "BOUNDARY_ARMED", nullptr, 0, nullptr, sender_identity);
}

inline bool emit_receipt(const Binding &binding, const char *state,
                         const char *reason, int rid,
                         const char *sender_identity)
{
    return emit(binding, "DISPATCH_RECEIPT", state, rid, reason, sender_identity);
}

}  // namespace mra_sender

#endif
