lib LibIntrinsics
  fun x86_avx_ptestz_256 = "llvm.x86.avx.ptestz.256"(SIMD::IntVector(UInt64, 4), SIMD::IntVector(UInt64, 4)) : UInt32
end

module Intrinsics::X86
  # vpxor
  @[AlwaysInline]
  def self.mm256_setzero_si256 : UInt8x32
    SIMD::IntVector.literal(
      0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8,
      0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8,
      0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8,
      0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8,
    )
  end

  # vpbroadcastb
  @[AlwaysInline]
  def self.mm256_set1_epi8(a : UInt8) : UInt8x32
    SIMD::IntVector.literal(
      a, a, a, a, a, a, a, a,
      a, a, a, a, a, a, a, a,
      a, a, a, a, a, a, a, a,
      a, a, a, a, a, a, a, a,
    )
  end

  @[AlwaysInline]
  def self.mm256_setr_epi8(
    e31 : UInt8, e30 : UInt8, e29 : UInt8, e28 : UInt8, e27 : UInt8, e26 : UInt8, e25 : UInt8, e24 : UInt8,
    e23 : UInt8, e22 : UInt8, e21 : UInt8, e20 : UInt8, e19 : UInt8, e18 : UInt8, e17 : UInt8, e16 : UInt8,
    e15 : UInt8, e14 : UInt8, e13 : UInt8, e12 : UInt8, e11 : UInt8, e10 : UInt8, e9 : UInt8, e8 : UInt8,
    e7 : UInt8, e6 : UInt8, e5 : UInt8, e4 : UInt8, e3 : UInt8, e2 : UInt8, e1 : UInt8, e0 : UInt8
  ) : UInt8x32
    SIMD::IntVector.literal(
      e31, e30, e29, e28, e27, e26, e25, e24,
      e23, e22, e21, e20, e19, e18, e17, e16,
      e15, e14, e13, e12, e11, e10, e9, e8,
      e7, e6, e5, e4, e3, e2, e1, e0,
    )
  end

  # vmovdqu
  @[AlwaysInline]
  def self.mm256_loadu_si256(mem_addr : UInt8x32*) : UInt8x32
    UInt8x32.unaligned_load(mem_addr)
  end

  # vtestz
  @[AlwaysInline]
  def self.mm256_testz_si256(a, b)
    LibIntrinsics.x86_avx_ptestz_256(UInt64x4.cast(a), UInt64x4.cast(b))
  end
end
