const Binding = @import("binding_types.zig").Binding;
const bindingForStdHttp = @import("binding_lookup_std_http.zig").bindingForStdHttp;
const bindingForCookieJsonFmt = @import("binding_lookup_cookie_json_fmt.zig").bindingForCookieJsonFmt;
const bindingForTaskTimeStrNet = @import("binding_lookup_task_time_str_net.zig").bindingForTaskTimeStrNet;
const bindingForMemSignalDlopen = @import("binding_lookup_mem_signal_dlopen.zig").bindingForMemSignalDlopen;

pub fn bindingForName(name: []const u8) ?Binding {
    return bindingForStdHttp(name) orelse bindingForCookieJsonFmt(name) orelse bindingForTaskTimeStrNet(name) orelse bindingForMemSignalDlopen(name);
}
