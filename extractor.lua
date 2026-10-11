local ffi = require("ffi")

-- C signatures declaration
ffi.cdef [[
    typedef struct archive archive;
    typedef struct archive_entry archive_entry;

    typedef int64_t la_int64_t;
    typedef int64_t la_ssize_t;

    archive* archive_read_new(void);
    int archive_read_support_filter_all(archive *);
    int archive_read_support_format_all(archive *);
    int archive_read_open_filename(archive *, const char *filename, size_t block_size);
    int archive_read_next_header(archive *, archive_entry **);
    const char* archive_entry_pathname(archive_entry *);
    la_int64_t archive_entry_size(archive_entry *);
    la_ssize_t archive_read_data(archive *, void *buff, size_t len);
    int archive_read_close(archive *);
    int archive_read_free(archive *);
    const char* archive_error_string(archive *);
]]

-- Loading dynamic system library
local archive_lib = ffi.load("archive")

-- Return constants (values from libarchive's archive.h)
local ARCHIVE_OK = 0
local ARCHIVE_EOF = 1
local ARCHIVE_WARN = -20

-- Returns libarchive's last error message, or a fallback when there is none
local function get_error(a)
    local msg = archive_lib.archive_error_string(a)
    if msg == nil then
        return "unknown error"
    end
    return ffi.string(msg)
end

-- Zip slip protection: rejects absolute paths and any ".." component,
-- so no entry can be written outside the current directory
local function is_safe_path(path)
    if path == "" or path:sub(1, 1) == "/" then
        return false
    end
    for part in path:gmatch("[^/]+") do
        if part == ".." then
            return false
        end
    end
    return true
end

-- Wraps a string in single quotes for the shell, escaping inner single quotes
local function shell_quote(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function extract_archive(filepath)
    local a = archive_lib.archive_read_new()
    if a == nil then
        error("Failed to initialize libarchive's reader.")
    end

    -- Support several filters (gzip, bzip2, xz, etc.) and formats (zip, tar, rar, etc.)
    archive_lib.archive_read_support_filter_all(a)
    archive_lib.archive_read_support_format_all(a)

    -- Open the file in disk (Standard 10240 bytes)
    local r = archive_lib.archive_read_open_filename(a, filepath, 10240)
    if r ~= ARCHIVE_OK then
        local err_msg = get_error(a)
        archive_lib.archive_read_free(a)
        error("Error opening file '" .. filepath .. "': " .. err_msg)
    end

    print("=== Reading file: " .. filepath .. " ===")

    -- Pointer to get the reference on each entry (internal file)
    local entry_ptr = ffi.new("archive_entry*[1]")
    local buffer_size = 8192
    local buffer = ffi.new("char[?]", buffer_size)

    while true do
        r = archive_lib.archive_read_next_header(a, entry_ptr)
        if r == ARCHIVE_EOF then
            break -- End of archive
        elseif r == ARCHIVE_WARN then
            -- Partial success: report it and keep going with this entry
            print("Header warning: " .. get_error(a))
        elseif r ~= ARCHIVE_OK then
            print("Header error: " .. get_error(a))
            break
        end

        local entry = entry_ptr[0]
        local pathname = ffi.string(archive_lib.archive_entry_pathname(entry))
        local entry_size = tonumber(archive_lib.archive_entry_size(entry))

        if not is_safe_path(pathname) then
            print("Skipping unsafe path: " .. pathname)
        else
            print(string.format("Extracting: %s (%d bytes)", pathname, entry_size))

            -- Ignoring folder entries (ending in '/')
            if not pathname:match("/$") then
                -- Creates main folders if needed via system's mkdir
                local dir = pathname:match("(.+)/[^/]+$")
                if dir then
                    os.execute("mkdir -p " .. shell_quote(dir))
                end

                local out_file = io.open(pathname, "wb")
                if out_file then
                    while true do
                        local bytes_read = archive_lib.archive_read_data(a, buffer, buffer_size)
                        if bytes_read < 0 then
                            print("Data error in " .. pathname .. ": " .. get_error(a))
                            break
                        elseif bytes_read == 0 then
                            break
                        end
                        out_file:write(ffi.string(buffer, tonumber(bytes_read)))
                    end
                    out_file:close()
                else
                    print("Failed to create output file: " .. pathname)
                end
            end
        end
    end

    -- Frees allocated memory
    archive_lib.archive_read_close(a)
    archive_lib.archive_read_free(a)
    print("Processing finished successfully.\n")
end

-- Entry point: accept files through command line args
if #arg < 1 then
    print("Usage: luajit extractor.lua <file.zip | file.tar.gz | file.rar>")
else
    for _, file in ipairs(arg) do
        extract_archive(file)
    end
end

