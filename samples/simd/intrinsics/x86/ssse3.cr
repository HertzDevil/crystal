lib LibIntrinsics
  fun x86_ssse3_pshuf_b_128 = "llvm.x86.ssse3.pshuf.b.128"(SIMD::IntVector(UInt8, 16), SIMD::IntVector(UInt8, 16)) : SIMD::IntVector(UInt8, 16)
end

module Intrinsics::X86
  # pshufb
  @[AlwaysInline]
  def self.mm_shuffle_epi8(a : UInt8x16, b : UInt8x16) : UInt8x16
    LibIntrinsics.x86_ssse3_pshuf_b_128(a, b)
  end

  # palignr
  macro mm_alignr_epi8(a, b, imm8)
    ::Intrinsics::X86.clang_builtin_ia32_palignr({{ a }}, {{ b }}, {{ imm8 }}, 16, 0_u8)
  end
end
