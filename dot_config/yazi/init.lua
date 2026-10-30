-- Keep content-based detection for unknown and extensionless local files.
require("mime-ext.local"):setup {
    fallback_file1 = true,
}
