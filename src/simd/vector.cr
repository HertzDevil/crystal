# Base methods
module SIMD::Vector(T, N)
  module ClassMethods(T, N)
    @[Primitive(:vector_literal)]
    def literal(*values : _)
    end

    @[Primitive(:vector_unaligned_load)]
    def unaligned_load(pointer : self*)
    end
  end

  macro included
    extend ::SIMD::Vector::ClassMethods(T, N)
  end

  @[Primitive(:vector_extract_element)]
  def unsafe_fetch(index : Int) : T
  end

  @[Primitive(:vector_insert_element)]
  def unsafe_copy_with(index : Int, value : T) : self
  end
end
