local ok, mem = pcall(require, 'pulpo.memory')
if not ok then
	local ffi = require 'engine.ffi'
	ffi.cdef [[
		void *malloc(size_t);
		void free(void *);
		void *realloc(void *, size_t);
		char *strdup(const char *);
		void *memmove(void *, const void *, size_t);
		int memcmp(const void *s1, const void *s2, size_t n);
	]]
end
return mem

