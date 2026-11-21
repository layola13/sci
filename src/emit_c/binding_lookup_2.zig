const std = @import("std");
const Binding = @import("binding_types.zig").Binding;

pub fn bindingForBucket2(name: []const u8) ?Binding {
    const all_void: u64 = ~@as(u64, 0);
    return     if (std.mem.eql(u8, name, "sa_cookie_parse_set_cookie"))
        .{ .voids = all_void ^ 0b11, .tag = .cookie_parse }
    else if (std.mem.eql(u8, name, "sa_cookie_last_error"))
        .{ .voids = all_void ^ 0b11, .tag = .cookie_last_error }
    else if (std.mem.eql(u8, name, "sa_cookie_free"))
        .{ .voids = all_void ^ 0b1, .tag = .cookie_free }
    else if (std.mem.eql(u8, name, "sa_cookie_new"))
        .{ .voids = all_void ^ 0b1111, .tag = .cookie_new }
    else if (std.mem.eql(u8, name, "sa_cookie_name"))
        .{ .voids = all_void ^ 0b111, .tag = .cookie_name }
    else if (std.mem.eql(u8, name, "sa_cookie_value"))
        .{ .voids = all_void ^ 0b111, .tag = .cookie_value }
    else if (std.mem.eql(u8, name, "sa_cookie_domain"))
        .{ .voids = all_void ^ 0b111, .tag = .cookie_domain }
    else if (std.mem.eql(u8, name, "sa_cookie_path"))
        .{ .voids = all_void ^ 0b111, .tag = .cookie_path }
    else if (std.mem.eql(u8, name, "sa_cookie_expires"))
        .{ .voids = all_void ^ 0b11, .tag = .cookie_expires }
    else if (std.mem.eql(u8, name, "sa_cookie_max_age"))
        .{ .voids = all_void ^ 0b11, .tag = .cookie_max_age }
    else if (std.mem.eql(u8, name, "sa_cookie_flags"))
        .{ .voids = all_void ^ 0b1111, .tag = .cookie_flags }
    else if (std.mem.eql(u8, name, "sa_cookie_same_site"))
        .{ .voids = all_void ^ 0b11, .tag = .cookie_same_site }
    else if (std.mem.eql(u8, name, "sa_cookie_is_host_only"))
        .{ .voids = all_void ^ 0b11, .tag = .cookie_is_host_only }
    else if (std.mem.eql(u8, name, "sa_cookie_set_domain"))
        .{ .voids = all_void ^ 0b111, .tag = .cookie_set_domain }
    else if (std.mem.eql(u8, name, "sa_cookie_set_path"))
        .{ .voids = all_void ^ 0b111, .tag = .cookie_set_path }
    else if (std.mem.eql(u8, name, "sa_cookie_set_expires"))
        .{ .voids = all_void ^ 0b11, .tag = .cookie_set_expires }
    else if (std.mem.eql(u8, name, "sa_cookie_set_max_age"))
        .{ .voids = all_void ^ 0b11, .tag = .cookie_set_max_age }
    else if (std.mem.eql(u8, name, "sa_cookie_clear_expiry"))
        .{ .voids = all_void ^ 0b1, .tag = .cookie_clear_expiry }
    else if (std.mem.eql(u8, name, "sa_cookie_set_secure"))
        .{ .voids = all_void ^ 0b11, .tag = .cookie_set_secure }
    else if (std.mem.eql(u8, name, "sa_cookie_set_http_only"))
        .{ .voids = all_void ^ 0b11, .tag = .cookie_set_http_only }
    else if (std.mem.eql(u8, name, "sa_cookie_set_partitioned"))
        .{ .voids = all_void ^ 0b11, .tag = .cookie_set_partitioned }
    else if (std.mem.eql(u8, name, "sa_cookie_set_same_site"))
        .{ .voids = all_void ^ 0b11, .tag = .cookie_set_same_site }
    else if (std.mem.eql(u8, name, "sa_cookie_serialize"))
        .{ .voids = all_void ^ 0b111, .tag = .cookie_serialize }
    else if (std.mem.eql(u8, name, "sa_cookie_serialize_pair"))
        .{ .voids = all_void ^ 0b111, .tag = .cookie_serialize_pair }
    else if (std.mem.eql(u8, name, "sa_cookie_is_expired"))
        .{ .voids = all_void ^ 0b111, .tag = .cookie_is_expired }
    else if (std.mem.eql(u8, name, "sa_cookie_domain_match"))
        .{ .voids = all_void ^ 0b11111, .tag = .cookie_domain_match }
    else if (std.mem.eql(u8, name, "sa_cookie_path_match"))
        .{ .voids = all_void ^ 0b11111, .tag = .cookie_path_match }
    else if (std.mem.eql(u8, name, "sa_cookie_header_pair_count"))
        .{ .voids = all_void ^ 0b111, .tag = .cookie_header_pair_count }
    else if (std.mem.eql(u8, name, "sa_cookie_header_pair_at"))
        .{ .voids = all_void ^ 0b111, .tag = .cookie_header_pair_at }
    else if (std.mem.eql(u8, name, "sa_cookie_jar_new"))
        .{ .voids = all_void, .tag = .cookie_jar_new }
    else if (std.mem.eql(u8, name, "sa_cookie_jar_free"))
        .{ .voids = all_void ^ 0b1, .tag = .cookie_jar_free }
    else if (std.mem.eql(u8, name, "sa_cookie_jar_set_policy"))
        .{ .voids = all_void ^ 0b11, .tag = .cookie_jar_set_policy }
    else if (std.mem.eql(u8, name, "sa_cookie_jar_policy"))
        .{ .voids = all_void ^ 0b11, .tag = .cookie_jar_policy }
    else if (std.mem.eql(u8, name, "sa_cookie_jar_store"))
        .{ .voids = all_void ^ 0b1111111, .tag = .cookie_jar_store }
    else if (std.mem.eql(u8, name, "sa_cookie_jar_header"))
        .{ .voids = all_void ^ 0b111111, .tag = .cookie_jar_header }
    else if (std.mem.eql(u8, name, "sa_cookie_jar_count"))
        .{ .voids = all_void ^ 0b11, .tag = .cookie_jar_count }
    else if (std.mem.eql(u8, name, "sa_cookie_jar_at"))
        .{ .voids = all_void ^ 0b11, .tag = .cookie_jar_at }
    else if (std.mem.eql(u8, name, "sa_cookie_jar_clear"))
        .{ .voids = all_void ^ 0b1, .tag = .cookie_jar_clear }
    else if (std.mem.eql(u8, name, "sa_cookie_jar_evict_expired"))
        .{ .voids = all_void ^ 0b111, .tag = .cookie_jar_evict_expired }
    else if (std.mem.eql(u8, name, "sa_cookie_jar_save"))
        .{ .voids = all_void ^ 0b111, .tag = .cookie_jar_save }
    else if (std.mem.eql(u8, name, "sa_cookie_jar_load"))
        .{ .voids = all_void ^ 0b1111, .tag = .cookie_jar_load }
    else if (std.mem.eql(u8, name, "sa_cookie_jar_request_header"))
        .{ .voids = all_void ^ 0b11111, .tag = .cookie_jar_request_header }
    else if (std.mem.eql(u8, name, "sa_cookie_jar_store_response"))
        .{ .voids = all_void ^ 0b11111, .tag = .cookie_jar_store_response }
    else if (std.mem.eql(u8, name, "sa_json_writer_new"))
        .{ .voids = all_void ^ 0b100000, .tag = .json_writer_new }
    else if (std.mem.eql(u8, name, "sa_json_writer_begin_object"))
        .{ .voids = all_void ^ 0b1, .tag = .json_writer_begin_object }
    else if (std.mem.eql(u8, name, "sa_json_writer_end_object"))
        .{ .voids = all_void ^ 0b1, .tag = .json_writer_end_object }
    else if (std.mem.eql(u8, name, "sa_json_writer_begin_array"))
        .{ .voids = all_void ^ 0b1, .tag = .json_writer_begin_array }
    else if (std.mem.eql(u8, name, "sa_json_writer_end_array"))
        .{ .voids = all_void ^ 0b1, .tag = .json_writer_end_array }
    else if (std.mem.eql(u8, name, "sa_json_writer_field_bool"))
        .{ .voids = all_void ^ 0b1111, .tag = .json_writer_field_bool }
    else if (std.mem.eql(u8, name, "sa_json_writer_field_i64"))
        .{ .voids = all_void ^ 0b1111, .tag = .json_writer_field_i64 }
    else if (std.mem.eql(u8, name, "sa_json_writer_field_f64"))
        .{ .voids = all_void ^ 0b1111, .tag = .json_writer_field_f64 }
    else if (std.mem.eql(u8, name, "sa_json_writer_field_string"))
        .{ .voids = all_void ^ 0b11111, .tag = .json_writer_field_string }
    else if (std.mem.eql(u8, name, "sa_json_writer_object_field"))
        .{ .voids = all_void ^ 0b111, .tag = .json_writer_object_field }
    else if (std.mem.eql(u8, name, "sa_json_writer_write_bool"))
        .{ .voids = all_void ^ 0b11, .tag = .json_writer_write_bool }
    else if (std.mem.eql(u8, name, "sa_json_writer_write_i64"))
        .{ .voids = all_void ^ 0b11, .tag = .json_writer_write_i64 }
    else if (std.mem.eql(u8, name, "sa_json_writer_write_f64"))
        .{ .voids = all_void ^ 0b11, .tag = .json_writer_write_f64 }
    else if (std.mem.eql(u8, name, "sa_json_writer_write_string"))
        .{ .voids = all_void ^ 0b111, .tag = .json_writer_write_string }
    else if (std.mem.eql(u8, name, "sa_json_writer_write_null"))
        .{ .voids = all_void ^ 0b1, .tag = .json_writer_write_null }
    else if (std.mem.eql(u8, name, "sa_json_writer_finish"))
        .{ .voids = all_void ^ 0b11, .tag = .json_writer_finish }
    else if (std.mem.eql(u8, name, "sa_json_writer_free"))
        .{ .voids = all_void ^ 0b1, .tag = .json_writer_free }
    else if (std.mem.eql(u8, name, "sa_json_buffer_data"))
        .{ .voids = all_void ^ 0b1, .tag = .json_buffer_data }
    else if (std.mem.eql(u8, name, "sa_json_buffer_len"))
        .{ .voids = all_void ^ 0b1, .tag = .json_buffer_len }
    else if (std.mem.eql(u8, name, "sa_json_buffer_free"))
        .{ .voids = all_void ^ 0b1, .tag = .json_buffer_free }
    else if (std.mem.eql(u8, name, "sa_json_parse"))
        .{ .voids = all_void ^ 0b11, .tag = .json_parse }
    else if (std.mem.eql(u8, name, "sa_json_free"))
        .{ .voids = all_void ^ 0b1, .tag = .json_free }
    else if (std.mem.eql(u8, name, "sa_json_object_get"))
        .{ .voids = all_void ^ 0b1111, .tag = .json_object_get }
    else if (std.mem.eql(u8, name, "sa_json_object_get_i64"))
        .{ .voids = all_void ^ 0b1111, .tag = .json_object_get_i64 }
    else if (std.mem.eql(u8, name, "sa_json_object_get_string"))
        .{ .voids = all_void ^ 0b11111, .tag = .json_object_get_string }
    else if (std.mem.eql(u8, name, "sa_json_object_get_bool"))
        .{ .voids = all_void ^ 0b1111, .tag = .json_object_get_bool }
    else if (std.mem.eql(u8, name, "sa_json_array_get"))
        .{ .voids = all_void ^ 0b111, .tag = .json_array_get }
    else if (std.mem.eql(u8, name, "sa_json_value_count"))
        .{ .voids = all_void ^ 0b11, .tag = .json_value_count }
    else if (std.mem.eql(u8, name, "sa_json_object_set_string"))
        .{ .voids = all_void ^ 0b11111, .tag = .json_object_set_string }
    else if (std.mem.eql(u8, name, "sa_json_object_set_i64"))
        .{ .voids = all_void ^ 0b1111, .tag = .json_object_set_i64 }
    else if (std.mem.eql(u8, name, "sa_json_object_set_f64"))
        .{ .voids = all_void ^ 0b1111, .tag = .json_object_set_f64 }
    else if (std.mem.eql(u8, name, "sa_json_object_set_bool"))
        .{ .voids = all_void ^ 0b1111, .tag = .json_object_set_bool }
    else if (std.mem.eql(u8, name, "sa_json_object_set_null"))
        .{ .voids = all_void ^ 0b111, .tag = .json_object_set_null }
    else if (std.mem.eql(u8, name, "sa_json_object_set_node"))
        .{ .voids = all_void ^ 0b1111, .tag = .json_object_set_node }
    else if (std.mem.eql(u8, name, "sa_json_object_remove"))
        .{ .voids = all_void ^ 0b111, .tag = .json_object_remove }
    else if (std.mem.eql(u8, name, "sa_json_array_push_string"))
        .{ .voids = all_void ^ 0b111, .tag = .json_array_push_string }
    else if (std.mem.eql(u8, name, "sa_json_array_push_i64"))
        .{ .voids = all_void ^ 0b11, .tag = .json_array_push_i64 }
    else if (std.mem.eql(u8, name, "sa_json_array_push_f64"))
        .{ .voids = all_void ^ 0b11, .tag = .json_array_push_f64 }
    else if (std.mem.eql(u8, name, "sa_json_array_push_bool"))
        .{ .voids = all_void ^ 0b11, .tag = .json_array_push_bool }
    else if (std.mem.eql(u8, name, "sa_json_array_push_null"))
        .{ .voids = all_void ^ 0b1, .tag = .json_array_push_null }
    else if (std.mem.eql(u8, name, "sa_json_array_push_node"))
        .{ .voids = all_void ^ 0b11, .tag = .json_array_push_node }
    else if (std.mem.eql(u8, name, "sa_json_as_i64"))
        .{ .voids = all_void ^ 0b11, .tag = .json_as_i64 }
    else if (std.mem.eql(u8, name, "sa_regex_compile"))
        .{ .voids = all_void ^ 0b111, .tag = .regex_compile }
    else if (std.mem.eql(u8, name, "sa_regex_match"))
        .{ .voids = all_void ^ 0b111, .tag = .regex_match }
    else if (std.mem.eql(u8, name, "sa_regex_group_ptr"))
        .{ .voids = all_void ^ 0b11, .tag = .regex_group_ptr }
    else if (std.mem.eql(u8, name, "sa_regex_group_len"))
        .{ .voids = all_void ^ 0b11, .tag = .regex_group_len }
    else if (std.mem.eql(u8, name, "sa_regex_group_start"))
        .{ .voids = all_void ^ 0b11, .tag = .regex_group_start }
    else if (std.mem.eql(u8, name, "sa_regex_group_count"))
        .{ .voids = all_void ^ 0b1, .tag = .regex_group_count }
    else if (std.mem.eql(u8, name, "sa_regex_free"))
        .{ .voids = all_void ^ 0b1, .tag = .regex_free }
    else if (std.mem.eql(u8, name, "sa_regex_match_free"))
        .{ .voids = all_void, .tag = .regex_match_free }
    else if (std.mem.eql(u8, name, "sa_regex_match_all"))
        .{ .voids = all_void ^ 0b111, .tag = .regex_match_all }
    else if (std.mem.eql(u8, name, "sa_regex_match_list_count"))
        .{ .voids = all_void ^ 0b1, .tag = .regex_match_list_count }
    else if (std.mem.eql(u8, name, "sa_regex_match_list_at"))
        .{ .voids = all_void ^ 0b11, .tag = .regex_match_list_at }
    else if (std.mem.eql(u8, name, "sa_regex_match_list_free"))
        .{ .voids = all_void, .tag = .regex_match_list_free }
    else if (std.mem.eql(u8, name, "sa_regex_replace"))
        .{ .voids = all_void ^ 0b11111, .tag = .regex_replace }
    else if (std.mem.eql(u8, name, "sa_regex_replace_all"))
        .{ .voids = all_void ^ 0b11111, .tag = .regex_replace_all }
    else if (std.mem.eql(u8, name, "sa_regex_buffer_data"))
        .{ .voids = all_void ^ 0b1, .tag = .regex_buffer_data }
    else if (std.mem.eql(u8, name, "sa_regex_buffer_len"))
        .{ .voids = all_void ^ 0b1, .tag = .regex_buffer_len }
    else if (std.mem.eql(u8, name, "sa_regex_buffer_free"))
        .{ .voids = all_void, .tag = .regex_buffer_free }
    else if (std.mem.eql(u8, name, "sa_regex_split"))
        .{ .voids = all_void ^ 0b1111, .tag = .regex_split }
    else if (std.mem.eql(u8, name, "sa_regex_split_count"))
        .{ .voids = all_void ^ 0b1, .tag = .regex_split_count }
    else if (std.mem.eql(u8, name, "sa_regex_split_ptr"))
        .{ .voids = all_void ^ 0b11, .tag = .regex_split_ptr }
    else if (std.mem.eql(u8, name, "sa_regex_split_len"))
        .{ .voids = all_void ^ 0b11, .tag = .regex_split_len }
    else if (std.mem.eql(u8, name, "sa_regex_split_free"))
        .{ .voids = all_void, .tag = .regex_split_free }
    else if (std.mem.eql(u8, name, "sa_sync_mutex_new"))
        .{ .voids = all_void ^ 0b1, .tag = .task_out0 }
    else if (std.mem.eql(u8, name, "sa_sync_rwlock_new"))
        .{ .voids = all_void ^ 0b1, .tag = .task_out0 }
    else if (std.mem.eql(u8, name, "sa_sync_waitgroup_new"))
        .{ .voids = all_void ^ 0b1, .tag = .task_out0 }
    else if (std.mem.eql(u8, name, "sa_sync_once_new"))
        .{ .voids = all_void ^ 0b1, .tag = .task_out0 }
    else if (std.mem.eql(u8, name, "sa_sync_destroy"))
        .{ .voids = all_void ^ 0b1, .tag = .task_handle_ret }
    else if (std.mem.eql(u8, name, "sa_sync_mutex_lock"))
        .{ .voids = all_void ^ 0b1, .tag = .task_handle_ret }
    else if (std.mem.eql(u8, name, "sa_sync_mutex_try_lock"))
        .{ .voids = all_void ^ 0b11, .tag = .task_try_lock }
    else if (std.mem.eql(u8, name, "sa_sync_mutex_unlock"))
        .{ .voids = all_void ^ 0b1, .tag = .task_handle_ret }
    else if (std.mem.eql(u8, name, "sa_sync_rwlock_rlock"))
        .{ .voids = all_void ^ 0b1, .tag = .task_handle_ret }
    else if (std.mem.eql(u8, name, "sa_sync_rwlock_runlock"))
        .{ .voids = all_void ^ 0b1, .tag = .task_handle_ret }
    else if (std.mem.eql(u8, name, "sa_sync_rwlock_lock"))
        .{ .voids = all_void ^ 0b1, .tag = .task_handle_ret }
    else if (std.mem.eql(u8, name, "sa_sync_rwlock_unlock"))
        .{ .voids = all_void ^ 0b1, .tag = .task_handle_ret }
    else if (std.mem.eql(u8, name, "sa_sync_waitgroup_add"))
        .{ .voids = all_void ^ 0b11, .tag = .task_wg_add }
    else if (std.mem.eql(u8, name, "sa_sync_waitgroup_done"))
        .{ .voids = all_void ^ 0b1, .tag = .task_handle_ret }
    else if (std.mem.eql(u8, name, "sa_sync_waitgroup_wait"))
        .{ .voids = all_void ^ 0b1, .tag = .task_handle_ret }
    else if (std.mem.eql(u8, name, "sa_sync_once_do"))
        .{ .voids = all_void ^ 0b111, .tag = .task_once_do }
    else if (std.mem.eql(u8, name, "sa_string_concat"))
        .{ .voids = all_void ^ 0b1111, .tag = .string_concat }
    else if (std.mem.eql(u8, name, "sa_string_index_of"))
        .{ .voids = all_void ^ 0b11111, .tag = .string_index_of }
    else if (std.mem.eql(u8, name, "sa_string_last_index_of"))
        .{ .voids = all_void ^ 0b11111, .tag = .string_last_index_of }
    else if (std.mem.eql(u8, name, "sa_string_starts_with"))
        .{ .voids = all_void ^ 0b1111, .tag = .string_starts_with }
    else if (std.mem.eql(u8, name, "sa_string_ends_with"))
        .{ .voids = all_void ^ 0b1111, .tag = .string_ends_with }
    else if (std.mem.eql(u8, name, "sa_string_to_lower_ascii"))
        .{ .voids = all_void ^ 0b11, .tag = .string_to_lower_ascii }
    else if (std.mem.eql(u8, name, "sa_string_to_upper_ascii"))
        .{ .voids = all_void ^ 0b11, .tag = .string_to_upper_ascii }
    else if (std.mem.eql(u8, name, "sa_string_repeat"))
        .{ .voids = all_void ^ 0b111, .tag = .string_repeat }
    else if (std.mem.eql(u8, name, "sa_string_pad_start"))
        .{ .voids = all_void ^ 0b11111, .tag = .string_pad_start }
    else if (std.mem.eql(u8, name, "sa_string_pad_end"))
        .{ .voids = all_void ^ 0b11111, .tag = .string_pad_end }
    else if (std.mem.eql(u8, name, "sa_string_from_char_code"))
        .{ .voids = all_void ^ 0b1, .tag = .string_from_char_code }
    else if (std.mem.eql(u8, name, "sa_string_from_code_point"))
        .{ .voids = all_void ^ 0b1, .tag = .string_from_code_point }
    else if (std.mem.eql(u8, name, "sa_string_code_point_at"))
        .{ .voids = all_void ^ 0b111, .tag = .string_code_point_at }
    else if (std.mem.eql(u8, name, "sa_string_replace"))
        .{ .voids = all_void ^ 0b1111111, .tag = .string_replace }
    else if (std.mem.eql(u8, name, "sa_fmt_i64_into"))
        .{ .voids = all_void ^ 0b11111, .tag = .fmt_i64_into }
    else if (std.mem.eql(u8, name, "sa_fmt_u64_into"))
        .{ .voids = all_void ^ 0b11111, .tag = .fmt_u64_into }
    else if (std.mem.eql(u8, name, "sa_fmt_f64_into"))
        .{ .voids = all_void ^ 0b11111, .tag = .fmt_f64_into }
    else if (std.mem.eql(u8, name, "sa_fmt_bool_into"))
        .{ .voids = all_void ^ 0b1111, .tag = .fmt_bool_into }
    else if (std.mem.eql(u8, name, "sa_fmt_bytes_into"))
        .{ .voids = all_void ^ 0b11111, .tag = .fmt_bytes_into }
    else if (std.mem.eql(u8, name, "sa_fmt_i64"))
        .{ .voids = all_void ^ 0b11, .tag = .fmt_i64 }
    else if (std.mem.eql(u8, name, "sa_fmt_u64"))
        .{ .voids = all_void ^ 0b11, .tag = .fmt_u64 }
    else if (std.mem.eql(u8, name, "sa_fmt_f64"))
        .{ .voids = all_void ^ 0b11, .tag = .fmt_f64 }
    else if (std.mem.eql(u8, name, "sa_fmt_bool"))
        .{ .voids = all_void ^ 0b1, .tag = .fmt_bool }
    else if (std.mem.eql(u8, name, "sa_fmt_bytes"))
        .{ .voids = all_void ^ 0b11, .tag = .fmt_bytes }
    else if (std.mem.eql(u8, name, "sa_fmt_buffer_data"))
        .{ .voids = all_void ^ 0b1, .tag = .fmt_buffer_data }
    else if (std.mem.eql(u8, name, "sa_fmt_buffer_len"))
        .{ .voids = all_void ^ 0b1, .tag = .fmt_buffer_len }
    else if (std.mem.eql(u8, name, "sa_fmt_buffer_free"))
        .{ .voids = all_void ^ 0b1, .tag = .fmt_buffer_free }
    else if (std.mem.eql(u8, name, "npm_totalmem"))
        .{ .voids = all_void, .tag = .npm_totalmem }
    else if (std.mem.eql(u8, name, "npm_parallelism"))
        .{ .voids = all_void, .tag = .npm_parallelism }
    else if (std.mem.eql(u8, name, "npm_isabs"))
        .{ .voids = all_void ^ 0b11, .tag = .npm_isabs }
    else if (std.mem.eql(u8, name, "npm_iseq"))
        .{ .voids = all_void ^ 0b1111, .tag = .npm_iseq }
    else
        null;
}
