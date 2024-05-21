lib LibIntrinsics
  fun x86_avx2_psrli_w = "llvm.x86.avx2.psrli.w"(SIMD::IntVector(UInt16, 16), UInt32) : SIMD::IntVector(UInt16, 16)
  fun x86_avx2_pshuf_b = "llvm.x86.avx2.pshuf.b"(SIMD::IntVector(UInt8, 32), SIMD::IntVector(UInt8, 32)) : SIMD::IntVector(UInt8, 32)
end

module Intrinsics::X86
  # vpaddb
  @[AlwaysInline]
  def self.mm256_add_epi8(a : UInt8x32, b : UInt8x32) : UInt8x32
    a &+ b
  end

  # vpsubusb
  @[AlwaysInline]
  def self.mm256_subs_epu8(a : UInt8x32, b : UInt8x32) : UInt8x32
    a.sat_sub(b)
  end

  # vpand
  @[AlwaysInline]
  def self.mm256_and_si256(a : UInt8x32, b : UInt8x32) : UInt8x32
    a & b
  end

  # vpor
  @[AlwaysInline]
  def self.mm256_or_si256(a : UInt8x32, b : UInt8x32) : UInt8x32
    a | b
  end

  # vpsrlw
  @[AlwaysInline]
  def self.mm256_srli_epi16(a : UInt16x16, imm8 : Int) : UInt16x16
    LibIntrinsics.x86_avx2_psrli_w(a, imm8.to_u32)
  end

  # vpcmpgtb
  @[AlwaysInline]
  def self.mm256_cmpgt_epi8(a : Int8x32, b : Int8x32) : Int8x32
    a.greater_than?(b).to_i8
  end

  # TODO: drop this
  @[AlwaysInline]
  def self.mm256_cmpgt_epi8(a : UInt8x32, b : UInt8x32) : UInt8x32
    UInt8x32.cast(mm256_cmpgt_epi8(Int8x32.cast(a), Int8x32.cast(b)))
  end

  # pcmpeqb
  @[AlwaysInline]
  def self.mm256_cmpeq_epi8(a : UInt8x32, b : UInt8x32) : UInt8x32
    UInt8x32.cast(a.equals?(b).to_i8)
  end

  # vpshufb
  @[AlwaysInline]
  def self.mm256_shuffle_epi8(a : UInt8x32, b : UInt8x32) : UInt8x32
    LibIntrinsics.x86_avx2_pshuf_b(a, b)
  end

  # vpalignr
  macro mm256_alignr_epi8(a, b, imm8)
    ::Intrinsics::X86.clang_builtin_ia32_palignr({{ a }}, {{ b }}, {{ imm8 }}, 32, 0_u8)
  end

  # vperm2i128
  macro mm256_permute2x128_si256(a, b, imm8)
    ::Intrinsics::X86.clang_builtin_ia32_perm2x128({{ a }}, {{ b }}, {{ imm8 }}, 32, 0_u8)
  end
end
