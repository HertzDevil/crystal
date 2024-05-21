lib LibIntrinsics
  fun x86_sse41_ptestz = "llvm.x86.sse41.ptestz"(SIMD::IntVector(UInt64, 2), SIMD::IntVector(UInt64, 2)) : UInt32
end

module Intrinsics::X86
  # ptest
  @[AlwaysInline]
  def self.mm_testz_si128(a, b)
    LibIntrinsics.x86_sse41_ptestz(UInt64x2.cast(a), UInt64x2.cast(b))
  end
end
