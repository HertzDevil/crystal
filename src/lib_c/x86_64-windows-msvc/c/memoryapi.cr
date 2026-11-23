lib LibC
  MEM_COMMIT     = 0x00001000_u32
  MEM_RESERVE    = 0x00002000_u32
  MEM_RESET      = 0x00080000_u32
  MEM_RESET_UNDO = 0x01000000_u32

  fun VirtualAlloc(lpAddress : Void*, dwSize : SizeT, flAllocationType : DWORD, flProtect : DWORD) : Void*

  MEM_DECOMMIT = 0x4000_u32
  MEM_RELEASE  = 0x8000_u32

  fun VirtualFree(lpAddress : Void*, dwSize : SizeT, dwFreeType : DWORD) : BOOL
  fun VirtualProtect(lpAddress : Void*, dwSize : SizeT, flNewProtect : DWORD, lpfOldProtect : DWORD*) : BOOL
  fun VirtualQuery(lpAddress : Void*, lpBuffer : MEMORY_BASIC_INFORMATION*, dwLength : SizeT) : SizeT

  FILE_MAP_WRITE = 2_u32
  FILE_MAP_READ  = 4_u32

  fun CreateFileMappingA(hFile : HANDLE, lpFileMappingAttributes : SECURITY_ATTRIBUTES*, flProtect : DWORD, dwMaximumSizeHigh : DWORD, dwMaximumSizeLow : DWORD, lpName : LPSTR) : HANDLE
  fun MapViewOfFile(hFileMappingObject : HANDLE, dwDesiredAccess : DWORD, dwFileOffsetHigh : DWORD, dwFileOffsetLow : DWORD, dwNumberOfBytesToMap : SizeT) : Void*
  fun UnmapViewOfFile(lpBaseAddress : Void*) : Bool
end
