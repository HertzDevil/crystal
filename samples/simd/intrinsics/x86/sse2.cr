lib LibIntrinsics
  fun x86_sse2_psrli_w = "llvm.x86.sse2.psrli.w"(SIMD::IntVector(UInt16, 8), UInt32) : SIMD::IntVector(UInt16, 8)
end

module Intrinsics::X86
  # pxor
  @[AlwaysInline]
  def self.mm_setzero_si128 : UInt8x16
    SIMD::IntVector.literal(
      0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8,
      0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8,
    )
  end

  @[AlwaysInline]
  def self.mm_set1_epi8(a : UInt8) : UInt8x16
    SIMD::IntVector.literal(
      a, a, a, a, a, a, a, a,
      a, a, a, a, a, a, a, a,
    )
  end

  @[AlwaysInline]
  def self.mm_setr_epi8(
    e15 : UInt8, e14 : UInt8, e13 : UInt8, e12 : UInt8, e11 : UInt8, e10 : UInt8, e9 : UInt8, e8 : UInt8,
    e7 : UInt8, e6 : UInt8, e5 : UInt8, e4 : UInt8, e3 : UInt8, e2 : UInt8, e1 : UInt8, e0 : UInt8
  ) : UInt8x16
    SIMD::IntVector.literal(
      e15, e14, e13, e12, e11, e10, e9, e8,
      e7, e6, e5, e4, e3, e2, e1, e0,
    )
  end

  # movdqu
  @[AlwaysInline]
  def self.mm_loadu_si128(mem_addr : UInt8x16*) : UInt8x16
    UInt8x16.unaligned_load(mem_addr)
  end

  # paddb
  @[AlwaysInline]
  def self.mm_add_epi8(a : UInt8x16, b : UInt8x16) : UInt8x16
    a &+ b
  end

  # psubusb
  @[AlwaysInline]
  def self.mm_subs_epu8(a : UInt8x16, b : UInt8x16) : UInt8x16
    a.sat_sub(b)
  end

  # pand
  @[AlwaysInline]
  def self.mm_and_si128(a : UInt8x16, b : UInt8x16) : UInt8x16
    a & b
  end

  # por
  @[AlwaysInline]
  def self.mm_or_si128(a : UInt8x16, b : UInt8x16) : UInt8x16
    a | b
  end

  # psrlw
  @[AlwaysInline]
  def self.mm_srli_epi16(a : UInt16x8, imm8 : Int) : UInt16x8
    LibIntrinsics.x86_sse2_psrli_w(a, imm8.to_u32)
  end

  # pcmpgtb
  @[AlwaysInline]
  def self.mm_cmpgt_epi8(a : Int8x16, b : Int8x16) : Int8x16
    a.greater_than?(b).to_i8
  end

  # TODO: drop this
  @[AlwaysInline]
  def self.mm_cmpgt_epi8(a : UInt8x16, b : UInt8x16) : UInt8x16
    UInt8x16.cast(mm_cmpgt_epi8(Int8x16.cast(a), Int8x16.cast(b)))
  end

  # pcmpeqb
  @[AlwaysInline]
  def self.mm_cmpeq_epi8(a : UInt8x16, b : UInt8x16) : UInt8x16
    UInt8x16.cast(a.equals?(b).to_i8)
  end
end
