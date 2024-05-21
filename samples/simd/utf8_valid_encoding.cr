require "simd"
require "./intrinsics/x86"

lib LibIntrinsics
  fun expect_i1 = "llvm.expect.i1"(Bool, Bool) : Bool
end

class String
  private module ValidEncoding
    module SSE41
      private alias UInt8x16 = SIMD::IntVector(UInt8, 16)
      private alias UInt16x8 = SIMD::IntVector(UInt16, 8)

      # all byte values must be no larger than 0xF4
      private def self.check_smaller_than_0xf4(current_bytes)
        # unsigned, saturates to 0 below max
        Intrinsics::X86.mm_subs_epu8(current_bytes, Intrinsics::X86.mm_set1_epi8(0xF4))
      end

      private def self.continuation_lengths(high_nibbles)
        Intrinsics::X86.mm_shuffle_epi8(
          Intrinsics::X86.mm_setr_epi8(
            1, 1, 1, 1, 1, 1, 1, 1, # 0xxx (ASCII)
            0, 0, 0, 0,             # 10xx (continuation)
            2, 2,                   # 110x
            3,                      # 1110
            4,                      # 1111, next should be 0 (not checked here)
          ),
          high_nibbles,
        )
      end

      private def self.carry_continuations(initial_lengths, previous_carries)
        right1 = Intrinsics::X86.mm_subs_epu8(
          Intrinsics::X86.mm_alignr_epi8(initial_lengths, previous_carries, {{ 16 - 1 }}),
          Intrinsics::X86.mm_set1_epi8(1))

        sum = Intrinsics::X86.mm_add_epi8(initial_lengths, right1)

        right2 = Intrinsics::X86.mm_subs_epu8(
          Intrinsics::X86.mm_alignr_epi8(sum, previous_carries, {{ 16 - 2 }}),
          Intrinsics::X86.mm_set1_epi8(2))

        Intrinsics::X86.mm_add_epi8(sum, right2)
      end

      private def self.check_continuations(initial_lengths, carries)
        # overlap || underlap
        # carry > length && length > 0 || !(carry > length) && !(length > 0)
        # (carries > length) == (lengths > 0)
        Intrinsics::X86.mm_cmpeq_epi8(
          Intrinsics::X86.mm_cmpgt_epi8(carries, initial_lengths),
          Intrinsics::X86.mm_cmpgt_epi8(initial_lengths, Intrinsics::X86.mm_setzero_si128))
      end

      # when 0xED is found, next byte must be no larger than 0x9F
      # when 0xF4 is found, next byte must be no larger than 0x8F
      # next byte must be continuation, ie sign bit is set, so signed < is ok
      private def self.check_first_continuation_max(current_bytes, off1_current_bytes)
        mask_ed = Intrinsics::X86.mm_cmpeq_epi8(off1_current_bytes, Intrinsics::X86.mm_set1_epi8(0xED))
        mask_f4 = Intrinsics::X86.mm_cmpeq_epi8(off1_current_bytes, Intrinsics::X86.mm_set1_epi8(0xF4))

        bad_follow_ed = Intrinsics::X86.mm_and_si128(
          Intrinsics::X86.mm_cmpgt_epi8(current_bytes, Intrinsics::X86.mm_set1_epi8(0x9F)), mask_ed)
        bad_follow_f4 = Intrinsics::X86.mm_and_si128(
          Intrinsics::X86.mm_cmpgt_epi8(current_bytes, Intrinsics::X86.mm_set1_epi8(0x8F)), mask_f4)

        Intrinsics::X86.mm_or_si128(bad_follow_ed, bad_follow_f4)
      end

      # map off1_hibits => error condition
      # hibits     off1    cur
      # C       => < C2 && true
      # E       => < E1 && < A0
      # F       => < F1 && < 90
      # else      false && false
      private def self.check_overlong(current_bytes, off1_current_bytes, hibits, previous_hibits)
        off1_hibits = Intrinsics::X86.mm_alignr_epi8(hibits, previous_hibits, {{ 16 - 1 }})

        initial_mins = Intrinsics::X86.mm_shuffle_epi8(
          Intrinsics::X86.mm_setr_epi8(
            0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80,
            0x80, 0x80, # 10xx => false
            0xC2, 0x80, # 110x
            0xE1,       # 1110
            0xF1,
          ),
          off1_hibits,
        )

        initial_under = Intrinsics::X86.mm_cmpgt_epi8(initial_mins, off1_current_bytes)

        second_mins = Intrinsics::X86.mm_shuffle_epi8(
          Intrinsics::X86.mm_setr_epi8(
            0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80,
            0x80, 0x80, # 10xx => false
            0x7F, 0x7F, # 110x => true
            0xA0,       # 1110
            0x90,
          ),
          off1_hibits,
        )
        second_under = Intrinsics::X86.mm_cmpgt_epi8(second_mins, current_bytes)

        Intrinsics::X86.mm_and_si128(initial_under, second_under)
      end

      private record ProcessedUTFBytes,
        raw_bytes : UInt8x16,
        high_nibbles : UInt8x16,
        carried_continuations : UInt8x16

      private def self.count_nibbles(bytes, answer)
        answer.copy_with(
          raw_bytes: bytes,
          high_nibbles: Intrinsics::X86.mm_and_si128(
            UInt8x16.cast(Intrinsics::X86.mm_srli_epi16(UInt16x8.cast(bytes), 4)),
            Intrinsics::X86.mm_set1_epi8(0x0F),
          ),
        )
      end

      # check whether the current bytes are valid UTF-8
      # at the end of the function, previous gets updated
      private def self.check_utf8_bytes(current_bytes, previous : ProcessedUTFBytes)
        pb = uninitialized ProcessedUTFBytes
        pb = count_nibbles(current_bytes, pb)

        has_error = check_smaller_than_0xf4(current_bytes)

        initial_lengths = continuation_lengths(pb.high_nibbles)

        pb = pb.copy_with(carried_continuations: carry_continuations(initial_lengths, previous.carried_continuations))

        has_error = Intrinsics::X86.mm_or_si128(has_error, check_continuations(initial_lengths, pb.carried_continuations))

        off1_current_bytes = Intrinsics::X86.mm_alignr_epi8(pb.raw_bytes, previous.raw_bytes, {{ 16 - 1 }})
        has_error = Intrinsics::X86.mm_or_si128(has_error, check_first_continuation_max(current_bytes, off1_current_bytes))

        has_error = Intrinsics::X86.mm_or_si128(has_error, check_overlong(current_bytes, off1_current_bytes, pb.high_nibbles, previous.high_nibbles))

        {pb, has_error}
      end

      def self.validate_utf8_fast(bytes : Bytes) : Bool
        src = bytes.to_unsafe
        len = bytes.size.to_u32!
        i = 0_u32

        previous = ProcessedUTFBytes.new(
          raw_bytes: Intrinsics::X86.mm_setzero_si128,
          high_nibbles: Intrinsics::X86.mm_setzero_si128,
          carried_continuations: Intrinsics::X86.mm_setzero_si128,
        )

        if len >= 16
          while i <= len &- 16
            current_bytes = Intrinsics::X86.mm_loadu_si128((src + i).as(UInt8x16*))
            previous, has_error = check_utf8_bytes(current_bytes, previous)
            if LibIntrinsics.expect_i1(Intrinsics::X86.mm_testz_si128(has_error, has_error) == 0, false)
              # Crystal only: return early on invalid chunks (~5% penalty on valid
              # strings, but makes a huge difference on strings that are clearly
              # invalid)
              return false
            end
            i &+= 16
          end
        end

        # last part
        if i < len
          buffer = StaticArray(UInt8, 16).new(0)
          (src + i).copy_to(buffer.to_unsafe, len &- i)
          current_bytes = Intrinsics::X86.mm_loadu_si128(buffer.to_unsafe.as(UInt8x16*))
          _, has_error = check_utf8_bytes(current_bytes, previous)
        else
          has_error = Intrinsics::X86.mm_cmpgt_epi8(
            previous.carried_continuations,
            Intrinsics::X86.mm_setr_epi8(
              9, 9, 9, 9, 9, 9, 9, 9,
              9, 9, 9, 9, 9, 9, 9, 1,
            ),
          )
        end

        Intrinsics::X86.mm_testz_si128(has_error, has_error) != 0
      end
    end

    module AVX2
      private alias UInt8x32 = SIMD::IntVector(UInt8, 32)
      private alias UInt16x16 = SIMD::IntVector(UInt16, 16)

      private def self.push_last_byte_of_a_to_b(a, b)
        Intrinsics::X86.mm256_alignr_epi8(b, Intrinsics::X86.mm256_permute2x128_si256(a, b, 0x21), 15)
      end

      private def self.push_last_2bytes_of_a_to_b(a, b)
        Intrinsics::X86.mm256_alignr_epi8(b, Intrinsics::X86.mm256_permute2x128_si256(a, b, 0x21), 14)
      end

      # all byte values must be no larger than 0xF4
      private def self.check_smaller_than_0xf4(current_bytes)
        # unsigned, saturates to 0 below max
        Intrinsics::X86.mm256_subs_epu8(current_bytes, Intrinsics::X86.mm256_set1_epi8(0xF4))
      end

      private def self.continuation_lengths(high_nibbles)
        Intrinsics::X86.mm256_shuffle_epi8(
          Intrinsics::X86.mm256_setr_epi8(
            1, 1, 1, 1, 1, 1, 1, 1, # 0xxx (ASCII)
            0, 0, 0, 0,             # 10xx (continuation)
            2, 2,                   # 110x
            3,                      # 1110
            4,                      # 1111, next should be 0 (not checked here)
            1, 1, 1, 1, 1, 1, 1, 1, # 0xxx (ASCII)
            0, 0, 0, 0,             # 10xx (continuation)
            2, 2,                   # 110x
            3,                      # 1110
            4,                      # 1111, next should be 0 (not checked here)
          ),
          high_nibbles,
        )
      end

      private def self.carry_continuations(initial_lengths, previous_carries)
        right1 = Intrinsics::X86.mm256_subs_epu8(
          push_last_byte_of_a_to_b(previous_carries, initial_lengths),
          Intrinsics::X86.mm256_set1_epi8(1))

        sum = Intrinsics::X86.mm256_add_epi8(initial_lengths, right1)

        right2 = Intrinsics::X86.mm256_subs_epu8(
          push_last_2bytes_of_a_to_b(previous_carries, sum),
          Intrinsics::X86.mm256_set1_epi8(2))

        Intrinsics::X86.mm256_add_epi8(sum, right2)
      end

      private def self.check_continuations(initial_lengths, carries)
        # overlap || underlap
        # carry > length && length > 0 || !(carry > length) && !(length > 0)
        # (carries > length) == (lengths > 0)
        Intrinsics::X86.mm256_cmpeq_epi8(
          Intrinsics::X86.mm256_cmpgt_epi8(carries, initial_lengths),
          Intrinsics::X86.mm256_cmpgt_epi8(initial_lengths, Intrinsics::X86.mm256_setzero_si256))
      end

      # when 0xED is found, next byte must be no larger than 0x9F
      # when 0xF4 is found, next byte must be no larger than 0x8F
      # next byte must be continuation, ie sign bit is set, so signed < is ok
      private def self.check_first_continuation_max(current_bytes, off1_current_bytes)
        mask_ed = Intrinsics::X86.mm256_cmpeq_epi8(off1_current_bytes, Intrinsics::X86.mm256_set1_epi8(0xED))
        mask_f4 = Intrinsics::X86.mm256_cmpeq_epi8(off1_current_bytes, Intrinsics::X86.mm256_set1_epi8(0xF4))

        bad_follow_ed = Intrinsics::X86.mm256_and_si256(
          Intrinsics::X86.mm256_cmpgt_epi8(current_bytes, Intrinsics::X86.mm256_set1_epi8(0x9F)), mask_ed)
        bad_follow_f4 = Intrinsics::X86.mm256_and_si256(
          Intrinsics::X86.mm256_cmpgt_epi8(current_bytes, Intrinsics::X86.mm256_set1_epi8(0x8F)), mask_f4)

        Intrinsics::X86.mm256_or_si256(bad_follow_ed, bad_follow_f4)
      end

      # map off1_hibits => error condition
      # hibits     off1    cur
      # C       => < C2 && true
      # E       => < E1 && < A0
      # F       => < F1 && < 90
      # else      false && false
      private def self.check_overlong(current_bytes, off1_current_bytes, hibits, previous_hibits)
        off1_hibits = push_last_byte_of_a_to_b(previous_hibits, hibits)

        initial_mins = Intrinsics::X86.mm256_shuffle_epi8(
          Intrinsics::X86.mm256_setr_epi8(
            0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80,
            0x80, 0x80, # 10xx => false
            0xC2, 0x80, # 110x
            0xE1,       # 1110
            0xF1,
            0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80,
            0x80, 0x80, # 10xx => false
            0xC2, 0x80, # 110x
            0xE1,       # 1110
            0xF1,
          ),
          off1_hibits,
        )

        initial_under = Intrinsics::X86.mm256_cmpgt_epi8(initial_mins, off1_current_bytes)

        second_mins = Intrinsics::X86.mm256_shuffle_epi8(
          Intrinsics::X86.mm256_setr_epi8(
            0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80,
            0x80, 0x80, # 10xx => false
            0x7F, 0x7F, # 110x => true
            0xA0,       # 1110
            0x90,
            0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80,
            0x80, 0x80, # 10xx => false
            0x7F, 0x7F, # 110x => true
            0xA0,       # 1110
            0x90,
          ),
          off1_hibits,
        )
        second_under = Intrinsics::X86.mm256_cmpgt_epi8(second_mins, current_bytes)

        Intrinsics::X86.mm256_and_si256(initial_under, second_under)
      end

      private record ProcessedUTFBytes,
        raw_bytes : UInt8x32,
        high_nibbles : UInt8x32,
        carried_continuations : UInt8x32

      private def self.count_nibbles(bytes, answer)
        answer.copy_with(
          raw_bytes: bytes,
          high_nibbles: Intrinsics::X86.mm256_and_si256(
            UInt8x32.cast(Intrinsics::X86.mm256_srli_epi16(UInt16x16.cast(bytes), 4)),
            Intrinsics::X86.mm256_set1_epi8(0x0F),
          ),
        )
      end

      # check whether the current bytes are valid UTF-8
      # at the end of the function, previous gets updated
      private def self.check_utf8_bytes(current_bytes, previous : ProcessedUTFBytes)
        pb = uninitialized ProcessedUTFBytes
        pb = count_nibbles(current_bytes, pb)

        has_error = check_smaller_than_0xf4(current_bytes)

        initial_lengths = continuation_lengths(pb.high_nibbles)

        pb = pb.copy_with(carried_continuations: carry_continuations(initial_lengths, previous.carried_continuations))

        has_error = Intrinsics::X86.mm256_or_si256(has_error, check_continuations(initial_lengths, pb.carried_continuations))

        off1_current_bytes = push_last_byte_of_a_to_b(previous.raw_bytes, pb.raw_bytes)
        has_error = Intrinsics::X86.mm256_or_si256(has_error, check_first_continuation_max(current_bytes, off1_current_bytes))

        has_error = Intrinsics::X86.mm256_or_si256(has_error, check_overlong(current_bytes, off1_current_bytes, pb.high_nibbles, previous.high_nibbles))

        {pb, has_error}
      end

      def self.validate_utf8_fast(bytes : Bytes) : Bool
        src = bytes.to_unsafe
        len = bytes.size.to_u32!
        i = 0_u32

        previous = ProcessedUTFBytes.new(
          raw_bytes: Intrinsics::X86.mm256_setzero_si256,
          high_nibbles: Intrinsics::X86.mm256_setzero_si256,
          carried_continuations: Intrinsics::X86.mm256_setzero_si256,
        )

        if len >= 32
          while i <= len &- 32
            current_bytes = Intrinsics::X86.mm256_loadu_si256((src + i).as(UInt8x32*))
            previous, has_error = check_utf8_bytes(current_bytes, previous)
            if LibIntrinsics.expect_i1(Intrinsics::X86.mm256_testz_si256(has_error, has_error) == 0, false)
              # Crystal only: return early on invalid chunks (~5% penalty on valid
              # strings, but makes a huge difference on strings that are clearly
              # invalid)
              return false
            end
            i &+= 32
          end
        end

        # last part
        if i < len
          buffer = StaticArray(UInt8, 32).new(0)
          (src + i).copy_to(buffer.to_unsafe, len &- i)
          current_bytes = Intrinsics::X86.mm256_loadu_si256(buffer.to_unsafe.as(UInt8x32*))
          _, has_error = check_utf8_bytes(current_bytes, previous)
        else
          has_error = Intrinsics::X86.mm256_cmpgt_epi8(
            previous.carried_continuations,
            Intrinsics::X86.mm256_setr_epi8(
              9, 9, 9, 9, 9, 9, 9, 9,
              9, 9, 9, 9, 9, 9, 9, 9,
              9, 9, 9, 9, 9, 9, 9, 9,
              9, 9, 9, 9, 9, 9, 9, 1,
            ),
          )
        end

        Intrinsics::X86.mm256_testz_si256(has_error, has_error) != 0
      end
    end
  end

  def sse41_valid_encoding? : Bool
    ValidEncoding::SSE41.validate_utf8_fast(to_slice)
  end

  def avx2_valid_encoding? : Bool
    ValidEncoding::AVX2.validate_utf8_fast(to_slice)
  end

  # before #12145
  def old_valid_encoding? : Bool
    reader = Char::Reader.new(self)
    while reader.has_next?
      return false if reader.error
      reader.next_char
    end
    true
  end
end

# --mcpu=x86-64-v3

require "benchmark"

CODEPOINT_RANGES = {
  (0x0..0x7F),
  (0x80..0x7FF),
  (0x800..0xD7FF),
  (0xE000..0xFFFF),
  (0x10000..0x10FFFF),
}

def rand_str(n)
  str = String.build do |io|
    while io.bytesize <= n - 4
      io << CODEPOINT_RANGES.sample.sample.unsafe_chr
    end
    while io.bytesize < n
      io << '\0'
    end
  end
  str.size
  str
end

subjects = Array.new(1000) { rand_str(0x10000) }

module Witness
  class_property x = false
end

Benchmark.ips do |b|
  b.report("old") do
    Witness.x = subjects.all? &.old_valid_encoding?
  end

  b.report("scalar") do
    Witness.x = subjects.all? &.valid_encoding?
  end

  {% if flag?(:x86_has_sse41) %}
    b.report("sse4.1") do
      Witness.x = subjects.all? &.sse41_valid_encoding?
    end
  {% end %}

  {% if flag?(:x86_has_avx2) %}
    b.report("avx2") do
      Witness.x = subjects.all? &.avx2_valid_encoding?
    end
  {% end %}
end
