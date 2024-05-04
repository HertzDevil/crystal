# Base methods
module SIMD::Vector(T, N)
  module ClassMethods(T, N)
    @[Primitive(:vector_literal)]
    def literal(*values : _)
    end
  end

  macro included
    extend ::SIMD::Vector::ClassMethods(T, N)
  end

  @[Primitive(:vector_extract_element)]
  def unsafe_fetch(index : Int) : T
  end
end
