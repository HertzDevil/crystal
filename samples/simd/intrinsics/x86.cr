module Intrinsics::X86
  alias Int8x16 = SIMD::IntVector(Int8, 16)
  alias Int8x32 = SIMD::IntVector(Int8, 32)
  alias UInt8x16 = SIMD::IntVector(UInt8, 16)
  alias UInt8x32 = SIMD::IntVector(UInt8, 32)
  alias UInt16x8 = SIMD::IntVector(UInt16, 8)
  alias UInt16x16 = SIMD::IntVector(UInt16, 16)
  alias UInt64x2 = SIMD::IntVector(UInt64, 2)
  alias UInt64x4 = SIMD::IntVector(UInt64, 4)

  # :nodoc:
  # https://github.com/llvm/llvm-project/blob/38a2051c5222b3e5245043a3056b3a1e89f69b22/clang/lib/CodeGen/CGBuiltin.cpp#L15252
  macro clang_builtin_ia32_palignr(a, b, imm, num_elts, zero)
    {% shift_val = 0xFF & imm %}
    {% if shift_val >= 32 %}
      ::SIMD::IntVector.literal({{ (0...num_elts).map { zero }.splat }})
    {% else %}
      {%
        if shift_val >= 16
          shift_val -= 16
          b = a
          a = "::SIMD::IntVector.literal(#{(0...num_elts).map { zero }.splat})".id
        end
      %}

      {%
        indices = [] of _
        (0...num_elts // 16).each do |l|
          l *= 16
          (0...16).each do |i|
            idx = shift_val + i
            idx += num_elts - 16 if idx >= 16
            indices << (idx + l)
          end
        end
      %}
      {{ b }}.unsafe_shuffle({{ a }}, ::SIMD::IntVector.literal({{ indices.splat }}))
    {% end %}
  end

  # :nodoc:
  # https://github.com/llvm/llvm-project/blob/5445a35d6ef5e8b6d3aafd78c48167ef22eef0af/clang/lib/CodeGen/CGBuiltin.cpp#L15343
  macro clang_builtin_ia32_perm2x128(a, b, imm, num_elts, zero)
    {%
      out_ops = [] of _
      indices = [] of _

      (0...2).each do |l|
        if imm & (1 << (l * 4 + 3)) != 0
          out_ops << "::SIMD::IntVector.literal(#{(0...num_elts).map { zero }.splat})".id
        elsif imm & (1 << (l * 4 + 1)) != 0
          out_ops << b
        else
          out_ops << a
        end

        (0...num_elts // 2).each do |i|
          idx = l * num_elts + i
          if imm & (1 << (l * 4)) != 0
            idx += num_elts // 2
          end
          indices << idx
        end
      end
    %}

    {{ out_ops[0] }}.unsafe_shuffle({{ out_ops[1] }}, ::SIMD::IntVector.literal({{ indices.splat }}))
  end
end

require "./x86/sse2"
require "./x86/ssse3"
require "./x86/sse41"
require "./x86/avx"
require "./x86/avx2"
